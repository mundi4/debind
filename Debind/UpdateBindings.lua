local _, DebindPrivate      = ...;
local Constants               = DebindPrivate.Constants;
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
local wipe, ipairs, pairs, tinsert, sort = wipe, ipairs, pairs, tinsert, sort;
local band, bor                          = bit.band, bit.bor;
local InCombatLockdown                   = InCombatLockdown;
local FindBaseSpellByID                  = C_SpellBook.FindBaseSpellByID;
local GetSpellNameAndIconID              = DebindPrivate.GetSpellNameAndIconID;
local GetSpellSubtext                    = C_Spell.GetSpellSubtext;
local IsPressHoldReleaseSpell            = C_Spell.IsPressHoldReleaseSpell;
local GetMountInfoByID                   = C_MountJournal.GetMountInfoByID;

local BindingAttrsCache                  = {};

--- 버튼 이름 -> 그 이름으로 `*typerelease-`를 구웠는가.
---
--- **구운 사실과 같은 출처에서 읽어야 한다.** 래퍼는 맨이름 `pressAndHoldAction`을 이 값으로
--- 쓰는데, 그걸 `IsPressHoldReleaseSpell`로 매번 다시 물으면 캐시 적중으로 속성을 안 건드린
--- 경우와 어긋난다. 그러면 눌러서 시작은 되는데 `*typerelease-`가 없어서 **안 놓인다.**
--- (500행 주석의 그 질문 - 특성으로 값이 바뀌는 경우)
local BindingPressHoldCache              = {};

local STATE_EVAL_EXPRESSIONS             = Constants.STATE_EVAL_EXPRESSIONS;


local NextButtonName;
do
    local _nextId = 100;
    function NextButtonName()
        _nextId = _nextId + 1;
        return "deb" .. _nextId;
    end
end

local SetBindingAttributes;
local UpdateBindingsMap;
local UpdateMacroTextsMap;
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
local _updateFlags       = {};

--- Which names already have a list in `MacroTextsMap`. Module level, so a rebuild reuses it rather
--- than allocating - the rule this file runs on.
local _keysSeen          = {};

--- The world a rebuild was built against, and what it decided to do about it. **Two tables, wiped
--- and refilled**, the way the rest of this file already works.
---
--- Holding the decision apart from the doing is what lets a spec ask what a profile comes to
--- without a client in front of it: `BuildBindingPlan` answers from `ctx`, and `ApplyBindingPlan`
--- is the only step with an effect (`devdocs/legacy/going-headless-outside-the-ui.md` §3-1).
local _ctx               = {};
local _plan              = { events = {}, units = {} };

--- **Build time, not runtime.** These two pick what gets measured; the secure globals `States` and
--- `UnitStates` hold what was measured. The underscore only says "local to this file" and left the
--- two kinds looking alike, which is a real source of confusion: being registered here decides
--- whether polling re-measures a value, and nothing else. Whether a record's condition is compared
--- is decided by the record carrying that field, not by anything in here.
local _measuredStates    = {};
local _measuredUnitAxes  = {};

--- Does any state-driven key have to be re-decided when the hover **frame** changes while the
--- unit under it does not? Only a `frameTypes` record can, and only the update loop acts on it,
--- so this is aggregated from the same per-key flags rather than kept as its own condition.
local _rebindOnHoverFrame = false;

--- Does any measured unit carry the reaction axis? That is what `UNIT_FACTION` is registered for.
--- Accumulated where the axes are worked out rather than derived by walking `_measuredUnitAxes` later,
--- because the axis constants are declared further down this file than the registration runs.
local _measuresReaction = false;

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
    wipe(_macrotexts);
    wipe(_macrotextBindings);
    wipe(_switches);
    wipe(_measuredStates);
    wipe(_measuredUnitAxes);
    wipe(_unitsSeen);
    _rebindOnHoverFrame = false;
    _measuresReaction = false;
end

--- This rebuild's take on one switch, or `false` where nothing defines the name.
---
--- **The name is not checked against a list any more.** It used to have to be one of the numbered
--- five, and a name outside them was answered `false` without so much as asking whether it was
--- defined. So a definition could never be found under any other name, which is what §10's 1b-2
--- lifts (`devdocs/redesigning-custom-states.md`). What decides now is the same thing that decides
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

local function appendLine(str, ...)
    if (select("#", ...)) then
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
--- turns those into values is stage 3 of `devdocs/legacy/going-headless-outside-the-ui.md`; naming the
--- seam is what makes it possible to move.
local function CollectBindingContext()
    -- **Where a specialization change reaches a switch** (§4-8 of
    -- `devdocs/redesigning-custom-states.md`). An override saying "always on in this
    -- specialization" has to be applied on the way *into* that specialization, not only at login,
    -- and a specialization change is a rebuild - this one. It is below the guard above on purpose:
    -- which answer wins depends on the specialization, so asking before it is known would resolve
    -- every switch against the wrong world and then not ask again.
    --
    -- Nothing is re-applied where the answer has not moved, so the ordinary rebuild - a binding
    -- edited, a macro saved - leaves every value where the reader left it.
    DebindPrivate.ApplySwitchResets();

    DebindPrivate.RefreshYieldedKeys();
    DebindPrivate.RefreshGameMenuKeys();

    DebindPrivate.BuildKeyMap();

    local ctx = _ctx;
    ctx.keyMap = DebindPrivate.KeyMap;
    ctx.updatetime = DebindPrivate.Options.updatetime;
    return ctx;
end

--- Puts the secure side back to nothing, so what the build emits lands on an empty table.
---
--- **It runs before the build rather than inside `ApplyBindingPlan`, and that is temporary.** The
--- build still stamps attributes and builds delegate frames as it goes (`SetBindingAttributes`),
--- so a reset deferred to the apply would land on top of what the build had already put out.
--- Stage 2 of `devdocs/legacy/going-headless-outside-the-ui.md` takes the stamping out of the build, and
--- this moves in with it.
local function ClearPreviousBindings()
    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
wipe(OldStates)
for k, v in pairs(States) do
    OldStates[k] = v
end
self:RunAttribute("ClearUnitAttributes")
wipe(StateDrivenBindings)
wipe(ClickTimeKeys)
for _, byMod in pairs(ClickCastKeys) do
    wipe(byMod)
end
wipe(HeldButtons)
wipe(HeldUnits)
-- Drop any unconsumed handoff -- it points into the old records.
HandoffBindings = nil
HandoffWinner = nil
HandoffHoverUnit = nil
wipe(MacroTextsMap)
wipe(UnitStates)
wipe(SwitchExpressions)

-- **`unitframe`은 살려서 넘긴다.** `States`에 든 나머지는 리빌드가 끝나면서 전부 다시
-- 채워지지만, 이건 enter/leave 이벤트로만 서는 값이라 **다시 채워줄 사람이 없다.** 지우면
-- 다음에 커서가 들어올 때까지 빈 채로 남는다.
--
-- 커서는 그대로 프레임 위에 있는데 조건 하나만 바뀌면(전투 진입, 자세 변경, 특성) 리빌드가
-- 돌고, 그 순간 hover 조건 바인딩이 전부 죽는다. 마우스를 뺐다 다시 올려야 살아났다.
--
-- 짝이 되는 `UnitAliasMap["hover"]`는 이 프롤로그가 안 지운다. 그래서 지우면 둘이 갈리기까지
-- 한다 - hover 유닛은 남아 있는데 hover 프레임은 없는 상태가 된다.
local hovered = States.unitframe
wipe(States)
States.unitframe = hovered
]]);

    ClearOverrideBindings(BindingDriver);
    DebindPrivate.BindingDriver:SetAttribute("_onattributechanged", nil);
end

