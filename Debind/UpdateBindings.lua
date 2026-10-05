local _, DebindPrivate      = ...;
local Constants               = DebindPrivate.Constants;
local Spells                  = DebindPrivate.Spells;
local BindingDriver           = DebindPrivate.BindingDriver;
local DefaultClickFrame       = DebindPrivate.DefaultClickFrame;

local DEBUG                   = DebindPrivate.DEBUG;
local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;
local BASIC_UNITS             = Constants.BASIC_UNITS;
local NIL                     = Constants.NIL;
local SWITCH_MODES            = Constants.SWITCH_MODES;



local dump                               = DebindPrivate.dump;
local luatype                            = type;
local format, tostring, select           = format, tostring, select;
local strsub, tconcat                    = string.sub, table.concat;
local wipe, ipairs, pairs, tinsert, sort = wipe, ipairs, pairs, tinsert, sort;
local band, bor                          = bit.band, bit.bor;
local InCombatLockdown                   = InCombatLockdown;
local GetSpellNameAndIconID              = DebindPrivate.GetSpellNameAndIconID;
local GetSpellSubtext                    = C_Spell.GetSpellSubtext;
local UnitGroupToCells                   = DebindPrivate.UnitGroupToCells;
--- The pure half of the pair in `Spells.lua`. **The other half asks the client and may not be used
--- here**: `DescribeBinding` is reached with the world already collected, and a spec hands it plain
--- values rather than standing an API up.
local ComposeSpellCastName               = DebindPrivate.ComposeSpellCastName;
local IsPressHoldReleaseSpell            = C_Spell.IsPressHoldReleaseSpell;
local GetMountInfoByID                   = C_MountJournal.GetMountInfoByID;

local BindingAttrsCache                  = {};

local NextButtonName;
do
    local _nextId = 100;
    function NextButtonName()
        _nextId = _nextId + 1;
        return "deb" .. _nextId;
    end
end

local SetBindingAttributes;

