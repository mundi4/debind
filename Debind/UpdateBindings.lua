local _, DebindPrivate      = ...;
local Constants               = DebindPrivate.Constants;
local BindingDriver           = DebindPrivate.BindingDriver;

local DEBUG                   = DebindPrivate.DEBUG;
local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;
local SWITCH_MODES            = Constants.SWITCH_MODES;
local JUDGE_BEAT_ATTRIBUTE    = DebindPrivate.JUDGE_BEAT_ATTRIBUTE;

local dump                               = DebindPrivate.dump;
local format, tostring                   = format, tostring;
local wipe, ipairs, pairs                = wipe, ipairs, pairs;
local InCombatLockdown                   = InCombatLockdown;

local GetModifierIndex   = DebindPrivate.GetModifierIndex;

local Rebuild               = DebindPrivate.Rebuild;
local _strArr               = Rebuild.strArr;
local _macrotexts           = Rebuild.macrotexts;
local _macrotextBindings    = Rebuild.macrotextBindings;
local _switches             = Rebuild.switches;
local _unitsSeen            = Rebuild.unitsSeen;
local sortedKeys            = Rebuild.sortedKeys;
local ResetContext          = Rebuild.ResetContext;
local addMacrotext          = Rebuild.addMacrotext;
local appendLine            = Rebuild.appendLine;
local AssertSnippetCompiles = Rebuild.AssertSnippetCompiles;
local BuildMacroTextEntries = Rebuild.BuildMacroTextEntries;
local BindingAttrsCache     = Rebuild.BindingAttrsCache;
local EmitStampedButtons    = Rebuild.EmitStampedButtons;
local BLOCKS                = Rebuild.BLOCKS;
local PrepareKeyBindings    = Rebuild.PrepareKeyBindings;
local WithBlocks            = Rebuild.WithBlocks;
local BuildKeyRecord        = Rebuild.BuildKeyRecord;
local CollectRecordNeeds    = Rebuild.CollectRecordNeeds;
local EmitRecord            = Rebuild.EmitRecord;
local AddModifier           = Rebuild.AddModifier;
local BeginCastChords       = Rebuild.BeginCastChords;
local NoteBareKey           = Rebuild.NoteBareKey;
local EmitCastChords        = Rebuild.EmitCastChords;
local JudgmentEntryFor      = Rebuild.JudgmentEntryFor;
local EmitJudgmentItems     = Rebuild.EmitJudgmentItems;
local BuildJudgeSnippet     = Rebuild.BuildJudgeSnippet;
local FillJudgePlan         = Rebuild.FillJudgePlan;
local ClearJudgeBodies      = Rebuild.ClearJudgeBodies;

local UpdateBindingsMap;
local UpdateAttrChangedHandler;

--- The world a rebuild was built against, and what it decided to do about it. **Two tables, wiped
--- and refilled**, the way the rest of this file already works.
---
--- Holding the decision apart from the doing is what lets a spec ask what a profile comes to
--- without a client in front of it: `BuildBindingPlan` answers from `ctx`, and `ApplyBindingPlan`
--- is the only step with an effect (`going-headless-outside-the-ui.md` §3-1).
local _ctx               = {};
local _plan              = { events = {}, units = {} };

