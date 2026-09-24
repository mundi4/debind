local _, DebindPrivate = ...;
local Constants               = DebindPrivate.Constants;

local band                    = bit.band;
local bor                     = bit.bor;

local UnitConditionForBinding = DebindPrivate.UnitConditionForBinding;
local UnitConditionToState    = DebindPrivate.UnitConditionToState;
local UnitGroupToCells        = DebindPrivate.UnitGroupToCells;
local RoleMeasuredUnder       = DebindPrivate.RoleMeasuredUnder;
local CannotStand             = DebindPrivate.CannotStand;
local SOURCE_ROW              = DebindPrivate.UNIT_SOURCE_ROW;
local SOURCE_AT               = DebindPrivate.UNIT_SOURCE_AT;

--- **Escape, and not whatever `TOGGLEGAMEMENU` happens to be on** (2026-09-19, owner). This used to
--- read the binding, which promised something it cannot keep: the reader can move that command in
--- the middle of a fight, and `UPDATE_BINDINGS` reaches a rebuild that a lockdown refuses
--- (`CanBuildBindings`). Our override on the new key is already up and stays up for the rest of the
--- fight, so the game menu is shut either way -- the check was chasing a value it could not follow.
---
--- Escape does not move. It is also the only one of the two the addon can act on at all: the window
--- never takes it as a key, because a capture dialog reads it as cancel and bind mode reads it as
--- "clear this row" (`KeyCapture.lua`, `DebindUI.lua`). An action sitting on it arrived from an
--- import or a hand-edited file.
--- **The second one is a mouse button with META held, and only over a unit frame.** The click
--- arrives at the wrapper as a bare button name, and which key it was is recovered there from the
--- modifiers held at that instant -- but the restricted environment has no `IsMetaKeyDown`
--- (`RestrictedEnvironment.lua` lists Alt, Ctrl and Shift and stops), so META cannot be read, and
--- `GetModifierIndex` folds the prefix to 0 on the insecure side. That is the unmodified click's
--- slot, and keys are walked in alphabetical order, so `META-BUTTON2` overwrites the working
--- `BUTTON2`.
---
--- **Off a frame the same key is fine.** It holds itself (`BuildKeyMap`'s `KeysToHold`) and the
--- game's own binding system answers the press, which takes a `META-` prefix like any other.
---
--- The raw key is asked rather than the prefix `GetMouseButtonAndPrefix` returns: that one is
--- canonicalized, and `META-CTRL-BUTTON2` comes back as `CTRL-` with the META already dropped.
function DebindPrivate.IsKeyInvalidForAction(action, key)
    if (key == "ESCAPE") then
        return Constants.BINDING_ISSUE_NOT_SUPPORTED_GAMEMENU_KEY;
    end
    if (type(key) == "string" and key:find("META-", 1, true)
            and DebindPrivate.GetMouseButtonAndPrefix(key)
            and DebindPrivate.ActionUnitFrameIsOn(action)) then
        return Constants.BINDING_ISSUE_NOT_SUPPORTED_META_CLICK;
    end
end

--- The first switch this action names that nothing defines, or nil.
---
--- **An action names a switch in four places, and they fail in different directions.**
---
--- One is a condition key, `action.conditions["$burst"]`. That one is already harmless and already
--- dead: codegen bakes the condition whether or not anything defines the name, and the restricted
--- side compares `States[name] ~= v` against a `nil`, so the binding matches on neither `true` nor
--- `false`. **Which is exactly why it needs saying out loud** -- the row draws like any other
--- conditional binding and the key does nothing, for ever, with no reason on screen. It could not
--- happen until §6-B: the five always had definitions, and the `dbver` 6 step keeps every
--- definition a condition still names. Deleting a switch is what makes it reachable, along with an
--- imported string naming one this profile never had.
---
--- Another is hand-written macro text, the one place a name is typed rather than picked:
--- `ParseMacroText` lets any `[a-zA-Z0-9_]+` through, and a name nothing defines used to reach
--- codegen and bake to `""` -- `[$typo]` became `[]`, which is **always true**. In a keybinding
--- addon that is the worst direction to fail in: the binding does not stop firing, it starts
--- firing everywhere.
---
--- The third is the target of an on/off/toggle action, which is `action.value`. That one is picked
--- from a list, so it cannot be mistyped. But the switch it was picked for can be deleted
--- afterwards, and a string from someone else arrives naming switches this profile has never had,
--- because an import plants no definitions (`building-export-import.md`). Nothing goes
--- wide there: the press sets a name nothing reads and the row draws clean. **Which is the
--- problem.** The reader's only sign that the key does nothing is that nothing happens, and this
--- mark is the only thing that can say so out loud.
---
--- The last is that same target after [Convert to macro text] has opened it out into
--- `/click DebindStates $burst-on` (`ForEachClickedSwitch`). It fails the way the third one does,
--- and it is here because otherwise converting an action would be a way of taking the mark off it.
---
--- Either way the action is marked, and the mark's outcome keeps it out of `KeyMap` entirely
--- (`Constants.BINDING_ISSUE_OUTCOMES`). Dropping the switch action loses nothing that was working:
--- it was a key that did nothing on press, the same trade the `MISSING_MACRO` branch below makes.
---
--- **The question is whether anything defines the name**, which is `ResolveSwitchDefinition` and
--- nothing else (`Profile.lua`). It used to be whether the name was one of the five, from when
--- those five always had a definition whether anybody had made one or not.
---
--- That makes this and codegen ask the same door, which they did not before: this side read the
--- name off the parser and codegen read what the compile had found. They are the same answer now,
--- and it has to stay that way -- a name codegen bakes to `known:0` with no mark on the action is
--- a binding whose macro quietly lost a clause.
---
--- Not memoized on purpose: `ParseMacroText` caches its own result per string, so a repeated
--- call here is a table lookup plus a walk over a handful of args.
--- The switch this action's **conditions** name that nothing defines, or nil.
---
--- Split out from the whole answer below because the condition menu asks exactly this: it colours
--- the box that owns switch conditions, and a macro body's typo must not turn that box red -- the
--- conditions in it would be fine and the reader would go looking in the wrong place
--- (`CreateSwitchConditionMenu`).
---
--- **The lowest name, not the first one `pairs` hands over.** One name gets printed, and a message
--- that names a different one each time it is opened cannot be acted on. Compared rather than
--- sorted, since this runs once per row while a list is drawn.
function DebindPrivate.GetUndefinedSwitchCondition(action)
    local conditions = action.conditions;
    if (not conditions) then
        return nil;
    end

    local undefined;
    for name in pairs(conditions) do
        if (Constants.IsSwitchName(name) and (undefined == nil or name < undefined)
                and not DebindPrivate.ResolveSwitchDefinition(name)) then
            undefined = name;
        end
    end
    return undefined;
end

function DebindPrivate.GetUndefinedSwitch(action)
    -- **Conditions before the value, because they hang off every type.** A spell action carries a
    -- number and a command carries nothing, and both can be conditioned on a switch -- a guard on
    -- `action.value` in front of this would read the conditions of macro-shaped actions only.
    local condition = DebindPrivate.GetUndefinedSwitchCondition(action);
    if (condition) then
        return condition;
    end

    if (type(action.value) ~= "string") then
        return nil;
    end

    if (Constants.SETSTATE_MODES[action.type]) then
        if (DebindPrivate.ResolveSwitchDefinition(action.value)) then
            return nil;
        end
        return action.value;
    end

    return DebindPrivate.GetUndefinedSwitchInBody(action);
end

--- The switch a `MACROTEXT` body names, read or worked, that nothing defines, or nil.
---
--- Apart from the whole answer above for the reason the condition half is: the issue check labels
--- each place a name is written with the menu it is fixed in, and a typo in a body is fixed in the
--- body.
function DebindPrivate.GetUndefinedSwitchInBody(action)
    if (action.type ~= Constants.MACROTEXT or type(action.value) ~= "string") then
        return nil;
    end

    local _, args = DebindPrivate.ParseMacroText(action.value);

    for i = 1, (args and #args or 0) do
        local arg = args[i];
        -- 부정형(`no$typo`)도 같이 잡는다. 그쪽은 지금도 거짓으로 떨어져 위험하지는 않지만
        -- 오타인 것은 똑같고, 한쪽만 말해주면 고쳐도 왜 아직 안 되는지 알 수 없다.
        if (arg.type == Constants.MACROTEXT_ARG_SWITCH
                and not DebindPrivate.ResolveSwitchDefinition(arg.name)) then
            return arg.name;
        end
    end

    -- **A body can work a switch as well as read one**, and the parser above only sees the reading.
    -- [Convert to macro text] opens an on/off/toggle action out into
    -- `/click DebindStates $burst-on`, so the reference the branch further up catches while it
    -- sits in `action.value` moves inside a string the moment the reader converts. Left out here,
    -- converting an action is a way to take the mark off it.
    return DebindPrivate.ForEachClickedSwitch(action.value, function(name)
        if (not DebindPrivate.ResolveSwitchDefinition(name)) then
            return name;
        end
    end);
end

--- The switch a computed switch's own `expr` names that nothing defines, or nil.
---
--- **A fifth place a name is written down, and the only one that is not in an action.** The four
--- above are asked of an action and answered by `GetUndefinedSwitch`; an `expr` belongs to a
--- definition, so there is no action to hand over and nothing above ever sees it. What that costs
--- is the quietest failure this system has: codegen bakes the dead name to `known:0`
--- (`EmitMacroTextArg` in `UpdateBindings.lua`), so the switch computed from it is false for ever
--- while its expression still reads correctly wherever it is drawn.
---
--- **Deleting is what makes it reachable, and leaving the reference behind is the design.** A
--- reference is kept so the reader can find it (`DeleteSwitch` in `Profile.lua`), which only works
--- while something is red. Renaming already rewrites this one; deleting has no rewrite to do and
--- so needs this instead.
---
--- **`ownerName` is not optional, and nil is not "no owner".** An expression naming its own switch
--- is erased rather than read (`EmitMacroTextArg` again) -- a defined name behaving oddly, not a
--- dead one. Passed nil, `[$a]` inside `$a` would be reported as broken.
---
--- **The first the parser hands over, not the lowest.** These arrive in the order they were typed,
--- unlike the condition keys above, so the first is already the same one on every draw and it is
--- the one nearest the start of the line the reader is looking at.
function DebindPrivate.GetUndefinedSwitchInExpr(expr, ownerName)
    if (type(expr) ~= "string") then
        return nil;
    end

    local _, args = DebindPrivate.ParseMacroText(expr);
    for i = 1, (args and #args or 0) do
        local arg = args[i];
        if (arg.type == Constants.MACROTEXT_ARG_SWITCH and arg.name ~= ownerName
                and not DebindPrivate.ResolveSwitchDefinition(arg.name)) then
            return arg.name;
        end
    end
end

--- The macro name this action points at, when nothing answers to it. nil when the action is fine
--- or is not a `MACRO` at all.
---
--- **This is the only check in the addon that asks whether an action's target exists**, and macros
--- are the only type that needs one. Every other type stores something the game resolves the same
--- way on every install -- a spell ID, an item ID, a mount ID -- so an action that names one either
--- resolves or names a thing that never existed anywhere. A macro name resolves against **this
--- computer's** macro store, which makes it the one reference that can be perfectly valid where it
--- was written and mean nothing here.
---
--- Which is why it could not be left out once strings started travelling between installs
--- (`building-export-import.md`). Until now a `MACRO` naming nothing simply bound and
--- did nothing on press: `UpdateBindings` stamps `*macro-<button>` with the name and the secure
--- handler finds no macro, with no error and no mark anywhere on screen. The imported-actions rule
--- is "send broken things too, the reader sees red and deletes them" -- and this was the hole in
--- it, the fallback for a macro that was already dangling when it was sent.
---
--- **Deliberately not extended to the other types**, each for its own reason: item names arrive
--- from an async cache, so a nil there means "not loaded yet" as often as it means "no such item",
--- and a check that reds out a working binding for the first few seconds of a session is worse than
--- no check; spell and mount IDs the reader has not learned still resolve to a name, so there is
--- nothing to detect; `PETACTION` carries its own name and icon. Adding any of those would have to
--- start from evidence that the resolve failing means the target is gone.
function DebindPrivate.GetMissingMacroName(action)
    if (action.type ~= Constants.MACRO) then
        return nil;
    end

    -- **A macro reference is a name. A slot number is not one, at any moment.** `GetMacroInfo`
    -- answers to either, which is the trap: a number is not a reference at all, it is a **position
    -- in a list ordered by name**, and the position moves. Create or delete any macro that sorts
    -- ahead of it and the number now belongs to a different macro. The key then casts something
    -- nobody chose, and nothing goes red, because nothing broke.
    --
    -- **No sharing is involved.** This goes wrong on one account with one character, the day after
    -- the user names a new macro `Aa`. Which is why the rule sits here rather than anywhere near
    -- the export: a stored number is already wrong before it travels.
    --
    -- Nor can one be repaired into a name. Asking what slot 4 holds answers for the store as it is
    -- right now, and that is a guess at what was meant, not a recovery of it.
    --
    -- So a value that is not a string is reported missing rather than resolved, which drops the
    -- action out of `KeyMap` entirely (`GetBindingIssue` -> `BuildKeyMap`). Nothing in the addon
    -- writes one: the picker (`ActionCatalog.lua`) reads a name out of the index it is looping
    -- over, the cursor drop (`GetActionTypeAndValueFromCursorInfo`) does the same and builds no
    -- action when no name comes back, and `BuildAction` (`DebindStorage/Import.lua`) refuses the
    -- field on a pasted one. This is the backstop under all three.
    local value = action.value;
    if (type(value) ~= "string") then
        -- Truthy whatever it holds, so the action is flagged instead of bound. An action with no
        -- value at all has no reference to print, and the empty name is the honest answer: the
        -- tooltip still says no such macro is here, which is the whole of what is known.
        if (value == nil) then
            return "";
        end
        return tostring(value);
    end

    if (GetMacroInfo(value)) then
        return nil;
    end
    return value;
end

--- Is this problem drawn as the action running with one thing missing?
---
--- Takes the code rather than the action because the callers have already asked for one, often for
--- a single category, and asking again would run the whole of `GetBindingIssue` a second time.
function DebindPrivate.IsIssueWarning(issue)
    return Constants.BINDING_ISSUE_GRADES[issue] == Constants.ISSUE_GRADE_WARNING;
end

--- An issue code's grade, defaulting to ERROR: a code with no row in `BINDING_ISSUE_GRADES` is a
--- code nobody graded, and the safe reading of that is the loud one.
local function IssueGrade(code)
    return Constants.BINDING_ISSUE_GRADES[code] or Constants.ISSUE_GRADE_ERROR;
end

--- Is this problem drawn red? **The same default as `IssueGrade`**: a table read by several functions
--- with different defaults once let an ungraded code through one of them looking fine.
function DebindPrivate.IsIssueError(issue)
    return issue ~= nil and IssueGrade(issue) == Constants.ISSUE_GRADE_ERROR;
end

--- What an issue code does to its action, defaulting to OMIT (`Constants.BINDING_ISSUE_OUTCOMES`).
local function IssueOutcome(code)
    return Constants.BINDING_ISSUE_OUTCOMES[code] or Constants.ISSUE_OUTCOME_OMIT;
end

--- What colour a problem is drawn in. **The grade picks it, never the code** -- that is the whole
--- of `grading-binding-issues.md`, and it is why a new issue needs one row in
--- `BINDING_ISSUE_GRADES` and no edit anywhere that paints.
---
--- Red is what waits on the reader; orange is the key working with one thing it was told to do
--- missing (2026-09-06, owner). **Grey is not one of these**: it says an action is not running,
--- which is the other axis, and the window paints it from there (a keyless row, an
--- off-specialization one, one every neighbour covers).
---
--- **nil for no issue**, so a caller can write `color = GetIssueColor(issue)` and leave the
--- no-problem case to whatever it already had.
function DebindPrivate.GetIssueColor(issue)
    if (issue == nil) then
        return nil;
    end
    if (Constants.BINDING_ISSUE_GRADES[issue] == Constants.ISSUE_GRADE_WARNING) then
        return ORANGE_FONT_COLOR;
    end
    return ERROR_COLOR;
end

--- Of the issue already found and one a branch just raised, the one that is reported, by `rank`
--- (lower is stronger). **A tie goes to the one already there**, so branches keep the order they are
--- written in among equals.
---
--- **Two ranks, because two questions fold differently.** The colour wants the loudest grade and
--- `BuildKeyMap` wants the strongest outcome, and a retired type is the case where they part: red
--- like a condition nothing meets, and kept where that one is left out. Folded by grade, the two tie
--- and whichever check is written first decides what happens to the key.
local function TakeIssue(current, candidate, rank)
    if (candidate ~= nil and (current == nil or rank(candidate) < rank(current))) then
        return candidate;
    end
    return current;
end

--- Is there any point asking another branch? **Only while the strongest there is has not been
--- found**, since nothing below could replace it. Both ranks start at 1.
local function LookingForWorse(issue, rank)
    return issue == nil or rank(issue) > 1;
end

--- The stored unit rows, under the pre-migration name too, the way `FillBinding` reads them.
local function StoredUnitRows(action)
    return (action.conditions and action.conditions.units) or rawget(action, "checkedUnits");
end

local function RowUnitName(key)
    if (key == "hover") then
        return "unitframe";
    end
    return key;
end

local function PickedUnitOf(action)
    if (not DebindPrivate.ActionHasPickedUnit(action)) then
        return nil;
    end
    return RowUnitName(action.unit);
end

--- The frame types every stored row that lands on the pointed frame's unit asks for together: the
--- `unitframe` row, and a `"@"` whose picked unit is `unitframe`. nil where none asks.
local function PointedFrameTypes(action, rows)
    local frameTypes;
    for key, value in pairs(rows) do
        if (RowUnitName(key) == "unitframe" or (key == "@" and PickedUnitOf(action) == "unitframe")) then
            local condition = UnitConditionForBinding(value);
            if (type(condition) == "table" and condition.frameTypes ~= nil) then
                frameTypes = frameTypes and band(frameTypes, condition.frameTypes) or condition.frameTypes;
            end
        end
    end
    return frameTypes;
end

--- Which axes of one stored row no unit can satisfy on their own: its states, its groups, its frame
--- types, its reactions, and its roles in two shapes. **Role and frame types only count where they
--- are measured**, on the `unitframe` row and on a `"@"` whose picked unit is `unitframe`; anywhere
--- else they are never narrowed (`BuildUnitStates`), so a zero there empties nothing.
---
--- **No reaction is its own axis, not a state mask of zero.** It is the one way that mask reaches
--- zero from a row the reader wrote, and it is nothing picked rather than a contradiction.
---
--- **No role is read against the frame types** (`RoleMeasuredUnder`): nothing left with party and
--- raid frames only (axis 5), those frames lost beside other types (axis 6), and nothing at all
--- without them.
local function EmptyUnitRow(action, key, value, rows)
    local condition = UnitConditionForBinding(value);
    if (type(condition) ~= "table") then
        return false, false, false, false, false, false;
    end
    local onFrame = RowUnitName(key) == "unitframe"
        or (key == "@" and PickedUnitOf(action) == "unitframe");
    local noReaction = condition.reaction == 0;
    local noRole, measured, onlyGroup = onFrame and condition.role == 0, false, false;
    if (noRole) then
        measured, onlyGroup = RoleMeasuredUnder(PointedFrameTypes(action, rows));
    end
    return not noReaction and UnitConditionToState(condition) == 0,
        condition.group ~= nil and UnitGroupToCells(condition.group) == 0,
        onFrame and condition.frameTypes == 0,
        noReaction,
        noRole and onlyGroup,
        noRole and measured and not onlyGroup;
end

--- The axes that leave a row matching nothing. **Not axis 6**: a role missing beside other frame
--- types still runs over those, so that row is not empty, and counting it as one hid a
--- contradiction on the same unit behind the warning (`HasAnyEmptyUnitRow`'s reader skips a row the
--- action check already spoke for).
local EMPTY_UNIT_ROW_AXES = 5;

--- Is one of the asked rows empty on `axis` (1 states, 2 groups, 3 frame types, 4 reactions,
--- 5 roles with party and raid frames only, 6 roles beside other frame types)? `unit` nil asks every
--- row, and `"@"` asks the Resolved Unit row.
local function HasEmptyUnitRow(action, unit, axis)
    local rows = StoredUnitRows(action);
    if (rows) then
        for key, value in pairs(rows) do
            if ((unit == nil or RowUnitName(key) == unit)
                    and (select(axis, EmptyUnitRow(action, key, value, rows)))) then
                return true;
            end
        end
    end
    return false;
end

local function HasAnyEmptyUnitRow(action, unit)
    for axis = 1, EMPTY_UNIT_ROW_AXES do
        if (HasEmptyUnitRow(action, unit, axis)) then
            return true;
        end
    end
    return false;
end

local EMPTY_CONDITIONS = {};

local function SpecialBarAgainstPetBattle(action)
    local conditions = action.conditions or EMPTY_CONDITIONS;
    if ((conditions.specialbar and conditions.petbattle == false)
            or (conditions.petbattle and conditions.specialbar == false)) then
        return Constants.BINDING_ISSUE_CONDITIONS_NEVER;
    end
end

--- **The one pair `skyriding` costs.** It and `bonusbars` read the same `GetBonusBarOffset()`, so the
--- two menus can set a pair no runtime state satisfies while neither looks wrong on its own.
---
--- **Asked as "is the offset only 5", not "is bit 5 in there"**: with another offset ticked too, the
--- binding still has somewhere to fire while not skyriding. A zero mask is `BONUSBARS_NONE_SELECTED`,
--- a different sentence.
local function SkyridingAgainstBonusBars(action)
    local conditions = action.conditions or EMPTY_CONDITIONS;
    local bonusbars = conditions.bonusbars;
    if (conditions.skyriding == nil or not bonusbars or bonusbars == 0) then
        return nil;
    end
    local skyridingBit = 2 ^ Constants.BONUSBAR_SKYRIDING;
    if ((conditions.skyriding and band(bonusbars, skyridingBit) == 0)
            or (conditions.skyriding == false and bonusbars == skyridingBit)) then
        return Constants.BINDING_ISSUE_CONDITIONS_NEVER;
    end
end

--- **What an action issue reads is only what is stored**
--- (`rewriting-evaluate-issues.md` §2-1). Each answer holds for every binding the
--- action could make, so none has to be made.
---
--- A pair that two menus can undo stands as two rows under the one code, so each menu hears it.
local ACTION_CHECKS = {
    -- **The key itself, not what else is on it.** Being covered by a neighbour is not this action's
    -- fault and `IsUnreachableAction` answers it; asked here, it hid the action's own warning.
    { category = "key", label = "KEY", check = function(action)
        if (action.key) then
            return DebindPrivate.IsKeyInvalidForAction(action, action.key);
        end
    end },
    { category = "groups", label = "CONDITION_GROUP", check = function(action)
        if ((action.conditions or EMPTY_CONDITIONS).groups == 0) then
            return Constants.BINDING_ISSUE_GROUPS_NONE_SELECTED;
        end
    end },
    { category = "specs", label = "CONDITION_SPEC", check = function(action)
        local specs = (action.conditions or EMPTY_CONDITIONS).specs;
        if (specs ~= nil and DebindPrivate.SpecSetIsEmpty(specs)) then
            return Constants.BINDING_ISSUE_SPECS_NONE_SELECTED;
        end
    end },
    -- **The name is handed to the conditional parser as it stands**, and a comma or a `]` there
    -- raises nothing: the key answers a question nobody asked. Only a type `FillBinding` keeps
    -- `known` on is asked; on any other the value never reaches a binding.
    { category = "known", label = "CONDITION_KNOWN", check = function(action)
        local known = (action.conditions or EMPTY_CONDITIONS).known;
        if (type(known) == "string" and known:find("[,%]]")
                and (action.type == Constants.SPELL or Constants.SPEC_RESOLVED_TYPES[action.type])) then
            return Constants.BINDING_ISSUE_KNOWN_NAME_UNPARSABLE;
        end
    end },
    -- **Two hero trees on one `taken` list.** A character stands in one at a time, so nothing can
    -- satisfy it; left alone the key would simply never fire and the rows would both look
    -- reachable (2026-09-19, owner).
    { category = "talents", label = "CONDITION_TALENT", check = function(action)
        if (DebindPrivate.TalentConditionContradicts(action)) then
            return Constants.BINDING_ISSUE_CONDITIONS_NEVER;
        end
    end },
    { category = "forms", label = "CONDITION_SHAPESHIFT", check = function(action)
        if ((action.conditions or EMPTY_CONDITIONS).forms == 0) then
            return Constants.BINDING_ISSUE_FORMS_NONE_SELECTED;
        end
    end },
    { category = "bonusbars", label = "CONDITION_BONUSBAR", check = function(action)
        if ((action.conditions or EMPTY_CONDITIONS).bonusbars == 0) then
            return Constants.BINDING_ISSUE_BONUSBARS_NONE_SELECTED;
        end
    end },
    -- **Each place a switch is named carries the menu it is fixed in.** One label for all of them
    -- sent a typo in a macro body to the switch conditions.
    --
    -- **Not chosen yet is asked first**: an on/off/toggle action arrives from the picker with no
    -- target, and "nothing defines nil" has no name to print. The binding builder keeps the same
    -- guard (`UpdateBindings.lua`); an action drawn clean must not be one it turns back.
    { category = "states", label = "TYPE_SETSTATE", check = function(action)
        if (not Constants.SETSTATE_MODES[action.type]) then
            return nil;
        end
        if (type(action.value) ~= "string") then
            return Constants.BINDING_ISSUE_SWITCH_NONE_SELECTED;
        end
        if (not DebindPrivate.ResolveSwitchDefinition(action.value)) then
            return Constants.BINDING_ISSUE_UNDEFINED_STATE, action.value;
        end
    end },
    { category = "states", label = "CONDITION_CUSTOM_STATES", check = function(action)
        local undefined = DebindPrivate.GetUndefinedSwitchCondition(action);
        if (undefined) then
            return Constants.BINDING_ISSUE_UNDEFINED_STATE, undefined;
        end
    end },
    { category = "states", label = "TYPE_MACROTEXT", check = function(action)
        local undefined = DebindPrivate.GetUndefinedSwitchInBody(action);
        if (undefined) then
            return Constants.BINDING_ISSUE_UNDEFINED_STATE, undefined;
        end
    end },
    { category = "macro", label = "TYPE_MACRO", check = function(action)
        local missing = DebindPrivate.GetMissingMacroName(action);
        if (missing) then
            return Constants.BINDING_ISSUE_MISSING_MACRO, missing;
        end
    end },
    { category = "retired", check = function(action)
        if (action.type == Constants.UNUSED or action.type == Constants.COMMAND) then
            return Constants.BINDING_ISSUE_TYPE_RETIRED;
        end
    end },
    -- **A row empty on its own.** Every binding that asks it cannot stand, so the answer needs none of
    -- them; asked of one unit, only that row answers. The root Target is not told: the reader fixes
    -- the row, not the unit they picked.
    { category = "units", label = "CONDITION_UNITS", check = function(action, unit)
        if (HasEmptyUnitRow(action, unit, 1)) then
            return Constants.BINDING_ISSUE_CONDITIONS_NEVER;
        end
    end },
    { category = "units", label = "CONDITION_UNITS", check = function(action, unit)
        if (HasEmptyUnitRow(action, unit, 4)) then
            return Constants.BINDING_ISSUE_REACTIONS_NONE_SELECTED;
        end
    end },
    { category = "units", label = "CONDITION_UNITS", check = function(action, unit)
        if (HasEmptyUnitRow(action, unit, 5)) then
            return Constants.BINDING_ISSUE_ROLES_NONE_SELECTED;
        end
    end },
    { category = "units", label = "CONDITION_UNITS", check = function(action, unit)
        if (HasEmptyUnitRow(action, unit, 6)) then
            return Constants.BINDING_ISSUE_ROLES_NONE_ON_GROUP_FRAMES;
        end
    end },
    { category = "units", label = "CONDITION_UNITS", check = function(action, unit)
        if (HasEmptyUnitRow(action, unit, 2)) then
            return Constants.BINDING_ISSUE_UNITGROUPS_NONE_SELECTED;
        end
    end },
    { category = "units", label = "CONDITION_UNITS", check = function(action, unit)
        if (HasEmptyUnitRow(action, unit, 3)) then
            return Constants.BINDING_ISSUE_HOVER_NONE_SELECTED;
        end
    end },
    { category = "specialbar", label = "CONDITION_SPECIALBAR", check = SpecialBarAgainstPetBattle },
    { category = "petbattle", label = "CONDITION_PETBATTLE", check = SpecialBarAgainstPetBattle },
    { category = "skyriding", label = "CONDITION_SKYRIDING", check = SkyridingAgainstBonusBars },
    { category = "bonusbars", label = "CONDITION_BONUSBAR", check = SkyridingAgainstBonusBars },
};

local BINDING_CATEGORIES = { units = true, unit = true, groups = true, casting = true, key = true,
    combat = true };

--- Why an action makes no binding at all, given its list; nil where the list has one.
---
---   `"NONE_LEFT"`           every press the reader could turn off is off
---   `"CONTRADICTION"`       Hover Cast is on, and [when there is none] on its unit leaves the twin
---                           nowhere to stand (`TwinUnitFor`)
---
--- **An empty list with Hover Cast on is always the second.** With it on the twin is missing for one
--- reason only, that condition, and every other press being gone is what emptied the list. Off is the
--- reader's own value; the condition against the mode is two menus disagreeing
--- (`reorganizing-binding-issues.md` §3-3).
--- Both readings of the unit a bare click lands on, in the order the message names them.
local BARE_CLICK_UNITS = { "unitframe", "mouseover" };

--- The unit whose [when there is none] leaves a bare left or right click nothing to run, or nil.
---
--- **Two units, one of them not the mode's.** That key answers one press, a click on a unit frame
--- (`which-action-a-key-runs.md` §7), and on such a click both the frame's own unit and `mouseover`
--- are there: the client sets `mouseover` off the frame's `unit` attribute, which is the very
--- attribute this addon reads for the frame's unit (`SecureBindings.lua`'s `setup_onenter`). A frame
--- that cannot answer with a unit sets neither: `setup_onenter` writes nothing when the attribute
--- is missing or the unit is not there.
---
--- **The resolved unit counts too**, since `"@"` is that unit's row under another name.
local function BareClickImpossibleUnit(action)
    if (not DebindPrivate.IsBareWorldClick(action.key)) then
        return nil;
    end
    local units = action.conditions and action.conditions.units;
    if (units == nil) then
        return nil;
    end
    local picked = PickedUnitOf(action);
    for _, unit in ipairs(BARE_CLICK_UNITS) do
        if (UnitConditionForBinding(units[unit]) == false
                or (picked == unit and UnitConditionForBinding(units["@"]) == false)) then
            return unit;
        end
    end
    return nil;
end

local function NoBindingCause(action, list)
    if (#list > 0) then
        return nil;
    end
    if (DebindPrivate.HoverCastChoiceOf(action) ~= nil) then
        return "CONTRADICTION";
    end
    return "NONE_LEFT";
end

--- Why this action does not run although nothing about it is wrong, or nil: `"DISABLED"`.
--- **A reason, not an issue.** The reader said so, and a mark on what they asked for is a mark with
--- nothing to fix. Every press being off is the other way to stand still and that one **is** an
--- issue, because turning the action off is a way to close it (`BINDING_ISSUE_NOTHING_RUNS`).
function DebindPrivate.GetNotRunningReason(action)
    if (action and action.disabled) then
        return "DISABLED";
    end
    return nil;
end

local function EvaluateIssues(action, category, notCategory, arg, collected, rank)
    -- **A category nothing below answers comes out nil**, which looks the same as "no problem".
    -- Stopped under DEBUG only; it is not a fault to raise in a shipped build.
    if (Constants.DEBUG and category ~= nil and not Constants.BINDING_ISSUE_CATEGORIES[category]) then
        error("GetBindingIssue: 없는 갈래 " .. tostring(category), 2);
    end

    --- **A branch may replace only something weaker by `rank`, and a tie goes to the branch that got
    --- there first.** Every branch used to stop at `not issue`, so the order they are written in
    --- decided the answer: an action carrying a milder code above an ERROR reported the milder one,
    --- and the key was decided off it. `TakeIssue` holds the tie rule and `LookingForWorse` is what
    --- the guards ask, so a branch stops being asked only once the strongest there is has been found.
    rank = rank or IssueGrade;
    local issue;

    --- Where a branch hands in the code it raised. `label` names the group that problem is fixed
    --- in, and a branch with no group to open passes none -- an action whose own value is wrong
    --- has no menu behind it. `arg` is the name a sentence with a `%s` in it has to print.
    ---
    --- **Only a collecting call keeps a list.** The same code under the same group is kept once.
    --- Under two different groups it stays two entries: one sentence under two names is a
    --- contradiction that spans both menus, and either one of them undoes it.
    local seen = collected and {};
    local function Report(candidate, label, arg)
        if (candidate == nil) then
            return;
        end
        if (collected) then
            local key = candidate .. "\0" .. (label or "");
            if (not seen[key]) then
                seen[key] = true;
                collected[#collected + 1] = { code = candidate, label = label, arg = arg };
            end
        end
        issue = TakeIssue(issue, candidate, rank);
    end

    --- Is there any point asking another branch? **A collecting call always has one**: only the
    --- caller that folds to the strongest one stops early, which is what `LookingForWorse` decides.
    local function Looking()
        return collected ~= nil or LookingForWorse(issue, rank);
    end

    for i = 1, #ACTION_CHECKS do
        if (not Looking()) then
            break;
        end
        local row = ACTION_CHECKS[i];
        if ((not category or category == row.category) and notCategory ~= row.category) then
            local code, name = row.check(action, arg);
            Report(code, row.label, name);
        end
    end

    -- **The binding issue reads the list `BuildKeyMap` binds**
    -- (`rewriting-evaluate-issues.md` §2-1, §2-4). With no unit row, no
    -- `casting` and no old `hover` pair, no binding can be empty and none can be dropped, so the
    -- list is not made: that is most rows the window draws. **A resurrection is the exception**: its
    -- branches carry conditions of their own, so a combat condition alone can rule them all out.
    --
    -- **`key` reaches it only on the bare click**, the one key a contradiction here is painted on.
    -- `BuildKeyMap` asks `key` of every action, and nothing else there has a list to make.
    if (Looking() and (not category or BINDING_CATEGORIES[category])
            and (category ~= "key" or DebindPrivate.IsBareWorldClick(action.key))
            and (StoredUnitRows(action) or action.casting or action.hover ~= nil
                or action.type == Constants.RESURRECT)) then
        local list = DebindPrivate.GetBindingsForAction(action);
        -- **The key and one condition, neither of them wrong on its own** (S5 #48, #49). Told before
        -- the list is looked at, because `mouseover` [when there is none] does not empty the list:
        -- the twin stands on [the frame's unit is there] and the solver keeps the two units apart,
        -- as it keeps every correlation apart (`Solver.lua`'s header). At the press they are one
        -- unit, and the click finds nothing to run.
        local impossible = BareClickImpossibleUnit(action);
        if (impossible) then
            if ((not category or category == "key") and notCategory ~= "key") then
                Report(Constants.BINDING_ISSUE_KEY_RULED_OUT, "KEY");
            end
            if ((not category or (category == "units"
                        and (arg == nil or RowUnitName(arg) == impossible)))
                    and notCategory ~= "units") then
                Report(Constants.BINDING_ISSUE_CONDITION_NEVER_ON_KEY, "CONDITION_UNITS");
            end
        elseif (#list == 0) then
            -- **Every press turned off is a warning on Cast Options** (2026-09-18, owner). It was a
            -- reason and nothing else while the only way to clear it was turning a press back on;
            -- an action can be turned off now, which says the reader meant it and takes the mark
            -- with it (`action.disabled`).
            --
            -- The contradiction is told on both sides that can undo it: the unit's row, and whatever
            -- emptied the rest of the list. On the bare click that is the key, which runs only over a
            -- unit frame (`which-action-a-key-runs.md` §7); anywhere else it is Cast Options.
            local cause = NoBindingCause(action, list);
            if (cause == "NONE_LEFT") then
                -- **Turned off, the warning has been answered.** Every other code stays, so turning
                -- the action back on is not a surprise.
                if (not action.disabled
                        and (not category or category == "casting") and notCategory ~= "casting") then
                    Report(Constants.BINDING_ISSUE_NOTHING_RUNS, "CASTING");
                end
            elseif (cause == "CONTRADICTION") then
                local side, sideLabel = "casting", "CASTING";
                if (DebindPrivate.IsBareWorldClick(action.key)) then
                    side, sideLabel = "key", "KEY";
                end
                if ((not category or category == side) and notCategory ~= side) then
                    Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, sideLabel);
                end
                if ((not category or (category == "units"
                            and (arg == nil or RowUnitName(arg) == DebindPrivate.HoverCastMode(action))))
                        and notCategory ~= "units") then
                    Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, "CONDITION_UNITS");
                end
            end
        elseif (category ~= "casting" and category ~= "key") then
            -- **Only an action none of whose bindings stands is in trouble** (2026-09-17, owner).
            -- One that cannot stand beside one that does is only left off the key.
            --
            -- **A binding that casts nothing is not one that stands**: `omitted` never reaches the
            -- key and `holdsOnly` only keeps it. A resurrection's branches carry conditions of their
            -- own, so they can all die under the reader's while the original lives.
            local standing, dead = false, false;
            for i = 1, #list do
                if (list[i].dead) then
                    dead = true;
                elseif (list[i].normalCast ~= false and not list[i].omitted
                        and not list[i].holdsOnly) then
                    standing = true;
                    break;
                end
            end
            if (dead and not standing) then
                local picked = PickedUnitOf(action);
                local toUnits, toGroups = false, false;
                for i = 1, #list do
                    local binding = list[i];
                    if (binding.dead) then
                        CannotStand(binding, function(unit, solo)
                            local sources = binding.unitSources[unit] or 0;
                            -- A row empty on its own is already the action issue's, and its zero
                            -- spreads to wherever `"@"` landed; painting it here would redden
                            -- menus the reader has nothing to fix in.
                            if ((band(sources, SOURCE_ROW) ~= 0 and HasAnyEmptyUnitRow(action, unit))
                                    or (band(sources, SOURCE_AT) ~= 0 and HasAnyEmptyUnitRow(action, "@"))) then
                                return false;
                            end
                            if (solo and (not category or category == "groups") and notCategory ~= "groups") then
                                toGroups = true;
                            end
                            if (notCategory ~= "units") then
                                if (not category) then
                                    toUnits = toUnits or not solo;
                                elseif (category == "units") then
                                    local asked;
                                    if (arg == nil) then
                                        asked = bor(SOURCE_ROW, SOURCE_AT);
                                    elseif (arg == "@") then
                                        asked = SOURCE_AT;
                                    elseif (arg == unit) then
                                        asked = SOURCE_ROW;
                                    else
                                        asked = 0;
                                    end
                                    toUnits = toUnits or band(sources, asked) ~= 0;
                                elseif (category == "unit") then
                                    -- **Only a unit the reader picked.** Unpicked, `"@"` lands on
                                    -- `target` all the same, and the Target menu holds nothing to
                                    -- undo there.
                                    toUnits = toUnits
                                        or (picked == unit and band(sources, SOURCE_AT) ~= 0);
                                end
                            end
                            return collected == nil and (toUnits or toGroups);
                        end);
                        if (collected == nil and (toUnits or toGroups)) then
                            break;
                        end
                    end
                end
                if (toUnits) then
                    Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, "CONDITION_UNITS");
                end
                if (toGroups) then
                    Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, "CONDITION_GROUP");
                end
                -- A resurrection branch the reader's combat condition rules out
                -- (`ApplyResurrectBranch`). It has no unit to paint, so it is told on the menu that
                -- set it.
                if ((not category or category == "combat") and notCategory ~= "combat") then
                    for i = 1, #list do
                        if (list[i].combatContradicts) then
                            Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, "CONDITION_COMBAT");
                            break;
                        end
                    end
                end
            end
        end
    end

    return issue;
end

--- One problem this action has: **the loudest by grade**, and within one category when a category is
--- given. Every place that picks one colour or one mark uses this.
function DebindPrivate.GetBindingIssue(action, category, notCategory, arg)
    return EvaluateIssues(action, category, notCategory, arg, nil);
end

--- What happens to this action on its key: the strongest outcome among its problems
--- (`Constants.ISSUE_OUTCOME_*`), or nil where it has none. `BuildKeyMap`'s one question.
function DebindPrivate.GetIssueOutcome(action)
    local code = EvaluateIssues(action, nil, nil, nil, nil, IssueOutcome);
    return code and IssueOutcome(code);
end

--- **Every** problem this action has, as `{ code, label, arg }` in the order the checks are written.
--- `label` is the locale key of the group the problem is fixed in, nil where there is none. Empty
--- when there is nothing wrong. `category` and `arg` narrow it the way `GetBindingIssue` does: the
--- tooltip asks one unit's row for all of its problems, so that a second one is not lost behind the
--- first.
---
--- Apart from the folding call because the askers differ: a colour or a gate needs the strongest
--- one and is cheaper stopping there, and only what tells the reader what is wrong needs them all.
function DebindPrivate.GetBindingIssues(action, category, arg)
    local collected = {};
    EvaluateIssues(action, category, nil, arg, collected);
    return collected;
end
