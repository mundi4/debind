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
local band                               = bit.band;
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
function addSwitch(stateName)
    local info = _switches[stateName];
    if (info == nil) then
        local options = DebindPrivate.ResolveSwitchDefinition(stateName);
        if (options) then
            local mode, _, expr = DebindPrivate.ResolveSwitchAnswer(stateName);
            info = {
                name = stateName,
                mode = mode,
                value = options.value,
            };
            if (mode == SWITCH_MODES.EXPR) then
                info.expr = expr or "";
                addMacrotextBinding(info.name, info.expr);
            end
        end
        info = info or false;
        _switches[stateName] = info;
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

function addMacrotextBinding(buttonOrStateName, macrotext)
    _macrotextBindings[buttonOrStateName] = addMacrotext(macrotext)
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
-- **`ClearOverrideBindings` below takes every key off**, so what a record list remembered about
-- being handed over is gone with it. The next pass of `UpdateGivenBackKeys` starts from nothing
-- given back, which is what the game is in after this.
wipe(BoundKeys)
wipe(GivenBackNow)
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

    for _, state in ipairs(sortedKeys(_switches, _sortedA)) do
        local stateInfo = _switches[state];
        if (stateInfo) then
            -- previous switch value. **Not for a computed one**: its value belongs to the press
            -- that worked it out (`COMPUTE_SWITCHES_SNIPPET`), so a stored one is what the last
            -- press left behind and pushing it in would stand it up as the switch's value until
            -- the next press. It goes in through `SetSwitch`, which reports it straight back out
            -- to the definition and to what this character remembers.
            if (stateInfo.mode ~= SWITCH_MODES.EXPR and stateInfo.value ~= nil) then
                appendLine([[self:RunAttribute("SetSwitch", %1$q, %s)]], state,
                    tostring(stateInfo.value));
            end

            -- fixed macro conditional
            if (stateInfo.mode == SWITCH_MODES.EXPR and not addMacrotext(stateInfo.expr)) then
                appendLine([[SwitchExpressions[%q]=%q]], state, stateInfo.expr);
            end

            if (stateInfo.mode == SWITCH_MODES.EXPR) then
                OrderComputedSwitch(state);
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
--- **Keys Given Back is the only reader left.** A condition is measured at the press, so no event
--- has to reach us for one; what these wake is `SecureStateDriverManager`'s evaluation of the
--- `state-giveback` attribute driver, which has to be current the moment a vehicle takes the bar
--- (`giving-keys-back.md` §4). Every event the state loop used to ask for went with it.
---
--- The order here is the order they are applied in. It is written out rather than walked out of a
--- table, so what a rebuild emits does not depend on `pairs`.
local function CollectDriverEvents(events)
    local function want(name, register)
        events[#events + 1] = { name = name, register = register and true or false };
    end

    local givesBackOnReplacedBar = DebindPrivate.GiveBackOnReplacedBar();
    want("UPDATE_OVERRIDE_ACTIONBAR", givesBackOnReplacedBar);
    want("UPDATE_VEHICLE_ACTIONBAR", givesBackOnReplacedBar);

    -- Both, because the client splits a pet battle into the two.
    local battle = DebindPrivate.GiveBackInPetBattle();
    want("PET_BATTLE_OPENING_START", battle);
    want("PET_BATTLE_CLOSE", battle);

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

--- Hands the plan to the game. **The only step of a rebuild with an effect on the secure side**,
--- once the two stages that still leave stamping inside the build are done.
local function ApplyBindingPlan(plan)
    local driver = DebindPrivate.BindingDriver;

    SecureHandlerExecute(driver, plan.bindingsMapSnippet);
    SecureHandlerExecute(driver, plan.macroTextsSnippet);

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

    for i = 1, #plan.events do
        local entry = plan.events[i];
        if (entry.register) then
            SecureStateDriverManager:RegisterEvent(entry.name);
        else
            SecureStateDriverManager:UnregisterEvent(entry.name);
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

    ApplyGiveBack(driver, plan.giveBack);
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
local function CollectBindingFacts(type, value, unit, facts, automatics, pinRank)
    wipe(facts);
    facts.pinRank = pinRank;

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
        local spellID = DebindPrivate.ResolveBaseSpell(value);
        facts.spellID = spellID;
        facts.spellName = GetSpellNameAndIconID(spellID);
        if (facts.spellName) then
            -- **A pinned rank is the stored id's own**, since the rank is what the reader picked.
            facts.spellSubtext = GetSpellSubtext(pinRank and value or spellID);
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
    -- **A pinned rank is another button than the highest rank of the same spell**, which shares the
    -- id and would otherwise be handed the other's.
    if (facts.pinRank and type == Constants.SPELL and value ~= nil) then
        out.cacheKey = tostring(value) .. ":rank";
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
        out.castSpell = ComposeSpellCastName(facts.spellName, facts.spellSubtext, facts.pinRank)
            or facts.spellID;
        attr(out, "*spell-", out.castSpell);

        -- **유지·시전 주문의 `*typerelease-`는 여기서 안 굽는다.** 클릭 때 쓴다
        -- (`SecureBindings.lua`). 여기 구우면 이 블록이 캐시 적중으로 통째로 건너뛰어지는 것도
        -- 문제고, 무엇보다 위의 `*spell-`이 **이름**이라 그 이름이 가리키는 주문이 덮이면 구운
        -- 답이 틀린 답이 된다.
    elseif (type == Constants.ITEM) then
        attr(out, "*type-", "item");
        attr(out, "*item-", format("item:%d", value));
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
    elseif (Constants.SETSTATE_MODES[type]) then
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
        attr(out, "*attribute-value-", Constants.SETSTATE_MODES[type]);
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
function SetBindingAttributes(type, value, unit, automatics, pinRank)
    local facts = CollectBindingFacts(type, value, unit, _facts, automatics, pinRank);

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

local REACTION_NAMES = {
    [Constants.REACTION_HELP]  = "help",
    [Constants.REACTION_HARM]  = "harm",
    [Constants.REACTION_OTHER] = "other",
};

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
--- Values carry one field per axis (`Profile.lua`'s `dbver <= 4` step), so merging is an
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
--- `Misc.BuildUnitStates` folds the same conditions with the same intersection, `FillBinding` marks
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
    -- kind a role is measured on (`Misc.lua`'s `RoleLeavesNothing`); meeting it keeps that.
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
    local button = bindingArray.button;
    local hasClickCast, hasKeyRecord = false, false;

    for i = 1, #bindingArray do
        local binding = bindingArray[i];
        -- **Never the self or focus twin.** A modifier held on a frame click is part of the binding
        -- the reader put on that exact combination, since nothing falls through to a click with
        -- fewer (`implementing-focus-and-self-cast.md` §3-10).
        local unitFrameCondition = DebindPrivate.UnitFrameConditionOf(binding);
        local wantsFrame = type(unitFrameCondition) == "table";
        binding.isClickCast = button ~= nil and
            (wantsFrame or binding.type == Constants.SETCUSTOM or binding.unit == "unitframe") and
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
        -- **`spellToCast` first where it is there.** The warlock's dispel is named and drawn after
        -- the spell in the book and cast under another one (`SpecSpells.lua`); this is the one
        -- place that reads it, so nothing on screen follows it.
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
                binding.automatics, binding.pinRank);

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
            local base = DebindPrivate.ResolveBaseSpell(bindingValue);
            tinsert(DebindPrivate.SpellFacts, {
                key = binding.key,
                stored = bindingValue,
                base = base,
                baseName = GetSpellNameAndIconID(base),
                subtext = GetSpellSubtext(base),
                override = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(base, 0, true, 0),
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
--- **No block after the hover twins.** The last one sits under every original's [none held], which
--- covers the pointed half and the rest alike.
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
            -- **저장은 겹치는 세 상자, 여기서부터는 네 칸이다.** 세 상자는 교집합에 안 닫혀
            -- 있다: {파티}와 {공대}가 만나는 곳은 "공대이면서 같은 소그룹" 한 칸인데 그 칸만
            -- 가리키는 상자 조합이 없다. 상자끼리 `band`를 걸면 그 교집합이 0으로 나와
            -- **발동할 수 있는 바인딩이 통째로 빠진다.** 솔버도 같은 칸을 쓰므로
            -- (`Misc.BuildUnitStates`) 두 쪽이 한 어휘가 된다.
            --
            -- 조건 표의 값을 그대로 고칠 수는 없어서 새 표를 만든다. 소속을 건 유닛에만,
            -- 리빌드 한 번에 한 번이다.
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
    -- the one on `units["unitframe"]` -- the same fold `Misc.BuildUnitStates` does for the solver.
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
    if (Constants.SETSTATE_MODES[binding.type] and luatype(binding.value) == "string") then
        out.setsSwitch = binding.value;
    end

    -- **A `SETCUSTOM` action reads the pointed frame's unit, and it is the one reader that names no
    -- unit.** Its value is which custom slot to fill; where the unit comes from is baked as the
    -- literal `"unitframe"` on the `UnitWatch` frame (`DescribeBinding`), and the restricted side
    -- resolves it through `GetUnitFrameUnit` at the press. So nothing about this binding's units or
    -- its target says "unitframe" and `_unitsSeen` would not hear about it -- which is what turns
    -- the slot off underneath it.
    out.readsUnitFrameUnit = binding.type == Constants.SETCUSTOM;

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
    for state, value in pairs(conditions) do
        if (Constants.IsSwitchName(state)) then
            out.switches[state] = value and true or false;
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

    for state in pairs(record.switches) do
        addSwitch(state);
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

    for i = 1, record.fieldCount do
        appendKeyValue(record.fieldNames[i], record.fieldValues[i]);
    end

    local unitsTblCreated;
    for _, unit in ipairs(sortedKeys(record.units, _sortedB)) do
        local condition = record.units[unit];
        if (not unitsTblCreated) then
            unitsTblCreated = true;
            appendLine("t.units=newtable()");
        end
        appendLine("u=newtable();t.units[%q]=u", unit);

        if (condition == false) then
            appendLine("u.exists=false");
        else
            appendLine("u.exists=true");
            if (condition.reaction) then
                -- A set, not a mask: membership is one lookup, while the `%` idiom the restricted
                -- environment forces on masks needs the same two lookups **plus** arithmetic.
                appendLine("u.reaction=newtable()");
                for _, bit in ipairs(sortedKeys(REACTION_NAMES, _sortedC)) do
                    if (band(condition.reaction, bit) ~= 0) then
                        appendLine("u.reaction.%s=true", REACTION_NAMES[bit]);
                    end
                end
            end
            if (condition.dead ~= nil) then
                appendLine("u.dead=%s", tostring(condition.dead));
            end
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
            -- **unitframe에만 나간다**, `Misc.BuildUnitStates`가 unitframe에만 축을 세우는 것과
            -- 같은 이유로. 다른 유닛에도 내보내면 재는 쪽이 그 행을 안 채워서 `cond.role[nil]`이
            -- 되고 그 키가 조용히 죽는다. 게다가 솔버는 그 조건을 무시하므로 둘이 갈린다.
            -- 메뉴로는 못 만드는 모양이지만 손으로 고친 프로필과 옛 문자열이 이리로 온다.
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
    for _, state in ipairs(sortedKeys(record.switches, _sortedB)) do
        if (not switchesTblCreated) then
            appendLine([[t.switches=newtable()]]);
            switchesTblCreated = true;
        end
        appendLine([[t.switches[%q]=%s]], state, record.switches[state] and "true" or "false");
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

function UpdateBindingsMap()
    appendLine("local bindings,t,u");
    -- **With the twins, not beside them.** A flag written anywhere else could say a key is on while
    -- the records on the keys were built without its twins.
    appendLine("SelfCastKeyOn=%s", tostring(DebindPrivate.SelfCastEnabled()));
    appendLine("FocusCastKeyOn=%s", tostring(DebindPrivate.FocusCastEnabled()));

    local keyMap, keysToHold = DebindPrivate.KeyMap, DebindPrivate.KeysToHold;
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
        end
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
--- `GetBindingIssue`'s `UNDEFINED_STATE` keeps such an action out of `KeyMap`, **and that is no
--- reason to leave this empty.** That side judges by the name the parser saw and this one by the
--- definition the compile actually found; folding two judges into one is how a quiet accident
--- happens. (A switch's own `expr` is not an action, so that check never sees it at all.)
local function EmitMacroTextArg(index, arg, ownerName, isState)
    appendLine([[t.args[%d]=newtable()]], index);

    if (arg.type == Constants.MACROTEXT_ARG_UNIT) then
        appendLine([[t.args[%d].unit=%q]], index, arg.name);
        return;
    end

    -- **A switch expression keeps `@@` as written.** It is worked out once per press, before any
    -- winner, and the records of one press aim at different units, so there is no one unit to put
    -- there. `@@` reaches the client as the unit `@`, which never exists.
    if (arg.type == Constants.MACROTEXT_ARG_PRESS_UNIT) then
        if (isState) then
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

    local selfReference = isState and arg.name == ownerName;
    if (selfReference or not addSwitch(arg.name)) then
        local fixed = "known:0";
        if (selfReference and not arg.reverse) then
            fixed = "";
        end
        appendLine([[t.args[%d].fixed=%q]], index, fixed);
    else
        appendLine([[t.args[%d].state=%q]], index, arg.name);
        if (arg.reverse) then
            appendLine([[t.args[%d].reverse=true]], index);
        end
    end
end

--- One entry per parsed macro body: where it is written back to, its fragments, the arguments that
--- get re-evaluated, and which of the two tables it lands in.
---
--- **Both are read by a click and by nothing else.** `DeferredMacroTexts` holds a button's
--- `*macrotext-`, composed by the click that picks that button; `SwitchEntries` holds a computed
--- switch's expression, composed by the press that has to know the switch's answer
--- (`COMPUTE_SWITCHES_SNIPPET`). That is what takes the frame sweep down: moving an alias walks no
--- list of bodies.
local function EmitMacroTextEntries()
    local index = 0;

    for _, buttonOrStateName in ipairs(sortedKeys(_macrotextBindings, _sortedA)) do
        local data = _macrotextBindings[buttonOrStateName];
        if (data) then
            index = index + 1;
            appendLine("t=newtable()");
            appendLine("t.id=%d", index);

            -- **Where the rebuilt body lands.** A switch's expression is written into
            -- `SwitchExpressions` under its own name; everything else is a button's
            -- `*macrotext-` attribute.
            local isState = strsub(buttonOrStateName, 1, 1) == "$";
            if (isState) then
                appendLine("t.state=%q", buttonOrStateName);
            else
                appendLine("t.attr=%q", "*macrotext-" .. buttonOrStateName);
            end

            appendLine("t.fragments,t.args=newtable(),newtable()");
            for i = 1, #data.fragments do
                appendLine([[t.fragments[%d]=%q]], i, data.fragments[i]);
            end
            for i = 1, #data.args do
                EmitMacroTextArg(i, data.args[i], buttonOrStateName, isState);
            end

            if (not isState) then
                appendLine("DeferredMacroTexts[%q]=t", buttonOrStateName);
            else
                -- **A computed switch keeps its entry for the press, and the press is the only
                -- reader.** Nothing works one out between presses, so there is nobody to recompose
                -- the body for either.
                appendLine("SwitchEntries[%q]=t", buttonOrStateName);
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

--- The driver's `_onattributechanged`, which is one branch: Keys Given Back.
---
--- **`state-unitexists` went with the state loop.** Nothing measured a value between presses once
--- a computed switch stopped announcing itself, so the pass had nothing to compute and nobody to
--- compute it for. Every condition is measured at the press (`SecureBindings.lua`'s matcher) and
--- every computed switch is worked out there too (`COMPUTE_SWITCHES_SNIPPET`).
function UpdateAttrChangedHandler()
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