--- Scratch array for `sortedKeys`. One is enough because no walk in this file runs inside another:
--- the walks a key's records and chords nest in theirs keep their own (`KeyRecords.lua`,
--- `CastChords.lua`).
---
--- **Wiped and refilled, never reallocated**, which is the rule this whole file already runs on -
--- a rebuild allocates no table it can reuse.
local _sortedA           = {};


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
wipe(JudgeByKey)
wipe(JudgeWakes)
-- A new table and not a wiped one: the values carried over sit in the same table as the column
-- array, and a wipe takes both. `switches` starts empty because a composition reads it ahead of
-- `States`, so a value left by a switch that has since become one set by hand would stand in front
-- of its real one. The pass writes every carried column's fragment and joins them again.
Judge = false
local old = JudgeStaged
local J = newtable()
J.bundles = newtable()
J.switches = newtable()
J.switchTexts = newtable()
J.classify = newtable()
J.byCell = newtable()
J.frags = newtable()
J.text = false
J.generation = 0
J.petBattle = old.petBattle
J.frameUnit = old.frameUnit
J.frameType = old.frameType
J.frameRole = old.frameRole
JudgeStaged = J
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
            if (column.kind ~= "bartakeover" or Rebuild.ParsesReplacedBars(column)) then
                judged[column.kind] = true;
            end
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
    want("UPDATE_OVERRIDE_ACTIONBAR", givesBackOnReplacedBar or judged.bartakeover);
    want("UPDATE_VEHICLE_ACTIONBAR", givesBackOnReplacedBar or judged.bartakeover);
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
    local roleSlots = Rebuild.readsRole and Constants.MAX_ROLE_SLOTS or nil;
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
    plan.roleMap = Rebuild.readsRole and true or false;

    --- The two settings of Keys Given Back that the driver's letter answers. The House Editor row is
    --- not here: what crosses for it is the claimed keys themselves (`BakeContextKeys`), because the
    --- set is the game's answer rather than a row we evaluate.
    plan.giveBack = {
        replacedBar = DebindPrivate.GiveBackOnReplacedBar(),
        petBattle = DebindPrivate.GiveBackInPetBattle(),
    };

    CollectDriverEvents(plan.events);

    --- Does any key have a judgment item, and so need the loop (`JudgeKeys`) and its beat?
    plan.judges = next(DebindPrivate.JudgmentItems) ~= nil;
    FillJudgePlan(plan);

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
        "GiveBack.replacedBar=%s GiveBack.petBattle=%s",
        tostring(giveBack.replacedBar), tostring(giveBack.petBattle)));

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
--- Which beat driver is registered on `BindingDriver`, `false` for none (`plan.beatSignal`).
--- Blizzard has no way to ask, so the rebuild that registers it keeps the answer.
local _beatRegistered = false;

function DebindPrivate.BeatOnAttribute()
    return _beatRegistered == "attribute";
end
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
    if (Constants.DEBUG) then
        driver:SetAttribute("JudgeWatchCheck", plan.judgeWatchCheck);
    end

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

--- `UpdateBindingsMap`'s scratch: the keys it walks, and the list a held key with nothing in
--- `KeyMap` stands on.
local _keysToWalk = {};
local _noBindings = {};

--- One emitted record, as a value.
---
--- **Two readers, one value.** `CollectRecordNeeds` works out what the rest of the rebuild has to
--- set up for this record and `EmitRecord` writes it into the snippet, and both read this. That is the whole point
--- of the record existing: while emitting and accumulating were one walk, the two could disagree
--- and nothing could tell (`going-headless-outside-the-ui.md` §3-2).
---
--- **One table, refilled**, like every other scratch table in this file. It is good until the next
--- `BuildKeyRecord`, and both readers run before that.
local _record            = {
    fieldNames = {},
    fieldValues = {},
    fieldCount = 0,
    units = false,
    switches = {},
    undefinedSwitches = {},
};

--- A judged key's self and focus tier entries, kept until its chords are known.
local _chordEntries = {};

--- **DEBUG only, and read by nothing in the addon.** Per key, the binding each record that went out
--- stands for, in the order the press walks them: a `KeyMap` binding, or one of `BLOCKS` and
--- `GIVEBACK_END`. The test kit names a press's winner from it. It kept a copy of this loop's layout
--- once, and the copy missed the blocks that go only where a cast key is on and the bindings
--- `PrepareKeyBindings` drops.
DebindPrivate.EmittedRecords = {};