--- The body a wrapped button carries: put each chosen CVar's current value aside and write the
--- action's, fire the real button, put them back. **The values are read in the body and not baked
--- in**, so a setting changed mid-fight is the one the next press restores
--- (`matching-the-clients-cast-targeting.md` §2-2).
---
--- **Lines, not nesting.** A macro inside a macro does not run, so the saves go in front of the one
--- `/click` and the restores behind it. The globals are how the two `/run` lines reach each other:
--- a macro body has no other scope, and the cast frame is protected from where this runs.
---
--- `key` is `CastAutomaticsKeyOf`'s, one character per row.
local function AutomaticsLines(key)
    local rows = DebindPrivate.CAST_AUTOMATIC_ROWS;
    local save, restore = {}, {};
    for i = 1, #rows do
        local mark = strsub(key, i, i);
        if (mark ~= "-") then
            local row = rows[i];
            local global = "DebindAuto_" .. row;
            save[#save + 1] = format('%s=GetCVar("%s");SetCVar("%s","%s")', global, row, row, mark);
            restore[#restore + 1] = format('SetCVar("%s",%s)', row, global);
        end
    end
    return "/run " .. tconcat(save, ";"), "/run " .. tconcat(restore, ";");
end

--- Around a `/click` at the real button, for the actions that reach the cast through one.
---
--- **`edge` is the third token `/click` takes**, and it is what a spell you hold needs: the inner
--- click has to arrive as a press on the way down and as a release on the way up
--- (`SlashCommands.lua` hands it to `Click(button, down)`). One body sent on both edges charges
--- the spell and never lets go, which is the 1.8 seconds §7 of the writeup measured. Left out
--- everywhere else, so those bodies stay exactly as they were.
local function AutomaticsBody(key, buttonname, edge)
    local save, restore = AutomaticsLines(key);
    return save .. "\n"
        .. format("/click %s %s%s\n", DebindPrivate.CastFrameName, buttonname,
            edge and (" " .. edge) or "")
        .. restore;
end

--- Around a body we wrote ourselves. **A macro inside a macro does not run**, so these actions
--- cannot be reached through a `/click` the way a spell is; their bodies are our strings, so the
--- lines go straight in front and behind
--- (`setting-the-clients-cast-automatics-per-action.md` §5).
local function AutomaticsWrap(body, key)
    local save, restore = AutomaticsLines(key);
    return save .. "\n" .. body .. "\n" .. restore;
end

--- `type -> cacheKey -> automatics key -> button name`, beside `BindingAttrsCache` and kept the
--- same way. **The plain button stays shared**: what the automatics split is the wrapper around it,
--- and the one inside is the same button for every combination
--- (`setting-the-clients-cast-automatics-per-action.md` §4).
local WrappedAttrsCache = {};

--- Every wrapped button stamped this session, as `wrapped -> the button its body clicks`. **The
--- click path reads it to know whether the press's unit has to go on the cast frame**, which is the
--- one thing about a wrapped button that cannot be baked: `@hover` and the custom aliases are
--- worked out at the press. What it maps to is for the readers who have to get back to the real
--- action from a button name.
---
--- Not wiped between rebuilds, because a button outlives the rebuild that stamped it
--- (`BindingAttrsCache`).
local _wrappedButtons = {};

--- 감싼 버튼 -> 그 버튼의 올림 엣지가 갈 버튼. 쥐는 주문에만 선다.
local _wrappedRelease = {};
--- `button name -> { info, bar, overrideBar }` for every action button action stamped this
--- session, emitted as `ActionSlots` on every rebuild. `info` is its `ACTION_BUTTON_COMMANDS` row.
local _actionSlots = {};
--- Blizzard bar button -> the button name that clicks it (`BarClickButton`).
local _barClickButtons = {};
local UpdateBindingsMap;
local BuildMacroTextEntries;
local UpdateAttrChangedHandler;

local addSwitch;
local addMacrotext;
local addMacrotextBinding;

local GetModifierIndex   = DebindPrivate.GetModifierIndex;

local _strArr            = {};

local _macrotexts        = {};
local _macrotextBindings = {};
local _switches          = {};
local _unitsSeen         = {};

--- The world a rebuild was built against, and what it decided to do about it. **Two tables, wiped
--- and refilled**, the way the rest of this file already works.
---
--- Holding the decision apart from the doing is what lets a spec ask what a profile comes to
--- without a client in front of it: `BuildBindingPlan` answers from `ctx`, and `ApplyBindingPlan`
--- is the only step with an effect (`going-headless-outside-the-ui.md` §3-1).
local _ctx               = {};
local _plan              = { events = {}, units = {} };

--- The attribute Blizzard's driver writes `"a"` to, once per manager tick while a key holds a tail
--- (`trimming-the-tail-key-beat.md` 5-1). The handler puts it back to `0` so the next tick writes
--- again.
local JUDGE_BEAT_ATTRIBUTE = "judgebeat";
DebindPrivate.JUDGE_BEAT_ATTRIBUTE = JUDGE_BEAT_ATTRIBUTE;
--- The loop's bodies the last rebuild generated besides the beat (`BuildJudgeSnippet`): the pass the
--- rebuild runs itself, and one per wake as `{ attribute = , body = }`.
local _judgePassBody;
local _judgeWakeBodies = {};
--- Does the beat measure any column of this rebuild (`JudgedOnBeat`)?
local _judgeBeats = false;
--- What carries the beat in this rebuild: `"visibility"` where the login's check found the manager
--- writing `statehidden` on every tick (`BeatSignal.lua`), `"attribute"` otherwise. Decided once
--- per rebuild, since the handler's branch and the driver `ApplyBindingPlan` registers have to
--- agree.
local _judgeBeatSignal = "attribute";

--- Does any action ask about the hovered unit's role? It is what turns the three role headers
--- on, and they are the only thing that fills `UnitRoles`.
local _readsRole = false;

--- Scratch arrays for `sortedKeys`. Three, because the walks nest: a key's units are sorted inside
--- the walk over keys, and one unit's reactions inside the walk over units.
---
--- **Wiped and refilled, never reallocated**, which is the rule this whole file already runs on -
--- a rebuild allocates no table it can reuse.
local _sortedA           = {};
local _sortedB           = {};
local _sortedC           = {};

--- A table's keys, in order.
---
--- **Nothing emitted may depend on `pairs`.** Two things rest on that. The generated snippets are
--- held against a recorded file at every run (`tests/emit_spec.lua`), and `pairs` answers in a
--- different order under each of the interpreters the specs run on, so an unsorted walk would make
--- the golden impossible rather than merely noisy. And the button names `SetBindingAttributes`
--- hands out are drawn in the order keys are visited, so an unsorted walk does not just reorder
--- the output - it changes what is in it.
---
--- In the game the same sort is what makes two dumps of one profile comparable.
---
--- The caller picks which scratch array to fill, and the choice is not free: the walks nest.
local function sortedKeys(t, out)
    wipe(out);
    local count = 0;
    for key in pairs(t) do
        count = count + 1;
        out[count] = key;
    end
    sort(out);
    return out;
end

local function ResetContext()
    wipe(DebindPrivate.ClickTimeKeys);
    wipe(DebindPrivate.SpellFacts);
    wipe(_macrotexts);
    wipe(_macrotextBindings);
    wipe(_switches);
    wipe(_unitsSeen);
    _readsRole = false;
end

--- This rebuild's take on one switch, or `false` where nothing defines the name.
---
--- **The name is not checked against a list any more.** It used to have to be one of the numbered
--- five, and a name outside them was answered `false` without so much as asking whether it was
--- defined. So a definition could never be found under any other name, which is what §10's 1b-2
--- lifts (`redesigning-custom-states.md`). What decides now is the same thing that decides
--- everywhere else: whether `ResolveSwitchDefinition` has an answer.
---
--- **How it behaves is asked of the layers, whether it exists is asked of the definition** (§4-6).
--- Those are two questions and they get two doors: a switch this character overrides is the same
--- switch, so `mode` and `expr` come from the row that wins here while the name, and the fact that
--- there is one at all, stay account-wide.
---
--- `false` is memoized alongside a real one so an undefined name is resolved once per rebuild
--- rather than once per reference.
function addSwitch(switchName)
    local info = _switches[switchName];
    if (info == nil) then
        local options = DebindPrivate.ResolveSwitchDefinition(switchName);
        if (options) then
            local mode, _, expr = DebindPrivate.ResolveSwitchAnswer(switchName);
            info = {
                name = switchName,
                mode = mode,
                value = DebindPrivate.GetSwitchValue(switchName),
            };
            if (mode == SWITCH_MODES.EXPR) then
                info.expr = expr or "";
                addMacrotextBinding(info.name, info.expr);
            end
        end
        info = info or false;
        _switches[switchName] = info;
    end
    return info;
end

function addMacrotext(macrotext)
    local ret = _macrotexts[macrotext];
    if (ret == nil) then
        local fragments, args = DebindPrivate.ParseMacroText(macrotext);
        if (args) then
            ret = {
                fragments = fragments,
                args = args,
            };
            _macrotexts[macrotext] = ret;

            for _, arg in ipairs(args) do
                if (arg.type == Constants.MACROTEXT_ARG_SWITCH) then
                    addSwitch(arg.name);
                elseif (arg.type == Constants.MACROTEXT_ARG_UNIT) then
                    _unitsSeen[arg.name] = true;
                end
            end
        else
            ret = false;
        end
        _macrotexts[macrotext] = ret;
    end
    return ret;
end

function addMacrotextBinding(buttonOrSwitchName, macrotext)
    _macrotextBindings[buttonOrSwitchName] = addMacrotext(macrotext)
end

--- Does a switch argument in `ownerName`'s text go in as that switch's value when the text is
--- composed? Where not, the rebuild fixes it (`EmitMacroTextArg`).
local function SwitchArgIsLive(arg, ownerName)
    return not DebindPrivate.IsSwitchIgnored(arg.name) and arg.name ~= ownerName
        and addSwitch(arg.name) and true or false;
end

--- What a computed switch's composed text reads, by name: an alias or `unitframe`, or a switch.
--- Nil where the switch has nothing to compose.
local function ComposedReads(name)
    local info = _switches[name];
    local parsed = info and info.mode == SWITCH_MODES.EXPR and _macrotexts[info.expr];
    if (not parsed) then
        return nil;
    end
    local reads = {};
    for _, arg in ipairs(parsed.args) do
        if (arg.type == Constants.MACROTEXT_ARG_UNIT
                or (arg.type == Constants.MACROTEXT_ARG_SWITCH and SwitchArgIsLive(arg, name))) then
            reads[#reads + 1] = arg.name;
        end
    end
    return reads;
end

-- **`> 0`, because `select("#")` answers `0` and `0` is true in Lua.** The guard never held, so a
-- string with no arguments still went through `format` -- which is only survivable while every such
-- string is free of `%`. One that is not would raise from inside a rebuild.
local function appendLine(str, ...)
    if (select("#", ...) > 0) then
        _strArr[#_strArr + 1] = format(str, ...);
    else
        _strArr[#_strArr + 1] = str or "";
    end
end

--- Compiles a generated snippet before it is handed over, in DEBUG builds only.
---
--- The literal snippets are covered by `tools/check-snippets.js`, but these are assembled at
--- runtime and nothing sees them until the restricted environment refuses them -- and what it
--- reports is a stack inside `RestrictedExecution.lua` with a line number into a chunk nobody can
--- look at. `loadstring` is not that environment, so this does not prove a snippet will run; it
--- only says the text is Lua, which is precisely the class of fault that is otherwise so
--- expensive to place.
---
--- Worth having because these strings are assembled from format specifiers: a `%q` too many turns
--- into a missing `end` several hundred lines away from the line that wrote it.
local function AssertSnippetCompiles(snippet, what)
    if (not DEBUG) then
        return;
    end

    local chunk, err = loadstring(snippet, what);
    if (not chunk) then
        DebindPrivate.log(format("|cffff0000[Debind]|r 생성된 스니펫 %s 가 컴파일 안 된다: %s", what, tostring(err)));
    end
end

local function appendKeyValue(key, value)
    if (value == nil) then
        return;
    elseif (value == true) then
        appendLine("t[%q]=true", key);
    elseif (value == false) then
        appendLine("t[%q]=false", key);
    elseif (luatype(value) == "string") then
        appendLine("t[%q]=%q", key, value);
    else
        appendLine("t[%q]=%d", key, value);
    end
end


--- May a rebuild run at all, and if not, which "no" is it?
---
--- **Two refusals, and they are not the same kind.** Combat is a lockdown we come back from -- the
--- caller records that a rebuild is owed and `PLAYER_REGEN_ENABLED` pays it. An unknown
--- specialization is a window that closes on its own, and there is nothing to remember.
---
--- **Not knowing the specialization means not building, not building without it.**
--- `EnumerateProfileLayers` takes nil and passes it on as 0 (its comment: insurance against dying
--- on the path that reads the XML), but that answer is **the list with both specialization layers
--- missing**. Somewhere that draws a list it ends in showing less; here it becomes real key
--- overrides, and **a lower priority action takes the key.** Quietly.
---
--- Not building is the safe side because the window shuts by itself:
--- `Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED` sees the nil, calls itself again 0.05s later, and
--- that path comes back through here. Until then there are no bindings, and that beats wrong ones.
---
--- **A character with no specialization does not land here.** What this API hands one that has not
--- picked yet is an out of range index rather than nil (`EnumerateProfileLayers`), so nil means
--- "not known yet" and nothing else.
local function CanBuildBindings()
    if (InCombatLockdown()) then
        return false, "combat";
    end
    if (C_SpecializationInfo.GetSpecialization() == nil) then
        return false, "spec";
    end
    return true;
end

--- Everything a rebuild reads before it decides anything.
---
--- **Most of what it collects is still not a value**, and saying so is the point of the step
--- existing this early. `BuildKeyMap` fills `DebindPrivate.KeyMap` and the switch reset writes the
--- profile, so what comes back is a reference to a table this call filled rather than a copy. What
--- turns those into values is stage 3 of `going-headless-outside-the-ui.md`; naming the
--- seam is what makes it possible to move.
local function CollectBindingContext()
    -- **Where a specialization change reaches a switch** (§4-8 of
    -- `redesigning-custom-states.md`). An override saying "always on in this
    -- specialization" has to be applied on the way *into* that specialization, not only at login,
    -- and a specialization change is a rebuild - this one. It is below the guard above on purpose:
    -- which answer wins depends on the specialization, so asking before it is known would resolve
    -- every switch against the wrong world and then not ask again.
    --
    -- Nothing is re-applied where the answer has not moved, so the ordinary rebuild - a binding
    -- edited, a macro saved - leaves every value where the reader left it.
    DebindPrivate.ApplySwitchResets();

    DebindPrivate.RefreshYieldedKeys();

    DebindPrivate.BuildKeyMap();

    local ctx = _ctx;
    ctx.keyMap = DebindPrivate.KeyMap;
    return ctx;
end

--- Puts the secure side back to nothing, so what the build emits lands on an empty table.
---
--- **It runs before the build rather than inside `ApplyBindingPlan`, and that is temporary.** The
--- build still stamps attributes and builds delegate frames as it goes (`SetBindingAttributes`),
--- so a reset deferred to the apply would land on top of what the build had already put out.
--- Stage 2 of `going-headless-outside-the-ui.md` takes the stamping out of the build, and
--- this moves in with it.
---
--- **`UnitAliasMap` is deliberately not among what goes.** It outlives the rebuild, which is why an
--- action targeting a custom unit does not have to register the alias itself. `/debtest`'s
--- `Custom target survives a rebuild` is what holds that.
local function ClearPreviousBindings()
    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
wipe(OldStates)
for k, v in pairs(States) do
    OldStates[k] = v
end
wipe(ClickTimeKeys)
wipe(ClickTimeTiers)
-- **`ClearOverrideBindings` below takes every key off**, so what a record list remembered about
-- being handed over is gone with it. The next pass of `UpdateGivenBackKeys` starts from nothing
-- given back, which is what the game is in after this.
wipe(BoundKeys)
wipe(GivenBackNow)
wipe(JudgeColumns)
wipe(JudgeBundles)
wipe(JudgeByKey)
wipe(JudgeWakes)
wipe(JudgeComposeAll)
wipe(JudgeComposeBy)
wipe(JudgeClassify)
wipe(JudgeSwitchTexts)
-- A composition reads this ahead of `States`, so a value left by a switch that has since become one
-- set by hand would stand in front of its real one.
wipe(JudgeSwitches)
-- The rebuild's columns start with no cell, and a detecting parse answering its last number would
-- leave them so: the pass then judges with nothing to compare.
JudgeDetect = false
JudgeReady = false
-- `ApplyGiveBack` bakes it again from the set as it stands, below.
wipe(ContextKeys)
for _, byMod in pairs(ClickCastKeys) do
    wipe(byMod)
end
wipe(HeldButtons)
wipe(HeldUnits)
-- Drop any unconsumed handoff -- it points into the old records.
HandoffBindings = nil
HandoffWinner = nil
HandoffUnitFrameUnit = nil
wipe(DeferredMacroTexts)
wipe(SwitchExpressions)
wipe(SwitchEntries)
wipe(ComputedSwitches)

-- **`unitframe`은 살려서 넘긴다.** `States`에 든 나머지는 리빌드가 끝나면서 전부 다시
-- 채워지지만, 이건 enter/leave 이벤트로만 서는 값이라 **다시 채워줄 사람이 없다.** 지우면
-- 다음에 커서가 들어올 때까지 빈 채로 남는다.
--
-- 커서는 그대로 프레임 위에 있는데 조건 하나만 바뀌면(전투 진입, 자세 변경, 특성) 리빌드가
-- 돌고, 그 순간 개체창 조건 바인딩이 전부 죽는다. 마우스를 뺐다 다시 올려야 살아났다.
--
-- 짝이 되는 `UnitAliasMap["unitframe"]`는 이 프롤로그가 안 지운다. 그래서 지우면 둘이 갈리기까지
-- 한다 - 유닛은 남아 있는데 프레임은 없는 상태가 된다.
local hovered = States.unitframe
wipe(States)
States.unitframe = hovered
]]);

    ClearOverrideBindings(BindingDriver);
    DebindPrivate.BindingDriver:SetAttribute("_onattributechanged", nil);
end

local _orderSeen = {};
local _order = {};

--- **A switch comes after every computed switch its expression reads**, so a press working them out
--- in this order reads the answer it just got. A cycle is cut where the walk meets it.
local function OrderComputedSwitch(name)
    if (_orderSeen[name]) then
        return;
    end
    _orderSeen[name] = true;

    local info = _switches[name];
    local parsed = info and _macrotexts[info.expr];
    if (parsed) then
        for _, arg in ipairs(parsed.args) do
            local other = arg.type == Constants.MACROTEXT_ARG_SWITCH and _switches[arg.name];
            if (other and other.mode == SWITCH_MODES.EXPR) then
                OrderComputedSwitch(arg.name);
            end
        end
    end
    _order[#_order + 1] = name;
end

--- The line that puts a switch's stored value back, plus the fixed macro conditional behind a
--- computed one, and the order a press works the computed ones out in. Returns nil where this
--- rebuild has no switch to say anything about.
---
--- Writing into `States` directly would skip the report the insecure side folds back into the
--- definition (`OnSwitchChanged`), which is what the Switches tab reads for a switch somebody
--- works by hand. The value goes back through `SetSwitch` for that reason.
local function BuildSwitchesSnippet()
    wipe(_orderSeen);
    wipe(_order);

    for _, name in ipairs(sortedKeys(_switches, _sortedA)) do
        local info = _switches[name];
        if (info) then
            -- previous switch value. **Not for a computed one**: its value belongs to the press
            -- that worked it out (`COMPUTE_SWITCHES_SNIPPET`), so a stored one is what the last
            -- press left behind and pushing it in would stand it up as the switch's value until
            -- the next press. It goes in through `SetSwitch`, which reports it straight back out
            -- to the definition and to what this character remembers.
            if (info.mode ~= SWITCH_MODES.EXPR and info.value ~= nil) then
                appendLine([[self:RunAttribute("SetSwitch", %1$q, %s)]], name,
                    tostring(info.value));
            end

            -- fixed macro conditional
            if (info.mode == SWITCH_MODES.EXPR and not addMacrotext(info.expr)) then
                appendLine([[SwitchExpressions[%q]=%q]], name, info.expr);
            end

            if (info.mode == SWITCH_MODES.EXPR) then
                OrderComputedSwitch(name);
            end
        end
    end

    for i = 1, #_order do
        appendLine([[ComputedSwitches[%d]=%q]], i, _order[i]);
    end

    if (#_strArr == 0) then
        return nil;
    end

    local snippet = table.concat(_strArr, "\n");
    AssertSnippetCompiles(snippet, "SwitchExpressions");
    if (DEBUG) then
        dump("SwitchExpressions snippet", { CopyTable(_strArr), snippet:len() });
    end
    wipe(_strArr);
    return snippet;
end

--- Which state driver events this rebuild wants, and which it wants gone.
---
--- **Two readers.** Keys Given Back, whose `state-giveback` attribute driver has to be current the
--- moment a vehicle takes the bar (`giving-keys-back.md` §4); and the loop that binds a tail key,
--- whose beat is the manager's own (`JudgeKeys`). An event on the manager puts its timer to zero,
--- so the column it announces is measured on the next frame rather than up to a beat later.
---
--- **Only what the manager does not already listen to.** Combat, stealth, the shape, the bonus bar,
--- the group, the target and the focus are on its own list (`SecureStateDriver.lua`).
---
--- The order here is the order they are applied in. It is written out rather than walked out of a
--- table, so what a rebuild emits does not depend on `pairs`.
local function CollectDriverEvents(events)
    local function want(name, register)
        events[#events + 1] = { name = name, register = register and true or false };
    end

    local judged, units = {}, {};
    for _, item in pairs(DebindPrivate.JudgmentItems) do
        for _, column in ipairs(item.columns) do
            judged[column.kind] = true;
            if (column.kind == "unit") then
                units[column.arg] = true;
            end
        end
    end

    -- **Fires when a mouseover unit appears, never when one goes away**, so the cursor leaving a
    -- unit for empty space waits for the beat.
    want("UPDATE_MOUSEOVER_UNIT", units.mouseover);
    -- Every unit cell carries the reaction, the pointed frame's included.
    want("UNIT_FACTION", judged.unit);

    local givesBackOnReplacedBar = DebindPrivate.GiveBackOnReplacedBar();
    want("UPDATE_OVERRIDE_ACTIONBAR", givesBackOnReplacedBar or judged.specialbar);
    want("UPDATE_VEHICLE_ACTIONBAR", givesBackOnReplacedBar or judged.specialbar);
    want("UPDATE_EXTRA_ACTIONBAR", judged.extrabar);
    want("PLAYER_MOUNT_DISPLAY_CHANGED", judged.mounted);

    -- The pair is what the client splits a move into: `ZONE_CHANGED_INDOORS` is the doorway and
    -- `ZONE_CHANGED` the rest. What a zone allows to fly lags the world by design, and every mount
    -- macro answers off the same delay.
    want("ZONE_CHANGED", judged.indoors or judged.flyable or judged.advflyable);
    want("ZONE_CHANGED_INDOORS", judged.indoors);
    want("ZONE_CHANGED_NEW_AREA", judged.flyable or judged.advflyable);

    -- Both, because the client splits a pet battle into the two. Keys Given Back only: the loop
    -- is told of a battle by `SetPetBattle`.
    local battle = DebindPrivate.GiveBackInPetBattle();
    want("PET_BATTLE_OPENING_START", battle);
    want("PET_BATTLE_CLOSE", battle);

    want("SPELLS_CHANGED", judged.known);

    return events;
end

--- Which special units this rebuild watches. A unit nobody named is not only left unwatched, its
--- alias is cleared as well -- a stale one would stay resolvable on the secure side.
---
--- `custom1` and `custom2` are set by an action rather than measured, so they are not this
--- function's to turn on or off.
--- `slots` is how many units the header has to be able to hold. Two is enough to tell one tank
--- from more than one, which is all `@tank` asks; the role map needs the whole group.
local function CollectWatchedUnits(units)
    local roleSlots = _readsRole and Constants.MAX_ROLE_SLOTS or nil;
    for _, unit in ipairs(sortedKeys(SPECIAL_UNITS, _sortedA)) do
        if (unit ~= "custom1" and unit ~= "custom2") then
            local forRole = roleSlots and DebindPrivate.ROLE_HEADER_BITS[unit];
            units[#units + 1] = {
                alias = unit,
                watch = (_unitsSeen[unit] or forRole) and true or false,
                slots = forRole and roleSlots or nil,
            };
        end
    end
    return units;
end

--- What this rebuild decided, as a value.
---
--- **What is not pure yet is the emitters.** `UpdateBindingsMap` reaches `SetBindingAttributes`,
--- which stamps the click frame and builds delegate frames as it walks; stages 2 and 3 of
--- `going-headless-outside-the-ui.md` take that out. What is already a value is every
--- decision below the snippets -- which events to register, which units to watch, the throttle --
--- and those are the ones a spec could not reach at all before.
---
--- **The plan is a module table, wiped and refilled**, which is the rule this whole file runs on.
--- Its two lists do allocate one small table per entry - nine events and five aliases, fixed
--- counts that do not follow the profile. What follows the profile is the record path, and that
--- one reuses (`BuildKeyRecord`).
local function BuildBindingPlan(ctx)
    ResetContext();

    local plan = _plan;
    wipe(plan.events);
    wipe(plan.units);

    plan.bindingsMapSnippet = UpdateBindingsMap();
    plan.macroTextsSnippet = BuildMacroTextEntries();
    plan.attrChangedSnippet = UpdateAttrChangedHandler();
    plan.switchesSnippet = BuildSwitchesSnippet();

    CollectWatchedUnits(plan.units);

    --- `damager` is not in `plan.units` because it is not an alias -- nothing can aim at it, and
    --- `CollectWatchedUnits` walks the units a binding can name. It exists so that a unit off the
    --- map means "role unknown" instead of "we only looked for two of the three".
    plan.roleMap = _readsRole and true or false;

    --- The two rows of Keys Given Back that the driver's letter answers, and the one that narrows
    --- them. The House Editor row is not here: what crosses for it is the claimed keys themselves
    --- (`BakeContextKeys`), because the set is the game's answer rather than a row we evaluate.
    plan.giveBack = {
        replacedBar = DebindPrivate.GiveBackOnReplacedBar(),
        petBattle = DebindPrivate.GiveBackInPetBattle(),
        onlyWithAction = DebindPrivate.GiveBackWhenActionExists(),
    };

    CollectDriverEvents(plan.events);

    --- Does any key hold a tail, and so need the loop (`JudgeKeys`) and its beat?
    plan.judges = next(DebindPrivate.JudgmentItems) ~= nil;
    --- And does the beat measure anything for it? A switch set by hand and a pet battle move only
    --- on a wake of ours, so a profile reading nothing else needs no beat.
    plan.beats = plan.judges and _judgeBeats;
    plan.beatSignal = _judgeBeatSignal;
    plan.judgePass = _judgePassBody;
    plan.judgeWakes = _judgeWakeBodies;

    return plan;
end

--- What wakes `UpdateGivenBackKeys`. Blizzard's manager resolves this insecurely on its own beat
--- and writes the attribute only when the value moves, so every transition between these states
--- costs one handler entry and a state that is not among them costs nothing
--- (`SecureStateDriver.lua`, `resolveDriver`).
---
--- **A token per state rather than a boolean.** How many buttons are live differs between them
--- (§2), so going straight from one to another has to read as a move.
---
--- **`[vehicleui]` stands before `[possessbar]`, and `HasVehicleActionBar()` is neither of them.**
--- Measured in a possession: `[possessbar]` is true, `[vehicleui]` is false, and the bar is a
--- vehicle bar (`legacy/dropping-the-game-fallback.md` §4-5).
---
--- **The letter is the whole of the answer now**, so the body no longer asks which state it is in
--- (§2 of `giving-keys-back.md`). That closed a hole: the driver wakes before
--- the bar is up, and a body asking `HasVehicleActionBar()` at that moment found nothing, handed no
--- key over, and stayed that way until the next transition. Measured 2026-09-19 on a Ulduar vehicle
--- and on the bonus bar.
local GIVE_BACK_PET_BATTLE = "[petbattle] b";
local GIVE_BACK_REPLACED_BAR = "[vehicleui] v; [possessbar] p; [overridebar] o; [shapeshift] s";

--- **Only the clauses the reader's rows need.** A clause in here is resolved by Blizzard's manager
--- on every beat whether or not anything would come of it.
local function GiveBackDriver(giveBack)
    if (giveBack.petBattle and giveBack.replacedBar) then
        return GIVE_BACK_PET_BATTLE .. "; " .. GIVE_BACK_REPLACED_BAR .. "; 0";
    elseif (giveBack.petBattle) then
        return GIVE_BACK_PET_BATTLE .. "; 0";
    end
    return GIVE_BACK_REPLACED_BAR .. "; 0";
end

--- Writes the reader's rows to the secure side and puts the driver on or takes it off.
---
--- **Off is not the same as leaving it registered with every row false.** A driver that stays on
--- goes on costing a resolve on the manager's beat for a reader who turned the feature off.
local function ApplyGiveBack(driver, giveBack)
    SecureHandlerExecute(driver, format(
        "GiveBack.replacedBar=%s GiveBack.petBattle=%s GiveBack.onlyWithAction=%s",
        tostring(giveBack.replacedBar), tostring(giveBack.petBattle),
        tostring(giveBack.onlyWithAction)));

    if (giveBack.replacedBar or giveBack.petBattle) then
        RegisterAttributeDriver(driver, "state-giveback", GiveBackDriver(giveBack));
    else
        UnregisterAttributeDriver(driver, "state-giveback");
        driver:SetAttribute("state-giveback", nil);
    end

    --- **The rebuild has to work it out again itself.** Registering the driver resolves it on the
    --- spot, but the manager writes the attribute only when the value moves, and a rebuild that
    --- happened inside one of these states finds the same value already there -- so no transition
    --- arrives. Meanwhile `ClearPreviousBindings` took every override off and `UpdateBindingsMap`
    --- put them all back, so without this the keys stay Debind's for as long as the state lasts.
    ---
    --- A pet battle is where that shows: it is not a combat lockdown, so a rebuild really does run
    --- in the middle of one.
    ---
    --- **The claimed keys go back on first**, for the same reason: `ClearPreviousBindings` wiped
    --- them along with the overrides, and a rebuild inside an open house editor would otherwise
    --- take the editor's keys back for as long as it stays open.
    DebindPrivate.BakeContextKeys(driver);
    SecureHandlerExecute(driver, [[self:RunAttribute("UpdateGivenBackKeys")]]);
end

--- The state driver events a rebuild registered and no rebuild has taken back since.
local _driverEventsOurs = {};
--- Which beat driver is registered on `BindingDriver`, `false` for none (`_judgeBeatSignal`).
--- Blizzard has no way to ask, so the rebuild that registers it keeps the answer.
local _beatRegistered = false;
--- The wake attributes the last rebuild filled, so the next can empty the ones it no longer has.
local _judgeWakeAttributesSet = {};

--- Hands the plan to the game. **The only step of a rebuild with an effect on the secure side**,
--- once the two stages that still leave stamping inside the build are done.
local function ApplyBindingPlan(plan)
    local driver = DebindPrivate.BindingDriver;

    SecureHandlerExecute(driver, plan.bindingsMapSnippet);
    SecureHandlerExecute(driver, plan.macroTextsSnippet);

    -- The loop's bodies besides the beat, while the handler is still off (`ClearPreviousBindings`):
    -- with it on, each of these writes would enter it for nothing. A wake the last rebuild had and
    -- this one does not is emptied, so nothing is left to run.
    for attribute in pairs(_judgeWakeAttributesSet) do
        driver:SetAttribute(attribute, nil);
    end
    wipe(_judgeWakeAttributesSet);
    for i = 1, #plan.judgeWakes do
        local wake = plan.judgeWakes[i];
        driver:SetAttribute(wake.attribute, wake.body);
        _judgeWakeAttributesSet[wake.attribute] = true;
    end
    driver:SetAttribute("JudgePass", plan.judgePass);

    driver:SetAttribute("_onattributechanged", plan.attrChangedSnippet);

    if (plan.switchesSnippet) then
        SecureHandlerExecute(driver, plan.switchesSnippet);
    end

    --- **헤더를 켜기 전에 선다.** 켜는 순간 배치가 돌고 그것이 `SetRoleUnits`를 부르는데,
    --- 표가 아직 없으면 그 패스가 그냥 돌아간다. 다음 로스터 변화까지 맵이 비어 있게 된다.
    if (plan.roleMap) then
        SecureHandlerExecute(driver, [[
            if (not UnitRoles) then
                UnitRoles = newtable()
                RoleOwners = newtable()
            end
        ]]);
    end

    for i = 1, #plan.units do
        local entry = plan.units[i];
        if (entry.watch) then
            DebindPrivate.EnableUnitWatch(entry.alias, entry.slots);
        else
            DebindPrivate.DisableUnitWatch(entry.alias);
            SecureHandlerExecute(driver,
                format([[self:RunAttribute("SetUnit", %q, nil)]], entry.alias));
        end
    end

    --- **표가 있다는 것이 곧 세 헤더가 다 서 있다는 뜻이다.** `"norole"`은 셋이 다 보고도
    --- 아무도 데려가지 않았다는 답이라, 하나라도 빠지면 낼 수 없다. 탱커 헤더만 켜진 채로
    --- 답을 내면 딜러가 전부 `"norole"`이 되고, [탱커]와 [역할 없음]을 고른 사용자에게
    --- 딜러까지 걸린다.
    ---
    --- 그래서 세우고 내리는 자리는 **셋을 켜기로 정한 리빌드 하나**다. 헤더가 저마다 세우면
    --- 반쪽 맵이 유효해 보인다. `SetRoleUnits`는 표가 있을 때만 채운다.
    if (plan.roleMap) then
        DebindPrivate.EnableUnitWatch("damager", Constants.MAX_ROLE_SLOTS);
    else
        DebindPrivate.DisableUnitWatch("damager");
        SecureHandlerExecute(driver, [[
            UnitRoles = false
            RoleOwners = false
            local unitframe = States.unitframe
            if (unitframe) then
                unitframe.role = nil
            end
        ]]);
    end

    --- **Only an event this addon registered is unregistered.** The manager is Blizzard's and shared
    --- with every addon, and one of them may have asked for the same event for its own drivers. An
    --- event already registered when we came to want it is somebody else's, and stays theirs.
    for i = 1, #plan.events do
        local entry = plan.events[i];
        if (entry.register) then
            if (not SecureStateDriverManager:IsEventRegistered(entry.name)) then
                SecureStateDriverManager:RegisterEvent(entry.name);
                _driverEventsOurs[entry.name] = true;
            end
        elseif (_driverEventsOurs[entry.name]) then
            SecureStateDriverManager:UnregisterEvent(entry.name);
            _driverEventsOurs[entry.name] = nil;
        end
    end
    --- **`updatetime` is Blizzard's and nobody here writes it** (2026-09-19, owner). Every moment
    --- a key is handed back arrives as an event, and an event on the manager's own list puts its
    --- timer to zero, so the interval never stood between one of those and the attribute moving.
    --- A shorter one bought nothing and the attribute is shared with every other addon.

    -- The aliases this rebuild watches, resolved once so a press finds them standing.
    SecureHandlerExecute(driver, [[
        self:RunAttribute("UpdateAllUnits")
    ]]);

    --- **The loop's first pass measures every column and binds every tail key**, after the aliases
    --- and the switches it reads are back. Before `ApplyGiveBack`, whose keys go over from wherever
    --- this leaves them and come back on what it judged.
    if (plan.judges) then
        SecureHandlerExecute(driver, [[self:RunAttribute("JudgePass")]]);
    end

    --- **The beat is a driver that answers one constant, not a unit watch** (`trimming-the-tail-key-
    --- beat.md` 5-1): a watch reads the frame's unit attributes and an existence cache on every tick,
    --- and the driver only parses the one expression. **Only on a change**, since registering
    --- resolves the driver on the spot, and **the old one comes off first**: two left standing would
    --- both carry the beat.
    local beat = plan.beats and plan.beatSignal or false;
    if (beat ~= _beatRegistered) then
        if (_beatRegistered == "attribute") then
            UnregisterAttributeDriver(driver, JUDGE_BEAT_ATTRIBUTE);
        elseif (_beatRegistered == "visibility") then
            UnregisterAttributeDriver(driver, "state-visibility");
        end
        if (beat == "attribute") then
            RegisterAttributeDriver(driver, JUDGE_BEAT_ATTRIBUTE, "a");
        elseif (beat == "visibility") then
            RegisterAttributeDriver(driver, "state-visibility", "show");
        end
        _beatRegistered = beat;
    end

    ApplyGiveBack(driver, plan.giveBack);
end

--- Every option whose answer reaches a secure frame is applied from here, and **nothing else
--- applies one**. The settings panel is open during a fight and every control in it is pressable
--- there, so a setter that wrote its own answer through would raise inside the panel's own click
--- handler. A setter writes the stored value and asks for a rebuild instead; `FinishBindingUpdate`
--- calls this with no argument, and a rebuild that could not run during the fight is replayed at
--- `PLAYER_REGEN_ENABLED` (`Events.lua`).
---
--- **The stored value is read here rather than carried in.** Two changes during one fight leave
--- two queued rebuilds and one answer, and it has to be the second one.
function DebindPrivate.ApplyOptions(option)
    if (option == nil or option == "unitframeUseMouseDown" or option == "empowerTapControls") then
        --- **Three answers folded into one boolean before it crosses.** The restricted side
        --- cannot read a CVar, so `nil` - the reader not having chosen - is resolved here, and
        --- re-resolved whenever the CVar moves (`Events.CVAR_UPDATE`).
        ---
        --- **`ActionButtonUseKeyDown` is a setting about keys**, and this is a click on somebody
        --- else's frame. It is what `nil` follows because it is the only place the game asks the
        --- question at all, and because the key side of the addon already falls to it: a reader
        --- who answered it once should not have to answer it twice.
        local onMouseDown = DebindPrivate.Options.unitframeUseMouseDown;
        if (onMouseDown == nil) then
            onMouseDown = GetCVarBool("ActionButtonUseKeyDown") and true or false;
        end
        --- **강화 주문 입력도 같은 문으로 간다.** 설정의 값이 `0`이면 길게 누르기, `1`이면 두 번
        --- 누르기다(`Blizzard_SettingsDefinitions_Frame/Combat.lua`). 두 번 누르기에서는 쥐는
        --- 구간이 없어서 뗌 엣지로 놓을 것이 없고, 그 판단을 클릭 때 해야 한다.
        ---
        --- **빌드 때 읽으면 안 된다.** 버튼 캐시는 한 번도 안 지워지므로 이 값으로 구운 것이
        --- 설정을 바꾼 뒤에도 계속 나간다(`BindingAttrsCache`).
        local tapControls = GetCVarBool("empowerTapControls") and true or false;
        --- **A lockdown blocks the only door these have.** `SecureHandlerExecute` cannot cross
        --- one, and no other path pushes them, so an answer given during a fight used to
        --- reach nothing and go on not reaching it for the rest of the session while the menu
        --- showed it as the one chosen. Both doors are open in combat: the CVar moves whenever the
        --- game says so (`Events.CVAR_UPDATE`), and the options menu takes the answer with the
        --- window up. Login is a third, since a reconnect into an encounter arrives locked down.
        ---
        --- The values are not carried, only the fact that one is owed. Whatever is read when the
        --- fight ends is the answer that stands then, which is the right one if the reader moved
        --- it twice while it could not cross.
        if (InCombatLockdown()) then
            DebindPrivate.secureValuesSuspended = true;
        else
            DebindPrivate.secureValuesSuspended = nil;
            SecureHandlerExecute(BindingDriver,
                format("ClickCastOnMouseDown=%s EmpowerTapControls=%s",
                    tostring(onMouseDown), tostring(tapControls)));
        end
    end

    --- **A unit watch header is a `SecureGroupHeaderTemplate`, so the attribute cannot be written
    --- during a fight.** A header built later reads the same option for itself
    --- (`CreateUnitWatchHeader`), so what is left here is the ones that already exist.
    if (option == nil or option == "excludePlayer") then
        if (not InCombatLockdown()) then
            local excluded = DebindPrivate.Options.excludePlayer;
            local units = DebindPrivate.EXCLUDE_PLAYER_UNITS;
            for i = 1, #units do
                local header = DebindPrivate.GetUnitWatchHeader(units[i]);
                if (header) then
                    header:SetAttribute("showPlayer", not (excluded and excluded[units[i]]));
                end
            end
        end
    end
end

--- What is left once the bindings are up: drop what this rebuild made stale, put the reader's own
--- options back, and say that it happened.
---
--- **All of them, not the throttle alone.** No option setter reaches a secure frame itself
--- (`ApplyOptions`), so this is the one hand that writes what a setter asked for -- and a rebuild
--- refused during a fight is replayed once it ends, which is what defers them.
local function FinishBindingUpdate()
    DebindPrivate.ClearMacroTextCache(_macrotexts);

    DebindPrivate.ApplyOptions();

    DebindPrivate.callbacks:Fire("OnBindingsUpdated");

    if (DEBUG) then
        dump("UpdateBindings", {
            unitsSeen = _unitsSeen,
            bindingAttrsCache = BindingAttrsCache,
            macrotexts = _macrotexts,
            macrotextBindings = _macrotextBindings,
            switches = _switches,
        });
    end
end

function DebindPrivate.UpdateBindings()
    local ok, why = CanBuildBindings();
    if (not ok) then
        -- **Only combat is owed a retry.** An unknown specialization asks itself again from
        -- `Events.lua`, so there is nothing here to remember about it.
        if (why == "combat") then
            DebindPrivate.updateBindingsSuspended = true;
            DebindPrivate.callbacks:Fire("OnBindingsSuspended");
        end
        return;
    end

    local ctx = CollectBindingContext();
    ClearPreviousBindings();
    local plan = BuildBindingPlan(ctx);
    ApplyBindingPlan(plan);
    FinishBindingUpdate();

    return true;
end

--- The steps that answer without doing anything.
---
--- **This is what the split was for.** `BuildBindingPlan` answers "what would this profile come
--- to" without touching the game, so which state driver events a profile registers -- six
--- decisions that could previously only be read off a live `SecureStateDriverManager` -- is now a
--- table a spec compares (`tests/plan_spec.lua`).
---
--- **The other two are not here.** `ApplyBindingPlan` and `FinishBindingUpdate` are reached the
--- only way that would mean anything, by running a rebuild; a name put out for symmetry is a name
--- nothing has ever called.
DebindPrivate.CanBuildBindings = CanBuildBindings;
DebindPrivate.CollectBindingContext = CollectBindingContext;
DebindPrivate.BuildBindingPlan = BuildBindingPlan;

--- One binding's attributes, worked out but not yet written anywhere.
---
--- **Two parallel arrays rather than a list of pairs**, because an attribute value is allowed to
--- be nil -- `*macrotext-` is cleared for a macro and `*macro-` for macro text -- and a nil in a
--- list of pairs is a hole `#` cannot see past. `count` is what says how long they are.
---
--- **One table, refilled.** A rebuild allocates nothing it can reuse, so the descriptor a caller
--- gets back is only good until the next `DescribeBinding` call. Everything that reads one
--- consumes it on the spot.
local _descriptor = { attrNames = {}, attrValues = {}, count = 0 };

--- What the client answered for the binding being described. One table, refilled, same as above.
local _facts = {};

--- **DEBUG only.** One row per spell binding of this rebuild, filled at the stamp where the key is
--- still in hand. `_facts` cannot show this: it is wiped per binding, so after a rebuild it holds
--- the last one and nothing else.
---
--- **Do not reassign.** DevTool holds this reference; a rebuild wipes and refills it.
DebindPrivate.SpellFacts = {};
DebindPrivate.dump("SpellFacts", DebindPrivate.SpellFacts);

--- Appends one attribute to a descriptor. **A nil value is meaningful** -- it clears the attribute
--- -- and assigning nil into the reused array is what stops the previous descriptor's value from
--- standing in for it.
local function attr(out, name, value)
    local count = out.count + 1;
    out.count = count;
    out.attrNames[count] = name;
    out.attrValues[count] = value;
end

--- What the game has to be asked before a binding can be described. **Every call to the client in
--- this whole path is here**, which is what leaves `DescribeBinding` with nothing to ask.
---
--- A spec hands these in as plain values instead: it is standing a world up, not imitating an API
--- (`going-headless-outside-the-ui.md` §4).
local function CollectBindingFacts(type, value, unit, facts, automatics, pinnedSpell, resolvedSpellID)
    wipe(facts);
    facts.pinnedSpell = pinnedSpell;

    -- A resolved spec type is a spell from here on; one that resolved to nothing asks nothing.
    if (Constants.SPEC_RESOLVED_TYPES[type] and value ~= nil) then
        type = Constants.SPELL;
    end

    if (type == Constants.PETACTION) then
        facts.petMacrotext = DebindPrivate.GetPetActionMacroText(value, unit);
    elseif (type == Constants.FLYOUT) then
        facts.flyoutOpener = DebindPrivate.GetFlyoutOpener(value);
    elseif (type == Constants.ACTIONBUTTON) then
        local info = Constants.ACTION_BUTTON_COMMANDS[value];
        if (info) then
            facts.barButton = _G[info.button];
            facts.overrideButton = info.override and _G[info.override];
        end
    elseif (type == Constants.SPELL) then
        -- **The name comes off the base and not off the stored id.** A talent version's name only
        -- exists while that talent is taken, so a button carrying it goes dead the moment the
        -- reader drops the talent; the base's name casts the talent version when it is taken and
        -- the plain one when it is not.
        --
        -- `ResolveBaseSpell` and not `FindBaseSpellByID`: the client places a stored id only while
        -- the talent combination that created it still stands, and the name index is what reaches
        -- the base after that (`Spells.lua`).
        local spellID = DebindPrivate.ResolveBaseSpell(value, resolvedSpellID);
        -- **A stored name is asked again at every rebuild** and from here on is the id it resolved
        -- to, so a specialization change resolves it through the new one's index. One that
        -- resolves to nothing, not even through the id stored beside it, goes on the button as it
        -- is.
        if (luatype(value) == "string") then
            facts.namedSpellID = spellID;
            if (spellID == nil) then
                facts.spellName = value;
                facts.pressAndHold = false;
                return facts;
            end
            value = spellID;
        end
        facts.spellID = spellID;
        facts.spellName = GetSpellNameAndIconID(spellID);
        if (facts.spellName) then
            -- **A pinned rank's subtext is the pinned id's**, since the rank is what the reader
            -- picked. A pin held as text needs none (`DescribeBinding` casts the text).
            facts.spellSubtext = GetSpellSubtext(luatype(pinnedSpell) == "number" and pinnedSpell or spellID);
        end
        facts.pressAndHold = IsPressHoldReleaseSpell(value) and true or false;
    elseif (type == Constants.MOUNT) then
        -- **Whether the journal names a spell is the fork, not whether that spell has a name.**
        -- A mount with a spell id goes out as a spell even where the name does not resolve; the
        -- macro text is only for the ones the journal answers no spell for.
        local _, spellID = GetMountInfoByID(value);
        facts.mountSpellID = spellID;
        if (spellID) then
            facts.mountSpellName = GetSpellNameAndIconID(spellID);
        else
            facts.mountMacrotext = DebindPrivate.GetMountMacroText(value,
                DebindPrivate.UnshiftsWith(
                    DebindPrivate.CastAutomaticInKey(automatics, "autoUnshift")));
        end
    end

    return facts;
end

--- What has to be stamped on the click frame for one binding to be able to fire, or **nil and a
--- reason**.
---
--- **The reason is the point of this function existing apart from the stamping.** A binding with
--- no way to fire used to leave one DEBUG log line and nothing else, and the caller had to infer
--- the refusal from a missing return value. Getting that wrong takes the **whole key**: the secure
--- side counts an emitted record as a binding that took, so `keyBound` goes up, and every lower
--- priority action on that key is blocked along with it. A hunter with no pet and a Call Pet
--- binding is the case.
---
--- Nothing here asks the client anything. Everything it needs is in `facts`.
local function DescribeBinding(type, value, unit, facts, out, automatics)
    out = out or { attrNames = {}, attrValues = {} };
    out.count = 0;

    -- **A block writes no attribute and is not a refusal.** It wins the press to do nothing with it.
    if (type == Constants.BLOCK) then
        return nil, "block";
    end

    -- 펫 명령은 **여기서 MACROTEXT가 된다.** 아래에 자기 갈래를 두면 세 가지를 각각 다시
    -- 만들어야 하는데, 셋 다 이미 매크로텍스트 쪽에 있다:
    --
    --   1. 캐시 키. `BindingAttrsCache`는 (type, value)로만 잡고 **한 번도 안 지운다.**
    --      대상을 본문에 굽는 타입이 자기 갈래를 가지면 같은 명령 + 다른 대상 둘이 한 버튼을
    --      나눠 쓰고, 뒤엣것이 앞엣것의 본문을 실행한다. 본문 자체를 value로 만들면 대상이
    --      키에 들어가므로 그 일이 없다. (캐시 자체는 여전히 이 구조다 - refactor-candidates 18)
    --   2. `@custom1`·`@hover`·`@tank`는 진짜 유닛 토큰이 아니다. 바꿔주는 것이
    --      `addMacrotextBinding` -> `ParseMacroText`이고, 그건 MACROTEXT에만 걸려 있다.
    --      (`@custom1`·`@unitframe`·`@tank` 이야기다.)
    --   3. unit을 여기서 떨군다. 본문이 대상을 들고 있으므로 delegate 프레임이 할 일이
    --      없다(`SECURE_ACTIONS.macro`는 버튼의 unit을 안 본다).
    --
    -- `*type-="pet"`을 안 쓰는 이유는 따로다. 그쪽은 `CastPetAction(슬롯, unit)`이라 unit이
    -- 공짜로 오지만 **슬롯이 펫마다 다르고 전투 중에는 못 고친다** - 전투 중에 펫이 바뀌면
    -- 그 바인딩이 남은 전투 내내 엉뚱한 명령을 실행한다. 안 되는 것보다 나쁘다.
    if (type == Constants.PETACTION) then
        if (not facts.petMacrotext) then
            return nil, "unknown-pet-action";
        end
        type, value, unit = Constants.MACROTEXT, facts.petMacrotext, nil;
    end

    -- **A spec-resolved type with no spell writes no attribute at all, and is not a refusal.** A
    -- refusal eats the whole key (below); what the design asks for is a key that stays ours and a
    -- press that does nothing, and a button with no `*type-` on it is exactly that. One such
    -- button per type: the cache files it under the type with a nil value.
    if (Constants.SPEC_RESOLVED_TYPES[type]) then
        if (value == nil) then
            out.type = type;
            out.value = nil;
            out.unit = nil;
            out.cacheKey = NIL;
            out.castsAtUnit = false;
            out.pressAndHold = false;
            out.castSpell = nil;
            return out;
        end
        type = Constants.SPELL;
    end

    out.type = type;
    out.value = value;
    out.unit = unit;
    out.actionSlot = nil;
    out.barButton = nil;
    out.overrideButton = nil;
    out.castSpell = nil;

    -- **The key the stamp files this button under**, taken before any branch below rewrites the
    -- value for its own attribute. It used to be read after, and only the item branch rewrites --
    -- so an item binding was looked up under `6948` and filed under `"item:6948"`, which is a
    -- cache that never hits and a button allocated afresh on every rebuild, for the whole session.
    --
    -- **`unit` is not in the key, and a new action type has to be checked against that.** A cache
    -- hit means the attributes below were not written at all (`StampBinding`), so two bindings that
    -- share a type and a value share a button -- which is only sound while the unit lives on the
    -- delegate frame rather than in an attribute. Bake the target into an attribute and the second
    -- binding silently gets the first one's target, and the symptom is "it aims at the wrong unit
    -- sometimes", a long way from here.
    --
    -- Pet commands are the one type that breaks the premise, and they dodge it above rather than
    -- here: the target goes into the macro body and the body becomes the value, so it is in the key
    -- after all. A type that cannot do that needs the key widened instead.
    -- **우리가 쓴 본문은 CVar 줄을 스스로 나른다.** 매크로 안에서 매크로가 안 돌아서 주문처럼
    -- `/click`으로 감쌀 수가 없고, 감쌀 필요도 없다. 본문이 우리 문자열이다.
    if (automatics) then
        if (type == Constants.MACROTEXT) then
            value = AutomaticsWrap(value, automatics);
            -- **위에서 잡아 둔 `out.value`를 고쳐 쓴다.** 등록되는 본문이 그 값이고
            -- (`addMacrotextBinding`), 안 고치면 인자가 든 본문은 첫 누름에 조각에서 다시
            -- 지어지면서 CVar 줄이 영영 벗겨진다.
            out.value = value;
        elseif (type == Constants.MOUNT and facts.mountMacrotext) then
            facts.mountMacrotext = AutomaticsWrap(facts.mountMacrotext, automatics);
        end
    end

    out.cacheKey = value or NIL;
    -- **A stored name is filed under the id it resolved to.** What it resolves to moves with the
    -- specialization, and a hit writes nothing, so filed under the name the button would go on
    -- casting whatever the first rebuild resolved.
    if (type == Constants.SPELL and facts.namedSpellID) then
        out.cacheKey = facts.namedSpellID;
    end
    -- **A pinned rank is another button than the highest rank of the same spell**, which shares the
    -- id and would otherwise be handed the other's, and two pins of one spell are two buttons.
    if (facts.pinnedSpell ~= nil and type == Constants.SPELL and value ~= nil) then
        out.cacheKey = tostring(out.cacheKey) .. ":rank:" .. tostring(facts.pinnedSpell);
    end

    -- **탈것의 본문은 탈것 하나로 안 정해진다.** `/cancelform` 줄이 `autoUnshift`를 따르고 CVar
    -- 줄도 액션마다 달라서, 같은 탈것이 여러 꼴로 구워진다. 열쇠가 탈것 번호뿐이면 먼저 구운
    -- 것이 나중 것에게 간다. 이 캐시는 한 번도 안 지워지므로 CVar가 움직인 뒤에도 같은 일이
    -- 난다. 본문을 value로 만들 수 없는 타입이라 열쇠를 넓힌다(위 펫 명령 주석의 마지막 문장).
    if (type == Constants.MOUNT and facts.mountMacrotext) then
        out.cacheKey = facts.mountMacrotext;
    end

    -- **Which actions the engine's automatic self-cast can reach**, and equally which ones may be
    -- fired from inside a macro body -- a `macro` type nested in one does not run. The three
    -- spec-resolved types are already rewritten to `SPELL` above, so they are in.
    --
    -- **A mount goes out as one of two things and only one of them belongs here.** Where the
    -- journal names a spell it is stamped `*type-="spell"` and a `/click` fires it; where it does
    -- not, the body is a macro of ours and carries what it needs itself. Reading the type alone
    -- would leave the same mount answering the action's values or ignoring them depending on what
    -- the journal happens to hold.
    out.castsAtUnit = type == Constants.SPELL or type == Constants.ITEM
        or type == Constants.USESLOT
        or (type == Constants.MOUNT and facts.mountSpellID ~= nil);

    if (type == Constants.SPELL) then
        attr(out, "*type-", "spell");
        -- **A name and not an id**, and the id was tried (2026-09-12, owner, in the game). The
        -- client files the same spell under a different id per specialization and the two are not
        -- related: Starfire is 194153 on Balance and 197628 on Restoration, Starsurge 78674 and
        -- 197626, Remove Corruption 2782 and 440015. Neither `FindBaseSpellByID` nor
        -- `GetBaseSpell` walks from one to the other, so an id baked here dies the moment the
        -- reader changes specialization. The subtext comes along because that is what tells two
        -- same-named spells apart (`Spells.lua`'s `ComposeSpellCastName`).
        -- **레코드가 싣는 것도 이 값 그대로다.** 클릭 때 이 주문을 다시 묻는 쪽이 있고
        -- (`BuildKeyRecord`), 둘을 따로 만들면 언젠가 갈린다.
        -- A pin held as text is what a Clique binding cast, and goes out as it is.
        if (luatype(facts.pinnedSpell) == "string") then
            out.castSpell = facts.pinnedSpell;
        else
            out.castSpell = ComposeSpellCastName(facts.spellName, facts.spellSubtext, facts.pinnedSpell ~= nil)
                or facts.spellID;
        end
        attr(out, "*spell-", out.castSpell);

        -- **유지·시전 주문의 `*typerelease-`는 여기서 안 굽는다.** 클릭 때 쓴다
        -- (`SecureBindings.lua`). 여기 구우면 이 블록이 캐시 적중으로 통째로 건너뛰어지는 것도
        -- 문제고, 무엇보다 위의 `*spell-`이 **이름**이라 그 이름이 가리키는 주문이 덮이면 구운
        -- 답이 틀린 답이 된다.
    elseif (type == Constants.ITEM) then
        attr(out, "*type-", "item");
        -- **A stored name goes on as it is**, since `*item-` takes what `/use` takes
        -- (`importing-clique-profiles.md` §4). So does a string of digits, which `*item-` reads as
        -- an inventory slot -- the meaning it had in the Clique profile it came from.
        if (luatype(value) == "string") then
            attr(out, "*item-", value);
        else
            attr(out, "*item-", format("item:%d", value));
        end
    elseif (type == Constants.USESLOT) then
        -- **A bare number, and that is what makes it a slot.** `SecureCmdItemParse` reads two
        -- numbers as a bag pair and one as an inventory slot, so `"13"` reaches
        -- `UseInventoryItem(13)` -- the same call `/use 13` makes. `item:%d` here would name an
        -- item id instead.
        attr(out, "*type-", "item");
        attr(out, "*item-", tostring(value));
    elseif (type == Constants.MACRO) then
        attr(out, "*type-", "macro");
        attr(out, "*macro-", value);
        attr(out, "*macrotext-", nil);
    elseif (type == Constants.MACROTEXT) then
        attr(out, "*type-", "macro");
        attr(out, "*macro-", nil);
        attr(out, "*macrotext-", value);
    elseif (type == Constants.MOUNT) then
        if (facts.mountSpellID) then
            attr(out, "*type-", "spell");
            attr(out, "*spell-", facts.mountSpellName);
        else
            attr(out, "*type-", "macro");
            attr(out, "*macro-", nil);
            attr(out, "*macrotext-", facts.mountMacrotext);
        end
    elseif (type == Constants.TARGET) then
        attr(out, "*type-", "target");
    elseif (type == Constants.FOCUS) then
        attr(out, "*type-", "focus");
    elseif (type == Constants.TOGGLEMENU) then
        attr(out, "*type-", "togglemenu");
    elseif (type == Constants.SETCUSTOM) then
        attr(out, "*type-", "attribute");
        attr(out, "*attribute-frame-", DebindPrivate.UnitWatch);
        attr(out, "*attribute-name-", "custom" .. value);
        attr(out, "*attribute-value-", "unitframe");
    elseif (Constants.SETSWITCH_MODES[type]) then
        -- **The type decides the mode, so the name is all that is left to be wrong.** What
        -- this guard turned away while the value was a bitpack was an undecodable mode; the
        -- name inherits the place. Handing `SetAttribute` a nil name raises nothing -- it
        -- clears the attribute -- and the key then dies quietly on the restricted side.
        if (luatype(value) ~= "string") then
            return nil, "switch-not-chosen";
        end
        attr(out, "*type-", "attribute");
        attr(out, "*attribute-frame-", DebindPrivate.SwitchesUpdaterFrame);
        attr(out, "*attribute-name-", value);
        attr(out, "*attribute-value-", Constants.SETSWITCH_MODES[type]);
    elseif (type == Constants.FLYOUT) then
        -- **`*type- = "flyout"`을 안 쓴다.** 블리자드의 그 갈래는 `SpellFlyout:Toggle(self, ...)`
        -- 한 줄이고 그 `self`는 `FlyoutButtonMixin`이어야 한다(`GetPopupDirection`을 부른다).
        -- 여기 `clickframe`은 맨몸 `SecureActionButtonTemplate`이라 nil 메서드 호출로 죽는다.
        -- 자세한 사정은 `Flyout.lua` 머리주석에 있다.
        --
        -- 대신 우리 손잡이를 클릭한다. 손잡이의 보안 스니펫이 커서 위치에 우리 플라이아웃을
        -- 열고, 그건 전투 중에도 돈다.
        --
        -- **살아있는지는 캐시보다 먼저 본다.** 캐시 적중은 "속성을 다시 안 써도 된다"는 뜻이지
        -- "아직 쓸 수 있다"는 뜻이 아닌데, 플라이아웃은 그 둘이 갈라진다. 마지막 야수를
        -- 놓아주면 `RebuildFlyout`이 `numSlots = 0`으로 만들고 `GetFlyoutOpener`가 nil을 준다.
        -- 그 검사가 캐시 안쪽에 있던 동안에는 적중에 통째로 건너뛰어졌고, 바인딩이 그대로
        -- 남았다. 눌러도 아무 일이 없는 데다 `keyBound`가 서므로 **그 키의 하위 Debind
        -- 바인딩까지 전부 막힌다** - 캐시를 안 지우니 `/reload` 전에는 안 풀렸다.
        if (not facts.flyoutOpener) then
            -- 안 배웠거나 슬롯이 전부 비었다(길들인 야수가 없는 야수 소환 등).
            return nil, "no-flyout-opener";
        end
        attr(out, "*type-", "click");
        attr(out, "*clickbutton-", facts.flyoutOpener);
    elseif (type == Constants.WORLDMARKER) then
        attr(out, "*type-", "worldmarker");
        attr(out, "*marker-", value);
    elseif (type == Constants.ACTIONBUTTON) then
        -- `*action-` is the press's to write: the main bar's page moves with vehicles and forms, and
        -- a flyout slot goes to the bar button instead (`SecureBindings.lua`'s `ACTION_SLOT_SNIPPET`).
        local info = Constants.ACTION_BUTTON_COMMANDS[value];
        if (not info) then
            return nil, "unknown-action-button";
        end
        if (info.pet) then
            attr(out, "*type-", "pet");
            attr(out, "*action-", info.index);
            -- No slot to work out, but the press still asks whether there is a pet.
            out.actionSlot = info;
        elseif (info.stance) then
            if (not facts.barButton) then
                return nil, "no-stance-button";
            end
            attr(out, "*type-", "click");
            attr(out, "*clickbutton-", facts.barButton);
        else
            attr(out, "*type-", "action");
            out.actionSlot = info;
            out.barButton = facts.barButton;
            out.overrideButton = facts.overrideButton;
        end
    else
        return nil, "unhandled-type";
    end

    out.pressAndHold = facts.pressAndHold and true or false;
    return out;
end

--- Writes a descriptor onto the click frame and answers what a record has to carry to reach it.
---
--- **The cache is this side's business, and `DescribeBinding` knows nothing about it.** A hit
--- means the attributes are already there under a button name we handed out earlier, so nothing
--- is written at all.
--- A button on the click frame that clicks one of Blizzard's bar buttons, made once per bar button.
--- Cached for the session the way `BindingAttrsCache` is: the bar buttons never go away.
local function BarClickButton(frame)
    if (not frame) then
        return nil;
    end
    local buttonname = _barClickButtons[frame];
    if (not buttonname) then
        buttonname = NextButtonName();
        DefaultClickFrame:SetAttribute("*type-" .. buttonname, "click");
        DefaultClickFrame:SetAttribute("*clickbutton-" .. buttonname, frame);
        _barClickButtons[frame] = buttonname;
    end
    return buttonname;
end

local function StampBinding(descriptor, automatics)
    local type, value, unit = descriptor.type, descriptor.value, descriptor.unit;

    local buttonname = BindingAttrsCache[type] and BindingAttrsCache[type][descriptor.cacheKey];
    local clickframe = DefaultClickFrame;
    local delegate = unit and unit ~= "" and DebindPrivate.GetDelegateFrame(unit) or nil;

    -- **캐시 적중은 "속성을 하나도 안 건드렸다"는 뜻이다.** 아래 블록을 통째로 건너뛴다.
    -- 그게 맞을 때가 대부분이지만, 키에 안 들어간 무언가(unit 등)가 달라졌으면 그게 곧
    -- 옛날 설정으로 도는 버그다. 로그가 없으면 이 분기는 화면에 흔적을 안 남긴다.
    if (DEBUG and buttonname) then
        DebindPrivate.log(format("|cffffcc66[Debind/cache]|r HIT %s/%s -> %s (unit=%s) 속성 갱신 안 함",
            tostring(type), tostring(value), tostring(buttonname), tostring(unit)));
    end

    if (not buttonname) then
        buttonname = NextButtonName();

        local names, values = descriptor.attrNames, descriptor.attrValues;
        for i = 1, descriptor.count do
            clickframe:SetAttribute(names[i] .. buttonname, values[i]);
        end

        if (descriptor.actionSlot) then
            _actionSlots[buttonname] = {
                info = descriptor.actionSlot,
                bar = BarClickButton(descriptor.barButton),
                overrideBar = BarClickButton(descriptor.overrideButton),
            };
        end

        if (unit and unit ~= "" and not delegate) then
            if (DEBUG) then
                DebindPrivate.log("No delegate frame for:", unit);
            end
        end

        -- 버튼에 방금 쓴 것. 속성은 열거가 안 되므로 **여기서 안 찍으면 다시 볼 수 없다.**
        -- 보안 쪽 짝은 `SecureBindings.lua`의 `printMacroText`이고, 둘을 같이 봐야
        -- "본문이 틀렸나"와 "본문이 아예 안 올라갔나"가 갈린다.
        if (DEBUG) then
            DebindPrivate.log(format("|cff88ff88[Debind/attr]|r SET %s/%s -> %s : %s",
                tostring(type), tostring(value), tostring(buttonname),
                tostring(clickframe:GetAttribute("*macrotext-" .. buttonname)
                    or clickframe:GetAttribute("*spell-" .. buttonname)
                    or clickframe:GetAttribute("*macro-" .. buttonname)
                    or clickframe:GetAttribute("*item-" .. buttonname)
                    or clickframe:GetAttribute("*type-" .. buttonname))));
        end

        BindingAttrsCache[type] = BindingAttrsCache[type] or {};
        BindingAttrsCache[type][descriptor.cacheKey] = buttonname;
    end

    -- **감싼 버튼은 자기 이름을 따로 받는다.** 값이 다른 액션 둘이 안쪽 버튼은 같이 쓰고 감싼
    -- 것만 갈린다. `nil`은 넷 다 기본이라는 뜻이고, 그때는 감쌀 것이 없어 이 아래가 통째로
    -- 없는 일이 된다.
    --
    if (automatics and descriptor.castsAtUnit) then
        local byKey = WrappedAttrsCache[type];
        if (not byKey) then
            byKey = {};
            WrappedAttrsCache[type] = byKey;
        end
        local byAutomatics = byKey[descriptor.cacheKey];
        if (not byAutomatics) then
            byAutomatics = {};
            byKey[descriptor.cacheKey] = byAutomatics;
        end

        local wrapped = byAutomatics[automatics];
        if (not wrapped) then
            -- **엣지 토큰은 언제나 굽고, 짝도 언제나 만든다.** 유지·시전인지는 누를 때 정해지고
            -- (`SecureBindings.lua`, 덮인 주문까지 따라가려고 그렇게 한다), 이 버튼은 세션 내내
            -- 캐시에 남는다. 굽는 쪽이 그 답을 미리 정하면 둘이 갈리는 날 조용히 죽는다.
            --
            -- 한 버튼은 본문을 하나만 들 수 있어서 내림과 올림이 버튼 둘로 갈린다. 게이트가
            -- 올림에서 읽는 것은 `*typerelease-`라 짝은 그 속성으로 선다.
            wrapped = NextButtonName();
            DefaultClickFrame:SetAttribute("*type-" .. wrapped, "macro");
            DefaultClickFrame:SetAttribute("*macrotext-" .. wrapped,
                AutomaticsBody(automatics, buttonname, "true"));
            byAutomatics[automatics] = wrapped;
            _wrappedButtons[wrapped] = buttonname;

            -- 주문만 유지·시전이 될 수 있다. 아이템과 장비칸은 그 답이 영영 거짓이라 짝을
            -- 만들어 둬도 아무도 안 누른다.
            if (type == Constants.SPELL) then
                local release = NextButtonName();
                -- `*type-`은 안 단다. 이 이름은 올림에서만 돌아가고, 달아 두면 내림으로 새어
                -- 들어올 길이 하나 생긴다.
                DefaultClickFrame:SetAttribute("*typerelease-" .. release, "macro");
                DefaultClickFrame:SetAttribute("*macrotext-" .. release,
                    AutomaticsBody(automatics, buttonname, "false"));
                _wrappedRelease[wrapped] = release;
                _wrappedButtons[release] = buttonname;
            end

            -- **캐스트 프레임은 액션의 사본을 따로 받고, 물려받는 것은 안 된다.** 예전에는
            -- `useparent*`로 닿았는데 그건 읽을 때만 맞고 시전이 안 된다(그 프레임을 세우는
            -- `Debind.lua`가 무엇을 쟀는지 적고 있다). 감싼 본문이 그 프레임을 누르는 유일한
            -- 것이라 감싼 버튼이 생길 때만 복사한다.
            local castframe = DebindPrivate.CastFrame;
            local names, values = descriptor.attrNames, descriptor.attrValues;
            for i = 1, descriptor.count do
                castframe:SetAttribute(names[i] .. buttonname, values[i]);
            end
        end

        -- **대리 프레임으로 안 간다.** 나가는 것이 매크로라 버튼의 `unit`을 아무도 안 읽는다.
        -- 누름의 대상은 클릭 때 캐스트 프레임에 얹힌다(`SecureBindings.lua`).
        return DefaultClickFrame, wrapped;
    end

    return delegate or clickframe, buttonname;
end

DebindPrivate.DescribeBinding = DescribeBinding;
DebindPrivate.StampBinding = StampBinding;

--- Asks, describes, stamps. **The reason a binding was refused is dropped here and nowhere else**,
--- because the caller's shape still cannot carry one; stage 3 of
--- `going-headless-outside-the-ui.md` is where the record loop learns to.
function SetBindingAttributes(type, value, unit, automatics, pinnedSpell, resolvedSpellID)
    local facts = CollectBindingFacts(type, value, unit, _facts, automatics, pinnedSpell, resolvedSpellID);

    local descriptor, reason = DescribeBinding(type, value, unit, facts, _descriptor, automatics);
    if (not descriptor) then
        if (DEBUG and reason ~= "block") then
            DebindPrivate.log("No attributes for:", type, value, reason);
        end
        return;
    end

    local clickframe, buttonname = StampBinding(descriptor, automatics);

    if (descriptor.type == Constants.MACROTEXT) then
        addMacrotextBinding(buttonname, descriptor.value);
    end

    return clickframe, buttonname, descriptor.castSpell;
end

--- **The names are the role headers' aliases**, which is what `UnitRoles` stores, so nothing
--- translates between the two sides. `unknown` has no header, and cannot: it is the answer for a
--- unit no header claimed.
--- The four cells, as the names both sides speak. **Not the three boxes a user ticks**: those
--- overlap and so cannot name the one thing a unit is (`Constants.lua`'s `UNITGROUPCELL_*`).
local UNITGROUPCELL_NAMES = {
    [Constants.UNITGROUPCELL_NEITHER] = "neither",
    [Constants.UNITGROUPCELL_PARTY]   = "party",
    [Constants.UNITGROUPCELL_RAID]    = "raid",
    [Constants.UNITGROUPCELL_BOTH]    = "both",
};

local ROLE_NAMES = {
    [Constants.ROLE_TANK]    = "tank",
    [Constants.ROLE_HEALER]  = "healer",
    [Constants.ROLE_DAMAGER] = "damager",
    [Constants.ROLE_NONE] = "norole",
};

---
--- Two conditions on one unit, merged into one.
---
--- **`"@"` lands on the unit the binding aims at**, so where that unit carries a condition of its
--- own, both are written under the same key of `t.units`. Unmerged, `pairs` order decides which one
--- survives, and a condition the reader set disappears at random.
---
--- Values carry one field per axis (`Migration.lua`'s `dbver <= 4` step), so merging is an
--- intersection **per axis**. One empty axis leaves no state at all, which is `NEVER` for the
--- whole condition.
---
--- ============================================================================================
--- `NEVER` IS UNREACHABLE. DO NOT BUILD A RUNTIME REPRESENTATION FOR IT.
--- ============================================================================================
---
--- Every way this function can return `NEVER` is a zero mask in `binding.unitStates`:
---
---   absent vs a constrained axis   `band(UNITSTATE_NONE, ...)`  == 0
---   reactions do not overlap       `band(reaction, reaction)`   == 0
---   life asked both ways           `band(ALIVE, DEAD)`          == 0
---
--- `BuildUnitStates` folds the same conditions with the same intersection, `FillBinding` marks
--- a binding with a zero `dead`, and `BuildKeyMap`'s `UnrollIntoTiers` leaves every such binding off
--- the key, one binding at a time. So a binding that cannot stand reaches **neither the solver nor
--- this file**, whatever its action's other bindings do.
---
--- That makes `NEVER` a backstop for one thing only: **the two intersections disagreeing.** Two
--- implementations of one rule -- this one and `BuildUnitStates` -- which is why the redesign
--- notes want this function gone once the runtime speaks masks.
---
--- The caller answers a `NEVER` by **not emitting the binding at all**. Do not reach for a marker
--- value or a `never` field instead. Anything carried into the secure environment is paid for
--- three times: the match loop walks and rejects the record on every re-selection, its units get
--- registered so the update loop measures them every tick forever, and a marker field costs every
--- *ordinary* condition a lookup on a path that runs thousands of times in a fight. All of that
--- to carry a case that cannot happen.
local NEVER = {};

local function mergeUnitConditions(a, b)
    if (a == nil) then return b; end
    if (b == nil) then return a; end
    if (a == NEVER or b == NEVER) then return NEVER; end

    -- `false` is "absent". The absent point sits on no axis, so it cannot overlap with a condition
    -- that constrains one -- but two conditions that both say "absent" agree, and that has to come
    -- back as `false`. Spelled out rather than `and false or`: that idiom cannot return `false`,
    -- so it answered `NEVER` for the one case it was written to let through and the binding was
    -- dropped without any issue being reported.
    if (a == false or b == false) then
        if (a == b) then
            return false;
        end
        return NEVER;
    end

    local reaction = a.reaction;
    if (reaction == nil) then
        reaction = b.reaction;
    elseif (b.reaction ~= nil) then
        reaction = band(reaction, b.reaction);
        if (reaction == 0) then
            return NEVER;
        end
    end

    local dead = a.dead;
    if (dead == nil) then
        dead = b.dead;
    elseif (b.dead ~= nil and b.dead ~= dead) then
        return NEVER;
    end

    -- **Only two picked sets that do not meet are NEVER.** A row with no role picked is already
    -- empty and still runs over every frame that is not a party or raid frame, which is the only
    -- kind a role is measured on (`Units.lua`'s `RoleLeavesNothing`); meeting it keeps that.
    local role = a.role;
    if (role == nil) then
        role = b.role;
    elseif (b.role ~= nil) then
        local met = band(role, b.role);
        if (met == 0 and role ~= 0 and b.role ~= 0) then
            return NEVER;
        end
        role = met;
    end

    local frameTypes = a.frameTypes;
    if (frameTypes == nil) then
        frameTypes = b.frameTypes;
    elseif (b.frameTypes ~= nil) then
        frameTypes = band(frameTypes, b.frameTypes);
        if (frameTypes == 0) then
            return NEVER;
        end
    end

    local group = a.group;
    if (group == nil) then
        group = b.group;
    elseif (b.group ~= nil) then
        group = band(group, b.group);
        if (group == 0) then
            return NEVER;
        end
    end

    return { reaction = reaction, dead = dead, role = role, group = group, frameTypes = frameTypes };
end

--- The condition axes that go out as a plain field, **in the order they are emitted in**, with the
--- value that means "no restriction" for the three that have one.
---
--- `known` carries `derived`: what goes out is not the condition's value but the macro conditional
--- built from the action's own value.
local CONDITION_AXES     = {
    { field = "groups",     allValue = Constants.GROUP_ALL },
    { field = "combat" },
    { field = "stealth" },
    { field = "mounted" },
    { field = "indoors" },
    { field = "flyable" },
    { field = "advflyable" },
    { field = "flying" },
    { field = "skyriding" },
    { field = "known",      derived = true },
    { field = "forms",      allValue = Constants.FORM_ALL },
    { field = "bonusbars",  allValue = Constants.BONUSBAR_ALL },
    { field = "specialbar" },
    { field = "extrabar" },
    { field = "petbattle" },
};

--- **The state axes the press asks by parsing**, each as what a value of it is in macro conditionals:
--- a list of alternatives, each a list of tokens that must all hold. A record's `expr` is the product
--- of its axes' lists (`StateExpression`). The beat writes its texts from the same lists
--- (`StateCellText`), so the two parse one text.
---
--- **The expensive two go last in every group**, so a group already lost on a cheaper token never
--- judges them (7-1: `[<false>,flyable]` 0.23 against `[flyable,<false>]` 5.16).
local PARSED_STATE_AXES = {
    combat = true, stealth = true, mounted = true, indoors = true, flying = true, skyriding = true,
    groups = true, forms = true, bonusbars = true, specialbar = true, extrabar = true, petbattle = true,
    flyable = true, advflyable = true,
};
local PARSED_STATE_ORDER = {
    "groups", "combat", "stealth", "mounted", "indoors", "flying", "skyriding", "forms", "bonusbars",
    "specialbar", "extrabar", "petbattle", "flyable", "advflyable",
};

--- The offsets of a mask, `2 ^ n` per offset `n`, from `from` up to `to`.
local function MaskOffsets(mask, from, to)
    local out = {};
    for n = from, to do
        if (band(mask, 2 ^ n) ~= 0) then
            out[#out + 1] = n;
        end
    end
    return out;
end

--- One axis's value as alternatives of tokens.
local function StateAlternatives(axis, value)
    if (axis == "groups") then
        -- `[group:party]` holds in a raid as well (measured 2026-10-05), so a party that is not a
        -- raid needs `nogroup:raid` beside it.
        local none = band(value, Constants.GROUP_NONE) ~= 0;
        local party = band(value, Constants.GROUP_PARTY) ~= 0;
        local raid = band(value, Constants.GROUP_RAID) ~= 0;
        if (party and raid) then
            return none and {} or { { "group" } };
        elseif (none and party) then
            return { { "nogroup:raid" } };
        elseif (none and raid) then
            return { { "nogroup" }, { "group:raid" } };
        elseif (none) then
            return { { "nogroup" } };
        elseif (party) then
            return { { "group:party", "nogroup:raid" } };
        end
        return { { "group:raid" } };
    elseif (axis == "forms") then
        return { { "form:" .. tconcat(MaskOffsets(value, 0, 10), "/") } };
    elseif (axis == "bonusbars") then
        -- Offset 0 is `[nobonusbar:1/2/3/4/5]`: `[bonusbar:0]` does not match it and a bare
        -- `[nobonusbar]` is always true (measured 2026-10-05).
        local alternatives = {};
        if (band(value, 1) ~= 0) then
            alternatives[#alternatives + 1] = {
                "nobonusbar:" .. tconcat(MaskOffsets(Constants.BONUSBAR_ALL, 1, Constants.MAX_BONUSBAR_OFFSET), "/"),
            };
        end
        local offsets = MaskOffsets(value, 1, Constants.MAX_BONUSBAR_OFFSET);
        if (#offsets > 0) then
            alternatives[#alternatives + 1] = { "bonusbar:" .. tconcat(offsets, "/") };
        end
        return alternatives;
    elseif (axis == "skyriding") then
        return { { (value and "" or "no") .. "bonusbar:" .. Constants.BONUSBAR_SKYRIDING } };
    elseif (axis == "specialbar") then
        -- The words Keys Given Back already reads a replaced bar by (`GIVE_BACK_REPLACED_BAR`,
        -- `GIVE_BACK_PET_BATTLE`), so the two read one answer.
        if (value) then
            return { { "vehicleui" }, { "possessbar" }, { "overridebar" }, { "shapeshift" }, { "petbattle" } };
        end
        return { { "novehicleui", "nopossessbar", "nooverridebar", "noshapeshift", "nopetbattle" } };
    end
    return { { (value and "" or "no") .. axis } };
end

--- Every token a `StateExpression` has written since load. The kit reads it to hold a state at the
--- press, since a parsed word can only be held by rewriting the token (`DebindTest.lua`, `MockBody`).
local _stateTokens = {};
function DebindPrivate.StateExpressionTokens()
    return _stateTokens;
end

--- The record's state axes as one macro conditional, or nil where it has none. Parsed at the press
--- in one call (`EVAL_SNIPPET`).
local function StateExpression(record)
    local values = {};
    for i = 1, record.fieldCount do
        if (PARSED_STATE_AXES[record.fieldNames[i]]) then
            values[record.fieldNames[i]] = record.fieldValues[i];
        end
    end
    local groups = { {} };
    local any = false;
    for _, axis in ipairs(PARSED_STATE_ORDER) do
        local value = values[axis];
        if (value ~= nil) then
            any = true;
            local alternatives = StateAlternatives(axis, value);
            if (#alternatives > 0) then
                local product = {};
                for _, group in ipairs(groups) do
                    for _, alternative in ipairs(alternatives) do
                        local tokens = {};
                        for _, token in ipairs(group) do tokens[#tokens + 1] = token; end
                        for _, token in ipairs(alternative) do tokens[#tokens + 1] = token; end
                        product[#product + 1] = tokens;
                    end
                end
                groups = product;
            end
        end
    end
    if (not any) then
        return nil;
    end
    local parts = {};
    for i, group in ipairs(groups) do
        for _, token in ipairs(group) do
            _stateTokens[token] = true;
        end
        parts[i] = "[" .. tconcat(group, ",") .. "]";
    end
    return tconcat(parts);
end

--- A set of reactions (`REACTION_*` bits) as alternatives of tokens, read the way the cell is read:
--- assist first, then attack, else other. So harm is `nohelp,harm`, and help with other is
--- `[help][noharm]` rather than `noharm`, for a unit the two predicates both take.
local REACTION_ALTERNATIVES = {
    [Constants.REACTION_HELP] = { { "help" } },
    [Constants.REACTION_HARM] = { { "nohelp", "harm" } },
    [Constants.REACTION_OTHER] = { { "nohelp", "noharm" } },
    [Constants.REACTION_HELP + Constants.REACTION_HARM] = { { "help" }, { "harm" } },
    [Constants.REACTION_HELP + Constants.REACTION_OTHER] = { { "help" }, { "noharm" } },
    [Constants.REACTION_HARM + Constants.REACTION_OTHER] = { { "nohelp" } },
    [Constants.REACTION_ALL] = { {} },
};

--- Each cell a unit can be in while it exists, as its reaction and life.
local PRESENT_CELLS = {
    { Constants.UNITSTATE_HELP_ALIVE, Constants.REACTION_HELP, false },
    { Constants.UNITSTATE_HELP_DEAD, Constants.REACTION_HELP, true },
    { Constants.UNITSTATE_HARM_ALIVE, Constants.REACTION_HARM, false },
    { Constants.UNITSTATE_HARM_DEAD, Constants.REACTION_HARM, true },
    { Constants.UNITSTATE_OTHER_ALIVE, Constants.REACTION_OTHER, false },
    { Constants.UNITSTATE_OTHER_DEAD, Constants.REACTION_OTHER, true },
};

--- Does a parse ask this unit `exists`? **Only where the beat would call `UnitExists`.** A map-only
--- alias and the pointed frame are there when their token is, which is decided before any parse;
--- asking the client would part from the beat until `exists` goes in on both sides at once (P3-2 of
--- `implementing-the-trimmed-tail-key-beat.md`). The player is never asked: in a vehicle on xptr
--- 120105 `[@player,exists]` stayed false the whole ride while `UnitExists("player")` held.
local function UnitAsksExists(unit)
    return unit ~= "player" and not (SPECIAL_UNITS[unit] and not DebindPrivate.ALIAS_NEEDS_EXISTS[unit]);
end

--- A unit's cells (`UNITSTATE_*` mask, not all of them) as alternatives of tokens, without the
--- `@unit`. **The press and the beat both take theirs from here**, so the two parse one text.
---
--- For a unit that does not ask `exists`, the absent cell is not in the text: the caller decides it
--- from the token. With no present cell left the alternative is the fixed false `known:0`.
local function UnitAlternatives(unit, mask)
    local deadSet, aliveSet = 0, 0;
    for _, cell in ipairs(PRESENT_CELLS) do
        if (band(mask, cell[1]) ~= 0) then
            if (cell[3]) then
                deadSet = bor(deadSet, cell[2]);
            else
                aliveSet = bor(aliveSet, cell[2]);
            end
        end
    end
    local alternatives = {};
    local function add(set, life)
        if (set == 0) then
            return;
        end
        for _, tokens in ipairs(REACTION_ALTERNATIVES[set]) do
            local alternative = {};
            for _, token in ipairs(tokens) do
                alternative[#alternative + 1] = token;
            end
            alternative[#alternative + 1] = life;
            alternatives[#alternatives + 1] = alternative;
        end
    end
    if (deadSet == aliveSet) then
        add(deadSet, nil);
    else
        add(deadSet, "dead");
        add(aliveSet, "nodead");
    end

    if (UnitAsksExists(unit)) then
        if (band(mask, Constants.UNITSTATE_NONE) ~= 0) then
            tinsert(alternatives, 1, { "noexists" });
        else
            for _, alternative in ipairs(alternatives) do
                tinsert(alternative, 1, "exists");
            end
        end
    elseif (#alternatives == 0) then
        alternatives[1] = { "known:0" };
    end
    return alternatives;
end

--- One unit's condition as the macro conditional the press parses (`EVAL_SNIPPET`): existence,
--- reaction and life. Answers `expr` for a fixed unit, or `tail` and `tail2` for an alias and the
--- pointed frame, whose token the press puts in front of each (`"[@" .. unit .. tail .. unit ..
--- tail2`). Nothing where there is nothing to parse: a condition on every present cell of a unit
--- whose presence is its existence, or `false` on one.
local function UnitExpression(unit, condition)
    local mask = DebindPrivate.UnitConditionToState(condition);
    if (not UnitAsksExists(unit) and band(mask, Constants.UNITSTATE_EXISTS) == 0) then
        return nil;
    end
    local groups = UnitAlternatives(unit, mask);
    if (#groups[1] == 0) then
        return nil;
    end
    -- A condition is one reaction set and at most one life, so two groups at most.
    assert(#groups <= 2, "a unit condition took more than two groups");
    if (SPECIAL_UNITS[unit]) then
        local tail = "," .. tconcat(groups[1], ",") .. "]";
        if (groups[2]) then
            return nil, tail .. "[@", "," .. tconcat(groups[2], ",") .. "]";
        end
        return nil, tail;
    end
    local parts = {};
    for i, group in ipairs(groups) do
        parts[i] = "[@" .. unit .. "," .. tconcat(group, ",") .. "]";
    end
    return tconcat(parts);
end

--- One emitted record, as a value.
---
--- **Two readers, one value.** `CollectRecordAxes` works out what has to be measured for this
--- record and `EmitRecord` writes it into the snippet, and both read this. That is the whole point
--- of the record existing: while emitting and accumulating were one walk, the two could disagree
--- and nothing could tell (`going-headless-outside-the-ui.md` §3-2).
---
--- **One table, refilled**, like every other scratch table in this file. It is good until the next
--- `BuildKeyRecord`, and both readers run before that.
local _record            = {
    fieldNames = {},
    fieldValues = {},
    fieldCount = 0,
    units = {},
    switches = {},
};

local function field(record, name, value)
    local count = record.fieldCount + 1;
    record.fieldCount = count;
    record.fieldNames[count] = name;
    record.fieldValues[count] = value;
end

--- Stamps every binding on one key and **drops the ones with no way to fire**.
---
--- `DescribeBinding` refuses a value it cannot build attributes for (an unknown pet command, a
--- flyout with every slot empty), and a record emitted for one of those would win the press and
--- fire nothing: **every action below it on the key would go with it.** A hunter with no pet and a
--- Call Pet binding is the case. A BLOCK is the one binding that is meant to do exactly that.
local function PrepareKeyBindings(key, bindingArray)
    local button, buttonPrefix = bindingArray.button, bindingArray.buttonPrefix;
    local hasClickCast, hasKeyRecord = false, false;

    for i = 1, #bindingArray do
        local binding = bindingArray[i];
        -- **Every record on a mouse button stands on the frame path unless it rules the frame out**,
        -- by the reader's [no unit frame] or by Hover Cast's `"skip"` on that unit
        -- (`which-action-a-key-runs.md` S4). The solver has no column for the path a record takes,
        -- so a box is right only where the record really is: a key-path-only record whose box spans
        -- the frame half would cover, and delete, a frame record it never meets.
        --
        -- **Never with META held.** The secure button builds a click's prefix from Shift, Ctrl and Alt
        -- alone, so a META click arrives on a frame as the bare one, and a record here would be filed
        -- under that button (`GetModifierIndex`) and take its clicks.
        --
        -- **One that needs a frame does not hold the key**: a click over a frame goes to the frame,
        -- so the key path never sees one, and holding the key for it would take the world click.
        --
        -- **Never the self or focus twin** (2026-10-04, owner). A modifier held on a frame click is
        -- that click as it stands: what the frame does with it is Blizzard's click bindings, the
        -- frame's own attributes or another addon's wrapper, differs per frame and cannot be read
        -- reliably, so taking it would hide the game's side of every modified frame click by
        -- default (`which-action-a-key-runs.md` §7).
        local unitFrameCondition = DebindPrivate.UnitFrameConditionOf(binding);
        local wantsFrame = type(unitFrameCondition) == "table";
        local refusesFrame = unitFrameCondition == false or binding.skipsPointedUnit == "unitframe"
            or (buttonPrefix ~= nil and buttonPrefix:find("META-", 1, true) ~= nil);
        binding.isClickCast = button ~= nil and not refusesFrame and
            (binding.castModifier == nil or binding.castModifier == Constants.CASTMOD_NONE) and
            true or false;
        binding.holdsKey = (button == nil or not wantsFrame) and true or false;
        -- A spec-resolved type's spell is on the binding, not in `value` (`FillBinding`), and nil
        -- there is a specialization with nothing to cast: the button is still handed out, with no
        -- action on it, so the key is taken and the press does nothing (§4 of the design).
        --
        -- **`if`, not `and`/`or`.** The ternary shape falls through to `value` when the spell is
        -- nil, which is the one answer this branch exists to produce.
        --
        -- **`spellToCast` first where it is there.** A spec-resolved binding casts its entry's spell
        -- (`SpecSpells.lua`), which is not always `spell`: the warlock's dispel is named and drawn
        -- after the spell in the book and cast under another one, and on camelot the row can show
        -- one of two spells while this binding casts the other. `KnownSpellAsked` reads it too, so
        -- the `known` this binding goes out under names the spell it casts.
        --
        -- **`holdsOnly` goes out as the specialization with nothing to cast does**: the key taken
        -- and the press doing nothing (`FillBinding`).
        local bindingValue = binding.value;
        if (Constants.SPEC_RESOLVED_TYPES[binding.type]) then
            if (binding.holdsOnly) then
                bindingValue = nil;
            else
                bindingValue = binding.spellToCast or binding.spell;
            end
        end
        binding.clickframe, binding.clickbutton, binding.castSpell =
            SetBindingAttributes(binding.type, bindingValue, DebindPrivate.CastUnitOf(binding),
                binding.automatics, binding.pinnedSpell, binding.resolvedSpellID);

        -- **DEBUG only.** Which key ended up on which spell id, which nothing else records: the
        -- action keeps the id the reader picked, `_facts` is wiped per binding, and the button name
        -- says nothing about either. `base` is resolved the same way the bake resolves it, so the
        -- row says what `*spell-`'s name was taken from.
        --
        -- **`ResolveBaseSpell` and not a bare client call, so this row says what the bake used.**
        -- The client places 390414 at 194223 only while the three talents that make it
        -- (`Celestial Alignment`, `Orbital Strike`, `Incarnation: Chosen of Elune`) are all taken
        -- and answers the id back otherwise; the name index is what carries it the rest of the way
        -- (`Spells.lua`). A row showing the client's answer alone would disagree with the button
        -- exactly where this dump is worth reading.
        if (DEBUG and binding.type == Constants.SPELL) then
            -- Nil for a stored name this specialization cannot obtain.
            local base = DebindPrivate.ResolveBaseSpell(bindingValue, binding.resolvedSpellID);
            tinsert(DebindPrivate.SpellFacts, {
                key = binding.key,
                stored = bindingValue,
                base = base,
                baseName = base and GetSpellNameAndIconID(base),
                subtext = base and GetSpellSubtext(base),
                override = base and C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(base, 0, true, 0),
                button = binding.clickbutton,
            });
        end

        if (binding.type ~= Constants.BLOCK
                and not (binding.clickframe and binding.clickbutton)) then
            if (DEBUG) then
                DebindPrivate.log(format("|cffff6666[Debind/attr]|r DROP %s/%s (%s) 걸 수단이 없다",
                    tostring(binding.type), tostring(binding.value), key));
            end
            binding.isClickCast, binding.holdsKey = false, false;
        end

        hasClickCast = hasClickCast or binding.isClickCast;
        hasKeyRecord = hasKeyRecord or binding.holdsKey;
    end

    return hasClickCast, hasKeyRecord;
end

--- One BLOCK per tier, shared by every key. **Nothing hands them to the solver**, so no key and no
--- unit state is read off them.
local BLOCKS = {
    [Constants.CASTMOD_SELF] = { type = Constants.BLOCK, conditions = {},
        castModifier = Constants.CASTMOD_SELF, holdsKey = true, isClickCast = false },
    [Constants.CASTMOD_FOCUS] = { type = Constants.BLOCK, conditions = {},
        castModifier = Constants.CASTMOD_FOCUS, holdsKey = true, isClickCast = false },
    [Constants.CASTMOD_NONE] = { type = Constants.BLOCK, conditions = {},
        castModifier = Constants.CASTMOD_NONE, holdsKey = true, isClickCast = false },
};

local _withBlocks = {};

--- `UpdateBindingsMap`'s scratch: the keys it walks, and the list a held key with nothing in
--- `KeyMap` stands on.
local _keysToWalk = {};
local _noBindings = {};

--- The key's bindings with a BLOCK closing the self tier, the focus tier and the whole list
--- (`dropping-the-game-fallback.md` §3). **Only for a key that holds a key record**: on a
--- click-cast-only key a block would take the key, and the world click and camera with it.
---
--- **No block between the hover twins and the originals.** They share the [none held] tier, each
--- twin beside its own original, and the last block closes it for the pointed half and the rest
--- alike.
---
--- **No block for a key turned off in the settings either.** The press never picks that tier
--- (`EVAL_SNIPPET`), so the block would be a record nothing reads.
local function WithBlocks(bindingArray)
    wipe(_withBlocks);
    local count = #bindingArray;
    local selfEnd, focusEnd = 0, 0;
    for i = 1, count do
        local castModifier = bindingArray[i].castModifier;
        if (castModifier == Constants.CASTMOD_SELF) then
            selfEnd = i;
        elseif (castModifier == Constants.CASTMOD_FOCUS) then
            focusEnd = i;
        end
    end
    if (focusEnd < selfEnd) then
        focusEnd = selfEnd;
    end

    local n = 0;
    for i = 1, selfEnd do
        n = n + 1;
        _withBlocks[n] = bindingArray[i];
    end
    if (DebindPrivate.SelfCastEnabled()) then
        n = n + 1;
        _withBlocks[n] = BLOCKS[Constants.CASTMOD_SELF];
    end
    for i = selfEnd + 1, focusEnd do
        n = n + 1;
        _withBlocks[n] = bindingArray[i];
    end
    if (DebindPrivate.FocusCastEnabled()) then
        n = n + 1;
        _withBlocks[n] = BLOCKS[Constants.CASTMOD_FOCUS];
    end
    for i = focusEnd + 1, count do
        n = n + 1;
        _withBlocks[n] = bindingArray[i];
    end
    n = n + 1;
    _withBlocks[n] = BLOCKS[Constants.CASTMOD_NONE];
    return _withBlocks;
end

--- The binding's unit conditions with every unit written once. **nil where the fold leaves
--- nothing**: that binding fires in no state, so no record is made for it.
---
--- **`"@"` lands on the unit the binding aims at**, so a condition of that unit's own lands on the
--- same key. Unfolded, `pairs` order decides which one survives.
---
--- **Nothing should reach the nil.** Each of the three ways `mergeUnitConditions` answers `NEVER`
--- leaves a zero mask in `binding.unitStates`, `FillBinding` marks that binding `dead`, and
--- `UnrollIntoTiers` leaves it off the key. It stays for the day the two intersections disagree,
--- and as a value it costs nothing.
local function MergeKeyUnitConditions(binding, out)
    wipe(out);

    -- **Hover Cast's `"skip"` is not in `conditions`** (`FillBinding`), since that table is what the
    -- order counts, so it is laid in here, where the record gets the unit rows the press checks.
    if (binding.skipsPointedUnit) then
        out[binding.skipsPointedUnit] = false;
    end

    local units = binding.conditions.units;
    if (not units) then
        return out;
    end

    for k, v in pairs(units) do
        if (k == "@") then
            k = DebindPrivate.ResolvedUnitOf(binding);
        end
        -- nil is a `unit` that is not a string at all, and `BuildUnitStates` has already taken
        -- that binding out of both solver roles, so the condition is dropped quietly here.
        if (k ~= nil) then
            -- **Storage holds three overlapping boxes; from here on it is four cells.** The boxes
            -- are not closed under intersection: {party} and {raid} meet on the one cell "in a raid
            -- and in my subgroup", and no combination of boxes names that cell alone. `band` on the
            -- boxes answers 0 for it, and **a binding that can fire drops out whole.** The solver
            -- uses the same cells (`BuildUnitStates`), so the two sides share one vocabulary.
            --
            -- The value in the condition table cannot be changed in place, so a new table is made:
            -- only for a unit with a group on it, once per rebuild.
            if (type(v) == "table" and v.group) then
                v = {
                    reaction = v.reaction,
                    dead = v.dead,
                    role = v.role,
                    frameTypes = v.frameTypes,
                    group = UnitGroupToCells(v.group),
                };
            end
            v = mergeUnitConditions(out[k], v);
            if (v == NEVER) then
                return nil;
            end
            out[k] = v;
        end
    end

    return out;
end

--- One binding, as the record the restricted side will hold. **nil where the binding can never
--- fire**, which is the unit conditions folding to nothing.
---
--- Nothing here reaches a frame or the client. The one frame question -- which click frame the
--- record hands `SetBindingClick` -- was answered in `PrepareKeyBindings` and arrives as a name.
local function BuildKeyRecord(binding, isClickCast, holdsKey, out)
    if (not MergeKeyUnitConditions(binding, out.units)) then
        return nil;
    end

    local conditions = binding.conditions;

    out.fieldCount = 0;
    wipe(out.switches);
    out.isClickCast = isClickCast;
    out.holdsKey = holdsKey;
    -- **Where the cast goes, not where the press aims.** `none` aims like an action with no target
    -- and still goes out asking; the unit it aims at reaches the snippet through its conditions.
    local castUnit = DebindPrivate.CastUnitOf(binding);
    out.targetUnit = castUnit;
    out.setsSwitch = nil;

    if (binding.clickframe and binding.clickbutton) then
        field(out, "clickbutton", binding.clickbutton);
    end

    -- **이 누름이 시전할 주문**, `*spell-`에 구운 그 값 그대로. 클릭 때 클라이언트에 다시 묻는
    -- 쪽이 있고, **이름으로 물으면 덮인 주문이 답한다** - `GetSpellInfo("Celestial Alignment")`가
    -- `Incarnation: Chosen of Elune`를 낸다(2026-09-21, 소유자가 게임에서). 빌드 때 구운 답은
    -- 원래 주문의 것이라 그 자리를 못 따라간다.
    --
    -- **없으면 안 묻는다는 뜻이다.** 아이템·매크로·탈것에는 시전할 주문이 없다.
    if (binding.castSpell) then
        field(out, "spell", binding.castSpell);
    end

    -- **The target rides on the record**, because the wrapper is what puts it on the button, at
    -- the click, for a key and a unit-frame click alike.
    local carriesTarget = isClickCast or holdsKey;

    if (binding.castModifier) then
        field(out, "castModifier", binding.castModifier);
    end

    if (carriesTarget and castUnit and castUnit ~= "") then
        if (SPECIAL_UNITS[castUnit]) then
            field(out, "unitAlias", castUnit);
        elseif (BASIC_UNITS[castUnit]) then
            field(out, "unit", castUnit);
        end
    end

    -- **A record field of its own, though it is stored as an axis of `units["unitframe"]`.** It
    -- describes the **frame** and only the frame record can answer it, where every other axis of
    -- that unit is answered by measuring the unit. It carries its own "is there a frame" guard in
    -- the snippet for that reason.
    --
    -- Read off the merged table, so a mask on `"@"` where the action aims at the frame's unit meets
    -- the one on `units["unitframe"]` -- the same fold `BuildUnitStates` does for the solver.
    local pointedFrame = out.units.unitframe;
    if (type(pointedFrame) == "table" and pointedFrame.frameTypes
            and pointedFrame.frameTypes ~= Constants.FRAMETYPE_ALL) then
        field(out, "frameTypes", pointedFrame.frameTypes);
    end

    for i = 1, #CONDITION_AXES do
        local axis = CONDITION_AXES[i];
        local value = conditions[axis.field];
        if (value ~= nil and value ~= axis.allValue) then
            local omit = false;
            if (axis.derived) then
                -- **대괄호까지 포함해 한 문자열로 굽는다.** 클릭 경로가 이 값을
                -- `SecureCmdOptionParse`에 그대로 넘긴다. 나눠 두면 클릭마다 결합이 난다.
                -- **The condition's own value is the question** -- a spell name, or the id where
                -- the client could not name one (`making-known-a-spell-name.md`).
                --
                -- `true` is the one shape still derived from the action, and it is left to the
                -- three types whose spell the specialization picks: they carry no value of their
                -- own, so a name would nail the condition to one specialization. One that resolved
                -- to nothing asks a conditional that is always false (`known:0` is the fixed
                -- false elsewhere in this file too).
                local spell = DebindPrivate.KnownSpellAsked(binding);
                -- A true that stands until the next rebuild is settled here instead of going out
                -- as an axis (`baking-the-known-condition.md`), so the press stops parsing it.
                omit = spell ~= nil and Spells.SettleKnown(spell) == true;
                -- **An id goes out twice: as the conditional and as itself.** `[known:<id>]`
                -- answers false for a spell the book holds under an override, so the press asks
                -- the book as well and takes either answer (`SpecSpells.lua`). The conditional
                -- cannot carry that question and the id cannot be read back out of the baked
                -- string.
                if (not omit and type(spell) == "number") then
                    field(out, "knownID", spell);
                end
                value = spell and ("[known:" .. spell .. "]") or "[known:0]";
            end
            if (not omit) then
                field(out, axis.field, value);
            end
        end
    end

    -- **A switch is used by acting on it too, not only by being a condition.** An on/off/toggle
    -- action names its switch in `value`, so the condition loop below never sees it, and
    -- registration is what puts the switch's stored value back into `States` at every rebuild.
    -- Without it the restricted side holds nil while the window shows the stored value, and the
    -- first press only brings the two back together -- it reads as a press that did nothing, and
    -- the rebuild after it puts the pair back out of step.
    --
    -- No flag: this key's own wiring does not depend on the switch, so there is nothing to
    -- re-decide when it changes.
    if (Constants.SETSWITCH_MODES[binding.type] and luatype(binding.value) == "string") then
        out.setsSwitch = binding.value;
    end

    -- **A `SETCUSTOM` action reads the pointed frame's unit, and it is the one reader that names no
    -- unit.** Its value is which custom slot to fill; where the unit comes from is baked as the
    -- literal `"unitframe"` on the `UnitWatch` frame (`DescribeBinding`), and the restricted side
    -- resolves it through `GetUnitFrameUnit` at the press. So nothing about this binding's units or
    -- its target says "unitframe" and `_unitsSeen` would not hear about it -- which is what turns
    -- the slot off underneath it.
    out.readsUnitFrameUnit = binding.type == Constants.SETCUSTOM;

    out.tail = binding.tail;
    out.command = binding.tail == Constants.COMMAND and binding.value or nil;

    -- **조건 표에 있는 스위치 이름을 그대로 훑는다.** 다섯 번호를 도는 루프였고, 그래서
    -- `$state1`~`$state5` 밖의 이름은 조건으로 걸려 있어도 여기서 안 보였다. 솔버는 그 이름에도
    -- 컬럼을 만드니 (`Solver.lua`) 둘이 갈리면 한쪽은 조건이 있다고 보고 다른 쪽은 없다고 본다.
    --
    -- **정의가 없어도 굽는다.** 정의를 못 찾으면 조건을 통째로 빼던 자리다 - 빼면 그 바인딩이
    -- 조건 없이 상시 발동한다. ⚑2가 매크로 본문에서 막은 것과 같은 실패 방향인데 이쪽이 더
    -- 나쁘다: 본문 쪽은 액션에 마커라도 붙는다. 구워두면 런타임 비교가 `States[name] ~= v`라
    -- 아무도 안 쓴 이름은 `nil`이고, 참을 걸었든 거짓을 걸었든 안 맞는다 - 어느 쪽으로 걸어도
    -- 안 나가는 쪽으로 떨어진다.
    --
    -- **이제 그 액션은 여기까지 오지도 않는다.** 정의 없는 이름을 조건으로 건 액션에도 마커가
    -- 붙어서(`GetUndefinedSwitch`) `KeyMap`에서 빠지고, 그래서 위 갈래는 액션 쪽으로는 도달
    -- 불가가 됐다. **그렇다고 지우지 말 것** - 스위치의 계산식은 액션이 아니라 이 길로 그대로
    -- 내려오고, 무엇보다 이건 위험한 방향을 막는 마지막 겹이다. 마커 하나가 빠지거나 좁아지는
    -- 날 여기가 없으면 ⚑2가 그대로 돌아온다.
    for name, value in pairs(conditions) do
        if (Constants.IsSwitchName(name)) then
            out.switches[name] = value and true or false;
        end
    end

    return out;
end

--- What the rest of the rebuild has to set up because of this record: the switches it reads or
--- sets, the aliases it resolves, and the role headers.
local function CollectRecordNeeds(record)
    for unit, condition in pairs(record.units) do
        -- **Role is read off the unitframe slot, not measured on a unit**, filled where the frame is
        -- in hand (`SecureBindings.lua`'s `setup_onenter`), so all this decides is whether the
        -- headers that fill `UnitRoles` run.
        if (unit == "unitframe" and condition ~= false and condition.role) then
            _readsRole = true;
        end

        -- 별칭 해석은 어느 갈래든 필요하다. `_unitsSeen`가 `EnableUnitWatch`를 몰고, 그게
        -- `UnitAliasMap[별칭]`을 채운다 - 클릭 경로가 대상을 푸는 자리가 정확히 거기다.
        _unitsSeen[unit] = true;
    end

    if (record.setsSwitch) then
        addSwitch(record.setsSwitch);
    end

    for name in pairs(record.switches) do
        addSwitch(name);
    end

    if (record.targetUnit) then
        _unitsSeen[record.targetUnit] = true;
    end

    if (record.readsUnitFrameUnit) then
        _unitsSeen.unitframe = true;
    end
end

--- Writes one record into the snippet being built.
local function EmitRecord(record)
    appendLine("t=newtable();tinsert(bindings,t)");

    -- The state axes go out as one conditional and not one by one: the press parses it.
    for i = 1, record.fieldCount do
        if (not PARSED_STATE_AXES[record.fieldNames[i]]) then
            appendKeyValue(record.fieldNames[i], record.fieldValues[i]);
        end
    end
    local expr = StateExpression(record);
    if (expr) then
        appendKeyValue("expr", expr);
    end

    local unitsTblCreated;
    for _, unit in ipairs(sortedKeys(record.units, _sortedB)) do
        local condition = record.units[unit];
        if (not unitsTblCreated) then
            unitsTblCreated = true;
            appendLine("t.units=newtable()");
        end
        appendLine("u=newtable();t.units[%q]=u", unit);

        local unitExpr, tail, tail2 = UnitExpression(unit, condition);
        if (unitExpr) then
            appendLine("u.expr=%q", unitExpr);
        end
        if (tail) then
            appendLine("u.tail=%q", tail);
        end
        if (tail2) then
            appendLine("u.tail2=%q", tail2);
        end
        if (condition == false) then
            appendLine("u.exists=false");
        else
            appendLine("u.exists=true");
            -- 칸으로 나간다. 상자로 내보내면 검사가 세 갈래가 되고, 무엇보다 `%q` 셋이
            -- 교집합을 못 나타낸다 - `MergeKeyUnitConditions`의 주석에 그 이유가 있다.
            if (condition.group) then
                appendLine("u.group=newtable()");
                for _, bit in ipairs(sortedKeys(UNITGROUPCELL_NAMES, _sortedC)) do
                    if (band(condition.group, bit) ~= 0) then
                        appendLine("u.group.%s=true", UNITGROUPCELL_NAMES[bit]);
                    end
                end
            end
            -- **Emitted for `unitframe` only**, for the reason `BuildUnitStates` gives that axis to
            -- `unitframe` only. Emitted for another unit, the measuring side never fills that row, so
            -- it reads `cond.role[nil]` and the key goes quietly dead; and the solver ignores the
            -- condition there, so the two part ways. The menu cannot make that shape, but a
            -- hand-edited profile or an old string arrives here with it.
            if (unit == "unitframe" and condition.role) then
                appendLine("u.role=newtable()");
                for _, bit in ipairs(sortedKeys(ROLE_NAMES, _sortedC)) do
                    if (band(condition.role, bit) ~= 0) then
                        appendLine("u.role.%s=true", ROLE_NAMES[bit]);
                    end
                end
            end
        end
    end

    local switchesTblCreated;
    for _, name in ipairs(sortedKeys(record.switches, _sortedB)) do
        if (not switchesTblCreated) then
            appendLine([[t.switches=newtable()]]);
            switchesTblCreated = true;
        end
        appendLine([[t.switches[%q]=%s]], name, record.switches[name] and "true" or "false");
    end

    -- **유닛 프레임은 매크로를 거치지 않는다.**
    --
    -- 옛 경로는 `type="macro"` + `macrotext="/click <프레임> <버튼>"`이었다. 그러면 **바깥이
    -- 매크로**가 되고, 도착한 버튼의 액션이 또 매크로면 실행되지 않는다(게임 제약,
    -- `click-time-poc-results.md` §2-5). 매크로텍스트·매크로·펫 명령·spellID 없는 탈것이 통째로
    -- 안 나갔다.
    --
    -- `type="click"`은 `SECURE_ACTIONS.click` 한 줄이라 매크로를 안 거친다. 대신 **버튼 이름을
    -- 못 싣는다** - `delegate:Click(button)`이 원래 마우스 버튼을 그대로 넘긴다. 그래서 어느
    -- 액션인지는 래퍼가 도착한 뒤에 `ClickCastKeys`에서 되찾는다.
    --
    -- 그 덕에 거기서 거는 `clickbutton`은 **언제나 같은 프레임**이다. 승자가 바뀌어도 안
    -- 바뀌므로 옛 경로처럼 액션마다 다시 쓸 일이 없다. **아무것도 안 굽는다.** 유닛 프레임에
    -- 미리 찍어둘 것이 없어서다 - 프레임이 들고 있는 것은 등록 때 한 번 쓴 고정값
    -- (`*type-debind1` / `*clickbutton-debind1`)뿐이고, 어느 액션인지는 래퍼가 클릭 순간에
    -- 정한다.
    --
    -- 그래서 이 레코드가 클릭 갈래에 속한다는 표시 하나면 된다. 래퍼가 그것으로 볼 레코드를
    -- 고른다(`EVAL_SNIPPET`의 `subset`). **`unitframe` 플래그를 안 세운다.** 옛 경로에서는 상태
    -- 루프가 승자를 유닛 프레임에 미리 찍어뒀으니 호버가 바뀌면 다시 골라야 했다. 지금은 래퍼가
    -- 클릭 순간에 고르므로 다시 걸 것이 없다.
    if (record.isClickCast) then
        appendLine("t.isClickCast=true");
    end

    if (record.holdsKey) then
        appendLine("t.holdsKey=true");
    end

    -- **An unused that wins a frame click lets it through** to the frame's own handler, which is the
    -- game's side of that click (`which-action-a-key-runs.md` S4). Every other winner with nothing
    -- to click spends it (2026-10-05, owner): a block does nothing, as its own row says, and a
    -- command cannot run on a frame. Let through, either would run whatever the frame has on that
    -- click, which the reader did not pick, and do what the unused does.
    if (record.isClickCast and record.tail == Constants.UNUSED) then
        appendLine("t.letsClickThrough=true");
    end

    -- **DEBUG only, and read by nothing in the addon.** A tail goes out as a BLOCK, so without these a
    -- spec asking which record won cannot tell it from the BLOCK closing the tier
    -- (`judgment_spec.lua`).
    if (DEBUG and record.tail) then
        appendLine("t.tail=%q", record.tail);
        if (record.command) then
            appendLine("t.command=%q", record.command);
        end
    end
end

DebindPrivate.MergeKeyUnitConditions = MergeKeyUnitConditions;
DebindPrivate.BuildKeyRecord = BuildKeyRecord;

--- Is anything this specialization binds reading this switch?
---
--- **`_switches` is the answer and not a count of the profile.** It is what the compile put in
--- front of the restricted side, so a name in it is a name that side holds a value for and reports
--- changes to. A name outside it has no current state at all: nothing pushes one, nothing reads
--- one, and the value on the definition is only a memory kept for the next reload.
---
--- Rebuilt on every compile, so this answers about the bindings that are up right now.
function DebindPrivate.IsSwitchTracked(name)
    return _switches[name] ~= nil;
end

--- The order the client drops modifiers in when a chord has no binding of its own
--- (`handing-the-rest-of-a-key-to-the-game.md` §6-2, measured), which is also the order a binding
--- string spells them in (`Constants.MODIFIER_ORDER`).
local CHORD_MODIFIERS = Constants.MODIFIER_ORDER;
local SplitChord = DebindPrivate.SplitKeyModifiers;
local JoinChord = DebindPrivate.JoinKeyModifiers;

local _chordMods = {};

--- `key` with `mod` added, or nil when it already holds it.
local function AddModifier(key, mod)
    local base = SplitChord(key, _chordMods);
    if (_chordMods[mod]) then
        return nil;
    end
    _chordMods[mod] = true;
    return JoinChord(_chordMods, base);
end

--- The bare key of ours a chord is bound to, false for somebody else's, nil for none. `ours` is the
--- set of bare keys bound this rebuild; `yield` says whether the game's side counts.
---
--- **The game's side is the saved set and every override in force but ours.** A bar or
--- click-casting addon routes its keys through overrides with nothing saved behind them, and a press
--- of such a chord went to it before the chords were bound. This runs after the rebuild has taken
--- our own overrides off (`ClearPreviousBindings`), so what is left there is someone else's.
local function DirectLanding(chord, ours, yield)
    if (ours[chord]) then
        return chord;
    end
    if (yield and GetBindingAction(chord, true) ~= "") then
        return false;
    end
    return nil;
end

--- `LandingOf`'s scratch, one pair per depth it recurses to.
local _landingMods, _landingDropped = {}, {};

--- **Where a press of `chord` lands with nothing but the bare keys we bind and the game's side**,
--- which is where every press landed before the chords were bound. The client takes the chord's own
--- binding, and failing that drops one modifier at a time, ALT, then CTRL, then SHIFT (measured,
--- §6-2). Dropping two is only ever asked of a chord we made from a key with both cast modifiers,
--- and both single drops are asked first there, so the order past one drop is the order of the
--- first.
local function LandingOf(chord, ours, yield, depth)
    local direct = DirectLanding(chord, ours, yield);
    if (direct ~= nil) then
        return direct;
    end

    depth = depth or 1;
    local mods = _landingMods[depth] or {};
    local dropped = _landingDropped[depth] or {};
    _landingMods[depth], _landingDropped[depth] = mods, dropped;
    wipe(dropped);
    local base = SplitChord(chord, mods);
    for _, mod in ipairs(CHORD_MODIFIERS) do
        if (mods[mod]) then
            mods[mod] = nil;
            dropped[#dropped + 1] = JoinChord(mods, base);
            mods[mod] = true;
        end
    end
    for _, smaller in ipairs(dropped) do
        local landing = DirectLanding(smaller, ours, yield);
        if (landing ~= nil) then
            return landing;
        end
    end
    for _, smaller in ipairs(dropped) do
        local landing = LandingOf(smaller, ours, yield, depth + 1);
        if (landing ~= nil) then
            return landing;
        end
    end
    return nil;
end

--- Every chord this rebuild weighed for a self or focus tier, and whether one of them was left
--- because somebody else holds it. What the override hooks ask (`Events.lua`): a call on anything
--- else cannot move a chord of ours.
local _chordCandidates = {};
local _chordsYielded = false;

function DebindPrivate.IsCastChordCandidate(key)
    return _chordCandidates[key] == true;
end

function DebindPrivate.CastChordsYielded()
    return _chordsYielded;
end

--- Does the game keep its own chords over our cast key ones? On unless the reader turned it off
--- (`handing-the-rest-of-a-key-to-the-game.md` 2-4).
function DebindPrivate.ChordsYieldToGame()
    return DebindPrivate.Options.castKeyChordsOverGame ~= true;
end

--- **The chords a bound key takes for its self and focus tiers**, as `chord -> tier`.
---
--- Taken exactly where a press used to fall to the key and read the modifier off the press: on a
--- chord that, with only the bare keys bound, lands on this key. A chord that lands elsewhere --
--- the game's own binding, another of our keys, a chord of one -- went there before and still does.
--- The tier is the one the press used to pick: the self modifier among the ones held on top wins
--- over the focus one (`implementing-focus-and-self-cast.md` §3-3).
local _castChords3, _ownMods = {}, {};

local function CastChordsOf(key, ours, selfMod, focusMod, yield, out)
    wipe(out);
    local selfChord = selfMod and AddModifier(key, selfMod);
    local chords = _castChords3;
    chords[1] = selfChord;
    chords[2] = focusMod and AddModifier(key, focusMod);
    chords[3] = selfChord and focusMod and AddModifier(selfChord, focusMod);
    for i = 1, 3 do
        local chord = chords[i];
        if (chord) then
            _chordCandidates[chord] = true;
            local landing = LandingOf(chord, ours, yield);
            if (landing == false) then
                _chordsYielded = true;
            elseif (landing == key) then
                SplitChord(chord, _chordMods);
                SplitChord(key, _ownMods);
                if (selfMod and _chordMods[selfMod] and not _ownMods[selfMod]) then
                    out[chord] = Constants.CASTMOD_SELF;
                elseif (focusMod and _chordMods[focusMod] and not _ownMods[focusMod]) then
                    out[chord] = Constants.CASTMOD_FOCUS;
                end
            end
        end
    end
    return out;
end

--- The game's modifier for a cast key, or nil where the reader turned ours off or the game has
--- none. `SetModifiedClick` takes any string, so only the three the options offer count.
local function CastModifier(enabled, action)
    if (not enabled) then
        return nil;
    end
    local mod = GetModifiedClick(action);
    if (mod == "ALT" or mod == "CTRL" or mod == "SHIFT") then
        return mod;
    end
    return nil;
end

local _boundBare = {};
local _castChords = {};
local _tierItems = {};

--- **Each key that holds a tail, and each chord made from one, by its binding string -> its judgment
--- item** (`Judgment.lua`). A key with no tail has none: it is ours in every state, and so are its
--- chords. Rebuilt whole by every rebuild.
DebindPrivate.JudgmentItems = {};

--- A tail key's self and focus tier entries, kept until its chords are known.
local _chordEntries = {};

--- What a record winning a press means for the key. A tier's own closing BLOCK means nothing of its
--- own on a chord: the chord then lands where its base key does (`handing-the-rest-of-a-key-to-the-game.md`
--- 2-3).
local function JudgmentEntryFor(binding, record, tier)
    local Judgment = DebindPrivate.Judgment;
    local outcome = Judgment.OURS;
    if (binding.tail == Constants.COMMAND) then
        outcome = Judgment.COMMAND;
    elseif (binding.tail == Constants.UNUSED) then
        outcome = Judgment.RELEASE;
    elseif (tier ~= Constants.CASTMOD_NONE and binding == BLOCKS[tier]) then
        outcome = Judgment.BASE;
    end
    return Judgment.Entry(record, outcome, record.command);
end

--- The attribute holding a wake's body: this, then the wake's name (`JudgeWakes`).
local JUDGE_WAKE_PREFIX = "judge-";

--- The wakes of ours that move a column, none where only Blizzard's beat does. The pointed
--- frame's columns move with the cursor, a switch with `SetSwitch`, an alias with `SetUnit`, and a
--- pet battle, which `specialbar` folds in, with `SetPetBattle`.
---
--- **A computed switch moves with whatever its text reads**, through the computed switches it
--- reads as well: that wake composes the text again, so it has to measure the switch.
local function JudgmentWakesOf(column)
    local kind, arg = column.kind, column.arg;
    if (kind == "role" or kind == "frameType") then
        return { "unitframe" };
    elseif (kind == "petbattle" or kind == "specialbar") then
        return { "petbattle" };
    elseif (kind == "unit" or kind == "unitgroup") then
        if (SPECIAL_UNITS[arg]) then
            return { arg };
        end
    elseif (kind == "switch") then
        local info = _switches[arg];
        if (not (info and info.mode == SWITCH_MODES.EXPR)) then
            return { arg };
        end
        local wakes, seen = {}, {};
        local function visit(name)
            for _, read in ipairs(ComposedReads(name) or {}) do
                if (not seen[read]) then
                    seen[read] = true;
                    local other = _switches[read];
                    if (other and other.mode == SWITCH_MODES.EXPR) then
                        visit(read);
                    else
                        wakes[#wakes + 1] = read;
                    end
                end
            end
        end
        seen[arg] = true;
        visit(arg);
        return wakes;
    end
    return {};
end

--- Does the beat measure this column again? Everything but a switch set by hand, which nothing but
--- `SetSwitch` moves, and a pet battle, which nothing but `SetPetBattle` does. A computed switch is
--- worked out from the world, like any state.
local function JudgedOnBeat(column)
    if (column.kind == "petbattle") then
        return false;
    elseif (column.kind ~= "switch") then
        return true;
    end
    local info = _switches[column.arg];
    return (info and info.mode == SWITCH_MODES.EXPR) and true or false;
end

local _judgmentKeys = {};
local _judgmentColumns = {};
local _judgmentColumnIndex = {};
--- The columns this rebuild handed the loop, by their index in `JudgeColumns`.
local _judgmentColumnOrder = {};

--- Every column the judgment items read, once each, as `column key -> column`.
local function CollectJudgmentColumns(items, out)
    wipe(out);
    for _, item in pairs(items) do
        for _, column in ipairs(item.columns) do
            out[column.key] = column;
        end
    end
    return out;
end

--- Text pieces as a template: literals and slots alternating, a literal first and last.
local function Template(pieces)
    local out, buffer = { "" }, {};
    for _, piece in ipairs(pieces) do
        if (luatype(piece) == "string") then
            buffer[#buffer + 1] = piece;
        else
            out[#out] = tconcat(buffer);
            buffer = {};
            out[#out + 1] = piece;
            out[#out + 1] = "";
        end
    end
    out[#out] = tconcat(buffer);
    return out;
end

--- What an item says, as a string two items share exactly when the loop would judge them alike:
--- the same checks on the same columns giving the same outcomes, and, for a chord, the same base
--- bundle to follow.
local function JudgmentSignature(item, baseBundle)
    local parts = { baseBundle or 0, item.rest.outcome, item.rest.command or "" };
    for _, entry in ipairs(item.entries) do
        parts[#parts + 1] = "|" .. entry.outcome .. " " .. (entry.command or "");
        for _, check in ipairs(entry.checks) do
            parts[#parts + 1] = item.columns[check.column].key .. ":" .. check.mask;
        end
    end
    return tconcat(parts, " ");
end

--- The alias and frame units the column loop classifies, `unit -> true`. Their texts are composed
--- with the unit's token when it moves (`JudgeClassify`).
local _judgeClassified = {};
--- Does anything the loop measures or composes read the pointed frame?
local _judgeReadsFrame = false;

--- Writes a classifying text under `JudgeClassify[unit][1]`, as a template `JUDGE_COMPOSE_SNIPPET`
--- fills in with the unit's token.
local function EmitClassifyTemplate(template)
    appendLine([[b[1]=""]]);
    appendLine("tp=newtable() tp.key=1 tp.frags=newtable() tp.slots=newtable() tinsert(b.templates,tp)");
    for k = 1, #template, 2 do
        appendLine("tp.frags[%d]=%q", k, template[k]);
        local slot = template[k + 1];
        if (slot) then
            appendLine([[s=newtable() tp.slots[%d]=s tp.frags[%d]=""]], (k + 1) / 2, k + 1);
            appendLine("s.unit=%q s.text=%q", slot.unit, slot.text);
        end
    end
end

--- The cells a classifying parse answers with, in the order the cell is read: assist first, then
--- attack, else other (`PRESENT_CELLS`). The last has no condition.
local CLASSIFY_CLAUSES = {
    { ",help,dead", Constants.UNITSTATE_HELP_DEAD },
    { ",help", Constants.UNITSTATE_HELP_ALIVE },
    { ",harm,dead", Constants.UNITSTATE_HARM_DEAD },
    { ",harm", Constants.UNITSTATE_HARM_ALIVE },
    { ",dead", Constants.UNITSTATE_OTHER_DEAD },
};

--- **A text the loop reads as a number ends in a clause with no condition** (`asNumber` in
--- `BuildJudgeSnippet`). Without one the parse answers nil where nothing holds, and `+ 0` raises in
--- the restricted environment, where nothing reports it.
local function AssertEndsInDefault(text)
    assert(text:match(";%s*%d+$"), "a numbered text with no default clause: " .. text);
    return text;
end

--- **One parse that answers a unit's cell** (P3-3), for the column loop's `unit` column. Its value
--- is the `UNITSTATE_*` number. `exists` is asked where `UnitAsksExists` says, so the loop reads a
--- unit's existence the way the press does. An alias or frame unit with no token is never parsed.
local function ClassifyPieces(unit)
    local pieces = {};
    local function at(text)
        if (SPECIAL_UNITS[unit]) then
            pieces[#pieces + 1] = "[";
            pieces[#pieces + 1] = { unit = unit, text = text };
            pieces[#pieces + 1] = "]";
        else
            pieces[#pieces + 1] = "[@" .. unit .. text .. "]";
        end
    end
    if (UnitAsksExists(unit)) then
        at(",noexists");
        pieces[#pieces + 1] = " " .. Constants.UNITSTATE_NONE .. "; ";
    end
    for _, clause in ipairs(CLASSIFY_CLAUSES) do
        at(clause[1]);
        pieces[#pieces + 1] = " " .. clause[2] .. "; ";
    end
    pieces[#pieces + 1] = tostring(Constants.UNITSTATE_OTHER_ALIVE);
    local template = Template(pieces);
    AssertEndsInDefault(template[#template]);
    return template;
end
DebindPrivate.ClassifyPieces = ClassifyPieces;

--- **The items, handed to the loop**: every column once, then each distinct item once as a bundle,
--- and each key's row pointing at its bundle (§3-3). The bare keys go ahead of the chords made from
--- them, since a chord's `base` answer is its base key's bundle's of the same pass.
local function EmitJudgmentItems(items)
    wipe(_judgeClassified);
    CollectJudgmentColumns(items, _judgmentColumns);
    wipe(_judgmentColumnIndex);
    wipe(_judgmentColumnOrder);
    local wakes = {};
    for i, key in ipairs(sortedKeys(_judgmentColumns, _sortedB)) do
        local column = _judgmentColumns[key];
        _judgmentColumnIndex[key] = i;
        _judgmentColumnOrder[i] = column;
        -- Its bundles at `2i`, beside the cell the loop keeps at `2i - 1`: one global read serves a
        -- mark's compare and its stamps (`BuildJudgeSnippet`).
        appendLine("JudgeColumns[%d]=newtable()", 2 * i);
        for _, wake in ipairs(JudgmentWakesOf(column)) do
            wakes[wake] = true;
        end
        if (column.kind == "unit" and SPECIAL_UNITS[column.arg]) then
            _judgeClassified[column.arg] = true;
        end
    end

    sortedKeys(items, _judgmentKeys);
    sort(_judgmentKeys, function(a, b)
        local aChord, bChord = items[a].base ~= nil, items[b].base ~= nil;
        if (aChord ~= bChord) then
            return bChord;
        end
        return a < b;
    end);

    local bundleOf, keyBundle, bundles = {}, {}, 0;
    for _, key in ipairs(_judgmentKeys) do
        local item = items[key];
        local baseBundle = item.base and keyBundle[item.base];
        local signature = JudgmentSignature(item, baseBundle);
        local n = bundleOf[signature];
        if (not n) then
            bundles = bundles + 1;
            n = bundles;
            bundleOf[signature] = n;
            -- Every key it stands for was bound by the line that put the key on, so it starts as
            -- ours.
            appendLine([[b=newtable() b.want="ours" b.keys=newtable() JudgeBundles[%d]=b]], n);
            appendLine("b.restOutcome=%q", item.rest.outcome);
            if (item.rest.command) then
                appendLine("b.restCommand=%q", item.rest.command);
            end
            if (baseBundle) then
                appendLine("b.base=JudgeBundles[%d]", baseBundle);
            end
            -- The columns its checks read, which is what has to wake it. One the item's boxes
            -- merged away decides nothing for it.
            local reads, readOrder = {}, {};
            for e, entry in ipairs(item.entries) do
                appendLine("e=newtable() e.outcome=%q b[%d]=e", entry.outcome, e);
                if (entry.command) then
                    appendLine("e.command=%q", entry.command);
                end
                for k, check in ipairs(entry.checks) do
                    local index = _judgmentColumnIndex[item.columns[check.column].key];
                    appendLine("e[%d]=%d e[%d]=%d", 2 * k - 1, 2 * index - 1, 2 * k, check.mask);
                    if (not reads[index]) then
                        reads[index] = true;
                        readOrder[#readOrder + 1] = index;
                    end
                end
            end
            sort(readOrder);
            for _, index in ipairs(readOrder) do
                appendLine("tinsert(JudgeColumns[%d],b)", 2 * index);
            end
        end
        keyBundle[key] = n;
        -- A chord's row writes at the priority its chord went on at.
        appendLine([[j=newtable() j.key=%1$q j.slot=BoundKeys[%1$q] j.bound="ours" j.bundle=JudgeBundles[%2$d] ]]
            .. [[j.priority=%3$s JudgeByKey[%1$q]=j tinsert(JudgeBundles[%2$d].keys,j)]], key, n,
            tostring(item.base == nil));
    end

    -- The classifying text of each alias or frame unit the loop measures.
    for _, unit in ipairs(sortedKeys(_judgeClassified, {})) do
        appendLine("b=newtable() b.templates=newtable() JudgeClassify[%q]=b", unit);
        EmitClassifyTemplate(ClassifyPieces(unit));
        appendLine("tinsert(JudgeComposeAll,b)");
        appendLine("JudgeComposeBy[%1$q]=JudgeComposeBy[%1$q] or newtable() tinsert(JudgeComposeBy[%1$q],b)", unit);
    end

    for _, wake in ipairs(sortedKeys(wakes, {})) do
        appendLine("JudgeWakes[%q]=%q", wake, JUDGE_WAKE_PREFIX .. wake);
    end
    _judgeReadsFrame = wakes.unitframe or false;
end

--- Boolean state columns, each measured by parsing what the press parses for "on". `petbattle` is
--- not one: it is pushed (`SetPetBattle`).
local JUDGED_BOOL_STATES = {
    combat = true, stealth = true, mounted = true, indoors = true, flyable = true, advflyable = true,
    flying = true, skyriding = true, extrabar = true, specialbar = true,
};

--- **The parse that answers a state column's cell on the column loop**, and whether its value is
--- the cell itself (F1 of `trimming-the-tail-key-beat.md`): a boolean column's "on" as the press
--- writes it, a mask column's clauses each worth its cell. The loop then reads what the press reads,
--- as the expressions do, and a parse is cheaper than the API it replaces (7-1, `[combat]` 0.21 to
--- `PlayerInCombat()` 0.91). nil for a column that is not a state.
---
--- A mask column falls back to the cell the press reads its value as: no form is form 0, and an
--- offset past the ones the press names is offset 0, since `[nobonusbar:1/2/3/4/5]` holds there.
local function StateCellText(kind)
    local tokens, numbered = {}, false;
    local text;
    if (JUDGED_BOOL_STATES[kind]) then
        local groups = {};
        for _, alternative in ipairs(StateAlternatives(kind, true)) do
            -- `specialbar`'s battle is the pushed one (`otherCell`).
            if (alternative[1] ~= "petbattle") then
                for _, token in ipairs(alternative) do
                    tokens[#tokens + 1] = token;
                end
                groups[#groups + 1] = "[" .. tconcat(alternative, ",") .. "]";
            end
        end
        text = tconcat(groups);
    elseif (kind == "groups") then
        tokens = { "group:raid", "group" };
        text = format("[group:raid] %d; [group] %d; %d", Constants.GROUP_RAID, Constants.GROUP_PARTY,
            Constants.GROUP_NONE);
        numbered = true;
    elseif (kind == "forms" or kind == "bonusbars") then
        local word, last = "form", 10;
        if (kind == "bonusbars") then
            word, last = "bonusbar", Constants.MAX_BONUSBAR_OFFSET;
        end
        local clauses = {};
        for n = 1, last do
            tokens[#tokens + 1] = word .. ":" .. n;
            clauses[n] = format("[%s:%d] %d; ", word, n, 2 ^ n);
        end
        text = tconcat(clauses) .. "1";
        numbered = true;
    else
        return nil;
    end
    for _, token in ipairs(tokens) do
        _stateTokens[token] = true;
    end
    if (numbered) then
        AssertEndsInDefault(text);
    end
    return text, numbered;
end

--- How many boolean columns one detecting parse reads. Its clauses are `2 ^ n - 1`, and the bench
--- prices a parse by the words it judges and not by the length of its text, which 7-1 measured to
--- cost even where the first word is false. At 3 the bench gave 12.98 -> 12.16 us a beat with 12
--- keys and no state changed; 4 gave 11.86 there, a gain the unpriced length could take back.
local JUDGE_DETECT_MAX = 3;

--- **The loop's bodies, written for this profile** (`handing-the-rest-of-a-key-to-the-game.md` 2-5,
--- §3). The beat's goes straight into the handler, which `UpdateAttrChangedHandler` takes as the
--- return value: a `RunAttribute` there would cost an environment swap and a `pcall` on every beat.
--- The rebuild's pass and each wake's are left in `_judgePassBody` and `_judgeWakeBodies` to be run.
--- Each body is `prepare` (the pointed frame, the classifying texts composed), the measuring half,
--- and `SecureBindings.lua`'s `JUDGE_BUNDLES_SNIPPET`, the judging half. The measuring half lists
--- each column once per body that moves it, as straight lines, and nothing in it asks what kind a
--- column is: the beat can run every frame for as long as a key holds a tail.
---
--- **Every cell is read the way the press reads it**, since an item's boxes were built from the
--- records the press walks: the states and units by the parse the press makes, the pointed frame
--- and the computed switches through the press's own splices, and an alias's existence the way
--- `UnitAsksExists` answers it. A cell read any other way binds a key to an answer the press would
--- not give; `judgment_spec.lua` holds the bound key to the item at every point.
---
---   the beat (`JUDGE_BEAT_ATTRIBUTE`): Blizzard's driver. Every column the world moves, the pointed
---                      frame's included: a raid frame laid out again or a unit dying under a cursor
---                      that never moved sends neither enter nor leave
---   `JudgePass`        the rebuild's own pass. Every column, a switch set by hand too
---   `judge-<name>`     one of our wakes, `unitframe`, a switch or an alias (`JudgeWakes`). Only what
---                      it names: whatever else moved has an event that already pulled the next beat
---                      in
local function BuildJudgeSnippet()
    local lines = {};
    local function add(str, ...)
        lines[#lines + 1] = select("#", ...) > 0 and format(str, ...) or str;
    end

    local TRUE, FALSE = Constants.JUDGMENT_TRUE, Constants.JUDGMENT_FALSE;

    local function computed(column)
        local info = _switches[column.arg];
        return info and info.mode == SWITCH_MODES.EXPR;
    end

    --- The computed switches `names` read, each after every computed switch its expression reads,
    --- the way the press orders them (`OrderComputedSwitch`). A cycle is cut where the walk meets it.
    ---
    --- **Over `ComposedReads`, the edges the wakes and `readers` are built from**: a switch the
    --- rebuild fixed in the text (ignored, or the switch itself) is no edge, and is worked out only
    --- where a column reads it.
    local function SwitchesToWorkOut(names)
        local order, seen = {}, {};
        local function visit(name)
            if (seen[name]) then
                return;
            end
            seen[name] = true;
            for _, read in ipairs(ComposedReads(name) or {}) do
                local other = _switches[read];
                if (other and other.mode == SWITCH_MODES.EXPR) then
                    visit(read);
                end
            end
            order[#order + 1] = name;
        end
        for _, name in ipairs(names) do
            visit(name);
        end
        return order;
    end

    --- The composed texts of the computed switches the loop works out, by each name they read
    --- (`ComposedReads`): what to clear when that name moves.
    local readers = {};
    do
        local switches = {};
        for _, column in ipairs(_judgmentColumnOrder) do
            if (column.kind == "switch" and computed(column)) then
                switches[#switches + 1] = column.arg;
            end
        end
        for _, name in ipairs(SwitchesToWorkOut(switches)) do
            -- A text can name one thing twice (`[$a,combat][$a,mounted]`).
            local seen = {};
            for _, read in ipairs(ComposedReads(name) or {}) do
                if (not seen[read]) then
                    seen[read] = true;
                    readers[read] = readers[read] or {};
                    tinsert(readers[read], name);
                end
            end
        end
    end

    --- Clears the composed text of every switch reading `name`, so the next body to work it out
    --- composes it again.
    --- `texts` is the local holding `JudgeSwitchTexts` where the body has one.
    local function clearReaders(name, texts)
        for _, reader in ipairs(readers[name] or {}) do
            add("%s[%q] = nil", texts or "JudgeSwitchTexts", reader);
        end
    end

    --- **The generation is raised by the first column that moves**, so a body where none moves
    --- writes no global. The rebuild's pass raises it up front (`body`). A column's cell and its
    --- bundles sit side by side in `columns` (`EmitJudgmentItems`).
    ---
    --- **The pass only writes the cell**: every cell starts nil there, and the judging half stamps
    --- every bundle for it (`wake == 1`).
    local inPass = false;
    local function mark(index)
        if (inPass) then
            add("columns[%d] = cell", 2 * index - 1);
            return;
        end
        add("if (columns[%d] ~= cell) then", 2 * index - 1);
        add("columns[%d] = cell", 2 * index - 1);
        add("if (not moved) then");
        add("moved = true");
        add("JudgeGeneration = JudgeGeneration + 1");
        add("generation = JudgeGeneration");
        add("end");
        add("local bundles = columns[%d]", 2 * index);
        add("for k = 1, #bundles do");
        add("bundles[k].stamp = generation");
        add("end");
        add("end");
    end

    --- The column index of each computed switch that is a column.
    local switchColumns = {};
    for i, column in ipairs(_judgmentColumnOrder) do
        if (column.kind == "switch" and computed(column)) then
            switchColumns[column.arg] = i;
        end
    end

    --- **Only the computed switches a column reads, and what they read**, each parsed the way
    --- `COMPUTE_SWITCHES_SNIPPET` does it at the press. That one works out every computed switch, a
    --- macro body's included, which the beat has no use for. An expression with nothing to compose
    --- is baked in as the literal the press would parse.
    ---
    --- **A text is composed only where `JudgeSwitchTexts` has none** (8-6 of
    --- `trimming-the-tail-key-beat.md`): whatever moves a name it reads clears it, a switch here
    --- included, and `SwitchesToWorkOut` puts the switch ahead of its readers.
    ---
    --- **`JudgeSwitches` and `JudgeSwitchTexts` are taken into locals once** where the body reads
    --- them, as `JudgeColumns` is (`body`).
    local function workOutSwitches(order)
        if (#order == 0) then
            return;
        end
        add("local switchValues = JudgeSwitches");
        local withTexts = false;
        for _, name in ipairs(order) do
            if (_macrotexts[_switches[name].expr] or readers[name]) then
                withTexts = true;
            end
        end
        if (withTexts) then
            add("local switchTexts = JudgeSwitchTexts");
        end
        for _, name in ipairs(order) do
            local info = _switches[name];
            add("do");
            if (_macrotexts[info.expr]) then
                add("local s = switchTexts[%q]", name);
                add("if (not s) then");
                add("local entry = SwitchEntries[%q]", name);
                add("local unitframeAlias = JudgeFrameUnit or nil");
                add("local clickSwitches = switchValues");
                add("local pressUnit");
                lines[#lines + 1] = DebindPrivate.COMPOSE_MACROTEXT_SNIPPET;
                add("switchTexts[%q] = s", name);
                add("end");
                add("local value = SecureCmdOptionParse(s) and true or false");
            else
                add("local value = SecureCmdOptionParse(%q) and true or false", info.expr);
            end
            add("if (value ~= switchValues[%q]) then", name);
            add("switchValues[%q] = value", name);
            clearReaders(name, "switchTexts");
            -- **Its column moves here, in whichever body works it out.** A reader's wake works it
            -- out without measuring its column, and the next beat finds the value already stored.
            local index = switchColumns[name];
            if (index) then
                add("cell = value and %d or %d", TRUE, FALSE);
                mark(index);
            end
            add("end");
            add("end");
        end
    end

    --- A unit's token and whether it is there, as `unit` and `exists`. The pointed frame's is what
    --- `prepare` read; `exists` is read only by the group cell, which stays on the API.
    local function unitAndExists(unit, withExists)
        if (unit == "unitframe") then
            add("local unit = JudgeFrameUnit");
        elseif (SPECIAL_UNITS[unit]) then
            add("local unit = UnitAliasMap[%q]", unit);
        else
            add("local unit = %q", unit);
        end
        if (not withExists) then
            return;
        end
        if (unit == "player") then
            -- Never absent, and the press does not ask (`UnitAsksExists`).
            add("local exists = true");
        elseif (SPECIAL_UNITS[unit] and not DebindPrivate.ALIAS_NEEDS_EXISTS[unit]) then
            add("local exists = unit and true or false");
        elseif (SPECIAL_UNITS[unit]) then
            add("local exists = unit and UnitExists(unit) and true or false");
        else
            add("local exists = UnitExists(unit) and true or false");
        end
    end

    --- **A parse that answers a number is read with `+ 0`, not `tonumber`**: the coercion looks no
    --- name up in the environment, and measured 0.043 µs against 0.204 (7-1). It raises where the
    --- parse answers nil or `""`, which `tonumber` would have turned into nil, so every text read
    --- this way has to end in a clause with no condition (`AssertEndsInDefault`, where each is
    --- built).
    local function asNumber(parse)
        return parse .. " + 0";
    end

    --- A unit's cell by the classifying parse (`ClassifyPieces`), into `cell`. The caller declares
    --- `unit`, the token or nil; an alias or frame unit with none is absent without a parse.
    local function unitCell(unitName)
        add("cell = %d", Constants.UNITSTATE_NONE);
        if (SPECIAL_UNITS[unitName]) then
            add("if (unit) then");
            add("cell = %s", asNumber(format("PROBE.ParseUnit(JudgeClassify[%q][1])", unitName)));
            add("end");
        else
            add("cell = %s", asNumber(format("PROBE.ParseUnit(%q)", ClassifyPieces(unitName)[1])));
        end
    end

    local function unitGroupCell()
        add("cell = %d", Constants.UNITGROUPCELL_NEITHER);
        add("if (exists) then");
        add("local raid = UnitPlayerOrPetInRaid(unit)");
        add("local party = UnitPlayerOrPetInParty(unit)");
        add([[local group = (raid and (party and "both" or "raid")) or (party and "party") or "neither"]]);
        add("PROBE.MockUnitGroup(unit)");
        add([[if (group == "both") then]]);
        add("cell = %d", Constants.UNITGROUPCELL_BOTH);
        add([[elseif (group == "raid") then]]);
        add("cell = %d", Constants.UNITGROUPCELL_RAID);
        add([[elseif (group == "party") then]]);
        add("cell = %d", Constants.UNITGROUPCELL_PARTY);
        add("end");
        add("end");
    end

    local function otherCell(column)
        local kind = column.kind;
        local text, numbered = StateCellText(kind);
        if (kind == "petbattle") then
            add("cell = JudgePetBattle and %d or %d", TRUE, FALSE);
        elseif (kind == "specialbar") then
            add("cell = (JudgePetBattle or PROBE.SecureCmdOptionParse(%q)) and %d or %d", text, TRUE, FALSE);
        elseif (text and numbered) then
            add("cell = %s", asNumber(format("PROBE.SecureCmdOptionParse(%q)", text)));
        elseif (text) then
            add("cell = PROBE.SecureCmdOptionParse(%q) and %d or %d", text, TRUE, FALSE);
        elseif (kind == "known") then
            -- Through the probes the press asks through. The question goes in a local first, since
            -- a probe's arguments end at the first `)` and a spell name can hold one.
            add("local asked = %q", column.arg);
            if (column.knownID) then
                add("if (PROBE.SecureCmdOptionParse(asked) or PROBE.FindSpellBookSlotBySpellID(%d)) then",
                    column.knownID);
            else
                add("if (PROBE.SecureCmdOptionParse(asked)) then");
            end
            add("cell = %d", TRUE);
            add("else");
            add("cell = %d", FALSE);
            add("end");
        elseif (kind == "switch") then
            add("local value = States[%q]", column.arg);
            add("if (value == true) then");
            add("cell = %d", TRUE);
            add("elseif (value == false) then");
            add("cell = %d", FALSE);
            add("else");
            add("cell = %d", Constants.JUDGMENT_SWITCH_UNSET);
            add("end");
        elseif (kind == "frameType") then
            add("cell = unitframeFrameType or %d", Constants.JUDGMENT_FRAMETYPE_NOFRAME);
        elseif (kind == "role") then
            add([[if (unitframeRole == "tank") then]]);
            add("cell = %d", Constants.ROLE_TANK);
            add([[elseif (unitframeRole == "healer") then]]);
            add("cell = %d", Constants.ROLE_HEALER);
            add([[elseif (unitframeRole == "damager") then]]);
            add("cell = %d", Constants.ROLE_DAMAGER);
            add([[elseif (unitframeRole == "norole") then]]);
            add("cell = %d", Constants.ROLE_NONE);
            add("else");
            add("cell = %d", Constants.JUDGMENT_ROLE_UNMEASURED);
            add("end");
        else
            error("no measurement for a judgment column of kind " .. tostring(kind));
        end
    end

    --- One branch's columns, in index order, a unit's two columns sharing what it measured.
    local function measure(list)
        local readsFrame = false;
        local switches = {};
        for _, i in ipairs(list) do
            local column = _judgmentColumnOrder[i];
            local kind = column.kind;
            if (kind == "role" or kind == "frameType"
                    or ((kind == "unit" or kind == "unitgroup") and column.arg == "unitframe")) then
                readsFrame = true;
            elseif (kind == "switch" and computed(column)) then
                switches[#switches + 1] = column.arg;
            end
        end
        -- Read off what `prepare` read at the top of the body.
        if (readsFrame) then
            add("local unitframeFrameType = JudgeFrameType or nil");
            add("local unitframeRole = JudgeFrameRole or nil");
        end
        workOutSwitches(SwitchesToWorkOut(switches));

        local units, unitOrder = {}, {};
        for _, i in ipairs(list) do
            local column = _judgmentColumnOrder[i];
            if (column.kind == "unit" or column.kind == "unitgroup") then
                local unit = column.arg;
                if (not units[unit]) then
                    units[unit] = {};
                    unitOrder[#unitOrder + 1] = unit;
                end
                units[unit][column.kind] = i;
            end
        end
        for _, unit in ipairs(unitOrder) do
            add("do");
            unitAndExists(unit, units[unit].unitgroup ~= nil);
            if (units[unit].unit) then
                unitCell(unit);
                mark(units[unit].unit);
            end
            if (units[unit].unitgroup) then
                unitGroupCell();
                mark(units[unit].unitgroup);
            end
            add("end");
        end

        -- **Boolean columns whose "on" is one word are read by one parse** (P3-7 of
        -- `implementing-the-trimmed-tail-key-beat.md`): its clauses run from every word held down to
        -- none, so the first that holds names exactly the ones that hold, as a bit each. Where the
        -- number is the last one, none of them moved and none is compared. `flyable` and
        -- `advflyable` stay out: put in a clause, they would be judged wherever the words ahead of
        -- them hold.
        local detected, detectedSet = {}, {};
        local detectMax = DebindPrivate.JudgeDetectMax or JUDGE_DETECT_MAX;
        for _, i in ipairs(list) do
            local column = _judgmentColumnOrder[i];
            local text, numbered = StateCellText(column.kind);
            if (text and not numbered and #detected < detectMax
                    and column.kind ~= "flyable" and column.kind ~= "advflyable"
                    and not text:find("[", 2, true) and not text:find(",", 1, true)) then
                detected[#detected + 1] = { index = i, word = text:sub(2, -2) };
                detectedSet[i] = true;
            end
        end
        if (#detected < 2) then
            detected, detectedSet = {}, {};
        end
        if (#detected > 0) then
            local clauses = {};
            local subsets = {};
            for s = 1, 2 ^ #detected - 1 do
                subsets[#subsets + 1] = s;
            end
            local function bits(s)
                local n = 0;
                while (s > 0) do
                    n = n + s % 2;
                    s = math.floor(s / 2);
                end
                return n;
            end
            sort(subsets, function(a, b)
                if (bits(a) ~= bits(b)) then
                    return bits(a) > bits(b);
                end
                return a < b;
            end);
            for _, s in ipairs(subsets) do
                local words = {};
                for k, entry in ipairs(detected) do
                    if (math.floor(s / 2 ^ (k - 1)) % 2 == 1) then
                        words[#words + 1] = entry.word;
                    end
                end
                clauses[#clauses + 1] = format("[%s] %d; ", tconcat(words, ","), s);
            end
            add("do");
            add("local code = %s", asNumber(format("PROBE.SecureCmdOptionParse(%q)",
                AssertEndsInDefault(tconcat(clauses) .. "0"))));
            add("if (code ~= JudgeDetect) then");
            add("JudgeDetect = code");
            for k, entry in ipairs(detected) do
                local b = 2 ^ (k - 1);
                add("if ((code %% %d) >= %d) then", b + b, b);
                add("cell = %d", TRUE);
                add("else");
                add("cell = %d", FALSE);
                add("end");
                mark(entry.index);
            end
            add("end");
            add("end");
        end

        -- A computed switch is marked where it is worked out, above.
        for _, i in ipairs(list) do
            local column = _judgmentColumnOrder[i];
            if (column.kind ~= "unit" and column.kind ~= "unitgroup" and not detectedSet[i]
                    and not (column.kind == "switch" and computed(column))) then
                add("do");
                otherCell(column);
                mark(i);
                add("end");
            end
        end
    end

    --- **What a body does before it measures anything**: the pointed frame read again where
    --- anything reads it, the classifying texts (`JudgeClassify`) composed where `mode` moves
    --- their unit, so no parse reads a text not yet composed, and the computed switches' texts
    --- cleared where it moves a name they read.
    ---
    --- `mode` is `"beat"`, `"pass"` (compose every text), `"unitframe"`, or `"wake"` with `wake` the
    --- alias whose text is composed again.
    local function prepare(mode, wake)
        if (mode == "unitframe" or (_judgeReadsFrame and mode ~= "wake")) then
            add("do");
            add("local unitframe = States.unitframe");
            -- **Only while pointing**, on the beat: a frame laid out again under a cursor that never
            -- moved sends neither enter nor leave (F3), and nothing else needs the read.
            if (mode == "beat") then
                add("if (unitframe) then");
            end
            add("local unitframeUnit");
            lines[#lines + 1] = DebindPrivate.READ_UNITFRAME_SNIPPET;
            -- `false` for none, never nil: a global set to nil is gone, not empty.
            add("unitframeUnit = unitframeUnit or false");
            add("unitframeFrameType = unitframeFrameType or false");
            add("unitframeRole = unitframeRole or false");
            add("if (unitframeUnit ~= JudgeFrameUnit or unitframeFrameType ~= JudgeFrameType"
                .. " or unitframeRole ~= JudgeFrameRole) then");
            add("JudgeFrameUnit = unitframeUnit");
            add("JudgeFrameType = unitframeFrameType");
            add("JudgeFrameRole = unitframeRole");
            if (mode ~= "pass") then
                add("local list = JudgeComposeBy.unitframe");
                add("if (list) then");
                lines[#lines + 1] = DebindPrivate.JUDGE_COMPOSE_SNIPPET;
                add("end");
                clearReaders("unitframe");
            end
            add("end");
            if (mode == "beat") then
                add("end");
            end
            add("end");
        end
        if (mode == "pass") then
            add("do");
            add("local list = JudgeComposeAll");
            lines[#lines + 1] = DebindPrivate.JUDGE_COMPOSE_SNIPPET;
            add("end");
        elseif (mode == "wake") then
            if (_judgeClassified[wake]) then
                add("do");
                add("local list = JudgeComposeBy[%q]", wake);
                lines[#lines + 1] = DebindPrivate.JUDGE_COMPOSE_SNIPPET;
                add("end");
            end
            clearReaders(wake);
        end
    end

    local beat, byHand, wakes, wakeOrder = {}, {}, {}, {};
    for i, column in ipairs(_judgmentColumnOrder) do
        if (JudgedOnBeat(column)) then
            beat[#beat + 1] = i;
        else
            byHand[#byHand + 1] = i;
        end
        for _, wake in ipairs(JudgmentWakesOf(column)) do
            if (not wakes[wake]) then
                wakes[wake] = {};
                wakeOrder[#wakeOrder + 1] = wake;
            end
            local list = wakes[wake];
            list[#list + 1] = i;
        end
    end
    sort(wakeOrder);
    _judgeBeats = #beat > 0;

    --- One body: what `build` measures, then the judging half, which reads `wake` -- `1` for the
    --- rebuild's pass, `true` for the beat, the wake's name for a wake of ours.
    ---
    --- **`JudgeColumns` is taken into a local once**, since a global read costs twice a field read
    --- of a local table (`restricted-environment.md`).
    local function body(wake, build)
        lines = {};
        inPass = wake == "1";
        add("local wake = %s", wake);
        if (inPass) then
            add("JudgeGeneration = JudgeGeneration + 1");
            add("local generation = JudgeGeneration");
            add("local moved = true");
        else
            add("local generation");
            add("local moved = false");
        end
        add("local columns = JudgeColumns");
        add("local cell");
        build();
        lines[#lines + 1] = DebindPrivate.JUDGE_BUNDLES_SNIPPET;
        return tconcat(lines, "\n");
    end

    --- **The beat goes in the handler and nothing else does.** It is the one that comes as an
    --- attribute write, from Blizzard's driver; the other two are run.
    ---
    --- On `"attribute"` its attribute goes back to `0` after every tick, or the driver never writes
    --- it again: the manager writes only a value that differs from the attribute's
    --- (`SecureStateDriver.lua`, `resolveDriver`). Putting it back enters the handler a second time,
    --- and the first line turns that round. On `"visibility"` the manager writes `statehidden` on
    --- every tick without comparing, so there is nothing to put back (`BeatSignal.lua`).
    _judgeBeatSignal = DebindPrivate.BeatSignal.comes and "visibility" or "attribute";
    local beatBody = body("true", function()
        add("if (not JudgeReady) then");
        add("return");
        add("end");
        prepare("beat");
        measure(beat);
    end);
    local opening;
    if (_judgeBeatSignal == "visibility") then
        opening = { [[if (name == "statehidden") then]] };
    else
        opening = {
            format("if (name == %q) then", JUDGE_BEAT_ATTRIBUTE),
            "if (value == 0) then",
            "return",
            "end",
            format("self:SetAttribute(%q, 0)", JUDGE_BEAT_ATTRIBUTE),
        };
    end
    opening[#opening + 1] = beatBody;
    opening[#opening + 1] = "return";
    opening[#opening + 1] = "end";
    local branch = DebindPrivate.BakeSnippet(tconcat(opening, "\n"));
    AssertSnippetCompiles(branch, "JudgeBeat");

    --- The rebuild's own pass: every column, a switch set by hand too.
    _judgePassBody = DebindPrivate.BakeSnippet(body("1", function()
        prepare("pass");
        measure(beat);
        measure(byHand);
    end));
    AssertSnippetCompiles(_judgePassBody, "JudgePass");

    --- A wake of ours: only what it names. Whatever else moved has an event that pulls the next
    --- beat in.
    wipe(_judgeWakeBodies);
    for _, wake in ipairs(wakeOrder) do
        local snippet = DebindPrivate.BakeSnippet(body(format("%q", wake), function()
            add("if (not JudgeReady) then");
            add("return");
            add("end");
            prepare(wake == "unitframe" and "unitframe" or "wake", wake);
            measure(wakes[wake]);
        end));
        AssertSnippetCompiles(snippet, JUDGE_WAKE_PREFIX .. wake);
        _judgeWakeBodies[#_judgeWakeBodies + 1] = { attribute = JUDGE_WAKE_PREFIX .. wake, body = snippet };
    end

    return branch;
end

function UpdateBindingsMap()
    appendLine("local bindings,t,u,c,b,j,e,tp,s");

    local keyMap, keysToHold = DebindPrivate.KeyMap, DebindPrivate.KeysToHold;
    local judgmentItems = DebindPrivate.JudgmentItems;
    wipe(judgmentItems);
    wipe(_chordEntries);
    wipe(_boundBare);
    wipe(_keysToWalk);
    for key in pairs(keyMap) do
        _keysToWalk[key] = true;
    end
    for key in pairs(keysToHold) do
        _keysToWalk[key] = true;
    end

    for _, key in ipairs(sortedKeys(_keysToWalk, _sortedA)) do
        local bindingArray = keyMap[key];
        if (not bindingArray) then
            bindingArray = _noBindings;
            bindingArray.button, bindingArray.buttonPrefix = DebindPrivate.GetMouseButtonAndPrefix(key);
        end

        local button, buttonPrefix = bindingArray.button, bindingArray.buttonPrefix;
        local hasClickCast, hasKeyRecord = PrepareKeyBindings(key, bindingArray);
        -- **A key held with nothing on it that holds it** gets the blocks alone: every action on it
        -- was left out before the key map, dropped for having no way to fire, or fires through the
        -- frame. The press then lands on a block and does nothing (`Debind.lua`'s `KeysToHold`).
        hasKeyRecord = hasKeyRecord or keysToHold[key] == true;
        local keyArray = hasKeyRecord and WithBlocks(bindingArray) or bindingArray;

        local first = true;
        local selfCount, focusCount = 0, 0;
        -- The records a press on this key or one of its chords walks, by tier.
        local tiers = {
            [Constants.CASTMOD_NONE] = {}, [Constants.CASTMOD_SELF] = {}, [Constants.CASTMOD_FOCUS] = {},
        };
        local hasTail = false;

        if (hasClickCast or hasKeyRecord) then
            for i = 1, #keyArray do
                local binding = keyArray[i];
                local isClickCast = hasClickCast and binding.isClickCast;
                local holdsKey = hasKeyRecord and binding.holdsKey;

                if (isClickCast or holdsKey) then
                    local record = BuildKeyRecord(binding, isClickCast, holdsKey, _record);
                    if (record) then
                        if (first) then
                            first = false;
                            if (DEBUG) then
                                appendLine("-- %s", key);
                            end
                            appendLine("bindings=newtable()");
                        end
                        CollectRecordNeeds(record);
                        EmitRecord(record);
                        if (holdsKey) then
                            local tier = binding.castModifier or Constants.CASTMOD_NONE;
                            local list = tiers[tier];
                            list[#list + 1] = JudgmentEntryFor(binding, record, tier);
                            hasTail = hasTail or binding.tail ~= nil;
                        end
                        if (binding.castModifier == Constants.CASTMOD_SELF) then
                            selfCount = selfCount + 1;
                        elseif (binding.castModifier == Constants.CASTMOD_FOCUS) then
                            focusCount = focusCount + 1;
                        end
                    end
                end
            end
        end

        -- **An empty list rather than none.** What follows goes by `hasClickCast`, settled before
        -- the loop above could emit nothing, and without a list of its own `bindings` would still
        -- point at the previous key's.
        if (first and (hasClickCast or hasKeyRecord)) then
            first = false;
            appendLine("bindings=newtable()");
        end

        -- **Where the key's tiers start, so a press walks only the one its modifier picks**
        -- (`EVAL_SNIPPET`). Counted off the records that went out: one that can never fire leaves
        -- no place behind it.
        if (not first) then
            appendLine("bindings.focusFrom=%d", selfCount + 1);
            appendLine("bindings.noneFrom=%d", selfCount + focusCount + 1);
        end

        if (hasClickCast) then
            -- 클릭캐스팅으로 도착할 자리를 등록한다. 유닛 프레임이 `type="click"`으로 넘기면
            -- 래퍼는 마우스 버튼 이름밖에 못 받으므로(`/click`과 달리 이름을 못 싣는다),
            -- **버튼 번호와 수식어로 이 키를 되찾는다.**
            --
            -- `ClickTimeKeys`와 나란한 등록이지 그것의 일부가 아니다. 저쪽은 키 역할을
            -- 클릭 시점에 정하는 키들이고 이쪽은 클릭캐스팅이라, 한 키가 양쪽에 다 있을 수도
            -- 어느 한쪽에만 있을 수도 있다.
            appendLine("ClickCastKeys[%d]=ClickCastKeys[%d] or newtable()", button, button);
            appendLine("ClickCastKeys[%d][%d]=bindings", button, GetModifierIndex(buttonPrefix));
        end

        -- **Diagnostic only.** Nothing reads it; it is there so one `bindings` shows its kind in
        -- the game.
        if (hasKeyRecord) then
            appendLine("bindings.hasKeyRecord=true");
        end

        -- **Bound once, for good.** Every tier ends in a BLOCK, so no state leaves the key to
        -- anyone else, and which action goes out is the wrapper's to decide at the press. The
        -- button name carries the key there, since the wrapper gets nothing but `self` and
        -- `button`.
        if (hasKeyRecord and not first) then
            local clickTimeButton = Constants.CLICKTIME_BUTTON_PREFIX .. key;
            DebindPrivate.ClickTimeKeys[key] = clickTimeButton;
            appendLine("ClickTimeKeys[%q]=bindings", clickTimeButton);
            appendLine("self:SetBindingClick(true,%q,DefaultClickFrameName,%q)", key,
                clickTimeButton);
            -- **The other direction of the line above, and the button name it just used**, so a
            -- key handed to the game can be found by its own spelling and put back with the same
            -- argument (`UpdateGivenBackKeys`). The rebuild has cleared every override on its way
            -- in, so nothing is given back at this point and no slot is written for that.
            appendLine("BoundKeys[%q]=bindings", key);
            appendLine("bindings.clickButton=%q", clickTimeButton);
            _boundBare[key] = true;

            if (hasTail) then
                judgmentItems[key] = DebindPrivate.Judgment.Build(tiers[Constants.CASTMOD_NONE]);
                _chordEntries[key] = tiers;
            end
        end
    end

    -- **The self and focus tiers get chords of their own** (`handing-the-rest-of-a-key-to-the-game.md`
    -- 2-3). After the loop, because where a chord lands depends on every bare key being known.
    local selfMod = CastModifier(DebindPrivate.SelfCastEnabled(), "SELFCAST");
    local focusMod = CastModifier(DebindPrivate.FocusCastEnabled(), "FOCUSCAST");
    wipe(_chordCandidates);
    _chordsYielded = false;
    if (selfMod or focusMod) then
        local yield = DebindPrivate.ChordsYieldToGame();
        for _, key in ipairs(sortedKeys(_boundBare, _sortedA)) do
            CastChordsOf(key, _boundBare, selfMod, focusMod, yield, _castChords);
            local first = true;
            local selfNamed, focusNamed = false, false;
            -- Two chords can land on one tier, and its item is the same for both.
            wipe(_tierItems);
            for _, chord in ipairs(sortedKeys(_castChords, _sortedB)) do
                local tier = _castChords[chord];
                local button = format("%s%s#%d", Constants.CLICKTIME_BUTTON_PREFIX, key, tier);
                if (first) then
                    first = false;
                    appendLine("bindings=ClickTimeKeys[%q]", Constants.CLICKTIME_BUTTON_PREFIX .. key);
                end
                -- One name per tier, though two chords can land on it (CTRL and ALT-CTRL both mean
                -- self where self is on CTRL).
                local named;
                if (tier == Constants.CASTMOD_SELF) then
                    named = selfNamed;
                else
                    named = focusNamed;
                end
                if (not named) then
                    appendLine("ClickTimeKeys[%q]=bindings", button);
                    appendLine("ClickTimeTiers[%q]=%d", button, tier);
                    if (tier == Constants.CASTMOD_SELF) then
                        selfNamed = true;
                    else
                        focusNamed = true;
                    end
                end
                -- **At priority false**, where the key itself is at true. A chord is ours only because
                -- a cast key made it, and priority decides between two owners on one key whatever
                -- order they were set in (§6, measured): another addon's override at true wins over
                -- it even when the loop sets it again later.
                appendLine("self:SetBindingClick(false,%q,DefaultClickFrameName,%q)", chord, button);
                appendLine("c=newtable() c.clickButton=%q c.base=%q c.priority=false BoundKeys[%q]=c",
                    button, key, chord);
                if (_chordEntries[key]) then
                    local item = _tierItems[tier]
                        or DebindPrivate.Judgment.Build(_chordEntries[key][tier], key);
                    _tierItems[tier] = item;
                    judgmentItems[chord] = item;
                end
            end
        end
    end

    -- After the chords, whose `BoundKeys` rows an item points at.
    if (next(judgmentItems)) then
        EmitJudgmentItems(judgmentItems);
    end

    -- **Emitted after the key loop, because that loop is what stamps them**, and emitted whole
    -- rather than per key: a button outlives the rebuild that stamped it (`BindingAttrsCache`), so
    -- this belongs to the click frame and not to any one key's records.
    for _, buttonname in ipairs(sortedKeys(_wrappedButtons, _sortedA)) do
        appendLine("WrappedButtons[%q]=%q", buttonname, _wrappedButtons[buttonname]);
    end

    for _, buttonname in ipairs(sortedKeys(_wrappedRelease, _sortedA)) do
        appendLine("WrappedRelease[%q]=%q", buttonname, _wrappedRelease[buttonname]);
    end

    for _, buttonname in ipairs(sortedKeys(_actionSlots, _sortedA)) do
        local entry = _actionSlots[buttonname];
        local info = entry.info;
        -- `GetExtraBarIndex` is not in the restricted environment, so its page is asked here.
        local page = info.page or (info.extra and C_ActionBar.GetExtraBarIndex());
        appendLine("ActionSlots[%q]=newtable()", buttonname);
        appendLine("ActionSlots[%q].attr=%q", buttonname, "*action-" .. buttonname);
        appendLine("ActionSlots[%q].index=%d", buttonname, info.index);
        if (page) then
            appendLine("ActionSlots[%q].page=%d", buttonname, page);
        end
        if (info.extra) then
            appendLine("ActionSlots[%q].extra=true", buttonname);
        end
        if (info.pet) then
            appendLine("ActionSlots[%q].pet=true", buttonname);
        end
        if (entry.bar) then
            appendLine("ActionSlots[%q].bar=%q", buttonname, entry.bar);
        end
        if (entry.overrideBar) then
            appendLine("ActionSlots[%q].overrideBar=%q", buttonname, entry.overrideBar);
        end
    end

    local snippet = table.concat(_strArr, "\n");
    AssertSnippetCompiles(snippet, "UpdateBindingsMap");
    if (DEBUG) then
        dump("UpdateBindingsMap", {
            CopyTable(_strArr),
            snippet:len(),
        });
    end
    wipe(_strArr);
    return snippet;
end

--- One `[$switch]` clause of a macro body, as the argument the restricted side re-evaluates.
---
--- **Two cases share this branch and they bake different values.**
---
--- Erasing a self reference (`[$a]` inside `$a`'s own expression) to `""` is deliberate - reading
--- your own value there has the value eat itself.
---
--- Undefined is the opposite. `""` turns `[$typo]` into `[]`, which is **always true**, so one
--- typo makes a binding fire more rather than less. It falls to false instead.
---
--- `GetBindingIssue`'s `UNDEFINED_SWITCH` keeps such an action out of `KeyMap`, **and that is no
--- reason to leave this empty.** That side judges by the name the parser saw and this one by the
--- definition the compile actually found; folding two judges into one is how a quiet accident
--- happens. (A switch's own `expr` is not an action, so that check never sees it at all.)
local function EmitMacroTextArg(index, arg, ownerName, isSwitch)
    appendLine([[t.args[%d]=newtable()]], index);

    if (arg.type == Constants.MACROTEXT_ARG_UNIT) then
        appendLine([[t.args[%d].unit=%q]], index, arg.name);
        return;
    end

    -- **A switch expression keeps `@@` as written.** It is worked out once per press, before any
    -- winner, and the records of one press aim at different units, so there is no one unit to put
    -- there. `@@` reaches the client as the unit `@`, which never exists.
    if (arg.type == Constants.MACROTEXT_ARG_PRESS_UNIT) then
        if (isSwitch) then
            appendLine([[t.args[%d].fixed="@"]], index);
        else
            appendLine([[t.args[%d].pressUnit=true]], index);
        end
        return;
    end

    if (arg.type ~= Constants.MACROTEXT_ARG_SWITCH) then
        return;
    end

    -- **Ignored erases the term, comma and all left behind.** `SecureCmdOptionParse` drops empty
    -- options wherever they fall, measured 2026-09-20 on `[,,,exists,,,,nodead,]`, so nothing has to
    -- reach back into the fragments to take the separator with it. A clause that held nothing else
    -- becomes `[]`, which is always true, and that is what being ignored means here.
    if (DebindPrivate.IsSwitchIgnored(arg.name)) then
        appendLine([[t.args[%d].fixed=""]], index);
        return;
    end

    if (not SwitchArgIsLive(arg, ownerName)) then
        local fixed = "known:0";
        if (isSwitch and arg.name == ownerName and not arg.reverse) then
            fixed = "";
        end
        appendLine([[t.args[%d].fixed=%q]], index, fixed);
    else
        appendLine([[t.args[%d].switch=%q]], index, arg.name);
        if (arg.reverse) then
            appendLine([[t.args[%d].reverse=true]], index);
        end
    end
end

--- One entry per parsed macro body: where it is written back to, its fragments, the arguments that
--- get re-evaluated, and which of the two tables it lands in.
---
--- `DeferredMacroTexts` holds a button's `*macrotext-`, composed by the click that picks that
--- button. `SwitchEntries` holds a computed switch's expression, composed by the press that has to
--- know the switch's answer (`COMPUTE_SWITCHES_SNIPPET`) and by the tail-key loop, which keeps what
--- it composed in `JudgeSwitchTexts` until a name the text reads moves (`workOutSwitches`). That is
--- what takes the frame sweep down: moving an alias composes no button body, and only the loop's
--- texts that read the alias again.
local function EmitMacroTextEntries()
    local index = 0;

    for _, buttonOrSwitchName in ipairs(sortedKeys(_macrotextBindings, _sortedA)) do
        local data = _macrotextBindings[buttonOrSwitchName];
        if (data) then
            index = index + 1;
            appendLine("t=newtable()");
            appendLine("t.id=%d", index);

            -- **Where the rebuilt body lands.** A button's goes to its `*macrotext-` attribute. A
            -- switch's is composed by the press that works it out, which finds the entry by name
            -- in `SwitchEntries`, so the entry carries no target.
            local isSwitch = strsub(buttonOrSwitchName, 1, 1) == "$";
            if (not isSwitch) then
                appendLine("t.attr=%q", "*macrotext-" .. buttonOrSwitchName);
            end

            appendLine("t.fragments,t.args=newtable(),newtable()");
            for i = 1, #data.fragments do
                appendLine([[t.fragments[%d]=%q]], i, data.fragments[i]);
            end
            for i = 1, #data.args do
                EmitMacroTextArg(i, data.args[i], buttonOrSwitchName, isSwitch);
            end

            if (not isSwitch) then
                appendLine("DeferredMacroTexts[%q]=t", buttonOrSwitchName);
            else
                -- **The press and the loop both compose it, each overwriting its fragments in
                -- place**, so neither may keep anything in them from one composition to the next.
                appendLine("SwitchEntries[%q]=t", buttonOrSwitchName);
            end
        end
    end
end

function BuildMacroTextEntries()
    appendLine("local t");

    EmitMacroTextEntries();

    local snippet = table.concat(_strArr, "\n");
    AssertSnippetCompiles(snippet, "MacroTextEntries");
    if (DEBUG) then
        dump("MacroTextEntries", {
            CopyTable(_strArr),
            snippet:len(),
        });
    end
    wipe(_strArr);
    return snippet;
end

--- The driver's `_onattributechanged`: Keys Given Back, and the loop that binds a tail key.
---
--- **Which action a press fires is still decided at the press** (`SecureBindings.lua`'s matcher).
--- What the loop measures between presses is only whose a tail key is, because that has to be
--- standing before the press arrives.
function UpdateAttrChangedHandler()
    -- **The loop's beat and our own wakes, first because they are by far the most frequent**
    -- (`handing-the-rest-of-a-key-to-the-game.md` 2-5). Only where a key holds a tail: anywhere
    -- else nothing writes those attributes.
    if (next(DebindPrivate.JudgmentItems)) then
        appendLine(BuildJudgeSnippet());
    else
        _judgePassBody = nil;
        wipe(_judgeWakeBodies);
        _judgeBeats = false;
    end

    -- **The bar changed under us, and a rebuild cannot answer it.** Blizzard's manager resolves the
    -- driver on its own beat and writes this attribute only when the value moves, so this branch is
    -- one transition and not a poll (`giving-keys-back.md` §4). The value itself says
    -- nothing the body does not read for itself; it exists to be different.
    appendLine([[
if (name == "state-giveback") then
    self:RunAttribute("UpdateGivenBackKeys")
    return
end
]]);

    local snippet = table.concat(_strArr, "\n");
    AssertSnippetCompiles(snippet, "_onattributechanged");

    if (DEBUG) then
        dump("_onattributechanged", { CopyTable(_strArr), snippet:len() });
    end
    wipe(_strArr);
    return snippet;
end