--- The line that puts a switch's stored value back, plus the fixed macro conditional behind a
--- computed one. Returns nil where this rebuild has no switch to say anything about.
---
--- Writing into `States` directly would raise no change event, so the state change message would
--- not print. The value goes back through `SetSwitch` for that reason.
local function BuildSwitchesSnippet()
    for _, state in ipairs(sortedKeys(_switches, _sortedA)) do
        local stateInfo = _switches[state];
        if (stateInfo) then
            -- previous switch value
            if (stateInfo.value ~= nil) then
                appendLine([[self:RunAttribute("SetSwitch", %1$q, %s, true)]], state,
                    tostring(stateInfo.value));
            end

            -- fixed macro conditional
            if (stateInfo.mode == SWITCH_MODES.EXPR and not addMacrotext(stateInfo.expr)) then
                appendLine([[SwitchExpressions[%q]=%q]], state, stateInfo.expr);
            end
        end
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
--- **Every one of these is a pure reading of what got measured**, and until they were collected
--- into a value the only way to see one was to stand a `SecureStateDriverManager` up and look at
--- what had been registered on it. Two faults lived here for exactly that reason, and both are
--- gone: the old `_measuredStates.reaction` term did not look at *which* unit, so a reaction
--- condition on `target` alone dragged the mouseover registration along with it, and
--- `HoverBindings` was so wide that the narrow test beside it meant nothing.
---
--- The order here is the order they are applied in. It is written out rather than walked out of a
--- table, so what a rebuild emits does not depend on `pairs`.
local function CollectDriverEvents(events)
    local function want(name, register)
        events[#events + 1] = { name = name, register = register and true or false };
    end

    -- **묻는 것은 "hover를 재나"다.** 이 등록의 목적이 호버 dangling 감지이므로, 답은 hover
    -- 축을 측정하는 유닛이 있느냐에 있다. 예전 술어의 `_measuredStates.reaction` 항은 잉여였다 -
    -- 반응 조건은 유닛 조건의 일부라 `_measuredUnitAxes`가 이미 덮는다.
    want("UPDATE_MOUSEOVER_UNIT", _measuredUnitAxes.hover or _measuredUnitAxes.mouseover);

    -- 반응 축을 재는 유닛이 하나라도 있으면 등록한다. 예전 술어(`_measuredStates.reaction`)는 어느
    -- 유닛인지를 안 봐서, `target`에만 반응 조건을 걸어도 위의 mouseover 등록까지 딸려 왔다.
    -- 측정에서 파생시키면 앞 단계의 좁히기도 그대로 따라온다 - 배선이 고정된 키만 반응을 묻는
    -- 프로필에서는 재는 유닛이 없고 이 이벤트도 안 걸린다.
    want("UNIT_FACTION", _measuresReaction);

    want("UPDATE_OVERRIDE_ACTIONBAR", _measuredStates.specialbar);
    want("UPDATE_VEHICLE_ACTIONBAR", _measuredStates.specialbar);

    want("UPDATE_EXTRA_ACTIONBAR", _measuredStates.extrabar);

    -- specialbar folds [petbattle] into its own value, so it needs these too
    want("PET_BATTLE_OPENING_START", _measuredStates.petbattle or _measuredStates.specialbar);
    want("PET_BATTLE_CLOSE", _measuredStates.petbattle or _measuredStates.specialbar);

    local hasKnownState = false;
    for state in pairs(_measuredStates) do
        if (strsub(state, 1, 7) == "[known:") then
            hasKnownState = true;
            break;
        end
    end
    want("SPELLS_CHANGED", hasKnownState);

    return events;
end

--- Which special units this rebuild watches. A unit nobody named is not only left unwatched, its
--- alias is cleared as well -- a stale one would stay resolvable on the secure side.
---
--- `custom1` and `custom2` are set by an action rather than measured, so they are not this
--- function's to turn on or off.
local function CollectWatchedUnits(units)
    for _, unit in ipairs(sortedKeys(SPECIAL_UNITS, _sortedA)) do
        if (unit ~= "custom1" and unit ~= "custom2") then
            units[#units + 1] = { alias = unit, watch = _unitsSeen[unit] and true or false };
        end
    end
    return units;
end

--- What this rebuild decided, as a value.
---
--- **What is not pure yet is the emitters.** `UpdateBindingsMap` reaches `SetBindingAttributes`,
--- which stamps the click frame and builds delegate frames as it walks; stages 2 and 3 of
--- `devdocs/legacy/going-headless-outside-the-ui.md` take that out. What is already a value is every
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
    plan.macroTextsSnippet = UpdateMacroTextsMap();
    plan.attrChangedSnippet = UpdateAttrChangedHandler();
    plan.switchesSnippet = BuildSwitchesSnippet();

    CollectWatchedUnits(plan.units);

    -- **호버 프레임이 바뀌었을 때 다시 걸 것이 있나.** 이름 그대로다: 유닛은 그대로인데
    -- 프레임만 바뀌는 사건에 반응해야 하는 상태 구동 키가 하나라도 있는가.
    --
    -- 예전 이름은 `HoverBindings`였고 값은 *"hover를 쓰는 바인딩이 있나"*였는데, 그건 훨씬
    -- 넓다 - 호버 유닛이 바뀌는 쪽은 `SetUnit`의 반환값이 이미 답한다. 둘을 `or`로 묶어 쓰는
    -- 자리가 셋 있고, 넓은 쪽이 켜져 있으면 좁은 쪽 판정이 아무 의미가 없었다.
    plan.rebindOnHoverFrame = _rebindOnHoverFrame and true or false;

    CollectDriverEvents(plan.events);

    -- **The throttle this rebuild asks for, and it is the fallback rather than the answer.**
    -- `FinishBindingUpdate` writes `updatetime` again from the option the window's slider sets
    -- (`ApplyOptions`), and that one usually wins.
    --
    -- **Usually, not always.** `ApplyOptions` only writes when the stored option is a number, and
    -- nothing type-checks `db.options` -- so a hand-edited SavedVariables holding a string skips it
    -- entirely, and then what the state driver runs on is the value decided here. Do not delete
    -- this write on the grounds that the other one covers it: `STATE_DRIVER_UPDATE_THROTTLE` is
    -- Blizzard's own, shared with every addon, and leaving nobody to write it means whatever was
    -- there last stays (`.zzz/refactor-candidates.md` 33).
    --
    -- `Options.updatetime` is a key nothing in the repository writes, so the clamp below comes out
    -- at the default today. It is also the only place a profile that polls for a mouseover unit
    -- could ever ask for a rate of its own -- which `ApplyOptions` running afterwards takes away.
    local updatetime = ctx.updatetime;
    if (not updatetime or updatetime < 0 or updatetime > Constants.STATE_DRIVER_UPDATETIME_DEFAULT) then
        updatetime = Constants.STATE_DRIVER_UPDATETIME_DEFAULT;
    end
    plan.updatetime = updatetime;

    return plan;
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

    for i = 1, #plan.units do
        local entry = plan.units[i];
        if (entry.watch) then
            DebindPrivate.EnableUnitWatch(entry.alias);
        else
            DebindPrivate.DisableUnitWatch(entry.alias);
            SecureHandlerExecute(driver,
                format([[self:RunAttribute("SetUnit", %q, nil)]], entry.alias));
        end
    end

    SecureHandlerExecute(driver, format("RebindOnHoverFrame=%s", tostring(plan.rebindOnHoverFrame)));

    for i = 1, #plan.events do
        local entry = plan.events[i];
        if (entry.register) then
            SecureStateDriverManager:RegisterEvent(entry.name);
        else
            SecureStateDriverManager:UnregisterEvent(entry.name);
        end
    end
    SecureStateDriverManager:SetAttribute("updatetime", plan.updatetime);

    -- 클릭캐스팅 라우팅을 프레임들에 반영한다. **아래 상태 루프보다 먼저다** - 그쪽이
    -- `<접두사>type<번호>`를 걸므로, 짝인 `clickbutton`이 아직 없으면 그 사이의 클릭이
    -- 조용히 사라진다(`SECURE_ACTIONS.click`이 delegate가 없으면 아무것도 안 한다).

    -- execute UpdateBindings with forceAll set
    SecureHandlerExecute(driver, [[
        DirtyFlags.forceAll = true
        self:RunAttribute("UpdateAllUnits")
        self:RunAttribute("UpdateMacroTexts", true)
        self:SetAttribute("state-unitexists", 1)
    ]]);
end

--- What is left once the bindings are up: drop what this rebuild made stale, put the reader's own
--- throttle back, and say that it happened.
local function FinishBindingUpdate()
    DebindPrivate.ClearMacroTextCache(_macrotexts);

    DebindPrivate.ApplyOptions("stateDriverUpdateThrottle");

    DebindPrivate.callbacks:Fire("OnBindingsUpdated");

    if (DEBUG) then
        dump("UpdateBindings", {
            states = _measuredStates,
            unitStates = _measuredUnitAxes,
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
--- (`devdocs/legacy/going-headless-outside-the-ui.md` §4).
local function CollectBindingFacts(type, value, unit, facts)
    wipe(facts);

    if (type == Constants.PETACTION) then
        facts.petMacrotext = DebindPrivate.GetPetActionMacroText(value, unit);
    elseif (type == Constants.FLYOUT) then
        facts.flyoutOpener = DebindPrivate.GetFlyoutOpener(value);
    elseif (type == Constants.SPELL) then
        -- id는 다르지만 이름은 같은 주문들이 있다.
        -- 예: 조화 전문화의 달빛야수 변신과 회복 전문화의 달빛야수 변신
        -- id로 바인딩하는 경우 다른 전문화의 주문은 실행되지 않음.
        local spellID = FindBaseSpellByID(value) or value;
        facts.spellID = spellID;
        facts.spellName = GetSpellNameAndIconID(spellID);
        if (facts.spellName) then
            facts.spellSubtext = GetSpellSubtext(spellID);
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
            facts.mountMacrotext = DebindPrivate.GetMountMacroText(value);
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
local function DescribeBinding(type, value, unit, facts, out)
    out = out or { attrNames = {}, attrValues = {} };
    out.count = 0;

    -- **Two types write no attribute at all and are not refusals.** Unused clears the key and a
    -- command binds itself, so neither needs a button to click.
    if (type == Constants.UNUSED or type == Constants.COMMAND) then
        return nil, "self-bound";
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

    out.type = type;
    out.value = value;
    out.unit = unit;

    -- **The key the stamp files this button under**, taken before any branch below rewrites the
    -- value for its own attribute. It used to be read after, and only the item branch rewrites --
    -- so an item binding was looked up under `6948` and filed under `"item:6948"`, which is a
    -- cache that never hits and a button allocated afresh on every rebuild, for the whole session.
    out.cacheKey = value or NIL;

    if (type == Constants.SPELL) then
        attr(out, "*type-", "spell");
        if (facts.spellName) then
            local spellName = facts.spellName;
            if (facts.spellSubtext and facts.spellSubtext ~= "") then
                spellName = spellName .. "(" .. facts.spellSubtext .. ")";
            end
            attr(out, "*spell-", spellName);
        else
            attr(out, "*spell-", facts.spellID);
        end

        -- what if 'IsPressHoldReleaseSpell' value is changed by a talent or something? is there a such situation?
        --
        -- 그렇다면 이 블록이 캐시 적중으로 통째로 건너뛰어지는 것이 문제가 된다. 답이
        -- 바뀌어도 `*typerelease-`는 옛날 그대로다. 그래서 **구웠다는 사실 자체를 남긴다** -
        -- 래퍼가 맨이름 `pressAndHoldAction`을 쓸 때 이 값을 보므로, 다시 물어서 답이
        -- 달라지면 "시작은 되는데 안 놓이는" 상태가 된다.
        if (facts.pressAndHold) then
            attr(out, "*typerelease-", "spell");
            attr(out, "*pressAndHoldAction-", true);
        end
    elseif (type == Constants.ITEM) then
        attr(out, "*type-", "item");
        attr(out, "*item-", format("item:%d", value));
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
        attr(out, "*attribute-value-", "hover");
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
--- is written at all -- and `pressAndHold` comes back out of `BindingPressHoldCache` rather than
--- off the descriptor, because what the wrapper reads is what was **baked**, not what the client
--- would answer if asked again.
local function StampBinding(descriptor)
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

        if (descriptor.pressAndHold) then
            BindingPressHoldCache[buttonname] = true;
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

    return delegate or clickframe, buttonname, BindingPressHoldCache[buttonname];
end

DebindPrivate.DescribeBinding = DescribeBinding;
DebindPrivate.StampBinding = StampBinding;

--- Asks, describes, stamps. **The reason a binding was refused is dropped here and nowhere else**,
--- because the caller's shape still cannot carry one; stage 3 of
--- `devdocs/legacy/going-headless-outside-the-ui.md` is where the record loop learns to.
function SetBindingAttributes(type, value, unit)
    local facts = CollectBindingFacts(type, value, unit, _facts);
    local descriptor, reason = DescribeBinding(type, value, unit, facts, _descriptor);
    if (not descriptor) then
        if (DEBUG and reason ~= "self-bound") then
            DebindPrivate.log("No attributes for:", type, value, reason);
        end
        return;
    end

    local clickframe, buttonname, pressAndHold = StampBinding(descriptor);

    if (descriptor.type == Constants.MACROTEXT) then
        addMacrotextBinding(buttonname, descriptor.value);
    end

    return clickframe, buttonname, pressAndHold;
end

--- Which axes have to be **measured** for a unit. Accumulated per unit across every binding that
--- names it, so an axis nobody asks about is never measured and simply has no field in
--- `UnitStates[unit]`. Nothing can ask about an unmeasured axis -- asking is what turns the bit on
--- -- so its absence never reaches a comparison.
---
--- This is what retires the old encoding's defect. Registration used to change the **meaning** of
--- the value (with nobody asking about reaction, a friendly unit came back as `true`), so every
--- consumer had to know who else had registered what. Now registration changes only precision.
local UNITAXIS_EXISTS   = 1;
--- Reaction is measured as **one axis, all the way**. Emitting a term per registered value saved a
--- call when only `help` was asked for, and paid for it by putting `true` in the place of the
--- values nobody asked about. Resolving to exactly one of help/harm/other costs one more C call in
--- the worst case and buys back a value that means the same thing to everyone.
local UNITAXIS_REACTION = 2;
--- Life is two C calls, not one: `UnitIsDeadOrGhost` is not in the restricted environment
--- (`RestrictedEnvironment.lua`'s `DIRECT_MACRO_CONDITIONAL_NAMES` lists only `UnitIsDead` and
--- `UnitIsGhost`). Both have to be asked, because a ghost is not dead by `UnitIsDead` and the
--- macro `[dead]` this mirrors counts it as dead. Reading a ghost as alive sends heals at a corpse.
local UNITAXIS_DEAD     = 4;

local REACTION_NAMES = {
    [Constants.REACTION_HELP]  = "help",
    [Constants.REACTION_HARM]  = "harm",
    [Constants.REACTION_OTHER] = "other",
};

---
--- 같은 유닛에 조건이 두 번 걸렸을 때 하나로 합친다.
---
--- `"@"`는 이 액션 자신의 대상 유닛을 가리키므로, 그 유닛에 명시 조건도 걸려 있으면
--- **`t.units`의 같은 키에 두 번 쓰게 된다.** 합치지 않으면 `pairs` 순서에 따라
--- 한쪽이 조용히 사라진다 - 걸어둔 조건이 무작위로 없어지는 것이다.
---
--- 포섭 관계(`true` vs `"help"`)는 `GetBindingInfoForAction`의 정규화가 앞에서
--- 걷어내지만 여기서도 받아준다. 나머지 조합은 전부 모순이고, 그건 `GetBindingIssue`가
--- 걸러서 `KeyMap`에 안 들어온다.
---
--- Values carry one field per axis (`Profile.lua`'s `dbver <= 4` step), so merging is an
--- intersection **per axis**. One empty axis leaves no state at all, which is `NEVER` for the
--- whole condition.
---
--- ============================================================================================
--- `NEVER` IS UNREACHABLE. DO NOT BUILD A RUNTIME REPRESENTATION FOR IT.
--- ============================================================================================
---
--- Every way this function can return `NEVER` is a zero mask in `binding.unitStates`, and a zero
--- mask is an issue, and an action with an issue never enters `KeyMap`:
---
---   absent vs a constrained axis   `band(UNITSTATE_NONE, ...)`  == 0
---   reactions do not overlap       `band(reaction, reaction)`   == 0
---   life asked both ways           `band(ALIVE, DEAD)`          == 0
---
--- `Misc.BuildUnitStates` folds the same conditions with the same intersection, `GetBindingIssue`
--- reports the zero, and `Debind.lua` leaves that binding out of `KeyMap`. So a contradictory
--- binding reaches **neither the solver nor this file**.
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

    return { reaction = reaction, dead = dead };
end

--- Emits the line that creates a key's record list, and puts it in `StateDrivenBindings` only when
--- the update loop has a wiring decision to make for that key.
---
--- **`StateDrivenBindings` is read by the update loop and by nothing else.** Two kinds of key leave
--- it with nothing to decide, and both stay out:
---
---   배선이 고정된 키      bound once, below. Which action goes out is the wrapper's call at the click
---   클릭캐스팅 전용 키     no record holds the key at all, so there is no key role to bind or release
---
--- Being in the table would only buy a walk over its records on every dirty flag, ending in
--- "nothing to do" -- and the second kind ended there without reading a single record. That is why
--- the loop can now open with `keyBound` unset instead of asking whether the key is held at all.
---
--- The list still has an owner either way: the `ClickTimeKeys` or `ClickCastKeys` registration
--- below holds it, and that is the table the wrapper reaches it through. Every one of those lines
--- is driven by the same `first` flag, so a key that emitted no records gets none of them.
local function AppendBindingsList(key, stateDriven)
    if (stateDriven) then
        appendLine("bindings=newtable();StateDrivenBindings[%q]=bindings", key);
        if (DEBUG) then
            DebindPrivate.StateDrivenKeys[key] = true;
        end
    else
        appendLine("bindings=newtable()");
    end
end

--- Which dirty flag re-decides a key that carries a record field.
---
--- **This table is what stops "what went out" and "what gets measured" from being written down
--- twice.** They used to be: the emitting branch for an axis set its own flag on the line below,
--- so an axis emitted without its flag was a key that never woke up, and a flag set without its
--- axis was a measurement nobody read. Both happened. The flags are read off the finished record
--- now (`CollectRecordAxes`), so there is no second place for them to be written.
---
--- The names do not match the field names for four of them, and that is the other half of why the
--- pairing was easy to get wrong: `groups` wakes on `group`, `forms` on `form`, `bonusbars` on
--- `bonusbar`.
---
--- `known` is `true` rather than a name: **the value it emits is the state name**, brackets and
--- all, because the click path hands the same string to `SecureCmdOptionParse` that the poll uses
--- as a key in `States`.
---
--- `frameTypes` is not in here. Its flag depends on the record's own `holdsKey`, so it is read
--- where that is in hand.
local FIELD_FLAGS        = {
    groups     = "group",
    combat     = "combat",
    stealth    = "stealth",
    known      = true,
    forms      = "form",
    bonusbars  = "bonusbar",
    specialbar = "specialbar",
    extrabar   = "extrabar",
    pet        = "pet",
    petbattle  = "petbattle",
};

--- The condition axes that go out as a plain field, **in the order they are emitted in**, with the
--- value that means "no restriction" for the three that have one.
---
--- `known` carries `derived`: what goes out is not the condition's value but the macro conditional
--- built from the action's own value.
local CONDITION_AXES     = {
    { field = "groups",     allValue = Constants.GROUP_ALL },
    { field = "combat" },
    { field = "stealth" },
    { field = "known",      derived = true },
    { field = "forms",      allValue = Constants.FORM_ALL },
    { field = "bonusbars",  allValue = Constants.BONUSBAR_ALL },
    { field = "specialbar" },
    { field = "extrabar" },
    { field = "pet" },
    { field = "petbattle" },
};

--- One emitted record, as a value.
---
--- **Two readers, one value.** `CollectRecordAxes` works out what has to be measured for this
--- record and `EmitRecord` writes it into the snippet, and both read this. That is the whole point
--- of the record existing: while emitting and accumulating were one walk, the two could disagree
--- and nothing could tell (`devdocs/legacy/going-headless-outside-the-ui.md` §3-2).
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
--- flyout with every slot empty), and a record emitted for one of those is counted by the secure
--- side as a binding that took: `keyBound` goes up, neither `SetBindingClick` nor `ClearBinding`
--- runs, and the `not keyBound` cleanup below it is skipped as well.
---
--- **So the whole key is eaten.** Not just that action -- every lower priority action on the same
--- key goes with it. A hunter with no pet and a Call Pet binding is the case.
---
--- Unused and command are the exception: both fire without a `clickbutton`, by their own route
--- (`ClearBinding` / `SetBinding`).
local function PrepareKeyBindings(key, bindingArray)
    local button = bindingArray.button;
    local hasClickCast, hasKeyRecord = false, false;

    for i = 1, #bindingArray do
        local binding = bindingArray[i];
        binding.isClickCast = button ~= nil and binding.type ~= Constants.COMMAND and
            (binding.hover or binding.type == Constants.SETCUSTOM or binding.unit == "hover") and
            true or false;
        binding.holdsKey = (button == nil or not binding.hover) and true or false;
        binding.clickframe, binding.clickbutton, binding.pressAndHold =
            SetBindingAttributes(binding.type, binding.value, binding.unit);

        -- Read here rather than where the record is built, so that nothing below this line needs
        -- a frame at all. `DefaultClickFrame` is the one the record leaves out.
        binding.clickframeName = (binding.clickframe and binding.clickframe ~= DefaultClickFrame)
            and binding.clickframe:GetName() or nil;

        if (binding.type ~= Constants.UNUSED and binding.type ~= Constants.COMMAND
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

--- The three answers a key gets before any of its records is built.
---
--- **두 결정은 원래 분리된다.** 한 플래그로 묶여 있던 것을 여기서 가른다.
---
---   이 키를 어떻게 걸 것인가   상태에 의존한다. 클릭이 도착하기 전에 정해져 있어야 한다
---   어느 액션이 나갈 것인가     클릭 순간에 정하면 된다
---
--- `IsKeyAlwaysOurs`는 **첫 번째**에만 답한다(`click-time-eval.md` §6). 그 답이 거짓이면 두
--- 번째까지 옛 방식에 남길 이유가 없는데 2단계가 그렇게 두었다. 같은 문서가 이미 적어둔
--- 결론이다 - "그 판정만 지금 방식으로 추적한다. 어느 액션인지는 여전히 클릭 시점에 정한다."
---
--- **`PrepareKeyBindings` 뒤에만 부를 수 있다.** `holdsKey`가 거기서 정해지고, 걸 수단이 없어
--- 떨궈진 항목도 거기서 걸러진다. 먼저 부르면 전부 nil이라 아무 키도 라우팅되지 않는데
--- 회귀는 안 나므로 알아채기 어렵다.
---
--- 나중에 이 앞에 tier 1이 들어온다 - 조건을 매크로 본문에 직접 구워 게임이 시전 순간에
--- 판정하게 하는 것. 되는 키는 클릭당 우리 비용이 0이라 래퍼를 태우는 것보다 싸다.
local function ClassifyKey(bindingArray, hasKeyRecord)
    -- 어느 액션인가를 클릭 시점에 정한다. 키를 잡는 레코드가 하나라도 있으면 된다.
    local clickTime = Constants.CLICK_TIME_EVAL and hasKeyRecord and true or false;

    -- 키 배선까지 고정이다. 한 번 `SetBindingClick` 걸고 상태 루프는 이 키의 키 역할을
    -- 아예 안 본다.
    local alwaysOurs = clickTime and DebindPrivate.IsKeyAlwaysOurs(bindingArray) and true or false;

    -- 상태 루프가 이 키에서 정할 것이 있나. 둘 다여야 한다: 키를 잡는 레코드가 있어야 하고
    -- (없으면 클릭캐스팅 전용이라 걸었다 놓았다 할 키 역할 자체가 없다), 그 배선이 고정이
    -- 아니어야 한다.
    local stateDriven = hasKeyRecord and not alwaysOurs;

    return clickTime, alwaysOurs, stateDriven;
end

--- 같은 유닛에 두 번 걸린 조건을 하나로 접는다. 접어서 아무것도 안 남으면 **nil** - 그 바인딩은
--- 어떤 상태에서도 안 나가므로 레코드를 만들지 않는다.
---
--- `"@"`는 이 액션 자신의 대상 유닛을 가리키므로, 그 유닛에 명시 조건도 걸려 있으면
--- **같은 키에 두 번 쓰게 된다.** 접지 않으면 `pairs` 순서에 따라 한쪽이 조용히 사라진다 -
--- 걸어둔 조건이 무작위로 없어지는 것이다.
---
--- **여기까지 오는 것 자체가 원래 없다.** `mergeUnitConditions`가 `NEVER`를 내는 세 갈래는 전부
--- `binding.unitStates`에 0 마스크를 남기고, 그것을 `GetBindingIssue`가 보고하고 `Debind.lua`가
--- `KeyMap`에서 빼므로 솔버에도 이 파일에도 안 온다. 남겨두는 것은 그 두 교집합 구현이 갈리는
--- 날을 위해서고, 값으로 만들고 나니 비용이 없다.
local function MergeKeyUnitConditions(binding, out)
    wipe(out);

    local units = binding.conditions.units;
    if (not units) then
        return out;
    end

    for k, v in pairs(units) do
        if (k == "@") then
            k = binding.unit;
        end
        -- A "@" with no unit to point at has no axis to land on. Normalization should have
        -- dropped it, so drop it quietly.
        if (k ~= nil) then
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
--- state loop hands `SetBindingClick` -- was answered in `PrepareKeyBindings` and arrives as a
--- name.
local function BuildKeyRecord(binding, isClickCast, holdsKey, alwaysOurs, clickTime, out)
    if (not MergeKeyUnitConditions(binding, out.units)) then
        return nil;
    end

    local conditions = binding.conditions;

    out.fieldCount = 0;
    wipe(out.switches);
    out.isClickCast = isClickCast;
    out.holdsKey = holdsKey;
    out.targetUnit = binding.unit;
    out.setsSwitch = nil;
    out.carriesFrameTypes = false;

    if (binding.type == Constants.UNUSED) then
        field(out, "type", Constants.UNUSED);
    elseif (binding.type == Constants.COMMAND) then
        field(out, "command", binding.value);
    end

    if (binding.clickframe and binding.clickbutton) then
        -- `clickframe`은 상태 루프가 `SetBindingClick`에 넘길 때만 읽는다. 배선이 고정된
        -- 키는 그 루프를 안 도니 실어 보낼 이유가 없다. `clickbutton`은 클릭 경로가
        -- 읽으므로 어느 갈래든 나간다.
        if (not alwaysOurs and binding.clickframeName) then
            field(out, "clickframe", binding.clickframeName);
        end
        field(out, "clickbutton", binding.clickbutton);
    end

    -- **대상은 여기서만 레코드에 실린다.**
    --
    -- 옛 경로는 대상을 delegate 프레임의 맨이름 `unit`으로 나르므로 실어 보낼 필요가 없었다.
    -- 클릭 시점 경로는 `DefaultClickFrame` 하나에 걸고 래퍼가 클릭 순간에 맨이름으로 넣기
    -- 때문에 어느 대상인지를 스니펫이 알아야 한다.
    --
    -- 범위를 `GetDelegateFrame`(Debind.lua)과 정확히 맞춘다. 그 밖의 값은 옛 경로에서도
    -- delegate가 없어 대상이 조용히 사라지므로, 여기서 안 내보내는 것이 곧 현행 유지다.
    -- `""`(hover인데 재타겟 금지)도 같다.
    --
    -- **클릭캐스팅 레코드도 같은 것을 실어야 한다.** 그쪽도 이제 래퍼가 대상을 맨이름으로
    -- 넣는다 - 유닛 프레임에서 delegate 프레임으로 가던 `/click` 한 단계가 없어졌으므로
    -- delegate가 들고 있던 `unit`이 안 실리면 대상이 조용히 사라진다.
    --
    -- `isClickCast` 쪽은 `CLICK_TIME_EVAL`을 안 본다. 그 플래그는 **키 역할을 클릭 시점으로
    -- 내릴지**를 가르는 것이고, 클릭캐스팅은 그 선택지가 없다 - 매크로를 안 거치려면 래퍼를
    -- 지날 수밖에 없어서 언제나 클릭 시점이다.
    local carriesTarget = isClickCast or (Constants.CLICK_TIME_EVAL and clickTime and holdsKey);

    -- up 엣지에서 `typerelease`가 나갈 수 있는 액션인가. 래퍼가 down의 선택을 붙들어야 하는지를
    -- 이걸로 가른다 - 그 밖의 액션은 up에서 `typerelease` 조회가 nil이라 아무 일도 안 나므로
    -- 붙들 이유가 없고, 괜히 붙들면 낡은 판단을 재사용하게 된다.
    --
    -- **press-and-hold는 키 갈래에만 싣는다.**
    --
    -- 클릭캐스팅은 `delegate:Click(button)`으로 오는데 그 호출이 엣지를 안 싣는다. 그래서
    -- 언제나 `down=false`로 도착하고, 래퍼의 `if (down)` 갈래가 영영 안 돌아 이 값을 읽을
    -- 자리가 없다.
    --
    -- **읽을 자리를 만들어서도 안 된다.** 여기서 `pressAndHoldAction`을 켜면 게이트가
    -- `useOnKeyDown`을 강제로 참으로 만드는데 (SecureTemplates.lua:813), 도착이 `down=false`라
    -- `clickAction = (down and useOnKeyDown)`이 거짓이 되고 `releasePressAndHoldAction`으로
    -- 넘어가 **누른 적 없는 주문의 `typerelease`만 나간다.** 지금처럼 안 싣는 쪽이 평범한
    -- 시전으로 떨어져서 낫다.
    --
    -- 그래서 클릭캐스팅으로 건 유지·시전 주문은 눌러서 시작하고 떼서 놓는 동작이 안 된다.
    -- 고치려면 엣지를 실어 올 길이 필요한데 `SECURE_ACTIONS.click`에는 없다.
    if (Constants.CLICK_TIME_EVAL and clickTime and holdsKey and binding.pressAndHold) then
        field(out, "pressAndHold", true);
    end

    if (carriesTarget and binding.unit and binding.unit ~= "") then
        if (SPECIAL_UNITS[binding.unit]) then
            field(out, "unitAlias", binding.unit);
        elseif (BASIC_UNITS[binding.unit]) then
            field(out, "unit", binding.unit);
        end
    end

    -- **`hover` and `reactions` are not emitted.** They are the derived view of `units["hover"]`,
    -- which goes out below with every other unit as `t.units["hover"]` -- emitting both would have
    -- the match loop ask the same question about the same unit twice, once against the frame
    -- record and once against `UnitStates`.
    --
    -- `frameTypes` stays, because it describes the **frame** and only the frame record can answer
    -- it. It carries its own "is there a frame" guard in the snippet for that reason -- there is
    -- no `t.hover` in front of it any more.
    if (binding.hover and conditions.frameTypes
            and conditions.frameTypes ~= Constants.FRAMETYPE_ALL) then
        field(out, "frameTypes", conditions.frameTypes);
        out.carriesFrameTypes = true;
    end

    for i = 1, #CONDITION_AXES do
        local axis = CONDITION_AXES[i];
        local value = conditions[axis.field];
        if (value ~= nil and value ~= axis.allValue) then
            if (axis.derived) then
                -- **대괄호까지 포함해 한 문자열로 굽는다.** 클릭 경로가 이 값을
                -- `SecureCmdOptionParse`에 그대로 넘기고, 상태 루프는 같은 값을 `States`의
                -- 키로 쓴다. 나눠 두면 클릭마다 결합이 나거나 같은 사실이 두 군데 적힌다.
                value = "[known:" .. binding.value .. "]";
            end
            field(out, axis.field, value);
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

--- What has to be measured because of this record, read **off the record itself**.
---
--- That is the whole reason the record is a value. While this was done on the way out, the axis
--- and the flag that wakes a key carrying it were two lines next to each other, and either could
--- go without the other -- an emitted axis with no flag is a key that never wakes up, and a flag
--- with no axis is a measurement nobody reads.
local function CollectRecordAxes(record, stateDriven)
    for i = 1, record.fieldCount do
        local name = record.fieldNames[i];
        if (name == "frameTypes") then
            -- **레코드 단위로, 키 잡는 레코드에만.** `DirtyFlags.unitframe`은 *유닛은 그대로인데
            -- 프레임이 바뀜*을 뜻하고, 상태 루프에서 그것에 걸리는 것은 `t.frameTypes`를 가진
            -- **`holdsKey`** 레코드뿐이다 (거는 갈래가 `not keyBound and t.holdsKey` 뒤에 있다).
            -- 키 단위로 잡으면 hover 조건이 `isClickCast` 레코드에만 있는 키까지 깨운다.
            --
            -- `frameType` 플래그는 안 세운다. `DirtyFlags.frameType`을 세우는 곳이 없어서 어떤
            -- 키도 못 깨웠다 - 세우는 쪽이 죽어 있었다.
            if (record.holdsKey) then
                _updateFlags.unitframe = true;
            end
        else
            local flag = FIELD_FLAGS[name];
            if (flag == true) then
                _updateFlags[record.fieldValues[i]] = true;
            elseif (flag) then
                _updateFlags[flag] = true;
            end
        end
    end

    for unit, condition in pairs(record.units) do
        local axes = UNITAXIS_EXISTS;
        if (condition ~= false) then
            if (condition.reaction) then
                axes = bor(axes, UNITAXIS_REACTION);
            end
            if (condition.dead ~= nil) then
                axes = bor(axes, UNITAXIS_DEAD);
            end
        end

        -- 별칭 해석은 어느 갈래든 필요하다. `_unitsSeen`가 `EnableUnitWatch`를 몰고, 그게
        -- `UnitAliasMap[별칭]`을 채운다 - 클릭 경로가 대상을 푸는 자리가 정확히 거기다.
        _unitsSeen[unit] = true;

        -- **Only a state-driven key asks for measurement.**
        --
        -- Two things read `UnitStates`: the state loop, and the `UnitStates[alias] ~= nil` test
        -- that decides whether `SetUnit` calls for a rebuild. A key the state loop never walks
        -- does not reach the first, and has nothing to ask of the second -- there is nothing to
        -- re-bind on its account, so the rebuild it used to trigger every time the hover moved
        -- goes with it.
        --
        -- The click path loses nothing. Units are the one thing it does not take from the cache;
        -- it measures them again at the press. Click-casting does not even take the hover from the
        -- cache -- the frame that was clicked is `evalFrame`.
        --
        -- **This is an accumulator, so the unit of the decision matters.** `_measuredUnitAxes` is
        -- one table per rebuild and grows by `bor`, so a unit any state-driven key asks about is
        -- measured anyway. What is withheld here is **this record's share**, not the unit.
        if (stateDriven) then
            _measuredUnitAxes[unit] = bor(_measuredUnitAxes[unit] or 0, axes);
            _updateFlags[unit .. "-exists"] = true;
            if (band(axes, UNITAXIS_REACTION) ~= 0) then
                _measuresReaction = true;
            end
        end
    end

    if (record.setsSwitch) then
        addSwitch(record.setsSwitch);
    end

    for state in pairs(record.switches) do
        addSwitch(state);
        _updateFlags[state] = true;
    end

    if (record.targetUnit) then
        _unitsSeen[record.targetUnit] = true;
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
    if (DEBUG) then
        wipe(DebindPrivate.StateDrivenKeys);
    end
    appendLine("local bindings,t,u");

    for _, key in ipairs(sortedKeys(DebindPrivate.KeyMap, _sortedA)) do
        local bindingArray = DebindPrivate.KeyMap[key];
        wipe(_updateFlags);

        local button, buttonPrefix = bindingArray.button, bindingArray.buttonPrefix;
        local hasClickCast, hasKeyRecord = PrepareKeyBindings(key, bindingArray);
        local clickTime, alwaysOurs, stateDriven = ClassifyKey(bindingArray, hasKeyRecord);

        local first = true;

        if (hasClickCast or hasKeyRecord) then
            for i = 1, #bindingArray do
                local binding = bindingArray[i];
                local isClickCast = hasClickCast and binding.isClickCast;
                local holdsKey = hasKeyRecord and binding.holdsKey;

                if (isClickCast or holdsKey) then
                    local record = BuildKeyRecord(binding, isClickCast, holdsKey, alwaysOurs,
                        clickTime, _record);
                    if (record) then
                        if (first) then
                            first = false;
                            if (DEBUG) then
                                appendLine("-- %s", key);
                            end
                            AppendBindingsList(key, stateDriven);
                        end
                        CollectRecordAxes(record, stateDriven);
                        EmitRecord(record);
                    end
                end
            end
        end

        -- **아무 레코드도 안 나갔으면 빈 목록이라도 세운다.** 아래로 이어지는 것들은
        -- (`bindings.updateFlags`, `ClickCastKeys`, `bindings.hasKeyRecord`, `alwaysOurs`)
        -- `hasClickCast`/`hasKeyRecord`을 보고 도는데, 그 둘은 위 루프가 레코드를 하나도 안
        -- 내보낼 수 있다는 것을 모른 채 앞에서 정해졌다. 그러면 `bindings`는 **직전 키의
        -- 목록**을 가리킨 채로 남고, 이 키의 표시가 남의 목록에 붙는다.
        --
        -- 빈 목록은 뜻이 맞다: 쓸 수 있는 레코드가 없는 키이므로 매치 루프가 아무것도 못
        -- 고르고 키는 안 걸린다.
        if (first and (hasClickCast or hasKeyRecord)) then
            first = false;
            AppendBindingsList(key, stateDriven);
        end

        -- **`_measuredStates` is what gets measured**, so the two flags that name something
        -- unmeasurable are filtered out here: `<unit>-exists` is a unit axis and
        -- `_measuredUnitAxes` covers it, and `unitframe` is not measured at all -- enter/leave
        -- push it.
        --
        -- **A key the state loop never walks registers nothing.** The click path measures those
        -- axes at the press, so there is nothing for the poll to have ready. On an ordinary
        -- profile `known:` comes out empty here and the `SPELLS_CHANGED` registration goes with
        -- it.
        --
        -- **The question is `stateDriven`, not `not alwaysOurs`.** Two kinds of key leave the
        -- state loop nothing to decide (`AppendBindingsList`), and `alwaysOurs` is only one of
        -- them: a click-cast-only key holds no key-binding record, which is exactly the case
        -- `IsKeyAlwaysOurs` answers `false` for. `not stateDriven` is the union of the two.
        --
        -- **Switches are the one exception.** They are the only axis the click path reads
        -- straight out of `States` -- there is nothing to measure, the stored value is the
        -- original -- so cutting the registration would take the value away entirely.
        for k, _ in pairs(_updateFlags) do
            if (k ~= "unitframe" and strsub(k, -7) ~= "-exists"
                    and (stateDriven or _switches[k])) then
                _measuredStates[k] = true;
            end
        end

        -- **The state loop is the only reader, so only a state-driven key gets these baked.**
        -- Any other key is absent from `StateDrivenBindings`, and nothing else looks at the
        -- flags. The `_measuredStates` registration above is a separate decision -- switches
        -- register from either kind, because the click path reads those out of `States`.
        if (stateDriven) then
            -- `RebindOnHoverFrame`은 정확히 이 플래그의 리빌드 전체 합이다. 같은 게이트 안에서
            -- 모아야 뜻이 어긋나지 않는다 - 굽지 않은 키는 깨어날 수도 없다.
            if (_updateFlags.unitframe) then
                _rebindOnHoverFrame = true;
            end

            if (next(_updateFlags)) then
                appendLine("bindings.updateFlags=newtable()");
                for _, flag in ipairs(sortedKeys(_updateFlags, _sortedB)) do
                    appendLine("bindings.updateFlags[%q]=true", flag);
                end
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
        end

        -- **진단으로만 남는다.** 상태 루프가 마지막 독자였는데, 그 루프가 도는 키는 이제 전부
        -- 이 값이 참이라 물어볼 것이 없어졌다. `alwaysOurs`와 같은 자리다(§2-2): 진짜는 어느
        -- 표에 들어 있느냐이고 이 필드는 그 사본이라, 이걸로 판정하는 코드를 새로 쓰면 안 된다.
        -- 남기는 이유도 같다 - `bindings` 하나만 보고 갈래를 알 수 있어야 인게임에서 확인이 된다.
        if (hasKeyRecord) then
            appendLine("bindings.hasKeyRecord=true");
        end

        -- 클릭 시점 키를 배선한다.
        --
        -- **이름 등록은 언제나 여기서 한 번이다.** 래퍼는 `self`와 `button`만 받으므로 버튼
        -- 이름에 키를 실어 보내고, 그 이름으로 `ClickTimeKeys`를 찾아 바인딩 목록을 얻는다.
        -- 목록은 리빌드마다 새로 만들어지니 등록도 리빌드마다 한 번이면 된다.
        --
        -- **거는 것은 갈린다:**
        --
        --   alwaysOurs   여기서 한 번 걸고 끝. 상태가 뭐가 되든 우리 클릭 프레임이라 다시 걸
        --                일이 없다. 상태 루프에 둘 이유가 없다
        --   그 밖         상태 루프가 건다. "잡느냐 놓느냐"가 상태에 달렸으므로 여기서 한 번
        --                걸어버리면 놓아줘야 할 때 못 놓는다
        --
        -- 순서는 맞다: 이 스니펫은 `ClearOverrideBindings` 뒤에 실행된다.
        if (clickTime and not first) then
            local clickTimeButton = Constants.CLICKTIME_BUTTON_PREFIX .. key;
            DebindPrivate.ClickTimeKeys[key] = clickTimeButton;
            appendLine("ClickTimeKeys[%q]=bindings", clickTimeButton);
            if (alwaysOurs) then
                -- **진단으로 남긴다.** 아무도 안 읽는다 - 어느 표에 들어 있느냐가 이미 답이고,
                -- 진짜는 그 멤버십이며 이 필드는 사본이다. 어긋나면 필드가 틀린 것이고, 이걸로
                -- 판정하는 코드를 새로 쓰면 안 된다. 그래도 두는 이유는 `bindings` 하나만 보고
                -- 이 키가 어느 갈래인지 알 수 있어야 인게임에서 확인이 되기 때문이다.
                appendLine("bindings.alwaysOurs=true");
                appendLine("self:SetBindingClick(true,%q,DefaultClickFrameName,%q)", key,
                    clickTimeButton);
            else
                -- 상태 루프가 걸 때 쓸 이름. 문자열 결합을 클릭 경로 밖으로 빼둔다.
                -- **이 값이 곧 "clickTime 키인가" 표시다** - 따로 불리언을 두면 둘이 갈라진다.
                -- 배선이 고정된 키에는 굽지 않는다: 거는 것은 위에서 이미 끝났고, 그 루프가
                -- 이 키를 보지 않는다.
                appendLine("bindings.clickTimeButton=%q", clickTimeButton);
            end
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

    if (arg.type ~= Constants.MACROTEXT_ARG_SWITCH) then
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

--- One entry per parsed macro body: where it is written back to, its fragments, and the arguments
--- that get re-evaluated. **Numbering happens here** - `data.index` is what the dependents map
--- below points at, so nothing else may hand out an id.
local function EmitMacroTextEntries()
    local index = 0;

    for _, buttonOrStateName in ipairs(sortedKeys(_macrotextBindings, _sortedA)) do
        local data = _macrotextBindings[buttonOrStateName];
        if (data) then
            index = index + 1;
            data.index = index;
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

            appendLine("tempArray[%d]=t", index);
        end
    end
end

--- Which bodies have to be rebuilt when one name moves. The state loop walks its dirty flags
--- against this map and rebuilds only the bodies that named the flag.
local function EmitMacroTextDependents()
    wipe(_keysSeen);

    for _, macrotext in ipairs(sortedKeys(_macrotexts, _sortedA)) do
        local data = _macrotexts[macrotext];
        if (data) then
            -- A parsed body with no id was never bound to a button or a switch, so nothing would
            -- read what this line points at.
            assert(data.index);
            for _, arg in ipairs(data.args) do
                local key = arg.name;
                if (not _keysSeen[key]) then
                    _keysSeen[key] = true;
                    appendLine("MacroTextsMap[%q]=newtable()", key);
                end
                appendLine("tinsert(MacroTextsMap[%q], tempArray[%d])", key, data.index);
            end
        end
    end
end

function UpdateMacroTextsMap()
    appendLine("local tempArray, t = newtable()");

    EmitMacroTextEntries();
    EmitMacroTextDependents();

    appendLine("tempArray = nil")

    local snippet = table.concat(_strArr, "\n");
    AssertSnippetCompiles(snippet, "UpdateMacroTextsMap");
    if (DEBUG) then
        dump("UpdateMacroTextsMap", {
            CopyTable(_strArr),
            snippet:len(),
        });
    end
    wipe(_strArr);
    return snippet;
end

local function compareStates(lhs, rhs)
    if (lhs == "petbattle") then
        return true;
    end
    if (rhs == "petbattle") then
        return false;
    end

    return lhs < rhs;
end

--- Emits the code that refreshes one unit's row in `UnitStates`. One field per axis, not one
--- value.
---
--- The row table is created once per unit and **reused**. Building a fresh one each tick would
--- destroy change detection: a new table never equals the old one, so every tick would look like
--- a change and rebind.
---
--- Axes that were not registered emit nothing and leave no field behind. Nothing can ask about
--- them, so the absence is never compared against.
---
--- A unit that does not exist is not asked anything else. Absence is not a point on the other
--- axes -- it is the case where those axes have no value at all -- and the condition side splits
--- at the same place.
---
--- `stateOverride` is the same optional line the basic states get, and it lands in the same place
--- -- after the value is computed, before it is compared. Life is the axis that needs it: a test
--- can stand up a friendly unit or an absent one on demand, but not a dead one.
local function appendUnitStateUpdate(unit, axes, unitExpr, existsExpr, stateOverride)
    local dirty = format([[DirtyFlags["%s-exists"]=true]], unit);

    appendLine("u=UnitStates[%1$q];if (not u) then u=newtable();UnitStates[%1$q]=u end", unit);
    appendLine("stateValue=%s and true or false", existsExpr);
    -- **계산 뒤, 비교 앞.** 이 줄이 계산보다 위에 있던 동안 `stateValue`가 바로 덮어써져서
    -- 존재 축 주입이 조용히 아무것도 안 했다.
    if (stateOverride) then
        appendLine(stateOverride, unit .. "-exists");
    end
    appendLine("if (u.exists ~= stateValue) then u.exists=stateValue;%s end", dirty);

    local wantsReaction = band(axes, UNITAXIS_REACTION) ~= 0;
    local wantsDead = band(axes, UNITAXIS_DEAD) ~= 0;

    -- Both axes share one existence test. They are asked the same question -- "does this unit have
    -- a value on the axis at all" -- and the answer was just computed above.
    if (wantsReaction or wantsDead) then
        appendLine("if (u.exists) then");

        if (wantsReaction) then
            -- Blizzard resolves the same fork with if/elseif (`SecureTemplates.lua`, the
            -- `helpbutton`/`harmbutton` substitution). It asks about hostile first; this asks about
            -- friendly first. If a state where both are true ever turns up, that is where they part.
            appendLine([[stateValue=(PlayerCanAssist(%1$s) and "help") or (PlayerCanAttack(%1$s) and "harm") or "other"]],
                unitExpr);
            appendLine("if (u.reaction ~= stateValue) then u.reaction=stateValue;%s end", dirty);
        end

        if (wantsDead) then
            -- `UnitIsDead` alone is not `[dead]`: a ghost answers false to it. The pair is what the
            -- macro conditional means, and the restricted environment has no `UnitIsDeadOrGhost`.
            appendLine("stateValue=(UnitIsDead(%1$s) or UnitIsGhost(%1$s)) and true or false", unitExpr);
            if (stateOverride) then
                appendLine(stateOverride, unit .. "-dead");
            end
            appendLine("if (u.dead ~= stateValue) then u.dead=stateValue;%s end", dirty);
        end

        appendLine("end");
    end
end

-- 'state-unitexists' attribute 값이 변경될 때 상태 업데이트 후 UpdateBindings 실행함.
-- 블리자드 StateDriverManager는 기존 값과 새로운 값(true or false)이 다른 경우에만 _onattributechanged를 호출하므로
-- 'state-unitexists'은 true/false가 아닌 값을 넣어둔다.
function UpdateAttrChangedHandler()
    appendLine([[
if (name == "state-unitexists") then
    if (value == 0) then return end
    self:SetAttribute("state-unitexists", 0)
]]);

    -- The `elseif` below is the half that was missing. A unit can go away under a cursor that
    -- never moves -- neither enter nor leave fires -- and without it the reaction the frame had
    -- when the cursor arrived stayed true forever. The frame itself is kept so this same poll
    -- can pick the unit back up; only the reaction is cleared, and `reaction == nil` is what
    -- every reader now treats as "not hovering".
    --
    -- **The last of the three formatted in below is `REACTION_OTHER`, not `REACTION_NONE`.** This
    -- is the branch where a unit is hovered and `UnitExists` is true, so "not hovering" has no
    -- place in it. `REACTION_NONE` is a bit outside `REACTION_ALL` (`Solver.lua`), so no mask a
    -- user can build ever matches it. Put it here and every hover binding carrying a reaction
    -- restriction dies on a target that can be neither helped nor attacked: friendly NPCs such as
    -- vendors and guards, corpses, totems. `setup_onenter` has used `OTHER` from the start, so the
    -- symptom was a binding that was right the moment the cursor arrived and went out on the first
    -- poll tick.
    appendLine([[
if (States.unitframe) then
    local unitframe = States.unitframe
    local unit = unitframe.frame:GetEffectiveAttribute("unit");
    if (UnitExists(unit)) then
        local reaction
        if (PlayerCanAssist(unit)) then
            reaction = %d
        elseif (PlayerCanAttack(unit)) then
            reaction = %d
        else
            reaction = %d
        end

        if (unitframe.unit ~= unit or unitframe.reaction ~= reaction) then
            unitframe.unit = unit
            unitframe.reaction = reaction
            if (self:RunAttribute("SetUnit", "hover", unit) or RebindOnHoverFrame) then
                DirtyFlags.unitframe = true
            end
        end
    elseif (unitframe.reaction) then
        unitframe.unit = nil
        unitframe.reaction = nil
        if (self:RunAttribute("SetUnit", "hover", nil) or RebindOnHoverFrame) then
            DirtyFlags.unitframe = true
        end
    end
end
]], Constants.REACTION_HELP, Constants.REACTION_HARM, Constants.REACTION_OTHER);

    -- Update States
    -- `u` holds the `UnitStates` row being refreshed. Declared here rather than assigned as a
    -- global: every snippet shares one environment, so a stray global would collide across them.
    appendLine("local stateValue,u")

    -- Update Basic States
    local stateArray = {};
    for state in pairs(_measuredStates) do
        tinsert(stateArray, state);
    end
    sort(stateArray, compareStates);

    -- An optional line, supplied from outside, that gets a say in `stateValue` between the
    -- expression that computed it and the comparison that stores it.
    --
    -- **Overriding has to happen here and nowhere else.** Writing into `States` from outside does
    -- not hold: the poll comes round every 0.2s, or any of the events fires, and the real value
    -- goes back. Stopping the loop to keep it would be switching off the code the override exists
    -- to exercise. So the loop runs exactly as it always does, and only the value it lands on is
    -- allowed to differ.
    --
    -- Debind does not know what the line says. It is a format string handed over by whoever wants
    -- it -- in practice the test addon, which is absent for every real user, so nothing is
    -- generated and the emitted snippet is unchanged.
    local stateOverride = DebindPrivate.SnippetProbes and DebindPrivate.SnippetProbes.stateValue;

    local function appendStateStore(state)
        if (stateOverride) then
            appendLine(stateOverride, state);
        end
        appendLine("if (States[%1$q] ~= stateValue) then States[%1$q]=stateValue;DirtyFlags[%1$q]=true; end", state);
    end

    for _, state in ipairs(stateArray) do
        if (STATE_EVAL_EXPRESSIONS[state]) then
            if (state == "specialbar") then
                if (_measuredStates.petbattle) then
                    appendLine("stateValue=(%s) or States.petbattle", STATE_EVAL_EXPRESSIONS.specialbar);
                else
                    appendLine([[stateValue=(%s) or (SecureCmdOptionParse("[petbattle]") and true or false)]], STATE_EVAL_EXPRESSIONS.specialbar);
                end
            else
                appendLine("stateValue=%s", STATE_EVAL_EXPRESSIONS[state]);
            end
            appendStateStore(state);
        elseif (state:sub(1, 7) == "[known:") then
            -- 이름이 곧 조건문이다(대괄호 포함). 클릭 경로가 같은 문자열을 그대로 파싱한다.
            appendLine([[stateValue=SecureCmdOptionParse(%q) and true or false]], state);
            appendStateStore(state);

        elseif (_switches[state] ~= nil) then
            -- 아래 "Update Switches"가 맡는다. **`~= nil`이다** - 정의를 못 찾은 이름은
            -- `false`로 메모되고, 그것도 스위치라서 여기서 잴 것이 없기는 마찬가지다.
            -- `_switches[state]`로 물으면 그 이름이 "모르는 상태"로 떨어져 DEBUG 로그가 뜬다.
        elseif (DEBUG) then
            DebindPrivate.log("Unhandled State: " .. state);
        end
    end

    -- Update Unit States
    for _, unit in ipairs(sortedKeys(_measuredUnitAxes, _sortedA)) do
        local axes = _measuredUnitAxes[unit];
        local unitExpr, existsExpr;
        if (unit == "custom1" or unit == "custom2") then
            unitExpr = format("UnitAliasMap[%q]", unit);
            existsExpr = format("UnitAliasMap[%1$q] and UnitExists(UnitAliasMap[%1$q])", unit);
        elseif (SPECIAL_UNITS[unit]) then
            -- For the other aliases, being in `UnitAliasMap` **is** the proof of existence -- `SetUnit`
            -- does not put one there otherwise. Asking `UnitExists` again would tighten the
            -- condition without anyone saying so.
            unitExpr = format("UnitAliasMap[%q]", unit);
            existsExpr = format("UnitAliasMap[%q]", unit);
        else
            unitExpr = format("%q", unit);
            existsExpr = format("UnitExists(%q)", unit);
        end

        appendUnitStateUpdate(unit, axes, unitExpr, existsExpr, stateOverride);
    end

    -- Update Switches
    for _, state in ipairs(sortedKeys(_switches, _sortedA)) do
        local stateInfo = _switches[state];
        if (stateInfo) then
            if (stateInfo.mode == SWITCH_MODES.EXPR) then
                appendLine([[stateValue=SecureCmdOptionParse(SwitchExpressions[%q] or "") and true or false]], stateInfo.name);
                appendLine([[if (States[%1$q] ~= stateValue) then self:RunAttribute("SetSwitch", %1$q, stateValue, true) end]], stateInfo.name);
            end
        end
    end

    appendLine([[
local shouldUpdate
for flag in pairs(DirtyFlags) do
    shouldUpdate = true
    if (MacroTextsMap[flag]) then
        self:RunAttribute("UpdateMacroTexts")
        break
    end
end

if (shouldUpdate) then
    self:RunAttribute("UpdateBindings")
end
]]);

    appendLine([[end]]);

    local snippet = table.concat(_strArr, "\n");
    AssertSnippetCompiles(snippet, "_onattributechanged");

    if (DEBUG) then
        dump("_onattributechanged", { CopyTable(_strArr), snippet:len() });
    end
    wipe(_strArr);
    return snippet;
end