function UpdateBindingsMap()
    appendLine("local bindings,t,u,c,b,j,e,w,x");

    -- **The cast keys a press reads**, settled here so a press does not ask the client about one
    -- turned off or on `NONE`. Like the chords, it holds until the next rebuild, which a cast key
    -- moved in combat waits for.
    local selfMod, focusMod = DebindPrivate.CastKeyModifiers();
    if (selfMod or focusMod) then
        appendLine("CastKeysOn=newtable()");
        if (selfMod) then
            appendLine("CastKeysOn.self=true");
        end
        if (focusMod) then
            appendLine("CastKeysOn.focus=true");
        end
    else
        appendLine("CastKeysOn=false");
    end

    local keyMap, handledKeys = DebindPrivate.KeyMap, DebindPrivate.HandledKeys;
    -- **Whether a key is held is settled in this loop and nowhere earlier** (`HandledKeys`): only
    -- after `PrepareKeyBindings` is it known whether any binding on the key can go out.
    local giveBack = DebindPrivate.GiveBackWhenNoActionRuns();
    local keysOnLiveLayers = not giveBack and DebindPrivate.KeysOnLiveLayers;
    local judgmentItems = DebindPrivate.JudgmentItems;
    wipe(judgmentItems);
    local emittedRecords = DebindPrivate.EmittedRecords;
    wipe(emittedRecords);
    wipe(_chordEntries);
    BeginCastChords();
    wipe(_keysToWalk);
    for key in pairs(keyMap) do
        _keysToWalk[key] = true;
    end
    if (keysOnLiveLayers) then
        for key in pairs(keysOnLiveLayers) do
            _keysToWalk[key] = true;
        end
    end

    for _, key in ipairs(sortedKeys(_keysToWalk, _sortedA)) do
        local bindingArray = keyMap[key];
        if (not bindingArray) then
            bindingArray = _noBindings;
            bindingArray.button, bindingArray.buttonPrefix = DebindPrivate.GetMouseButtonAndPrefix(key);
        end

        local button, buttonPrefix = bindingArray.button, bindingArray.buttonPrefix;
        local hasClickCast, hasKeyRecord = PrepareKeyBindings(key, bindingArray);
        -- **With `giveBackWhenNoActionRuns` off, a key an action sits on is held even with nothing on
        -- it that holds it**: every action on it was left out before the key map, or every binding
        -- on it dropped by `PrepareKeyBindings`. It gets its ends alone, so the press lands on a
        -- block and does nothing. On, such a key is not held at all
        -- (`giving-keys-back-when-no-action-runs.md` 1-1): bound and let go by the beat, it would
        -- still read as ours.
        hasKeyRecord = hasKeyRecord or (keysOnLiveLayers and keysOnLiveLayers[key] == true);
        local keyArray = hasKeyRecord and WithBlocks(bindingArray, giveBack) or bindingArray;

        local first = true;
        local selfCount, focusCount = 0, 0;
        local selfTwins, focusTwins = 0, 0;
        -- The records a press on this key or one of its chords walks, by tier.
        local tiers = {
            [Constants.CASTMOD_NONE] = {}, [Constants.CASTMOD_SELF] = {}, [Constants.CASTMOD_FOCUS] = {},
        };

        if (hasClickCast or hasKeyRecord) then
            for i = 1, #keyArray do
                local binding = keyArray[i];
                local isClickCast = hasClickCast and binding.isClickCast;
                local holdsKey = hasKeyRecord and binding.holdsKey;

                if (isClickCast or holdsKey) then
                    local record = BuildKeyRecord(binding, isClickCast, holdsKey, _record);
                    if (first) then
                        first = false;
                        if (DEBUG) then
                            appendLine("-- %s", key);
                        end
                        appendLine("bindings=newtable()");
                    end
                    CollectRecordNeeds(record);
                    EmitRecord(record);
                    if (DEBUG) then
                        local emitted = emittedRecords[key] or {};
                        emittedRecords[key] = emitted;
                        emitted[#emitted + 1] = binding;
                    end
                    if (holdsKey) then
                        local tier = binding.castModifier or Constants.CASTMOD_NONE;
                        local list = tiers[tier];
                        list[#list + 1] = JudgmentEntryFor(binding, record, tier);
                        if (binding ~= BLOCKS[tier]) then
                            if (tier == Constants.CASTMOD_SELF) then
                                selfTwins = selfTwins + 1;
                            elseif (tier == Constants.CASTMOD_FOCUS) then
                                focusTwins = focusTwins + 1;
                            end
                        end
                    end
                    if (binding.castModifier == Constants.CASTMOD_SELF) then
                        selfCount = selfCount + 1;
                    elseif (binding.castModifier == Constants.CASTMOD_FOCUS) then
                        focusCount = focusCount + 1;
                    end
                end
            end
        end

        -- **Where the key's tiers start, so a press walks only the one its modifier picks**
        -- (`EVAL_SNIPPET`). Counted off the records that went out.
        if (not first) then
            appendLine("bindings.focusFrom=%d", selfCount + 1);
            appendLine("bindings.noneFrom=%d", selfCount + focusCount + 1);
        end

        -- **Which cast keys a press on the key itself reads**, named after the action button
        -- attributes that mean the same: a key with no self twin is a button with `checkselfcast`
        -- off (`picking-the-cast-tier-like-an-action-button.md` §1-4). Not where the key's own
        -- name holds the modifier: the client hides it on every press of the key.
        if (hasKeyRecord and not first) then
            if (selfMod and selfTwins > 0 and AddModifier(key, selfMod)) then
                appendLine("bindings.checkSelfCast=true");
            end
            if (focusMod and focusTwins > 0 and AddModifier(key, focusMod)) then
                appendLine("bindings.checkFocusCast=true");
            end
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
            handledKeys[key] = true;
        end

        -- **Diagnostic only.** Nothing reads it; it is there so one `bindings` shows its kind in
        -- the game.
        if (hasKeyRecord) then
            appendLine("bindings.hasKeyRecord=true");
        end

        -- **Bound here; let go and taken again by the loop where its item says so.** Which action
        -- goes out is the wrapper's to decide at the press. The button name carries the key there,
        -- since the wrapper gets nothing but `self` and `button`.
        if (hasKeyRecord and not first) then
            local clickTimeButton = Constants.CLICKTIME_BUTTON_PREFIX .. key;
            DebindPrivate.ClickTimeKeys[key] = clickTimeButton;
            handledKeys[key] = true;
            appendLine("ClickTimeKeys[%q]=bindings", clickTimeButton);
            appendLine("self:SetBindingClick(true,%q,DefaultClickFrameName,%q)", key,
                clickTimeButton);
            -- **The other direction of the line above, and the button name it just used**, so a
            -- key handed to the game can be found by its own spelling and put back with the same
            -- argument (`UpdateGivenBackKeys`). The rebuild has cleared every override on its way
            -- in, so nothing is given back at this point and no slot is written for that.
            appendLine("BoundKeys[%q]=bindings", key);
            appendLine("bindings.clickButton=%q", clickTimeButton);
            NoteBareKey(key, selfTwins > 0, focusTwins > 0);

            -- **Kept only where some state lets the key go or binds it elsewhere.** Asked of the
            -- item rather than of the key's last action: an action with no conditions still runs on
            -- no plain press when it is set to run only while pointing, or has every cast value
            -- off, and the item knows that from the records.
            --
            -- **No key is spared `ItemFor`, one whose answer shows without it included** (an action
            -- with no condition reached first). That function is the one place deciding which keys
            -- are judged; asking it costs a rebuild hundredths of a ms per key and the beat nothing.
            local item = DebindPrivate.Judgment.ItemFor(tiers[Constants.CASTMOD_NONE]);
            if (item) then
                judgmentItems[key] = item;
                _chordEntries[key] = tiers;
            end
        end
    end

    -- **The self and focus tiers get chords of their own** (`handing-the-rest-of-a-key-to-the-game.md`
    -- 2-3). After the loop, because where a chord lands depends on every bare key being known.
    EmitCastChords(selfMod, focusMod, judgmentItems, _chordEntries);

    -- After the chords, whose `BoundKeys` rows an item points at.
    if (next(judgmentItems)) then
        EmitJudgmentItems(judgmentItems);
    end

    -- **Emitted after the key loop, because that loop is what stamps them.**
    EmitStampedButtons();

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
        ClearJudgeBodies();
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

