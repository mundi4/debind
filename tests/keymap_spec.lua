-- **What `BuildKeyMap` hands out for one key.** No WoW client needed.
--
-- The specs beside this one stop a step short of it on purpose: `normalize_spec` reads the binding
-- `GetBindingInfoForAction` makes from one action, `ordering_spec` reads the comparator, `solver_spec`
-- reads the boxes. This reads the list a key actually ends up with -- the same walk, run whole.
--
-- **Two walks cross this profile and they must not disagree.** `CollectActionsForKey` is the list
-- the window draws and `BuildKeyMap` is the list the key fires from, and a reader shown one order
-- while the key runs another has no way to find out. So the cases here read `KeyMap` and the cases
-- in `renumber_spec` read both.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local castmod = require("castmod");
    local band, bor = bit.band, bit.bor;

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

    local ME = "Player-1-KEYMAP";

    --- **Hover Cast는 기본값 그대로 꺼져 있다.** 대부분의 케이스가 재는 것은 한 키의 순서이고,
    --- 켜져 있으면 액션마다 쌍둥이가 하나씩 더 서서 목록이 두 배가 된다 (`tests/casting.lua`).
    --- 층을 재는 케이스만 켠다.
    local function Bind(actions, switches, options, hoverCast)
        if (hoverCast) then
            require("casting").castOnHoverAll(actions);
        end
        _G.UnitGUID = function() return ME; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [ME] = { layers = {}, switches = {} } },
            migrated = {},
            switches = switches or {},
            options = options,
        };
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
    end

    --- The records the key came out with, or nil where it came out with none. The self and focus
    --- twins are left out; the one case that is about them reads `KeyMap` itself.
    local function Records(key)
        return castmod.without(Constants, DebindPrivate.KeyMap[key]);
    end

    local function Values(key)
        local records = Records(key);
        if (not records) then return "<none>"; end
        local out = {};
        for i = 1, #records do out[i] = tostring(records[i].value); end
        return table.concat(out, " ");
    end

    ---------------------------------------------------------------------------
    -- What a record carries out
    ---------------------------------------------------------------------------

    -- **A saved `UNUSED` or `COMMAND` stands on the key as a BLOCK**, and the action keeps the type
    -- it was saved with (`dropping-the-game-fallback.md` §3). Nothing after it on the key
    -- can fire, so it has to reach the key rather than be left out.
    test("an unused or command action stands on the key as a block", function()
        local unused = { type = Constants.UNUSED, key = "F1", seq = 1 };
        local command = { type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = "F2", seq = 2 };
        Bind({ unused, command });

        for key, stored in pairs({ F1 = unused, F2 = command }) do
            local list = DebindPrivate.KeyMap[key];
            local original;
            for i = 1, #(list or {}) do
                if (not castmod.isTwin(Constants, list[i])) then
                    original = list[i];
                end
            end
            check(original, key .. ": the action did not reach the key");
            check(original.type == Constants.BLOCK, key .. ": it came out as " .. tostring(original.type));
            check(stored.type ~= Constants.BLOCK, key .. ": the stored action was rewritten");
            check(DebindPrivate.GetBindingIssue(stored) == Constants.BINDING_ISSUE_TYPE_RETIRED,
                key .. ": the row is not marked");
        end
    end);

    -- **A saved BLOCK is the reader's own, not a retired type.** It stands on the key the same way,
    -- and nothing under it on that key fires, which is the whole of what the reader picked it for.
    -- The mark is what tells the two apart: a retired type is red because there is nothing the
    -- reader can do with it, and this one is not.
    test("a block action stands on the key and closes it", function()
        local block = { type = Constants.BLOCK, key = "F1", seq = 1 };
        local under = { type = Constants.SPELL, value = 585, key = "F1", seq = 2 };
        Bind({ block, under });

        local list = DebindPrivate.KeyMap.F1 or {};
        local first, spell;
        for i = 1, #list do
            if (not castmod.isTwin(Constants, list[i])) then
                first = first or list[i];
                spell = spell or (list[i].value == 585 and list[i] or nil);
            end
        end
        check(first, "the action did not reach the key");
        check(first.type == Constants.BLOCK, "it came out as " .. tostring(first.type));
        check(DebindPrivate.GetBindingIssue(block) == nil,
            "the row is marked: " .. tostring(DebindPrivate.GetBindingIssue(block)));
        check(not spell, "the action under it is still on the key");
    end);

    -- **The strongest outcome among an action's issues is the one it gets.** A retired type stays
    -- on its key as a block; a condition no state can meet leaves it out. Carrying both, it is left
    -- out: folded by grade instead, the two tie and whichever check is written first decides
    -- (`reorganizing-binding-issues.md` §3-1).
    test("a retired type carrying an issue that leaves it out is left out", function()
        -- Special bar against pet battle, on purpose: that check runs after the retired type's, so a
        -- fold that keeps the first of equals keeps the wrong one, and it leaves the binding standing,
        -- so nothing but the outcome can take it off the key.
        local retired = { type = Constants.UNUSED, key = "F1", seq = 1,
            conditions = { specialbar = true, petbattle = false } };
        Bind({ retired });
        -- Read off `KeyMap` itself: a block is not a record `Records` hands back.
        local list = DebindPrivate.KeyMap.F1 or {};
        check(#list == 0, "it reached the key as " .. #list .. " bindings");
    end);

    -- **A hover condition is two answers, and both ride the record.** Which reactions the frame's
    -- unit may have, and which kinds of frame count at all. Either one lost leaves a key that fires
    -- over frames the reader excluded, and nothing says so.
    test("a hover condition carries its reactions and its frame types", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "BUTTON3", seq = 1,
                conditions = {
                    units = { unitframe = {
                        reaction = bor(Constants.REACTION_HELP, Constants.REACTION_HARM),
                        frameTypes = Constants.FRAMETYPE_GROUP,
                    } },
                } },
        });

        local record = Records("BUTTON3") and Records("BUTTON3")[1];
        check(record, "the hover record did not reach the key");

        local unitframe = record.conditions.units and record.conditions.units.unitframe;
        check(type(unitframe) == "table", "the unitframe condition came out as " .. tostring(unitframe));
        check(band(unitframe.reaction, Constants.REACTION_HELP) ~= 0, "the friendly bit is gone");
        check(band(unitframe.reaction, Constants.REACTION_HARM) ~= 0, "the hostile bit is gone");
        check(record.unitFrameTypes == Constants.FRAMETYPE_GROUP,
            "frameTypes came out as " .. tostring(record.unitFrameTypes));
    end);

    -- **Five axes at once, which is what a real profile looks like.** One condition on one key only
    -- answers "does it look at conditions at all"; a record dropping *one* of several is the shape
    -- that gets through, and it widens the binding rather than narrowing it.
    test("every condition on one record reaches the key", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "HOME", seq = 1,
                conditions = {
                    combat = true,
                    groups = Constants.GROUP_RAID,
                    stealth = false,
                    mounted = true,
                    ["$state2"] = true,
                } },
        }, { ["$state2"] = { mode = Constants.SWITCH_MODES.MANUAL } });

        local record = Records("HOME") and Records("HOME")[1];
        check(record, "the record did not reach the key");
        local c = record.conditions;
        check(c.combat == true, "combat: " .. tostring(c.combat));
        check(c.groups == Constants.GROUP_RAID, "groups: " .. tostring(c.groups));
        -- `false` is "when there is not", which is a point on the axis and not an absence.
        check(c.stealth == false, "stealth: " .. tostring(c.stealth));
        check(c.mounted == true, "mounted: " .. tostring(c.mounted));
        check(c["$state2"] == true, "$state2: " .. tostring(c["$state2"]));
    end);

    -- **A record is a pure derivation of one action**, and the numbers that order it are not: where
    -- an action stands is a fact about the profile around it, so `Misc.MakeOrderRecord` holds those
    -- beside the record rather than on it.
    --
    -- **Going back is silent.** `BuildKeyMap` used to write these fields on and nobody wiped them,
    -- so they survived to the next rebuild and the second writer agreed with the first. The order
    -- stays right; what stops being true is "a record tells you its action", and no screen says so.
    test("a record carries no ordering fields", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", priority = 5, seq = 1 },
            { type = Constants.SPELL, value = 116, key = "F1", priority = 1, seq = 2,
                conditions = { combat = true } },
        });

        local records = Records("F1");
        check(records and #records == 2, "expected two records, got " .. Values("F1"));
        for i = 1, #records do
            for _, field in ipairs({ "layerRank", "specRank", "seq", "isConditional", "priority" }) do
                check(records[i][field] == nil,
                    "record " .. i .. " carries " .. field .. "=" .. tostring(records[i][field]));
            end
        end
    end);

    ---------------------------------------------------------------------------
    -- Which record goes first
    ---------------------------------------------------------------------------

    -- **A conditional record goes ahead of an unconditional one on the same key**, whatever order
    -- they were written in. The other way round the unconditional one matches everything and the
    -- conditional one below it can never be reached -- the reader's narrower answer would be the
    -- one that never runs.
    test("a conditional record comes before an unconditional one", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "DELETE", seq = 1 },
            { type = Constants.SPELL, value = 116, key = "DELETE", seq = 2,
                conditions = { combat = true } },
        });
        check(Values("DELETE") == "116 585", "the order came out " .. Values("DELETE"));
    end);

    -- **A condition on the resolved target makes the action conditional, target or not.** An
    -- action with no target and nothing but that condition used to read as unconditional, so it sat
    -- behind an unconditional one placed earlier, and that one's self twin covered its own: held or
    -- not, the key never reached it (`implementing-focus-and-self-cast.md` §3-6).
    test("a resolved target condition with no target picked sorts as conditional", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "DELETE", seq = 1 },
            { type = Constants.SPELL, value = 116, key = "DELETE", seq = 2,
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } },
        });
        check(Values("DELETE") == "116 585", "the order came out " .. Values("DELETE"));
    end);

    -- **An ignored Switch still makes its action conditional in the order** (`MakeOrderRecord`).
    -- Ignoring drops the condition from the binding, so the action fires on every press; standing
    -- in front, it covers the one behind it and that one leaves the key. Read as unconditional it
    -- would stand behind on `seq`, and the two would be the other way round.
    test("an ignored Switch still sorts as conditional", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "DELETE", seq = 1 },
            { type = Constants.SPELL, value = 116, key = "DELETE", seq = 2,
                conditions = { ["$burst"] = true } },
        }, { ["$burst"] = { mode = Constants.SWITCH_MODES.IGNORE } });
        check(DebindPrivate.IsSwitchIgnored("$burst"), "setup: the Switch is not ignored");
        check(Values("DELETE") == "116", "the order came out " .. Values("DELETE"));
    end);

    -- **What arrives keeps the sender's key and the sender's order.** The badge is the only thing
    -- holding it out of the build, so the key it names is a real one -- and once the badge comes off
    -- the order the set was sent in is the order it fires in.
    --
    -- **The stored array is deliberately out of step with it.** If the two agreed, this would be
    -- measuring the array's order rather than the order that arrived.
    test("an accepted arrival fires in the order it was sent in", function()
        local third = { type = Constants.SPELL, value = 3, key = "F4", arrivalID = 1, seq = 3,
            conditions = { combat = true } };
        local first = { type = Constants.SPELL, value = 1, key = "F4", arrivalID = 1, seq = 1,
            conditions = { stealth = true } };
        local second = { type = Constants.SPELL, value = 2, key = "F4", arrivalID = 1, seq = 2,
            conditions = { mounted = true } };
        Bind({ third, first, second });

        check(Records("F4") == nil, "a badged set stood on the key it arrived on");

        local group = DebindPrivate.CollectKeyGroupActions("F4", 1);
        check(#group == 3, "the set did not come back together: " .. #group);

        DebindPrivate.SetKeyForActions(group, "F4");
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        check(Values("F4") == "1 2 3", "the sender's order was not kept: " .. Values("F4"));
    end);

    ---------------------------------------------------------------------------
    -- What never reaches the key
    ---------------------------------------------------------------------------

    -- **An imported string plants no switch definitions**, so an on/off/toggle action arriving from
    -- somebody else can name a switch this profile has never had. Nothing about the row says so;
    -- what says so is the action going red and dropping out of the build.
    --
    -- **The passing half first.** Without it a missing key reads as "switch actions do not bind at
    -- all" rather than as the marker doing its job.
    test("a setstate action naming an undefined switch reaches no key", function()
        Bind({
            { type = Constants.SETSTATE_TOGGLE, value = "$defined", key = "F1", seq = 1 },
            { type = Constants.SETSTATE_TOGGLE, value = "$nodefinition", key = "F2", seq = 2 },
        }, { ["$defined"] = { mode = Constants.SWITCH_MODES.MANUAL } });

        check(Records("F1"), "an action naming a defined switch was kept out too -- bad premise");
        check(Records("F2") == nil, "an action naming nothing that exists bound anyway");

        check(DebindPrivate.GetBindingIssue({ type = Constants.SETSTATE_TOGGLE,
            value = "$nodefinition", key = "F2" }) == Constants.BINDING_ISSUE_UNDEFINED_STATE,
            "the row is drawn as though nothing were wrong with it");
    end);

    ---------------------------------------------------------------------------
    -- One action, two records (`splitting-an-action-into-bindings.md`)
    ---------------------------------------------------------------------------

    -- **The key is laid out in tiers**: every self twin, every focus twin, every hover twin, every
    -- original (`which-action-a-key-runs.md` §3). Side by side, an original placed first took
    -- a pointed press before the hover twin of the action behind it had a turn. Action 1 has no hover
    -- twin, since its [when none is pointed at] leaves the twin nothing to match.
    test("the key is laid out in tiers", function()
        Bind({
            { type = Constants.SPELL, value = 1, key = "F1", seq = 1,
                conditions = { units = { unitframe = false }, stealth = true } },
            { type = Constants.SPELL, value = 2, key = "F1", seq = 2, conditions = { combat = true } },
        }, nil, nil, true);

        local records = DebindPrivate.KeyMap["F1"];
        local shape = {};
        for i = 1, #records do
            local record = records[i];
            local tier = (record.castModifier == Constants.CASTMOD_SELF and "self")
                or (record.castModifier == Constants.CASTMOD_FOCUS and "focus")
                or (record.hoverTwin and "hover")
                or "original";
            shape[i] = tier .. ":" .. tostring(record.value);
        end
        shape = table.concat(shape, " ");
        check(shape == "self:1 self:2 focus:1 focus:2 hover:2 original:1 original:2",
            "F1 came out as " .. shape);
    end);

    -- **A mouse button gets its hover twin like every other key** (§3, §7). The original with no unit
    -- frame condition stands on [not pointing] -- that is the key's own rule and not a unit condition
    -- (`BuildUnitStates`) -- so the two never meet: the twin takes the click on a frame and the
    -- original takes the click anywhere else. A type that carries no target is no different; whether
    -- it can use the unit is that action's business.
    test("on a mouse button the hover twin is the frame's record", function()
        Bind({
            { type = Constants.MACROTEXT, value = "/say hi", key = "BUTTON4", seq = 1 },
            { type = Constants.SPELL, value = 585, key = "SHIFT-BUTTON4", seq = 2 },
        }, nil, nil, true);

        for _, key in ipairs({ "BUTTON4", "SHIFT-BUTTON4" }) do
            local records = DebindPrivate.KeyMap[key];
            local frameRecord, plain;
            for i = 1, #(records or {}) do
                if (records[i].hoverTwin) then
                    frameRecord = records[i];
                elseif (records[i].castModifier == Constants.CASTMOD_NONE) then
                    plain = records[i];
                end
            end
            check(frameRecord and frameRecord.isClickCast and frameRecord.unit == "unitframe",
                key .. ": the hover twin is not the frame's record");
            check(plain and plain.isClickCast == false and plain.holdsKey == true,
                key .. ": the original does not hold the key");
        end
    end);

    -- **Every tier is in the originals' order, the hover tier included** (§3, 2026-09-16, owner).
    -- That order is the one the window draws, and an order the reader cannot see is one they cannot
    -- fix. The hover tier used to sort itself by where each twin's own condition would have stood,
    -- so the twin of an action with no condition fell behind every twin that had one -- here, 2
    -- would have come out ahead of 1.
    test("the hover tier stands in the originals' order", function()
        Bind({
            -- Both carry conditions, on different axes. With only one conditional, having
            -- conditions would settle the order before the number is read and this case would not
            -- ask its question; on one axis, the solver would drop one of the two.
            { type = Constants.SPELL, value = 1, key = "F5", seq = 1,
                conditions = { combat = true } },
            { type = Constants.SPELL, value = 2, key = "F5", seq = 2,
                conditions = { units = { unitframe = { exists = true,
                    reaction = Constants.REACTION_HELP } } } },
        }, nil, nil, true);

        local records = DebindPrivate.KeyMap["F5"];
        local order = {};
        for i = 1, #records do
            if (records[i].hoverTwin) then
                order[#order + 1] = tostring(records[i].value);
            end
        end
        check(table.concat(order, " ") == "1 2",
            "the hover tier came out " .. table.concat(order, " "));
    end);

    -- **Normal Cast off leaves the original out of the last tier** (§6), so a press with nothing
    -- held and nothing pointed at falls through to the next action. The twins stay: the action still
    -- takes its turn in the tiers it did not turn off.
    test("normal cast off keeps the action out of the last tier only", function()
        Bind({
            { type = Constants.SPELL, value = 1, key = "F6", seq = 1,
                casting = { normalCast = false } },
            { type = Constants.SPELL, value = 2, key = "F6", seq = 2 },
        }, nil, nil, true);

        check(Values("F6") == "1 2", "the hover tier and the last tier came out " .. Values("F6"));

        local records = DebindPrivate.KeyMap["F6"];
        local last;
        for i = 1, #records do
            if (records[i].castModifier == Constants.CASTMOD_NONE and not records[i].hoverTwin) then
                last = (last and last .. " " or "") .. tostring(records[i].value);
            end
        end
        check(last == "2", "the last tier came out " .. tostring(last));
    end);

    --- **An action the reader turned off reaches no record and hands its key back** (2026-09-18,
    --- 소유자). That last part is what tells it from an action whose presses are all off: there the
    --- key stays held so the next action on it answers, here nobody asked us to hold anything.
    test("an action turned off reaches no record and does not hold its key", function()
        Bind({
            { type = Constants.SPELL, value = 1, key = "F8", seq = 1, disabled = true },
        });
        check(DebindPrivate.KeyMap["F8"] == nil, "the action reached a record");
        check(DebindPrivate.KeysToHold["F8"] == nil, "the key was held");
        check(DebindPrivate.IsKeyHandled("F8") == false, "the key still reads as one we answer");
    end);

    --- 같은 키에 켜진 액션이 있으면 키는 그 액션이 잡는다. 이것이 없으면 위 테스트는 "키를 영영
    --- 안 잡는다"로도 통과한다.
    test("an action turned off leaves the key to the action beside it", function()
        Bind({
            { type = Constants.SPELL, value = 1, key = "F8", seq = 1, disabled = true },
            { type = Constants.SPELL, value = 2, key = "F8", seq = 2 },
        });
        check(Values("F8") == "2", "the key came out " .. Values("F8"));
        check(DebindPrivate.KeysToHold["F8"] == true, "the key was not held");
        check(DebindPrivate.IsKeyHandled("F8") == true, "the key does not read as one we answer");
    end);

    -- **An action with all four values off is not on the key at all** (§6). It keeps its row and its
    -- warning; what it does not keep is a record, so the action behind it answers every press.
    test("an action with nothing left to cast reaches no record", function()
        Bind({
            { type = Constants.SPELL, value = 1, key = "F7", seq = 1,
                casting = { normalCast = false, selfCastKey = "skip", focusCastKey = "skip" } },
            { type = Constants.SPELL, value = 2, key = "F7", seq = 2 },
        });

        local records = DebindPrivate.KeyMap["F7"];
        for i = 1, #(records or {}) do
            check(records[i].value ~= 1, "the action that casts nothing reached the key at " .. i);
        end
        check(Values("F7") == "2", "the key came out " .. Values("F7"));
    end);

    -- **An action that only runs over a frame keeps the bare left button** (§7, §8). That is the shape
    -- a unit frame condition is carried over as -- Hover Cast on Unit Frames with Normal Cast off,
    -- and **no condition left to read it off**. Asked of the condition alone, the whole of a reader's
    -- click casting on BUTTON1 came out red the day their profile moved, and nothing they could do in
    -- the window would have cleared it.
    --
    -- **The self and focus twins have to fall the same way.** They carry no unit frame condition
    -- either, and each one that holds the key takes the world's left click with it.
    test("an action that only runs over a frame may take the bare left button", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "BUTTON1", seq = 1,
                casting = { normalCast = false, hoverCastMode = "unitframe" } },
        }, nil, nil, true);

        local action = DebindPrivate.CollectActionsForKey("BUTTON1")[1].action;
        check(DebindPrivate.GetBindingIssue(action) == nil,
            "the action is refused: " .. tostring(DebindPrivate.GetBindingIssue(action)));
        check(DebindPrivate.KeysToHold["BUTTON1"] == nil, "the bare left click was taken");
        -- **Held and answered are two questions, and this is the case that parts them.** The press
        -- arrives through the frame and fires; a screen that asked whether the key was held would
        -- call a working button dead.
        check(DebindPrivate.IsKeyHandled("BUTTON1") == true,
            "a click-cast button does not read as one we answer");

        local records = DebindPrivate.KeyMap["BUTTON1"];
        check(records and #records > 0, "the action reached no record");
        for i = 1, #records do
            check(records[i].holdsKey == false, "record " .. i .. " holds the key");
        end
    end);

    --- **A broken action still answers its key.** Nothing comes out of the press, but the key is
    --- ours and the game's own binding does not run either -- which is why the window marks the
    --- group rather than greying its name (`DebindKeyHeaderMixin:Init`).
    test("an action that cannot fire still answers its key", function()
        Bind({
            { type = Constants.MACRO, value = "DebindNoSuchMacro", key = "F6", seq = 1 },
        });
        local action = DebindPrivate.CollectActionsForKey("F6")[1].action;
        check(DebindPrivate.GetBindingIssue(action) == Constants.BINDING_ISSUE_MISSING_MACRO,
            "the action carries " .. tostring(DebindPrivate.GetBindingIssue(action)));
        check(DebindPrivate.KeyMap["F6"] == nil, "the broken action reached a record");
        check(DebindPrivate.IsKeyHandled("F6") == true, "a key held for a broken action reads as dead");
    end);

    --- **Escape is the one key nothing can take** (`ISSUE_OUTCOME_RELEASE`), so it is the one error
    --- that does not answer. That is the difference the case above is standing next to.
    test("Escape answers nothing of ours", function()
        Bind({ { type = Constants.SPELL, value = 585, key = "ESCAPE", seq = 1 } });
        check(DebindPrivate.KeysToHold["ESCAPE"] == nil, "Escape was held");
        check(DebindPrivate.IsKeyHandled("ESCAPE") == false, "Escape reads as ours");
    end);

    -- **On a mouse button over a frame there are no cast key twins at all** (§7). A frame click is
    -- always [none held] (`EVAL_SNIPPET`), and the action holds no key, so nothing else can arrive
    -- either: a self or focus record there is one no press can reach, and while they were made they
    -- were also what held the bare left button.
    test("a mouse button over a frame gets no cast key twins", function()
        for _, casting in ipairs({
            { normalCast = false, hoverCastMode = "unitframe" },
            {},
        }) do
            Bind({
                { type = Constants.SPELL, value = 585, key = "BUTTON2", seq = 1, casting = casting,
                    conditions = casting.hoverCastMode and {}
                        or { units = { unitframe = { exists = true } } } },
            }, nil, nil, true);

            local records = DebindPrivate.KeyMap["BUTTON2"];
            check(records and #records > 0, "the action reached no record");
            for i = 1, #records do
                check(records[i].castModifier == Constants.CASTMOD_NONE,
                    "record " .. i .. " carries cast modifier "
                        .. tostring(records[i].castModifier));
            end
        end
    end);

    -- 반대쪽. 키보드 키에서는 같은 액션이 조합키 쌍둥이를 그대로 갖는다 - 그 누름은 키 경로로
    -- 오고, 그 층에서 이 액션이 제 차례를 지킨다.
    test("the same action on a keyboard key keeps its cast key twins", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F8", seq = 1,
                casting = { normalCast = false, hoverCastMode = "unitframe" } },
        }, nil, nil, true);

        local records = DebindPrivate.KeyMap["F8"];
        local held = 0;
        for i = 1, #(records or {}) do
            if (records[i].castModifier ~= Constants.CASTMOD_NONE) then
                held = held + 1;
            end
        end
        check(held == 2, "조합키 쌍둥이가 " .. held .. "개다");
    end);

    -- **Normal Cast on and Mouseover changes nothing on the bare left button** (§7). The original
    -- would hold the key off the frame and a Mouseover twin would have to hold it to stand, so the
    -- button gets the Unit Frames twin alone, and no warning for values the reader never has to
    -- change.
    test("the bare left button with Normal Cast on gets only the unit frame twin", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "BUTTON1", seq = 1,
                casting = { hoverCastMode = "mouseover" } },
        }, nil, nil, true);

        local action = DebindPrivate.CollectActionsForKey("BUTTON1")[1].action;
        check(DebindPrivate.GetBindingIssue(action) == nil,
            "the action has an issue: " .. tostring(DebindPrivate.GetBindingIssue(action)));
        check(DebindPrivate.KeysToHold["BUTTON1"] == nil, "the bare left click was taken");

        local records = DebindPrivate.KeyMap["BUTTON1"];
        check(records and #records == 1, "BUTTON1 came out with " .. tostring(records and #records));
        check(records[1].hoverTwin and records[1].isClickCast == true and records[1].holdsKey == false,
            "the one record is not the frame click");
        check(records[1].conditions.units.unitframe ~= nil and records[1].conditions.units.mouseover == nil,
            "the twin stands on the wrong unit");
    end);

    -- On a mouse button the two split the way a hover record and a plain one always have: the twin
    -- is a click on the frame, the original holds the key.
    test("on a mouse button the twin is the click-cast and the original holds the key", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "BUTTON3", seq = 1 },
        }, nil, nil, true);

        local records = Records("BUTTON3");
        check(records and #records == 2, "BUTTON3 came out with " .. tostring(records and #records));
        check(records[1].isClickCast == true and records[1].holdsKey == false,
            "the twin is not the click-cast");
        check(records[2].isClickCast == false and records[2].holdsKey == true,
            "the original does not hold the key");
    end);

    ---------------------------------------------------------------------------
    -- `rewriting-evaluate-issues.md` §4: how many records each row puts on its key
    --
    -- **A binding that cannot stand is not on the key**, the other bindings of its action are.
    -- Nothing after `BuildKeyMap` would drop it (`Debind.lua`'s `UnrollIntoTiers`).
    ---------------------------------------------------------------------------

    local ROWS = require("answer_rows")(Constants);

    --- Per row, the records on the key, spelled the way the table spells them.
    local RECORDS = {
        [1] = "", [2] = "self focus hover", [3] = "hover", [4] = "", [5] = "", [6] = "", [7] = "",
        [8] = "", [9] = "", [10] = "self focus original", [11] = "original", [12] = "",
        [13] = "focus hover original", [14] = "", [15] = "self focus original", [16] = "hover",
        [17] = "", [18] = "", [19] = "original", [20] = "", [21] = "self focus hover", [22] = "", [23] = "self focus hover original",
        [24] = "", [25] = "self focus hover original", [26] = "self focus hover original", [27] = "",
    };

    local function shapeOf(records)
        local out = {};
        for i = 1, #(records or {}) do
            local record = records[i];
            out[i] = (record.castModifier == Constants.CASTMOD_SELF and "self")
                or (record.castModifier == Constants.CASTMOD_FOCUS and "focus")
                or (record.hoverTwin and "hover")
                or "original";
        end
        return table.concat(out, " ");
    end

    for _, row in ipairs(ROWS) do
        test("§4 #" .. row.n .. " KeyMap: " .. row.label, function()
            local action = row.action();
            Bind({ action }, nil, row.options);
            local shape = shapeOf(DebindPrivate.KeyMap[action.key]);
            check(shape == RECORDS[row.n],
                "came out [" .. shape .. "] (" .. select(2, shape:gsub("%S+", "")) .. "), want ["
                    .. RECORDS[row.n] .. "]");
        end);
    end

    -- **"Every binding was covered" means every binding that stands.** #13's self twin cannot stand,
    -- and nothing covers a box with a zero in it, so counted it would keep an action whose every
    -- press goes to the one ahead of it from ever reading as unreachable.
    test("§4 #13 IsUnreachableAction: a binding that cannot stand is not counted", function()
        local subject = ROWS[13].action();
        subject.seq = 2;
        Bind({ { type = Constants.SPELL, value = 116, key = "F1", seq = 1, priority = 1 }, subject },
            nil, nil, true);
        local left = {};
        for _, record in ipairs(DebindPrivate.KeyMap["F1"]) do
            if (record.value == 585) then
                left[#left + 1] = shapeOf({ record });
            end
        end
        check(DebindPrivate.IsUnreachableAction(subject) == true,
            "the action ahead covers every binding that stands, and it still reads as reachable;"
                .. " left on the key: " .. table.concat(left, " "));
    end);

    -- The other half: with nothing that stands there is nothing to have been covered.
    test("§4 #1 IsUnreachableAction: an action with nothing that stands is not unreachable", function()
        local subject = ROWS[1].action();
        subject.seq = 2;
        Bind({ { type = Constants.SPELL, value = 116, key = "F1", seq = 1, priority = 1 }, subject },
            nil, nil, true);
        check(DebindPrivate.IsUnreachableAction(subject) == false, "read as covered");
    end);

    return T;
end
