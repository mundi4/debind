-- **Which action a key fires, asked without the game.**
--
-- Everything above this file measures what a rebuild decided. This one runs the decision: the
-- emitted records go into a restricted environment, `EVAL_SNIPPET` walks them, and the winner is
-- read back (`going-headless-outside-the-ui.md` §5, `tests/restricted.lua`).
--
-- These came down from `/debtest`, where they were the only layer that could see them. What each
-- one gives up by coming down is the same three things (§8): whether the sandbox would compile the
-- body at all, whether a real press arrives under the button name we bound, and what the action
-- button does once it has one. **The two `Multi-axis:` sweeps stay in both places** -- they are the
-- anchor, and if this interpretation and the game ever part, that is where it shows.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

    local T = { passed = 0, failures = {} };

    --- **In the shipped shape there is nothing here to run, and that is the check.**
    ---
    --- Every case below reaches the decision through `EvalClickTimeKey`, an attribute
    --- `SecureBindings.lua` sets only under `DEBUG` -- a way to ask the click path what it would
    --- pick without hardware input, which a released build has no business carrying. So the
    --- shipped pass asks the one question that is left: **is it really not there.** A hook that
    --- shipped would be a test entry point on every user's driver frame, reachable by anything
    --- that can run a snippet.
    if (ctx and ctx.shipped) then
        local driver = DebindPrivate.BindingDriver;
        if (driver:GetAttribute("EvalClickTimeKey") ~= nil
                or driver:GetAttribute("EvalClickCastFrame") ~= nil) then
            T.failures[#T.failures + 1] =
                "the DEBUG-only eval hooks are installed in the shipped shape";
        else
            T.passed = T.passed + 1;
        end
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

    --- A registered unit frame, for the click-cast test far below.
    ---
    --- **Registered before the first rebuild, on purpose.** The interpreter is stood up on
    --- everything recorded so far and fed each rebuild after that, so anything that has to be in
    --- its world has to cross before it exists -- a registration slipped in between two rebuilds
    --- would be in neither window.
    local unitFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(unitFrame, "group");
    unitFrame:SetAttribute("unit", "party1");

    --- A frame that is not a party or raid frame, for the role cases: the role is only measured on
    --- those, so this one is where a role condition has no say.
    local playerFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(playerFrame, "player");
    playerFrame:SetAttribute("unit", "player");

    local seq = 0;
    --- One action, in the shape the profile stores. `seq` runs on its own so the order actions
    --- are written in is the order they sit in the layer.
    --- **Hover Cast는 기본값 그대로 꺼져 있다.** 이 파일 대부분이 재는 것은 조건과 조합키가 고르는
    --- 승자이고, 켜져 있으면 액션마다 쌍둥이가 하나씩 더 서서 승자의 자리 번호가 밀린다. 가리킨
    --- 누름을 재는 케이스는 `casting`을 스스로 적는다 (`tests/casting.lua`).
    local function action(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.seq = seq;
        return t;
    end

    --- Stands a profile up, rebuilds, and hands back the interpreter with the new records in it.
    ---
    --- **The interpreter is built once and fed each rebuild after that.** Standing a new one up
    --- would mean replaying the login setup again for every test, and the login setup is what
    --- creates the tables -- replaying it twice into one environment is not what the game does.
    local function Bind(actions, switches, options)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            options = options,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = switches or {},
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

    local castmod = require("castmod");

    --- Which record wins on this key right now, by its place among the records that are not self or
    --- focus twins. Every action has both, and a press with no modifier held never reaches them;
    --- the cases about the twins read `interp:evalKey` itself.
    local function winner(key)
        return castmod.index(Constants, interp:recordsFor(key), (interp:evalKey(key)));
    end

    ---------------------------------------------------------------------------
    -- The client's own targeting branches
    ---------------------------------------------------------------------------

    -- **All three of the client's targeting branches are off.** Mouseover cast cannot reach a right
    -- answer on our button (`CalculateAction` answers slot 1 for it), and self cast and focus cast
    -- are the click wrapper's to decide now: left on, they would still redirect every press that
    -- fires with no unit, in the order the addon took them over to fix
    -- (`implementing-focus-and-self-cast.md` §1, §3-7).
    --
    -- A key press and a frame click are both run through the wrapper here, since the wrapper used
    -- to write two of them on every click.
    test("the client's three targeting branches stay off", function()
        -- Named before the first bind: the button a type and value get is stamped once and cached,
        -- and the cases below read the name off it.
        shim.world.spells[585] = { name = "Renew" };
        Bind({
            action({ value = 585, key = "F1" }),
            action({ value = 585, key = "BUTTON2",
                casting = { hoverCast = "usual" },
                conditions = { units = { unitframe = { reaction = Constants.REACTION_ALL } } } }),
        });
        local clickFrame = DebindPrivate.DefaultClickFrame;
        shim.world.units = { party1 = { id = "friend", reaction = "help" } };

        local function allOff(when)
            for _, name in ipairs({ "checkmouseovercast", "checkselfcast", "checkfocuscast" }) do
                check(clickFrame:GetAttribute(name) == false,
                    when .. ": " .. name .. " is " .. tostring(clickFrame:GetAttribute(name)));
            end
        end

        allOff("at login");
        interp:runWrapped(clickFrame, "OnClick", Constants.CLICKTIME_BUTTON_PREFIX .. "F1", true);
        allOff("after a key press");
        interp:clickFrame(unitFrame, "RightButton", false);
        interp:runWrapped(clickFrame, "OnClick", "debind1", false);
        allOff("after a frame click");

        shim.world.units = {};
    end);


    -- **A value the reader set is the whole condition for the wrapped button.** The press comes
    -- back with a macro button whose body puts each chosen CVar where the action wants it around
    -- the real one, and the target goes on the cast frame rather than on the wrapped click frame --
    -- the wrapper's own prologue would wipe it off that one.
    --
    -- **A chosen target no longer sends a press this way** (2026-09-21). Turning the engine's
    -- automatic self-cast off under a target nobody asked to turn it off for was adding a
    -- behaviour the client does not have; a target with nothing set goes out exactly as an action
    -- bar button with a `unit` on it does
    -- (`setting-the-clients-cast-automatics-per-action.md` §3).
    test("an action that sets one of the automatics gets a wrapped button", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        shim.world.spells[8936] = { name = "Regrowth", pressAndHold = true };
        Bind({
            action({ value = 585, key = "F1", unit = "focus",
                casting = { autoSelfCast = false } }),
            action({ value = 774, key = "F2", unit = "focus" }),
            action({ value = 8936, key = "F3", casting = { autoSelfCast = false } }),
            action({ value = 585, key = "F4",
                casting = { autoUnshift = true, autoDismountFlying = false } }),
        });

        local clickFrame = DebindPrivate.DefaultClickFrame;

        local _, chosen = interp:evalKey("F1");
        check(clickFrame:GetAttribute("*type-" .. chosen) == "macro",
            "a set value did not reach a wrapped button: " .. tostring(chosen));
        check(clickFrame:GetAttribute("*macrotext-" .. chosen) ==
            '/run DebindAuto_autoSelfCast=GetCVar("autoSelfCast");SetCVar("autoSelfCast","0")\n'
            .. '/click DebindCastButton ' .. interp:actionButton(chosen) .. '\n'
            .. '/run SetCVar("autoSelfCast",DebindAuto_autoSelfCast)',
            "the body: " .. tostring(clickFrame:GetAttribute("*macrotext-" .. chosen)));
        check(clickFrame:GetAttribute("*spell-" .. interp:actionButton(chosen)) == "Renew",
            "the wrapper clicks the wrong button: " .. tostring(interp:actionButton(chosen)));

        -- **The target goes on the cast frame**, because that is the one the body clicks and the
        -- only one nothing wipes between the decision and the cast.
        check(DebindPrivate.CastFrame:GetAttribute("unit") == "focus",
            "the cast frame's unit: " .. tostring(DebindPrivate.CastFrame:GetAttribute("unit")));

        -- **Nothing set, no wrapper**, target or no target.
        local _, plain = interp:evalKey("F2");
        check(clickFrame:GetAttribute("*type-" .. plain) == "spell",
            "an action with nothing set took the wrapped route: " .. tostring(plain));

        -- **A press-and-hold spell is wrapped too**, on a button per edge. The test below measures
        -- the pair; what matters here is that it is not left on the direct route.
        local _, held = interp:evalKey("F3");
        check(clickFrame:GetAttribute("*type-" .. held) == "macro",
            "a press-and-hold spell stayed on the direct route: " .. tostring(held));

        -- **Two rows, two pairs of lines, one `/click` between them.** A macro inside a macro does
        -- not run, so the rows stack as lines rather than as nesting.
        local _, two = interp:evalKey("F4");
        check(clickFrame:GetAttribute("*macrotext-" .. two) ==
            '/run DebindAuto_autoUnshift=GetCVar("autoUnshift");SetCVar("autoUnshift","1")'
            .. ';DebindAuto_autoDismountFlying=GetCVar("autoDismountFlying")'
            .. ';SetCVar("autoDismountFlying","0")\n'
            .. '/click DebindCastButton ' .. interp:actionButton(two) .. '\n'
            .. '/run SetCVar("autoUnshift",DebindAuto_autoUnshift)'
            .. ';SetCVar("autoDismountFlying",DebindAuto_autoDismountFlying)',
            "two rows: " .. tostring(clickFrame:GetAttribute("*macrotext-" .. two)));

        -- **The same spell with different values does not share a button.** The one inside is
        -- shared; the wrapper around it is what the values split.
        check(interp:actionButton(chosen) == interp:actionButton(two),
            "the two wrappers do not click the same button");
        check(chosen ~= two, "two sets of values shared one wrapper");
    end);

    -- **Whether a spell is empowered is asked at the press, not at the rebuild.** The name baked on
    -- the button is what the client resolves at the cast, so an override makes the two disagree:
    -- the base spell is not empowered and the one that actually goes out is. An answer baked at
    -- the rebuild is the base spell's and cannot follow that, and getting it wrong leaves a spell
    -- that charges and never lets go.
    test("an empowered spell is told apart at the press", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        shim.world.spells[102560] = { name = "Chosen of Elune", pressAndHold = true };
        Bind({
            action({ value = 585, key = "F1" }),
            action({ value = 774, key = "F2" }),
        });

        local clickFrame = DebindPrivate.DefaultClickFrame;
        local function Press(key)
            interp:runWrapped(clickFrame, "OnClick", Constants.CLICKTIME_BUTTON_PREFIX .. key, true);
            local _, button = interp:evalKey(key);
            return clickFrame:GetAttribute("*typerelease-" .. button);
        end

        check(Press("F1") == nil, "an ordinary spell named typerelease: " .. tostring(Press("F1")));

        -- **The override**: the baked name now resolves to a spell that is empowered.
        shim.world.castNames["Renew"] = 102560;
        check(Press("F1") == "spell", "the override did not reach the press");

        -- **Press and Tap leaves it alone.** There is no held key there, so the release edge has
        -- nothing to let go of; a second press is what finishes the spell.
        interp.env.EmpowerTapControls = true;
        check(Press("F1") == nil, "tap controls still named typerelease");
        interp.env.EmpowerTapControls = false;

        shim.world.castNames["Renew"] = nil;
        check(Press("F2") == nil, "a second ordinary spell named typerelease");

        -- **A click-cast press is never told it holds the key.** It arrives through
        -- `delegate:Click(button)` with no edge, so `down` is always false; turning it on there
        -- makes the gate force `useOnKeyDown` and send the release of a spell nobody pressed.
        check(DebindPrivate.DefaultClickFrame:GetAttribute("pressAndHoldAction") == nil,
            "the bare name survived the press");
    end);

    -- **An empowered spell reaches the wrapped route too**, and what it takes is a body per edge:
    -- one `/click` carrying `true` on the way down and one carrying `false` on the way up. One
    -- body sent on both edges charges the spell and never releases it, which is what kept these
    -- spells out (`setting-the-clients-cast-automatics-per-action.md` §7).
    test("an empowered spell that sets a value is wrapped on both edges", function()
        shim.world.spells[271466] = { name = "Will of the Necropolis", pressAndHold = true };
        Bind({
            action({ value = 271466, key = "F1", casting = { autoSelfCast = false } }),
        });

        local clickFrame = DebindPrivate.DefaultClickFrame;
        local button = Constants.CLICKTIME_BUTTON_PREFIX .. "F1";

        local down = interp:runWrapped(clickFrame, "OnClick", button, true);
        check(clickFrame:GetAttribute("*type-" .. down) == "macro",
            "the down edge did not reach a wrapped button: " .. tostring(down));
        local inner = interp:actionButton(down);
        check(clickFrame:GetAttribute("*macrotext-" .. down) ==
            '/run DebindAuto_autoSelfCast=GetCVar("autoSelfCast");SetCVar("autoSelfCast","0")\n'
            .. '/click DebindCastButton ' .. inner .. ' true\n'
            .. '/run SetCVar("autoSelfCast",DebindAuto_autoSelfCast)',
            "the down body: " .. tostring(clickFrame:GetAttribute("*macrotext-" .. down)));

        interp.state.channeling = true;
        local up = interp:runWrapped(clickFrame, "OnClick", button, false);
        check(up ~= down, "both edges went to one button: " .. tostring(up));
        check(clickFrame:GetAttribute("*typerelease-" .. up) == "macro",
            "the release button does not fire on the release: " .. tostring(up));
        check(clickFrame:GetAttribute("*macrotext-" .. up) ==
            '/run DebindAuto_autoSelfCast=GetCVar("autoSelfCast");SetCVar("autoSelfCast","0")\n'
            .. '/click DebindCastButton ' .. inner .. ' false\n'
            .. '/run SetCVar("autoSelfCast",DebindAuto_autoSelfCast)',
            "the up body: " .. tostring(clickFrame:GetAttribute("*macrotext-" .. up)));
        interp.state.channeling = false;
    end);

    ---------------------------------------------------------------------------
    -- The binding types
    ---------------------------------------------------------------------------

    -- **What a press ends at is a button name**, and the attributes under that name are what the
    -- game reads to fire the action. So the two halves are checked together: the record picked,
    -- and what is stamped on the button it names.
    test("each type reaches the attributes that fire it", function()
        shim.world.spells[585] = { name = "Renew" };
        Bind({
            action({ value = 585, key = "F1" }),
            action({ type = Constants.ITEM, value = 6948, key = "F2" }),
            action({ type = Constants.MACROTEXT, value = "/cast Renew", key = "F3" }),
            action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = "F4" }),
            action({ type = Constants.TARGET, key = "F5", unit = "focus" }),
            action({ type = Constants.USESLOT, value = 13, key = "F6" }),
        });

        local clickFrame = DebindPrivate.DefaultClickFrame;
        local function attributesOf(key)
            local _, button = interp:evalKey(key);
            check(button, key .. " picked no action");
            button = interp:actionButton(button);
            return clickFrame:GetAttribute("*type-" .. button),
                clickFrame:GetAttribute("*spell-" .. button)
                or clickFrame:GetAttribute("*item-" .. button)
                or clickFrame:GetAttribute("*macrotext-" .. button);
        end

        local spellType, spellValue = attributesOf("F1");
        check(spellType == "spell" and spellValue == "Renew", "spell: " .. tostring(spellValue));

        local itemType, itemValue = attributesOf("F2");
        check(itemType == "item" and itemValue == "item:6948", "item: " .. tostring(itemValue));

        -- **An equipment slot is the same attribute with a different shape of value**, and the
        -- shape is the whole of it: `SecureCmdItemParse` reads a bare number as an inventory slot
        -- and `item:13` as an item id. Getting this wrong fires item 13 instead of the trinket,
        -- and nothing anywhere says so.
        local slotType, slotValue = attributesOf("F6");
        check(slotType == "item" and slotValue == "13", "equipslot: " .. tostring(slotValue));

        -- **And it keeps a target, because the game hands one on.** `SECURE_ACTIONS.item` passes
        -- its `unit` down to `UseInventoryItem(slot, target)`, so a slot aims exactly the way an
        -- item id does. A type left out of `TYPES_WITH_UNIT` has its unit wiped on the way to the
        -- binding while the window still shows the one that was picked -- the fault that list was
        -- made single for.
        local targeted = DebindPrivate.GetBindingInfoForAction(
            { type = Constants.USESLOT, value = 13, key = "F7", unit = "focus" });
        check(targeted.unit == "focus",
            "equipslot lost its unit: " .. tostring(targeted.unit));

        local textType, textValue = attributesOf("F3");
        check(textType == "macro" and textValue == "/cast Renew", "macrotext: " .. tostring(textValue));

        local targetType = attributesOf("F5");
        check(targetType == "target", "target: " .. tostring(targetType));
    end);

    -- **Unused wins by having nothing to fire.** A key whose conditional action does not match
    -- falls through to it, and the press answers with no button at all.
    test("unused wins the key and fires nothing", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { combat = true } }),
            action({ type = Constants.UNUSED, key = "F1" }),
        });

        interp.state.combat = true;
        check(winner("F1") == 1, "the conditional action did not win in combat");

        interp.state.combat = false;
        local index, button = interp:evalKey("F1");
        check(index == nil and button == nil, "unused fired something: " .. tostring(button));
        interp:resetState();
    end);

    ---------------------------------------------------------------------------
    -- One axis at a time
    ---------------------------------------------------------------------------

    --- Every plain axis, with the world that makes it true. Two actions per key: the first
    --- carries the condition, the second is the fallback -- so **both directions are asked in
    --- one pass** and a test that only ever set the state would also pass on a condition nobody
    --- reads.
    local AXES = {
        { name = "combat", conditions = { combat = true }, on = function(s) s.combat = true; end },
        { name = "stealth", conditions = { stealth = true }, on = function(s) s.stealth = true; end },
        { name = "extrabar", conditions = { extrabar = true }, on = function(s) s.extrabar = true; end },
        { name = "petbattle", conditions = { petbattle = true }, on = function(s) s.petbattle = true; end },
        { name = "specialbar", conditions = { specialbar = true },
            on = function(s) s.vehiclebar = true; end },
        { name = "groups", conditions = { groups = Constants.GROUP_RAID },
            on = function(s) s.group = "raid"; end },
        -- **The form axis is a bit, and what the client answers is an index.** The condition is a
        -- mask over `2^index`, so form 2 is bit 4 -- getting that shift wrong is a class of fault
        -- the two sides used to be able to disagree about.
        { name = "forms", conditions = { forms = 4 }, on = function(s) s.form = 2; end },
        { name = "bonusbars", conditions = { bonusbars = 8 }, on = function(s) s.bonusbar = 3; end },
        { name = "mounted", conditions = { mounted = true }, on = function(s) s.mounted = true; end },
        { name = "indoors", conditions = { indoors = true }, on = function(s) s.indoors = true; end },
        -- **The one axis here whose world is a number rather than a flag.** `skyriding` reads the
        -- same `GetBonusBarOffset()` that `bonusbars` above reads, so what turns it on is that
        -- offset landing on `BONUSBAR_SKYRIDING` -- and a press that read the offset as a bit, or
        -- compared against the wrong number, fails here rather than in the game.
        { name = "skyriding", conditions = { skyriding = true },
            on = function(s) s.bonusbar = Constants.BONUSBAR_SKYRIDING; end },
        -- **Area predicates, not state.** They answer what the zone allows rather than what the
        -- reader is doing, which is what lets several mounts on one key pick themselves. Both
        -- also read a function whose name is one word off the other's, so the pair is here as
        -- much to catch a swap as to check the wiring.
        { name = "flyable", conditions = { flyable = true }, on = function(s) s.flyable = true; end },
        { name = "advflyable", conditions = { advflyable = true },
            on = function(s) s.advflyable = true; end },
        -- The pair of `flyable` above, and the one that is not about the zone: whether the reader
        -- is off the ground. Their functions differ by one word too.
        { name = "flying", conditions = { flying = true }, on = function(s) s.flying = true; end },
    };

    test("every axis decides the press, both ways", function()
        for i = 1, #AXES do
            local axis = AXES[i];
            Bind({
                action({ value = 585, key = "F1", conditions = axis.conditions }),
                action({ value = 774, key = "F1" }),
            });

            check(winner("F1") == 2, axis.name .. ": the fallback did not win with the axis off");

            axis.on(interp.state);
            check(winner("F1") == 1, axis.name .. ": the condition did not win with the axis on");
            interp:resetState();
        end
    end);

    -- **`specialbar` is three bars folded into one value, plus pet battle.** Any one of them turns
    -- it on, which is what the state loop measures too -- if the two sides folded it differently
    -- the same world would answer two ways.
    test("specialbar answers to each of the bars it folds", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { specialbar = true } }),
            action({ value = 774, key = "F1" }),
        });

        local FOLDS = { "vehiclebar", "overridebar", "shapeshiftbar", "petbattle" };
        for i = 1, #FOLDS do
            interp:resetState();
            check(winner("F1") == 2, FOLDS[i] .. ": it won with nothing on");
            interp.state[FOLDS[i]] = true;
            check(winner("F1") == 1, FOLDS[i] .. " did not turn specialbar on");
        end
        interp:resetState();
    end);

    -- A `known` condition is answered by parsing the conditional the record carries. The value it
    -- names is the spell, and `true` is the action's own, named at the bake
    -- (`making-known-a-spell-name.md`). The state loop reads the same string as a key in
    -- `States`.
    test("a known condition follows the spell book", function()
        Bind({
            action({ value = 8936, key = "F1", conditions = { known = true } }),
            action({ value = 774, key = "F1" }),
        });

        check(winner("F1") == 2, "the known action won without the spell");
        interp.state.known["Regrowth"] = true;
        check(winner("F1") == 1, "the known action did not win with the spell");
        interp:resetState();
    end);

    -- **The same two outcomes, reached at the rebuild instead of at the press.** A `known` the
    -- rebuild can settle carries no axis at all, or takes its record out of the key
    -- (`baking-the-known-condition.md` §5) -- and the press has to land where it lands
    -- today either way. That is the whole claim the optimization rests on, and the restricted
    -- side is the only thing that can check it.
    --
    -- **The restricted side is never told about either spell.** A record that still carried the
    -- axis would ask `[known:]` here and lose, so the settled-true action winning is what says
    -- the axis is really gone rather than merely quiet.
    test("a known settled at the rebuild lands where a measured one does", function()
        for spellID, learned in pairs({ [1000] = true, [1001] = false }) do
            shim.world.spellbook[spellID] = true;
            shim.world.spells[spellID] = { name = "Spell " .. spellID, levelLearned = 10 };
            shim.world.knownSpells[spellID] = learned or nil;
        end

        Bind({
            action({ value = 1000, key = "F1", conditions = { known = true } }),
            action({ value = 774, key = "F1" }),
            action({ value = 1001, key = "F2", conditions = { known = true } }),
            action({ value = 774, key = "F2" }),
        });

        check(winner("F1") == 1, "the settled-true action did not win");

        -- **The record count, not only the winner.** With the dropped record still emitted, the
        -- fallback would sit at index 2 and this key would answer 2; asserting the count is what
        -- keeps "it was dropped" apart from "it lost".
        local f2 = castmod.without(Constants,
            interp.env.ClickTimeKeys[Constants.CLICKTIME_BUTTON_PREFIX .. "F2"]);
        check(#f2 == 1, "the settled-false record was emitted: " .. #f2);
        check(winner("F2") == 1, "the fallback did not win the key");
        interp:resetState();
    end);

    -- A switch is the one axis the press does **not** measure: there is nothing to measure, the
    -- stored value is the original, so it is read straight out of `States`.
    test("a switch condition is read out of the shared state", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { ["$burst"] = true } }),
            action({ value = 774, key = "F1" }),
        }, { ["$burst"] = { mode = Constants.SWITCH_MODES.MANUAL } });

        check(winner("F1") == 2, "the switch action won with the switch off");
        interp.env.States["$burst"] = true;
        check(winner("F1") == 1, "the switch action did not win with the switch on");
        interp.env.States["$burst"] = false;
    end);

    ---------------------------------------------------------------------------
    -- Units
    ---------------------------------------------------------------------------

    -- **Existence, reaction and life are three axes on one unit**, and the press measures each of
    -- them again rather than reading what the poll left -- a click is where the truth can be had.
    test("a unit condition is measured at the press", function()
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = {};
        check(winner("F1") == 2, "the unit action won with no unit there");

        shim.world.units = { target = { id = "friend", reaction = "help" } };
        check(winner("F1") == 1, "the unit action did not win on a friendly target");

        shim.world.units = { target = { id = "enemy", reaction = "harm" } };
        check(winner("F1") == 2, "a hostile target matched a friendly condition");

        shim.world.units = {};
    end);

    -- Life is the axis a poll cannot be asked to stand up on demand, and the one the press has to
    -- get right: a heal sent at a corpse is a wasted global cooldown.
    test("the life axis splits a living unit from a dead one", function()
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = { ["@"] = { dead = true } } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = { target = { id = "friend", reaction = "help" } };
        check(winner("F1") == 2, "the dead condition won on a living unit");

        shim.world.units = { target = { id = "friend", reaction = "help", dead = true } };
        check(winner("F1") == 1, "the dead condition lost on a corpse");

        -- **A ghost is dead**, which `UnitIsDead` alone does not say -- and the restricted
        -- environment has no `UnitIsDeadOrGhost`, so both have to be asked.
        shim.world.units = { target = { id = "friend", reaction = "help", ghost = true } };
        check(winner("F1") == 1, "a ghost read as alive");

        shim.world.units = {};
    end);

    -- **The overlap, at the press.** The two predicates are not exclusive: a raid member in the
    -- reader's own subgroup answers true to both. So [in my party] has to keep reaching the people
    -- beside the reader once the party becomes a raid, which is the whole reason this axis is
    -- three overlapping boxes rather than three values picked by an ordered chain.
    --
    -- The third world is what stops this passing on a stub that answers true to everything.
    test("in my party reaches a raid member in my own subgroup", function()
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = { ["@"] = { group = Constants.UNITGROUP_PARTY } } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = { target = { id = "mate", inParty = true } };
        check(winner("F1") == 1, "a party condition missed a plain party member");

        shim.world.units = { target = { id = "mate", inParty = true, inRaid = true } };
        check(winner("F1") == 1,
            "a party condition missed a raid member in my own subgroup");

        shim.world.units = { target = { id = "other", inRaid = true } };
        check(winner("F1") == 2,
            "a party condition caught a raid member in another subgroup");

        shim.world.units = { target = { id = "stranger" } };
        check(winner("F1") == 2, "a party condition caught an outsider");

        shim.world.units = {};
    end);

    -- **Two group conditions on one unit, which is the case the three boxes cannot represent.**
    -- `"@"` and an explicit condition on the same unit are merged before anything is emitted, and
    -- [in my party] meeting [in my raid] leaves exactly one cell: in the raid, in my own subgroup.
    -- No combination of the three boxes says that, so intersecting the stored bits answers zero,
    -- the record is dropped as unsatisfiable, and the key quietly does nothing.
    test("in my party and in my raid on one unit leave the shared cell", function()
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = {
                    ["@"] = { group = Constants.UNITGROUP_PARTY },
                    target = { group = Constants.UNITGROUP_RAID },
                } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = { target = { id = "mate", inParty = true, inRaid = true } };
        check(winner("F1") == 1,
            "the intersection lost the raid member in my own subgroup");

        shim.world.units = { target = { id = "mate", inParty = true } };
        check(winner("F1") == 2, "a plain party member passed both conditions");

        shim.world.units = { target = { id = "other", inRaid = true } };
        check(winner("F1") == 2, "a raid member in another subgroup passed both conditions");

        shim.world.units = {};
    end);

    test("not in my group is the outsider and nobody else", function()
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = { ["@"] = { group = Constants.UNITGROUP_NONE } } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = { target = { id = "stranger" } };
        check(winner("F1") == 1, "an outsider failed [not in my group]");

        shim.world.units = { target = { id = "mate", inParty = true } };
        check(winner("F1") == 2, "a party member passed [not in my group]");

        shim.world.units = { target = { id = "other", inRaid = true } };
        check(winner("F1") == 2, "a raid member passed [not in my group]");

        shim.world.units = {};
    end);

    -- **The case that shipped unverified.** One key asks whether the focus exists; another asks
    -- whether it is friendly. Under the old encoding, *registering* the reaction axis changed what
    -- the measured value **meant** -- with nobody asking about reaction a friendly unit came back
    -- as `true` -- so the second key's condition silently decided the first key's. The symptom was
    -- key one dying for no reason anyone could see from key one.
    --
    -- It went out in 3.1.1 with the secure half checked by a one-off script and nothing else
    -- (`.zzz/TODO.md` E-7). Both halves are asked here: the press, and the poll that takes the key.
    test("a reaction condition on one key does not decide another key's", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { units = { focus = {} } } }),
            action({ value = 774, key = "F2",
                conditions = { units = { focus = { reaction = Constants.REACTION_HELP } } } }),
        });

        shim.world.units = { focus = { id = "friend", reaction = "help" } };
        check(winner("F1") == 1, "the existence key did not fire on a friendly focus");
        check(winner("F2") == 1, "the friendly key did not fire on a friendly focus");

        shim.world.units = { focus = { id = "enemy", reaction = "harm" } };
        check(winner("F1") == 1,
            "the existence key died on a hostile focus -- another key's reaction decided it");
        check(winner("F2") == nil, "the friendly key fired on a hostile focus");

        shim.world.units = {};
        check(winner("F1") == nil, "the existence key fired with the focus gone");
    end);

    ---------------------------------------------------------------------------
    -- Order
    ---------------------------------------------------------------------------

    -- **The first record that matches wins**, so the order they were emitted in is the order the
    -- reader set. A conditional action placed above an unconditional one is the ordinary shape,
    -- and the unconditional one must not be able to take the press from it.
    test("the first matching record wins", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { combat = true, stealth = true } }),
            action({ value = 774, key = "F1", conditions = { combat = true } }),
            action({ value = 8936, key = "F1" }),
        });

        check(winner("F1") == 3, "the fallback did not win at rest");

        interp.state.combat = true;
        check(winner("F1") == 2, "the wider condition did not win in combat");

        interp.state.stealth = true;
        check(winner("F1") == 1, "the narrower condition lost to the wider one");
        interp:resetState();
    end);

    ---------------------------------------------------------------------------
    -- How the key is wired
    ---------------------------------------------------------------------------

    --- Which of the two the key came out as. Read off the tables the restricted side actually
    --- holds, rather than the copies baked beside them.
    local function wiring(key)
        local button = Constants.CLICKTIME_BUTTON_PREFIX .. key;
        return {
            clickTime = interp.env.ClickTimeKeys[button] ~= nil,
            bound = interp.bindings[key] ~= nil,
        };
    end

    -- A key that only click-casts holds no key-binding record at all, so it must not be bound: the
    -- world click and the camera stay the game's.
    test("a click-casting-only key is not bound", function()
        Bind({
            action({ value = 585, key = "BUTTON2", unit = "unitframe",
                conditions = { units = { unitframe = { reaction = Constants.REACTION_ALL } } } }),
        });

        local how = wiring("BUTTON2");
        check(not how.clickTime, "a click-cast-only key was registered as a click-time key");
        check(not how.bound, "a click-cast-only key was bound");

        -- It is registered where a click that arrives on a unit frame can find it, which is the
        -- one table it does belong in.
        check(interp.env.ClickCastKeys[2] and interp.env.ClickCastKeys[2][0],
            "the click-cast registration is missing");
    end);

    -- **A click that arrives on a unit frame judges the conditions on the frame**, not from the
    -- hover cache -- the frame that was clicked is the hover, so there is nothing to look up.
    -- Answering nil is the fall-through: the click carries on into the frame's own handler, which
    -- is only reachable from that side.
    test("a click-cast click is judged against the frame it arrived on", function()
        Bind({
            action({ value = 585, key = "BUTTON2", unit = "unitframe",
                conditions = { units = { unitframe = { reaction = Constants.REACTION_HELP } } } }),
        });

        shim.world.units = { party1 = { id = "friend", reaction = "help" } };
        check(interp:evalClickCast(unitFrame, 2, 0), "a friendly unit frame was declined");

        shim.world.units = { party1 = { id = "enemy", reaction = "harm" } };
        check(interp:evalClickCast(unitFrame, 2, 0) == nil,
            "a hostile unit frame was taken by a friendly condition");

        shim.world.units = {};
        check(interp:evalClickCast(unitFrame, 2, 0) == nil, "an empty unit frame was taken");
    end);

    ---------------------------------------------------------------------------
    -- Self cast and focus cast (`implementing-focus-and-self-cast.md`)
    ---------------------------------------------------------------------------

    --- Two actions on F1: a heal that asks for a friendly target, and a plain one behind it. Both
    --- aim at `target`, so a press with nothing held goes where they say.
    local function ModifierBind()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
            action({ value = 774, key = "F1" }),
        });
    end

    --- What a press fires: the record, the spell on the button it clicks, and the unit it goes at.
    local function Fired(key)
        local _, button, record, unit = interp:evalKey(key);
        if (not button) then
            return nil;
        end
        -- **겨눈 대상은 평가가 낸 것을 읽는다.** 감싼 버튼으로 나가는 누름만 그 값을 캐스트
        -- 프레임에 얹으므로, 프레임에서 읽으면 안 감싼 누름은 늘 대상이 없어 보인다.
        return record, DebindPrivate.DefaultClickFrame:GetAttribute("*spell-" .. interp:actionButton(button)),
            unit;
    end

    -- **A held key moves an action with no target, and the reader's condition goes with it** (§3-6).
    -- The `@` that asked whether the target is friendly asks it of the player once self cast is held
    -- -- so the heal goes out at a friendly player over a hostile target, and a hostile player falls
    -- to the next action, still at the player.
    test("a held self-cast modifier sends the press at the player", function()
        ModifierBind();
        shim.world.units = { target = { id = "enemy", reaction = "harm" },
            player = { id = "me", reaction = "help" } };

        check(winner("F1") == 2, "nothing held, hostile target: " .. tostring(winner("F1")));

        interp.state.modifiedClick.SELFCAST = true;
        local record, spell, unit = Fired("F1");
        check(record and record.castModifier == Constants.CASTMOD_SELF,
            "the winner is not a self twin: " .. tostring(record and record.castModifier));
        check(spell == "Renew" and unit == "player", "fired " .. tostring(spell) .. " at " .. tostring(unit));

        shim.world.units.player = { id = "me", reaction = "harm" };
        record, spell, unit = Fired("F1");
        check(spell == "Rejuvenation" and unit == "player",
            "a hostile player: fired " .. tostring(spell) .. " at " .. tostring(unit));

        interp:resetState();
        shim.world.units = {};
    end);

    -- **Focus cast never falls back to the target** (§3-2). The first action's condition fails on
    -- a hostile focus, and what wins is the next action's focus twin -- not the first action at the
    -- friendly target the press would have reached with nothing held.
    test("a held focus-cast modifier keeps to the focus", function()
        ModifierBind();
        shim.world.units = { target = { id = "friend", reaction = "help" },
            focus = { id = "enemy", reaction = "harm" } };

        check(winner("F1") == 1, "nothing held, friendly target: " .. tostring(winner("F1")));

        interp.state.modifiedClick.FOCUSCAST = true;
        local record, spell, unit = Fired("F1");
        check(record and record.castModifier == Constants.CASTMOD_FOCUS,
            "the winner is not a focus twin: " .. tostring(record and record.castModifier));
        check(spell == "Rejuvenation" and unit == "focus",
            "fired " .. tostring(spell) .. " at " .. tostring(unit));

        interp:resetState();
        shim.world.units = {};
    end);

    -- **With no target picked, `@` is asked of `target`, and the press still carries no unit**
    -- (§3-6). The game keeps deciding where the cast goes; the condition only decides whether this
    -- action is the one that goes. The shape the decision was made on: an attack for enemies ahead
    -- of a heal, where a friendly target has to fall through to the heal.
    test("with no target picked the resolved target's condition is asked of the target", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM } } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = { target = { id = "friend", reaction = "help" } };
        check(winner("F1") == 2, "a friendly target: " .. tostring(winner("F1")));

        shim.world.units = { target = { id = "enemy", reaction = "harm" } };
        check(winner("F1") == 1, "a hostile target: " .. tostring(winner("F1")));
        local _, button, record = interp:evalKey("F1");
        check(record and record.unit == nil and record.unitAlias == nil,
            "the press carries a unit: " .. tostring(record and (record.unit or record.unitAlias)));
        check(button == interp:actionButton(button), "the press took the route that turns Auto Self Cast off");

        shim.world.units = {};
    end);

    -- **`@` is the unit the press aims at, whether or not the action uses it** (2026-09-15, owner).
    -- A macro takes no unit, but its focus twin still goes out at the focus, so its condition asks
    -- the focus; with nothing held it asks the target, as it does on a spell with none picked.
    test("a macro's resolved unit condition follows the held key", function()
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ type = Constants.MACROTEXT, value = "/say hi", key = "F1",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
            action({ value = 774, key = "F1" }),
        });

        local function firedMacro()
            local _, button = interp:evalKey("F1");
            return button ~= nil
                and DebindPrivate.DefaultClickFrame:GetAttribute("*type-" .. interp:actionButton(button)) == "macro";
        end

        shim.world.units = { target = { id = "enemy", reaction = "harm" },
            focus = { id = "friend", reaction = "help" } };
        check(winner("F1") == 2, "nothing held, hostile target: " .. tostring(winner("F1")));

        shim.world.units.target = { id = "friend", reaction = "help" };
        check(winner("F1") == 1, "nothing held, friendly target: " .. tostring(winner("F1")));

        shim.world.units.target = { id = "enemy", reaction = "harm" };
        interp.state.modifiedClick.FOCUSCAST = true;
        check(firedMacro(), "focus held, friendly focus: the macro did not go");

        shim.world.units.focus = { id = "enemy", reaction = "harm" };
        check(not firedMacro(), "focus held, hostile focus: the macro went");

        interp:resetState();
        shim.world.units = {};
    end);

    -- The client's own order: `checkselfcast` is read first and ends it (§3-3).
    test("both modifiers held is self cast", function()
        ModifierBind();
        shim.world.units = { player = { id = "me", reaction = "help" },
            focus = { id = "friend", reaction = "help" } };

        interp.state.modifiedClick.SELFCAST = true;
        interp.state.modifiedClick.FOCUSCAST = true;
        local _, spell, unit = Fired("F1");
        check(spell == "Renew" and unit == "player", "fired " .. tostring(spell) .. " at " .. tostring(unit));

        interp:resetState();
        shim.world.units = {};
    end);

    -- **A key turned off in the settings is a key not held** (§3-12). The self twin is gone and the
    -- press does not ask about the key, so the heal that needs a friendly target falls to the next
    -- action with no unit; the Focus Cast Key, left on, still goes to the focus.
    --
    -- The unit is read off the record, not the cast frame: a press with no unit never writes that
    -- frame, and what it holds is whatever the press before it left.
    test("a cast key turned off counts as not held", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        local actions = {
            action({ value = 585, key = "F1",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
            action({ value = 774, key = "F1" }),
        };
        Bind(actions, nil, { selfCast = false });
        shim.world.units = { target = { id = "enemy", reaction = "harm" },
            player = { id = "me", reaction = "help" }, focus = { id = "friend", reaction = "help" } };

        interp.state.modifiedClick.SELFCAST = true;
        local record, spell, unit = Fired("F1");
        check(record and record.castModifier == Constants.CASTMOD_NONE,
            "self cast off: the winner carries " .. tostring(record and record.castModifier));
        check(spell == "Rejuvenation" and record.unit == nil,
            "self cast off: fired " .. tostring(spell) .. " at " .. tostring(record and record.unit));
        for _, r in ipairs(interp:recordsFor("F1")) do
            check(r.castModifier ~= Constants.CASTMOD_SELF, "a self record is still on the key");
        end

        interp.state.modifiedClick.FOCUSCAST = true;
        record, spell, unit = Fired("F1");
        check(spell == "Renew" and unit == "focus",
            "self cast off, both held: fired " .. tostring(spell) .. " at " .. tostring(unit));

        Bind(actions, nil, { focusCast = false });
        interp.state.modifiedClick.FOCUSCAST = true;
        record, spell, unit = Fired("F1");
        check(spell == "Rejuvenation" and record.unit == nil,
            "focus cast off: fired " .. tostring(spell) .. " at " .. tostring(record and record.unit));

        interp:resetState();
        shim.world.units = {};
    end);

    -- **An action that sits a cast key out, and one that keeps its turn on it** (§6). The first
    -- action carries the value and wants a friendly target; the second carries neither. Neither has
    -- a unit picked, since a picked unit is not moved by the key in the first place. With a friendly
    -- target and the key held, Skip this action sends the second at you or your focus, and Cast as
    -- usual sends the first where it goes with no key held. With a hostile target the first fails
    -- either way. Units are read off the record, which a press with no unit leaves empty.
    test("an action that skips a cast key, or casts as usual on it", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        local ok, err = pcall(function()
            for _, case in ipairs({
                { row = "selfCastKey", key = "SELFCAST", unit = "player" },
                { row = "focusCastKey", key = "FOCUSCAST", unit = "focus" },
            }) do
                for _, mode in ipairs({
                    { "skip", "skip", "Rejuvenation", case.unit },
                    { "usual", "usual", "Renew", nil },
                }) do
                    local first = action({ value = 585, key = "F1",
                        casting = { [case.row] = mode[1] },
                        conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } });
                    Bind({ first, action({ value = 774, key = "F1" }) });
                    interp.state.modifiedClick[case.key] = true;
                    local label = case.row .. ", " .. mode[2];

                    shim.world.units = { target = { id = "friend", reaction = "help" },
                        player = { id = "me", reaction = "help" }, focus = { id = "other", reaction = "help" } };
                    local record, spell = Fired("F1");
                    local unit = record and record.unit;
                    check(spell == mode[3] and unit == mode[4],
                        label .. ", friendly target: fired " .. tostring(spell) .. " at " .. tostring(unit));

                    shim.world.units.target = { id = "enemy", reaction = "harm" };
                    record, spell = Fired("F1");
                    unit = record and record.unit;
                    check(spell == "Rejuvenation" and unit == case.unit,
                        label .. ", hostile target: fired " .. tostring(spell) .. " at " .. tostring(unit));

                    interp:resetState();
                end
            end
        end);
        shim.world.units = {};
        if (not ok) then
            error(err, 0);
        end
    end);

    -- **A held key does not move a unit the reader picked** (2026-09-15, owner). A modifier carried
    -- over from the key pressed before reads as held (ALT-1, then 2), and moving a picked unit on it
    -- sends the action somewhere nobody chose. The client's own buttons never let a held key move a
    -- unit set on them. The action keeps its turn in the held tier, so the action with no target
    -- behind it gets the press only where the first one's condition fails, and goes where the key
    -- sends it.
    test("a held key does not move a picked unit", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
            action({ value = 774, key = "F1" }),
        });

        for _, case in ipairs({ { "SELFCAST", "player" }, { "FOCUSCAST", "focus" } }) do
            shim.world.units = { target = { id = "friend", reaction = "help" },
                player = { id = "me", reaction = "harm" }, focus = { id = "other", reaction = "harm" } };
            interp.state.modifiedClick[case[1]] = true;
            local _, spell, unit = Fired("F1");
            check(spell == "Renew" and unit == "target",
                case[1] .. ", friendly target: fired " .. tostring(spell) .. " at " .. tostring(unit));

            shim.world.units.target = { id = "enemy", reaction = "harm" };
            _, spell, unit = Fired("F1");
            check(spell == "Rejuvenation" and unit == case[2],
                case[1] .. ", hostile target: fired " .. tostring(spell) .. " at " .. tostring(unit));
            interp:resetState();
        end

        shim.world.units = {};
    end);

    -- **A frame click ignores what is held** (§3-10). A modifier on a click arrives only with the
    -- binding made for that exact combination, so it picked the binding and says nothing about the
    -- target. The click goes at the frame's unit whatever `IsModifiedClick` answers.
    test("a frame click goes at the frame with a modifier held", function()
        Bind({
            action({ value = 585, key = "BUTTON2", unit = "unitframe",
                conditions = { units = { unitframe = { reaction = Constants.REACTION_HELP } } } }),
        });
        shim.world.units = { party1 = { id = "friend", reaction = "help" },
            player = { id = "me", reaction = "help" }, focus = { id = "friend", reaction = "help" } };
        interp.state.modifiedClick.SELFCAST = true;
        interp.state.modifiedClick.FOCUSCAST = true;

        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1", "the frame click was declined");
        local handed = interp.env.HandoffWinner;
        check(handed and not castmod.isTwin(Constants, handed),
            "a twin took the frame click: " .. tostring(handed and handed.castModifier));
        interp:runWrapped(DebindPrivate.DefaultClickFrame, "OnClick", "debind1", false);
        -- **맨이름 `unit`이 겨눈 대상이 서는 자리다.** 캐스트 프레임은 감싼 버튼으로 나가는
        -- 누름만 거치고, 이 액션은 값을 하나도 안 켜서 평범한 버튼으로 나간다.
        local unit = DebindPrivate.DefaultClickFrame:GetAttribute("unit");
        check(unit == "party1", "the click went at " .. tostring(unit));

        interp:resetState();
        shim.world.units = {};
    end);

    ---------------------------------------------------------------------------
    -- The key laid out in tiers (`implementing-focus-and-self-cast.md` §3-4)
    ---------------------------------------------------------------------------

    local FRIEND = { id = "friend", reaction = "help" };
    local ENEMY = { id = "enemy", reaction = "harm" };

    --- The unit a record goes out at, whichever field carries it.
    local function Aimed(record)
        return record and (record.unit or record.unitAlias);
    end

    --- Which of the key's originals a winning record came from, by the button both click.
    local function ActionOf(key, record)
        local originals = castmod.without(Constants, interp:recordsFor(key));
        for i = 1, #originals do
            if (originals[i].clickbutton == record.clickbutton) then
                return i;
            end
        end
    end

    local function PointAt(unit)
        unitFrame:SetAttribute("unit", unit);
        interp:hoverEnter(unitFrame);
    end

    -- **Every hover twin stands ahead of every original** (§3-4, 2026-09-13, owner). An attack for
    -- hostile units ahead of a heal for friendly ones, neither with a target picked, Hover Cast on.
    -- With each twin beside its own original, a press over a friendly frame with a hostile target
    -- reached the attack's original before the heal's twin, and the attack went at the target; over
    -- a hostile frame with a friendly target the attack went at the frame. One key, two rules.
    test("a pointed unit is tried for every action before any target is", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1", casting = { hoverCast = "cast" },
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM } } } }),
            action({ value = 774, key = "F1", casting = { hoverCast = "cast" },
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
        });

        shim.world.units = { target = ENEMY, party1 = FRIEND };
        PointAt("party1");
        local record, spell = Fired("F1");
        check(spell == "Rejuvenation" and Aimed(record) == "unitframe",
            "hostile target, friendly frame: fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));

        shim.world.units = { target = FRIEND, party1 = ENEMY };
        record, spell = Fired("F1");
        check(spell == "Renew" and Aimed(record) == "unitframe",
            "friendly target, hostile frame: fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));

        interp:hoverLeave(unitFrame);
        shim.world.units = {};
    end);

    -- **The hover tier stands in the originals' order** (§3, 2026-09-16, owner). Ordered by each
    -- twin's own condition, the twin of the action with the wider condition stood behind the other
    -- whichever the reader had put first, and the drawn order said otherwise. Both actions here are
    -- conditional and at the same importance, so nothing but the reader's own order can split them.
    test("hover twins keep the order the reader put the actions in", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        for _, case in ipairs({ { "plain", "Rejuvenation" }, { "hover", "Renew" } }) do
            local plain = { value = 774, key = "F1", casting = { hoverCast = "cast" },
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } };
            local hovered = { value = 585, key = "F1", casting = { hoverCast = "cast" },
                conditions = { units = { unitframe = { exists = true,
                    reaction = Constants.REACTION_HELP } } } };
            if (case[1] == "plain") then
                Bind({ action(plain), action(hovered) });
            else
                Bind({ action(hovered), action(plain) });
            end
            shim.world.units = { party1 = FRIEND };
            PointAt("party1");
            local record, spell = Fired("F1");
            check(spell == case[2] and Aimed(record) == "unitframe",
                case[1] .. " first: fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));
            interp:hoverLeave(unitFrame);
        end
        shim.world.units = {};
    end);

    -- **An action that takes no unit has the twins too** (§3-4). Placed first, a macro carried no
    -- modifier column and answered every held modifier, so nothing behind it could be focus cast.
    -- A held modifier is now answered in its own tier: the spell's twin where its condition holds on
    -- the focus, and otherwise the macro's -- carrying `focus`, which is what lets the client's own
    -- `UnitExists` guard stop it where there is no focus, as it does on an action bar.
    test("a macro placed ahead of a spell answers a held focus cast key as a focus cast", function()
        shim.world.spells[585] = { name = "Renew" };
        Bind({
            action({ type = Constants.MACROTEXT, value = "/say hi", key = "F1" }),
            action({ value = 585, key = "F1",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
        });
        interp.state.modifiedClick.FOCUSCAST = true;

        for _, case in ipairs({ { FRIEND, 1, "a friendly focus" }, { ENEMY, 2, "a hostile focus" },
                { nil, 2, "no focus" } }) do
            shim.world.units = { focus = case[1] };
            local _, _, record = interp:evalKey("F1");
            check(record and record.castModifier == Constants.CASTMOD_FOCUS,
                case[3] .. ": the winner is not a focus twin: " .. tostring(record and record.castModifier));
            check(ActionOf("F1", record) == case[2] and Aimed(record) == "focus",
                case[3] .. ": action " .. tostring(ActionOf("F1", record)) .. " at " .. tostring(Aimed(record)));
        end

        interp:resetState();
        shim.world.units = {};
    end);

    -- The same for a pet command whose handler takes no unit. Whether a focus exists is the client's
    -- guard to ask, so both answers pick the same twin here.
    test("a pet command that takes no unit is focus cast like any action", function()
        _G.SLASH_PET_FOLLOW1 = "/petfollow";
        Bind({ action({ type = Constants.PETACTION, value = "PET_FOLLOW", key = "F1" }) });
        interp.state.modifiedClick.FOCUSCAST = true;

        for _, focus in ipairs({ false, true }) do
            shim.world.units = { focus = focus and FRIEND or nil };
            local _, _, record = interp:evalKey("F1");
            check(record and record.castModifier == Constants.CASTMOD_FOCUS and Aimed(record) == "focus",
                "focus " .. tostring(focus) .. ": " .. tostring(record and record.castModifier)
                    .. " at " .. tostring(Aimed(record)));
        end

        interp:resetState();
        shim.world.units = {};
    end);

    -- **`@@` in a macro body is where the press aims** (§4). The twins pass a unit whether or not the
    -- action reads it, and this is how a body reads it: the self twin's `player`, the focus twin's
    -- `focus`, the hover twin's pointed unit, and on the original `target`, the unit a press with no
    -- key held goes at.
    --
    -- A switch expression has no one press to aim with (its value is worked out once for the whole
    -- press, before any winner), so there it stays as written.
    test("@@ in a macro body is the unit the press aims at", function()
        shim.world.spells[585] = { name = "Renew" };
        Bind({
            action({ type = Constants.MACROTEXT, value = "/cast [@@,help] Renew", key = "F1",
                casting = { hoverCast = "cast" } }),
            -- Only a switch some action names is compiled at all.
            action({ value = 585, key = "F2", conditions = { ["$state1"] = true } }),
        }, {
            ["$state1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[@@,combat]" },
        });
        shim.world.units = { focus = FRIEND, party1 = FRIEND };

        local function body(label)
            local _, _, record = interp:evalKey("F1");
            check(record and record.clickbutton, label .. ": nothing won");
            return DebindPrivate.DefaultClickFrame:GetAttribute("*macrotext-" .. record.clickbutton);
        end

        local text = body("no key held");
        check(text == "/cast [@target,help]Renew", "no key held: " .. tostring(text));

        interp.state.modifiedClick.SELFCAST = true;
        text = body("self cast key");
        check(text == "/cast [@player,help]Renew", "self cast key: " .. tostring(text));
        interp.state.modifiedClick.SELFCAST = nil;

        interp.state.modifiedClick.FOCUSCAST = true;
        text = body("focus cast key");
        check(text == "/cast [@focus,help]Renew", "focus cast key: " .. tostring(text));
        interp.state.modifiedClick.FOCUSCAST = nil;

        PointAt("party1");
        text = body("pointed at party1");
        check(text == "/cast [@party1,help]Renew", "pointed at party1: " .. tostring(text));
        interp:hoverLeave(unitFrame);

        -- The press is what composes a switch's expression, so the string it hands the parser is
        -- where "as written" is visible.
        local before = interp:parseCount("[@@,combat]");
        interp:evalKey("F2");
        check(interp:parseCount("[@@,combat]") > before,
            "the press worked the switch out from something other than the expression as written");

        interp:resetState();
        shim.world.units = {};
    end);

    -- **`none` has every twin and every one of them asks** (§3-4). Its twins stand in each tier the
    -- way any action's do, so an Always Ask action put first keeps the key whatever is held or
    -- pointed at -- and the cast still asks for a unit.
    test("an Always Ask action placed first answers a held key and a pointed unit by asking", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1", unit = "none", priority = Constants.MIN_IMPORTANCE,
                casting = { hoverCast = "cast" } }),
            action({ value = 774, key = "F1", casting = { hoverCast = "cast" } }),
        });
        shim.world.units = { focus = FRIEND, party1 = FRIEND };

        interp.state.modifiedClick.FOCUSCAST = true;
        local record, spell = Fired("F1");
        check(spell == "Renew" and Aimed(record) == "none",
            "focus cast key: fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));
        interp:resetState();

        PointAt("party1");
        record, spell = Fired("F1");
        check(spell == "Renew" and Aimed(record) == "none",
            "pointing: fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));

        interp:hoverLeave(unitFrame);
        shim.world.units = {};
    end);

    -- **Cast as usual still stands in the pointed tier** (§6). It goes out where the press would send
    -- it with nothing pointed at; with no twin at all it would wait in the last tier and the Hover
    -- Cast action behind it would take every press made over a unit, whatever the reader put first.
    test("an action that casts as usual placed first keeps a pointed press at its own target", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1", priority = Constants.MIN_IMPORTANCE,
                casting = { hoverCast = "usual" } }),
            action({ value = 774, key = "F1", casting = { hoverCast = "cast" } }),
        });
        shim.world.units = { target = FRIEND, party1 = FRIEND };

        PointAt("party1");
        local record, spell = Fired("F1");
        check(spell == "Renew" and Aimed(record) == nil,
            "fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));

        interp:hoverLeave(unitFrame);
        shim.world.units = {};
    end);

    -- **[when there is none] on the pointed unit takes the action out of the pointed press** (§6).
    -- Alone on the key it answers nothing while a unit frame is pointed at and runs once nothing is;
    -- with a Hover Cast action behind it, that one takes the pointed press.
    test("an action with the pointed unit [none] does not run while a unit frame is pointed at", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        local function noFrame()
            return { units = { unitframe = false } };
        end
        Bind({
            action({ value = 585, key = "F1", conditions = noFrame() }),
        });
        shim.world.units = { target = FRIEND, party1 = FRIEND };

        PointAt("party1");
        local _, spell = Fired("F1");
        check(spell == nil, "alone, pointing: fired " .. tostring(spell));
        interp:hoverLeave(unitFrame);
        _, spell = Fired("F1");
        check(spell == "Renew", "alone, nothing pointed at: fired " .. tostring(spell));

        Bind({
            action({ value = 585, key = "F1", priority = Constants.MAX_IMPORTANCE,
                conditions = noFrame() }),
            action({ value = 774, key = "F1", casting = { hoverCast = "cast" } }),
        });
        PointAt("party1");
        _, spell = Fired("F1");
        check(spell == "Rejuvenation", "with a Hover Cast action behind, pointing: fired " .. tostring(spell));

        interp:hoverLeave(unitFrame);
        shim.world.units = {};
    end);

    -- **Hover Cast does not move a unit the reader picked** (2026-09-15, owner). An action aimed at
    -- the target keeps going there over a frame, and still takes the pointed press ahead of the action
    -- with no target behind it.
    test("a pointed press leaves a picked unit where it is", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1", unit = "target", casting = { hoverCast = "cast" } }),
            action({ value = 774, key = "F1", casting = { hoverCast = "cast" } }),
        });
        shim.world.units = { target = FRIEND, party1 = FRIEND };

        PointAt("party1");
        local record, spell = Fired("F1");
        check(spell == "Renew" and Aimed(record) == "target",
            "fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));

        interp:hoverLeave(unitFrame);
        shim.world.units = {};
    end);

    -- **`none` is aimed like an action with no target, and only the cast asks** (2026-09-15, owner).
    -- It settles nothing before the press, so its Resolved Unit condition is asked of the target with
    -- nothing held, of you or your focus with a key held, and of the unit pointed at; whichever of its
    -- bindings wins goes out as `none`, and one that fails hands the press to the action behind it.
    test("an Always Ask action's resolved unit condition follows the key and the pointer", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1", unit = "none", casting = { hoverCast = "cast" },
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
            action({ value = 774, key = "F1", casting = { hoverCast = "cast" } }),
        });

        local function Press(label, units, held, expectSpell, expectAimed)
            shim.world.units = units;
            if (held) then
                interp.state.modifiedClick[held] = true;
            end
            local record, spell, castUnit = Fired("F1");
            check(spell == expectSpell and Aimed(record) == expectAimed,
                label .. ": fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));
            if (expectAimed == "none") then
                check(castUnit == "none", label .. ": the cast frame's unit is " .. tostring(castUnit));
            end
            if (held) then
                interp.state.modifiedClick[held] = nil;
            end
        end

        Press("nothing held, friendly target", { target = FRIEND }, nil, "Renew", "none");
        Press("nothing held, hostile target", { target = ENEMY }, nil, "Rejuvenation", nil);
        Press("self cast, friendly player", { target = ENEMY, player = FRIEND }, "SELFCAST", "Renew", "none");
        Press("self cast, hostile player", { target = FRIEND, player = ENEMY }, "SELFCAST", "Rejuvenation", "player");
        Press("focus cast, friendly focus", { target = ENEMY, focus = FRIEND }, "FOCUSCAST", "Renew", "none");
        Press("focus cast, hostile focus", { target = FRIEND, focus = ENEMY }, "FOCUSCAST", "Rejuvenation", "focus");

        PointAt("party1");
        Press("pointing at a friend", { target = ENEMY, party1 = FRIEND }, nil, "Renew", "none");
        Press("pointing at an enemy", { target = FRIEND, party1 = ENEMY }, nil, "Rejuvenation", "unitframe");
        interp:hoverLeave(unitFrame);

        interp:resetState();
        shim.world.units = {};
    end);

    ---------------------------------------------------------------------------
    -- Which edge of the click we take
    ---------------------------------------------------------------------------

    -- **Which edges arrive is the frame's state and not ours.** `RegisterForClicks` is set on the
    -- frame, so the last addon to call it decides for every wrapper on it, and a frame we put on
    -- the release can be moved to the press behind our back. `FrameRegistry` therefore asks for
    -- both, and the wrapper has to answer for both. Three rules come out of that, one test each:
    --
    --   * the release is the edge we act on, which is the one every unit frame Blizzard ships is
    --     registered for (`SecureUnitButton_OnLoad`);
    --   * a click we are not taking is left alone on both edges, so the frame's own action runs
    --     exactly where it would have;
    --   * a click we *are* taking is swallowed on the press as well, or the frame acts on the
    --     press and we act on the release and one click casts twice.
    --
    -- These run the shipped wrapper body (`interp:clickFrame`), not `EVAL_SNIPPET` with the
    -- prologue replaced -- the prologue is the whole of what is being asked about here.
    --- The reader's answer, put in the way the options menu puts it. `nil` is one of the three and
    --- means the game decides, so the CVar it falls to is set here alongside it.
    local function SetClickEdge(value, useKeyDown)
        DebindPrivate.Options.unitframeUseMouseDown = value;
        shim.world.cvars.ActionButtonUseKeyDown = useKeyDown;

        local mark = frames.mark();
        DebindPrivate.ApplyOptions("unitframeUseMouseDown");
        interp:replay(frames.since(mark));
    end

    local function ClickCastBind()
        Bind({
            action({ value = 585, key = "BUTTON2", unit = "unitframe",
                conditions = { units = { unitframe = { reaction = Constants.REACTION_HELP } } } }),
            -- A second button, for the case where two are held at once.
            action({ value = 585, key = "BUTTON1", unit = "unitframe",
                conditions = { units = { unitframe = { reaction = Constants.REACTION_HELP } } } }),
        });
        shim.world.units = { party1 = { id = "friend", reaction = "help" } };
        -- Nothing chosen and the game's own setting off, which is where a fresh install stands.
        SetClickEdge(nil, nil);
    end

    test("the release fires the binding", function()
        ClickCastBind();
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1",
            "the release did not take the click");
    end);

    -- `debindnull` is a suffix nobody wrote an attribute for, so the press is taken and nothing
    -- runs on it -- the frame's own `type1` included.
    test("the press of a click we take is swallowed", function()
        ClickCastBind();
        check(interp:clickFrame(unitFrame, "RightButton", true) == "debindnull",
            "the press was left for the frame's own action");
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1",
            "the release did not fire after its press was swallowed");
    end);

    -- **Both edges of a click we decline are left alone**, so the frame keeps whichever one it
    -- acts on. Answering the press with `debindnull` here would eat clicks we have no binding for.
    test("a click we decline is left alone on both edges", function()
        ClickCastBind();
        shim.world.units = { party1 = { id = "enemy", reaction = "harm" } };
        check(interp:clickFrame(unitFrame, "RightButton", true) == nil,
            "the press of a declined click was swallowed");
        check(interp:clickFrame(unitFrame, "RightButton", false) == nil,
            "the release of a declined click was swallowed");
    end);

    -- A button we bound nothing to is declined the same way, and never reaches the eval at all.
    test("a button with no binding is left alone on both edges", function()
        ClickCastBind();
        check(interp:clickFrame(unitFrame, "MiddleButton", true) == nil,
            "the press of an unbound button was swallowed");
        check(interp:clickFrame(unitFrame, "MiddleButton", false) == nil,
            "the release of an unbound button was swallowed");
    end);

    -- **Nothing is carried between buttons.** Two held at once interleave their presses and
    -- releases, and each has to be judged where it stands.
    test("two buttons held at once each resolve on their own release", function()
        ClickCastBind();
        check(interp:clickFrame(unitFrame, "LeftButton", true) == "debindnull",
            "the first press was not swallowed");
        check(interp:clickFrame(unitFrame, "RightButton", true) == "debindnull",
            "the second press was not swallowed");
        check(interp:clickFrame(unitFrame, "LeftButton", false) == "debind1",
            "the first button did not fire on its release");
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1",
            "the second button did not fire on its release");
    end);


    -- **And which edge that is, is the reader's.** The wrapper reads one boolean; folding the
    -- three answers onto it is `ApplyOptions`', and the restricted side cannot read a CVar for
    -- itself. The swallowing goes with it: whichever edge is not the one we act on.
    test("choosing the press moves both the firing and the swallowing", function()
        ClickCastBind();
        SetClickEdge(true, nil);
        check(interp:clickFrame(unitFrame, "RightButton", true) == "debind1",
            "the press did not fire once it was chosen");
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debindnull",
            "the release was left for the frame's own action");
    end);

    -- The third answer: the reader has chosen nothing, so the game's own keybind setting decides.
    test("leaving it to the game follows the game's setting", function()
        ClickCastBind();
        SetClickEdge(nil, true);
        check(interp:clickFrame(unitFrame, "RightButton", true) == "debind1",
            "the press did not fire with the game's setting on");

        SetClickEdge(nil, false);
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1",
            "the release did not fire with the game's setting off");
    end);

    -- And an answer of their own outranks it, or the third answer would be the only one there is.
    test("a chosen edge outranks the game's setting", function()
        ClickCastBind();
        SetClickEdge(false, true);
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1",
            "the release did not fire though it was the one chosen");
        check(interp:clickFrame(unitFrame, "RightButton", true) == "debindnull",
            "the press fired against the reader's answer");
    end);

    --- The same answer given during a lockdown, and the fight ending after it.
    ---
    --- Answers how much crossed while the lockdown was up, and replays whatever crosses when it
    --- lifts. The push is the only thing the wrapper reads, so a value that never crosses is a
    --- value the reader does not have.
    --- **The login is fired first because nothing listens for the fight ending before it.**
    --- `PLAYER_REGEN_ENABLED` is registered in the login handler, so a spec that only sends the
    --- second one measures nothing at all and goes green on a broken addon.
    local function SetClickEdgeInCombat(apply)
        DebindPrivate.ShowMigrationDialogIfPending =
            DebindPrivate.ShowMigrationDialogIfPending or function() end;
        check(frames.fireEvent("PLAYER_LOGIN") > 0, "nothing is listening for PLAYER_LOGIN");

        shim.world.inCombat = true;
        local mark = frames.mark();
        apply();
        local crossed = #frames.since(mark);

        shim.world.inCombat = false;
        mark = frames.mark();
        check(frames.fireEvent("PLAYER_REGEN_ENABLED") > 0,
            "nothing is listening for PLAYER_REGEN_ENABLED");
        interp:replay(frames.since(mark));
        return crossed;
    end

    -- **`SecureHandlerExecute` cannot cross a lockdown, and nothing else pushes this value.** So an
    -- answer given in combat reached nothing and stayed unreached for the session, while the menu
    -- went on showing it as the one chosen. It waits for the end of the fight now.
    test("an edge chosen in combat is pushed when the fight ends", function()
        ClickCastBind();
        DebindPrivate.Options.unitframeUseMouseDown = true;
        check(SetClickEdgeInCombat(function()
            DebindPrivate.ApplyOptions("unitframeUseMouseDown");
        end) == 0, "the push crossed during the lockdown");

        check(interp:clickFrame(unitFrame, "RightButton", true) == "debind1",
            "the answer given in combat never reached the wrapper");
    end);

    -- The same road for the third answer, which the game moves rather than the reader. A CVar can
    -- be set in a fight, and `Events.CVAR_UPDATE` re-resolves the edge off it through this same
    -- call. **What waits is the fact that a push is owed, not the value**, so the answer that
    -- crosses is the one standing when the fight ends.
    test("the game's setting moving in combat is followed when the fight ends", function()
        ClickCastBind();
        DebindPrivate.Options.unitframeUseMouseDown = nil;
        check(SetClickEdgeInCombat(function()
            shim.world.cvars.ActionButtonUseKeyDown = true;
            DebindPrivate.ApplyOptions("unitframeUseMouseDown");
            shim.world.cvars.ActionButtonUseKeyDown = false;
            DebindPrivate.ApplyOptions("unitframeUseMouseDown");
            shim.world.cvars.ActionButtonUseKeyDown = true;
            DebindPrivate.ApplyOptions("unitframeUseMouseDown");
        end) == 0, "a push crossed during the lockdown");

        check(interp:clickFrame(unitFrame, "RightButton", true) == "debind1",
            "the setting that moved in combat never reached the wrapper");
    end);

    ---------------------------------------------------------------------------
    -- Four axes over seven records
    ---------------------------------------------------------------------------

    -- **One condition on one key proves almost nothing.** Every fault worth finding is past that
    -- line: a key carrying several records, each naming several axes, where exactly one has to
    -- win. This sweeps the full cross product of four axes over a seven-record key.
    --
    -- **The expectations are derived from the same definition the actions are**, because a
    -- mistranscribed row reads exactly like a bug in the addon. And the sweep checks two things
    -- about itself, or it goes green measuring nothing: that the emitted record count still
    -- matches (an index means nothing once the solver drops one and shifts the rest), and that
    -- every record won at least once (a record no combination can reach is a hole, not a pass).
    --
    -- **This one stays in `/debtest` as well.** It is the anchor: four axes over seven records is
    -- where a difference between this interpretation and the real environment would show
    -- (`going-headless-outside-the-ui.md` §9).
    test("the press picks the exact record out of seven", function()
        --- The key's records, in order, each as the world it needs. `nil` means the axis is not
        --- named by that record.
        local ROWS = {
            { combat = true, stealth = true, group = "raid", petbattle = false },
            { combat = true, stealth = true },
            { combat = true, group = "raid" },
            { combat = true },
            { stealth = true, petbattle = true },
            { group = "raid" },
            {},
        };

        local actions = {};
        for i = 1, #ROWS do
            local row = ROWS[i];
            local conditions = {};
            if (row.combat ~= nil) then conditions.combat = row.combat; end
            if (row.stealth ~= nil) then conditions.stealth = row.stealth; end
            if (row.petbattle ~= nil) then conditions.petbattle = row.petbattle; end
            if (row.group ~= nil) then conditions.groups = Constants.GROUP_RAID; end
            actions[i] = action({ value = 100 + i, key = "F1", conditions = conditions });
        end
        Bind(actions);

        local records = castmod.without(Constants, interp:recordsFor("F1"));
        check(records and #records == #ROWS,
            "records emitted: " .. tostring(records and #records) .. " of " .. #ROWS);

        --- Which row the definition says should win in a given world. The same walk the snippet
        --- does, written from the rows rather than from the snippet.
        local function expected(world)
            for i = 1, #ROWS do
                local row = ROWS[i];
                local matched = true;
                if (row.combat ~= nil and row.combat ~= world.combat) then matched = false; end
                if (row.stealth ~= nil and row.stealth ~= world.stealth) then matched = false; end
                if (row.petbattle ~= nil and row.petbattle ~= world.petbattle) then matched = false; end
                if (row.group ~= nil and world.group ~= "raid") then matched = false; end
                if (matched) then
                    return i;
                end
            end
        end

        local won = {};
        local combinations = 0;
        for combat = 0, 1 do
            for stealth = 0, 1 do
                for petbattle = 0, 1 do
                    for grouped = 0, 1 do
                        local world = {
                            combat = combat == 1,
                            stealth = stealth == 1,
                            petbattle = petbattle == 1,
                            group = grouped == 1 and "raid" or "none",
                        };
                        interp:resetState();
                        interp.state.combat = world.combat;
                        interp.state.stealth = world.stealth;
                        interp.state.petbattle = world.petbattle;
                        interp.state.group = world.group;

                        combinations = combinations + 1;
                        local got = winner("F1");
                        local want = expected(world);
                        check(got == want, ("combat=%s stealth=%s petbattle=%s group=%s: got %s, want %s")
                            :format(tostring(world.combat), tostring(world.stealth),
                                tostring(world.petbattle), world.group,
                                tostring(got), tostring(want)));
                        if (got) then
                            won[got] = true;
                        end
                    end
                end
            end
        end

        check(combinations == 16, "combinations swept: " .. combinations);
        for i = 1, #ROWS do
            check(won[i], "record " .. i .. " never won -- the sweep cannot reach it");
        end
        interp:resetState();
    end);

    ---------------------------------------------------------------------------
    -- `which-action-a-key-runs.md` §S5: one row, one test
    --
    -- Written from the table and not from the code: each row's action, press and answer are the
    -- row's own. "Next" is the action alone on its key, so the answer is that nothing fires.
    ---------------------------------------------------------------------------

    do
        local NAMES = { [701] = "A", [702] = "B", [703] = "X" };
        for id, name in pairs(NAMES) do
            shim.world.spells[id] = { name = name };
        end

        --- An action as the profile stores it, with Hover Cast on. **The rows are about the pointed
        --- press**, so "기본" here means the action answers it at the pointed unit; a row that turns
        --- Hover Cast off writes that for itself.
        local function A(fields)
            local t = { type = Constants.SPELL, value = 701, key = "F1", seq = 1 };
            for k, v in pairs(fields or {}) do
                t[k] = v;
            end
            if (t.casting == nil) then
                t.casting = {};
            end
            -- **`false` is this helper's word for off**, which is stored as nothing at all: written
            -- as nil a row could not tell "leave it off" from "say nothing and get the default".
            if (t.casting.hoverCast == false) then
                t.casting.hoverCast = nil;
            elseif (t.casting.hoverCast == nil) then
                t.casting.hoverCast = "cast";
            end
            return t;
        end

        --- The pointed unit's world. The frame's unit is `party1`, and over a frame the mouseover
        --- unit is that same unit, as the client has it.
        local function PointFrame(unit)
            shim.world.units.party1 = unit or FRIEND;
            shim.world.units.mouseover = unit or FRIEND;
            PointAt("party1");
        end
        local function PointWorld()
            interp:clearHoverSlot();
            shim.world.units.mouseover = ENEMY;
        end
        local function PointNothing()
            interp:clearHoverSlot();
            shim.world.units.mouseover = nil;
        end

        local HELD = { self = { "SELFCAST" }, focus = { "FOCUSCAST" }, both = { "SELFCAST", "FOCUSCAST" } };

        --- Presses `key` and answers the spell's name, the unit the record aims at, and which of the
        --- action's bindings the record is: `self`, `focus`, `hover` (it stands on [H is there]) or
        --- `original`.
        local function Press(key, held, H)
            for _, name in ipairs(HELD[held] or {}) do
                interp.state.modifiedClick[name] = true;
            end
            local record, spell = Fired(key);
            for _, name in ipairs(HELD[held] or {}) do
                interp.state.modifiedClick[name] = nil;
            end
            if (not record) then
                return nil;
            end
            local kind = "original";
            local units = record.units;
            if (record.castModifier == Constants.CASTMOD_SELF) then
                kind = "self";
            elseif (record.castModifier == Constants.CASTMOD_FOCUS) then
                kind = "focus";
            elseif (units and units[H] and units[H].exists == true) then
                kind = "hover";
            end
            return spell, Aimed(record), kind;
        end

        --- A click that arrives on the frame, answered with the spell's name or nil.
        local function Click(n)
            local button = interp:evalClickCast(unitFrame, n, 0);
            if (not button) then
                return nil;
            end
            return DebindPrivate.DefaultClickFrame:GetAttribute("*spell-" .. interp:actionButton(button));
        end

        local function Expect(row, got, want)
            local g = table.concat({ tostring(got[1]), tostring(got[2]), tostring(got[3]) }, " / ");
            local w = table.concat({ tostring(want[1]), tostring(want[2]), tostring(want[3]) }, " / ");
            check(g == w, "#" .. row .. ": got " .. g .. ", want " .. w);
        end

        local function Row(n, fn)
            test("§S5 #" .. n, function()
                shim.world.units = { target = FRIEND, player = FRIEND, focus = FRIEND };
                local ok, err = pcall(fn);
                interp:clearHoverSlot();
                interp:resetState();
                shim.world.units = {};
                if (not ok) then
                    error(err, 0);
                end
            end);
        end

        local MOUSEOVER = { hoverCastMode = "mouseover" };

        Row(1, function()
            Bind({ A() });
            PointFrame();
            Expect(1, { Press("F1", nil, "unitframe") }, { "A", "unitframe", "hover" });
        end);
        Row(2, function()
            Bind({ A() });
            PointWorld();
            Expect(2, { Press("F1", nil, "unitframe") }, { "A", nil, "original" });
        end);
        Row(3, function()
            Bind({ A() }, nil, MOUSEOVER);
            PointWorld();
            Expect(3, { Press("F1", nil, "mouseover") }, { "A", "mouseover", "hover" });
        end);
        Row(4, function()
            Bind({ A({ casting = { hoverCastMode = "mouseover" } }) });
            PointWorld();
            Expect(4, { Press("F1", nil, "mouseover") }, { "A", "mouseover", "hover" });
        end);
        Row(5, function()
            Bind({ A({ casting = { hoverCast = "usual" } }) });
            PointFrame();
            Expect(5, { Press("F1", nil, "unitframe") }, { "A", nil, "hover" });
        end);
        Row(6, function()
            Bind({ A({ conditions = { units = { unitframe = false } } }) });
            PointFrame();
            Expect(6, { Press("F1", nil, "unitframe") }, {});
        end);
        Row(7, function()
            Bind({ A({ conditions = { units = { unitframe = false } } }) });
            PointNothing();
            Expect(7, { Press("F1", nil, "unitframe") }, { "A", nil, "original" });
        end);
        Row(8, function()
            Bind({ A({ conditions = { units = { mouseover = false } } }) }, nil, MOUSEOVER);
            PointWorld();
            Expect(8, { Press("F1", nil, "mouseover") }, {});
        end);
        --- **[when there is none] is a condition, so it reaches every press**, the held ones too. Off
        --- is the value that takes only the pointed press away, and no value takes the pointed press
        --- away while leaving the held ones: a condition is the only thing that can say "not while a
        --- frame is pointed at", and conditions are inherited by every twin.
        Row(9, function()
            local subject = A({ conditions = { units = { unitframe = false } },
                casting = { hoverCast = "cast" } });
            Bind({ subject });
            PointFrame(ENEMY);
            Expect(9, { Press("F1", nil, "unitframe") }, {});
            Expect(9, { Press("F1", "self", "unitframe") }, {});
            Expect(9, { Press("F1", "focus", "unitframe") }, {});
            PointNothing();
            Expect(9, { Press("F1", nil, "unitframe") }, { "A", nil, "original" });
            check(DebindPrivate.GetBindingIssue(subject) == nil,
                "#9: an issue was raised: " .. tostring(DebindPrivate.GetBindingIssue(subject)));
        end);
        Row(10, function()
            Bind({ A({ casting = { normalCast = false } }) });
            PointNothing();
            Expect(10, { Press("F1", nil, "unitframe") }, {});
        end);
        Row(11, function()
            Bind({ A({ casting = { normalCast = false } }) });
            PointFrame();
            Expect(11, { Press("F1", nil, "unitframe") }, { "A", "unitframe", "hover" });
        end);
        Row(12, function()
            Bind({ A({ conditions = { units = { unitframe = {} } } }) });
            PointNothing();
            Expect(12, { Press("F1", nil, "unitframe") }, {});
        end);
        Row(13, function()
            Bind({ A({ conditions = { units = { unitframe = {} } } }) });
            PointFrame();
            Expect(13, { Press("F1", nil, "unitframe") }, { "A", "unitframe", "hover" });
        end);
        Row(14, function()
            Bind({ A({ conditions = { units = { unitframe = false } } }) });
            PointFrame();
            Expect(14, { Press("F1", nil, "unitframe") }, {});
        end);
        Row(15, function()
            Bind({ A({ conditions = { units = { unitframe = false } } }) }, nil, MOUSEOVER);
            PointWorld();
            Expect(15, { Press("F1", nil, "mouseover") }, { "A", "mouseover", "hover" });
        end);
        Row(16, function()
            Bind({ A({ unit = "focus" }) });
            PointFrame();
            Expect(16, { Press("F1", nil, "unitframe") }, { "A", "focus", "hover" });
        end);
        Row(17, function()
            Bind({ A({ unit = "focus" }) });
            PointNothing();
            Expect(17, { Press("F1", "self", "unitframe") }, { "A", "focus", "self" });
        end);
        Row(18, function()
            Bind({ A({ value = 703, seq = 1 }), A({ unit = "mouseover", seq = 2 }) });
            PointWorld();
            Expect(18, { Press("F1", nil, "unitframe") }, { "X", nil, "original" });
        end);
        Row(19, function()
            Bind({ A({ value = 703, seq = 1 }),
                A({ unit = "mouseover", seq = 2, casting = { hoverCastMode = "mouseover" } }) });
            PointWorld();
            Expect(19, { Press("F1", nil, "mouseover") }, { "A", "mouseover", "hover" });
        end);
        Row(20, function()
            Bind({ A({ unit = "unitframe" }) });
            PointNothing();
            Expect(20, { Press("F1", nil, "unitframe") }, { "A", "unitframe", "original" });
        end);
        Row(21, function()
            Bind({ A() });
            PointNothing();
            Expect(21, { Press("F1", "self", "unitframe") }, { "A", "player", "self" });
        end);
        Row(22, function()
            Bind({ A() });
            PointNothing();
            Expect(22, { Press("F1", "focus", "unitframe") }, { "A", "focus", "focus" });
        end);
        Row(23, function()
            Bind({ A() });
            PointNothing();
            Expect(23, { Press("F1", "both", "unitframe") }, { "A", "player", "self" });
        end);
        Row(24, function()
            Bind({ A({ casting = { selfCastKey = "skip" } }) });
            PointNothing();
            Expect(24, { Press("F1", "self", "unitframe") }, {});
        end);
        Row(25, function()
            Bind({ A({ casting = { selfCastKey = "usual" } }) });
            PointNothing();
            Expect(25, { Press("F1", "self", "unitframe") }, { "A", nil, "self" });
        end);
        Row(26, function()
            Bind({ A() }, nil, { focusCast = false });
            PointNothing();
            Expect(26, { Press("F1", "focus", "unitframe") }, { "A", nil, "original" });
        end);

        local function AB(order, bCasting)
            local a = A({ value = 701 });
            local b = A({ value = 702, casting = bCasting });
            if (order == "AB") then
                a.seq, b.seq = 1, 2;
            else
                a.seq, b.seq = 2, 1;
            end
            return { a, b };
        end
        Row(27, function()
            Bind(AB("AB", { hoverCast = false }));
            PointFrame();
            Expect(27, { Press("F1", nil, "unitframe") }, { "A", "unitframe", "hover" });
        end);
        Row(28, function()
            Bind(AB("BA", { hoverCast = false }));
            PointFrame();
            Expect(28, { Press("F1", nil, "unitframe") }, { "A", "unitframe", "hover" });
        end);
        Row(29, function()
            Bind(AB("BA", { hoverCast = false }));
            PointNothing();
            Expect(29, { Press("F1", nil, "unitframe") }, { "B", nil, "original" });
        end);

        --- A in the account layer on [a unit frame is there], B in the character layer in combat.
        local function Layered(bCasting)
            _G.DebindVars = nil;
            local a = A({ value = 701, conditions = { units = { unitframe = {} } } });
            local b = A({ value = 702, conditions = { combat = true }, casting = bCasting });
            local mark = frames.mark();
            _G.DebindVars = {
                dbver = Constants.DB_VERSION,
                shared = { GENERAL = { a }, classes = { [Constants.PLAYER_CLASS] = {} } },
                characters = { [GUID] = { layers = { [0] = { b } }, switches = {} } },
                migrated = {},
                switches = {},
            };
            DebindPrivate.InitDB();
            check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
            interp:replay(frames.since(mark));
            interp:resetState();
            interp.state.combat = true;
        end
        Row(30, function()
            Layered(nil);
            PointFrame();
            Expect(30, { Press("F1", nil, "unitframe") }, { "B", "unitframe", "hover" });
        end);
        Row(31, function()
            Layered({ hoverCast = "usual" });
            PointFrame();
            Expect(31, { Press("F1", nil, "unitframe") }, { "B", nil, "hover" });
        end);
        Row(32, function()
            Layered({ hoverCast = false });
            PointFrame();
            Expect(32, { Press("F1", nil, "unitframe") }, { "A", "unitframe", "hover" });
        end);

        Row(33, function()
            Bind({ A({ key = "BUTTON4" }) });
            PointFrame();
            check(Click(4) == "A", "#33: the frame click fired " .. tostring(Click(4)));
        end);
        Row(34, function()
            Bind({ A({ key = "BUTTON4", casting = { hoverCast = false } }) });
            PointFrame();
            check(Click(4) == nil, "#34: the frame click fired " .. tostring(Click(4)));
        end);
        Row(35, function()
            Bind({ A({ key = "BUTTON4" }) });
            PointNothing();
            Expect(35, { Press("BUTTON4", nil, "unitframe") }, { "A", nil, "original" });
        end);
        Row(36, function()
            Bind({ A({ key = "BUTTON4", conditions = { units = { unitframe = { reaction = Constants.REACTION_HARM } } } }) });
            PointFrame(ENEMY);
            check(Click(4) == "A", "#36: the frame click fired " .. tostring(Click(4)));
        end);
        Row(37, function()
            Bind({ A({ key = "BUTTON4", conditions = { units = { unitframe = { reaction = Constants.REACTION_HARM } } } }) });
            PointFrame(FRIEND);
            check(Click(4) == nil, "#37: the frame click fired " .. tostring(Click(4)));
        end);
        Row(38, function()
            Bind({ A({ key = "BUTTON4" }) });
            PointFrame();
            interp.state.modifiedClick.SELFCAST = true;
            check(Click(4) == "A", "#38: the frame click fired " .. tostring(Click(4)));
        end);
        Row(39, function()
            Bind({ A({ type = Constants.MACROTEXT, value = "/cast [@@] A" }) });
            PointFrame();
            local record = select(3, interp:evalKey("F1"));
            check(record and Aimed(record) == "unitframe",
                "#39: the macro's record aims at " .. tostring(record and Aimed(record)));
        end);
        --- **`"@"` is asked of the frame's unit**, which a Resolved Unit condition shows: friendly on the
        --- frame against a hostile target, it holds.
        Row(40, function()
            Bind({ A({ unit = "none", conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }) });
            shim.world.units.target = ENEMY;
            PointFrame(FRIEND);
            local record, spell, castUnit = Fired("F1");
            check(spell == "A" and castUnit == "none" and record.units.unitframe
                    and record.units.unitframe.exists == true,
                "#40: fired " .. tostring(spell) .. " cast at " .. tostring(castUnit));
        end);
        Row(41, function()
            local subject = A({ casting = { normalCast = false, hoverCast = false,
                selfCastKey = "skip", focusCastKey = "skip" } });
            Bind({ subject });
            PointFrame();
            Expect(41, { Press("F1", nil, "unitframe") }, {});
            PointNothing();
            Expect(41, { Press("F1", nil, "unitframe") }, {});
            Expect(41, { Press("F1", "self", "unitframe") }, {});
            Expect(41, { Press("F1", "focus", "unitframe") }, {});
            check(DebindPrivate.GetBindingIssue(subject) == Constants.BINDING_ISSUE_NOTHING_RUNS,
                "#41: the issue is " .. tostring(DebindPrivate.GetBindingIssue(subject)));
            check(DebindPrivate.GetNotRunningReason(subject) == nil,
                "#41: the reason is " .. tostring(DebindPrivate.GetNotRunningReason(subject)));
        end);
        Row(42, function()
            Bind({ A({ casting = { normalCast = false, hoverCast = false,
                selfCastKey = "skip", focusCastKey = "skip" } }) });
            check(_G.GetBindingAction("F1", true) == "CLICK " .. DebindPrivate.DefaultClickFrame:GetName()
                    .. ":" .. Constants.CLICKTIME_BUTTON_PREFIX .. "F1",
                "#42: the key is bound to " .. tostring(_G.GetBindingAction("F1", true)));
            check(DebindPrivate.IsKeyOurs("F1"), "#42: IsKeyOurs says no");
            PointNothing();
            Expect(42, { Press("F1", nil, "unitframe") }, {});
        end);
        Row(43, function()
            Bind({ A({ key = "BUTTON1", casting = { normalCast = false, hoverCast = false,
                selfCastKey = "skip", focusCastKey = "skip" } }) });
            check((_G.GetBindingAction("BUTTON1", true) or "") == "",
                "#43: the key is bound to " .. tostring(_G.GetBindingAction("BUTTON1", true)));
            check(not DebindPrivate.IsKeyOurs("BUTTON1"), "#43: IsKeyOurs says yes");
        end);
        Row(44, function()
            local subject = A({ key = "BUTTON1" });
            Bind({ subject });
            check(DebindPrivate.GetBindingIssue(subject) == nil,
                "#44: the issue is " .. tostring(DebindPrivate.GetBindingIssue(subject)));
            PointFrame();
            check(Click(1) == "A", "#44: the frame click fired " .. tostring(Click(1)));
            interp.state.modifiedClick.SELFCAST = true;
            check(Click(1) == "A", "#44: the frame click with Self Cast Key held fired " .. tostring(Click(1)));
        end);
        Row(45, function()
            Bind({ A({ key = "BUTTON1" }) });
            check((_G.GetBindingAction("BUTTON1", true) or "") == "",
                "#45: the key is bound to " .. tostring(_G.GetBindingAction("BUTTON1", true)));
            check(not DebindPrivate.IsKeyOurs("BUTTON1"), "#45: IsKeyOurs says yes");
        end);
        Row(46, function()
            for _, bound in ipairs({
                { actions = { A({ key = "BUTTON2", casting = { hoverCastMode = "mouseover" } }) } },
                { actions = { A({ key = "BUTTON2" }) }, options = MOUSEOVER },
            }) do
                Bind(bound.actions, nil, bound.options);
                check(DebindPrivate.GetBindingIssue(bound.actions[1]) == nil,
                    "#46: the issue is " .. tostring(DebindPrivate.GetBindingIssue(bound.actions[1])));
                check((_G.GetBindingAction("BUTTON2", true) or "") == "",
                    "#46: the key is bound to " .. tostring(_G.GetBindingAction("BUTTON2", true)));
                PointFrame();
                check(Click(2) == "A", "#46: the frame click fired " .. tostring(Click(2)));
                interp:clearHoverSlot();
            end
        end);
        --- **The bare click cannot be turned off, so [when there is none] is what empties it**, and
        --- that is the key and a condition disagreeing rather than a reason (S5 #48).
        Row(47, function()
            local subject = A({ key = "BUTTON1", conditions = { units = { unitframe = false } } });
            Bind({ subject });
            check((_G.GetBindingAction("BUTTON1", true) or "") == "",
                "#47: the key is bound to " .. tostring(_G.GetBindingAction("BUTTON1", true)));
            PointFrame();
            check(Click(1) == nil, "#47: the frame click fired " .. tostring(Click(1)));
            check(DebindPrivate.GetBindingIssue(subject) == Constants.BINDING_ISSUE_KEY_RULED_OUT,
                "#47: the issue is " .. tostring(DebindPrivate.GetBindingIssue(subject)));
            check(DebindPrivate.GetNotRunningReason(subject) == nil,
                "#47: the reason is " .. tostring(DebindPrivate.GetNotRunningReason(subject)));
        end);

        --- **The move answers like the rows it names** (§S5, last paragraph). The profile is written
        --- at `dbver` 6, so the ladder is what turns each old action into its new shape.
        ---
        --- **`casting` comes off first.** These actions are what the ladder is handed, and an old
        --- profile has no such table; leaving `A`'s in would hand the migration a shape it is meant
        --- to produce.
        local function BindOld(actions)
            for i = 1, #actions do
                actions[i].casting = nil;
            end
            local mark = frames.mark();
            _G.DebindVars = {
                dbver = 6,
                shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
                characters = { [GUID] = { layers = {}, switches = {} } },
                migrated = {},
                switches = {},
            };
            DebindPrivate.InitDB();
            check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
            interp:replay(frames.since(mark));
            interp:resetState();
        end
        Row("move: an old unit frame condition", function()
            BindOld({ A({ conditions = { units = { hover = {} } } }) });
            PointFrame();
            Expect("move 13", { Press("F1", nil, "unitframe") }, { "A", "unitframe", "hover" });
            PointNothing();
            Expect("move 10", { Press("F1", nil, "unitframe") }, {});
        end);
        --- **An old action with no unit frame condition is moved with Hover Cast off**, which is what
        --- it did: the pointed press reaches its original in the last tier and goes to its own
        --- target, and the mouse button keeps the key's own [no unit frame] (§8).
        Row("move: an old keyboard action", function()
            BindOld({ A() });
            PointFrame();
            Expect("move 5", { Press("F1", nil, "unitframe") }, { "A", nil, "original" });
            PointNothing();
            Expect("move 7", { Press("F1", nil, "unitframe") }, { "A", nil, "original" });
        end);
        Row("move: an old mouse button action", function()
            BindOld({ A({ key = "BUTTON4" }) });
            PointFrame();
            check(Click(4) == nil, "move 34: the frame click fired " .. tostring(Click(4)));
            PointNothing();
            Expect("move 35", { Press("BUTTON4", nil, "unitframe") }, { "A", nil, "original" });
        end);

        -----------------------------------------------------------------------
        -- No role picked (`reorganizing-binding-issues.md` §3-6)
        --
        -- **A role is only measured on a party or raid frame.** Everywhere else the condition has no
        -- say, so an empty one stops the action on those frames and nowhere else. Asked of the press
        -- itself, since what the issue check and the binding decide has to agree with it.
        -----------------------------------------------------------------------

        --- A frame click on `frame`, answered with the spell's name or nil.
        local function ClickOn(frame)
            local button = interp:evalClickCast(frame, 3, 0);
            if (not button) then
                return nil;
            end
            return DebindPrivate.DefaultClickFrame:GetAttribute("*spell-" .. interp:actionButton(button));
        end

        local function RoleRow(name, frameTypes, onParty, onPlayer)
            Row("role: " .. name, function()
                Bind({ A({ key = "BUTTON3", conditions = { units = { unitframe = {
                    role = 0, frameTypes = frameTypes } } } }) });
                shim.world.units.party1 = FRIEND;
                interp.env.UnitRoles = { party1 = "tank" };
                local party, player = ClickOn(unitFrame), ClickOn(playerFrame);
                interp.env.UnitRoles = false;
                check(party == onParty, name .. ": over the party frame fired " .. tostring(party));
                check(player == onPlayer, name .. ": over the player frame fired " .. tostring(player));
            end);
        end

        RoleRow("no role, every frame type", nil, nil, "A");
        RoleRow("no role, player and party frames", Constants.FRAMETYPE_PLAYER + Constants.FRAMETYPE_GROUP,
            nil, "A");
        RoleRow("no role, no party frames", Constants.FRAMETYPE_PLAYER, nil, "A");
        RoleRow("no role, party frames only", Constants.FRAMETYPE_GROUP, nil, nil);
    end

    return T;
end
