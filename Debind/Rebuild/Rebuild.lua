local _, DebindPrivate = ...;
local Constants          = DebindPrivate.Constants;

local DEBUG              = DebindPrivate.DEBUG;
local SWITCH_MODES       = Constants.SWITCH_MODES;

local dump                      = DebindPrivate.dump;
local luatype                   = type;
local format, tostring, select  = format, tostring, select;
local strsub                    = string.sub;
local wipe, ipairs, pairs, sort = wipe, ipairs, pairs, sort;

--[[
    What every part of a rebuild writes into: the one buffer its snippets are assembled in, and the
    registries it fills as it walks, which `ResetContext` empties.

    **Every table here is wiped and refilled, never replaced**, and that is what lets the other files
    of the rebuild hold them as locals from load. A new table put in place of one would leave each of
    those files writing to the old one, and nothing would say so. `readsRole` is the one value among
    them, so it is read off `Rebuild` every time.
]]
local Rebuild = {};
DebindPrivate.Rebuild = Rebuild;

local addSwitch;
local addMacrotext;
local addMacrotextBinding;

local _strArr            = {};

local _macrotexts        = {};
local _macrotextBindings = {};
local _switches          = {};
local _unitsSeen         = {};

--- Does any action ask about the hovered unit's role? It is what turns the three role headers
--- on, and they are the only thing that fills `UnitRoles`.
Rebuild.readsRole = false;

local _sortedA           = {};

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
    wipe(DebindPrivate.HandledKeys);
    wipe(DebindPrivate.SpellFacts);
    wipe(_macrotexts);
    wipe(_macrotextBindings);
    wipe(_switches);
    wipe(_unitsSeen);
    Rebuild.readsRole = false;
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
--- it composed in `J.switchTexts` until a name the text reads moves (`workOutSwitches`). That is
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

local function BuildMacroTextEntries()
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

Rebuild.strArr                = _strArr;
Rebuild.macrotexts            = _macrotexts;
Rebuild.macrotextBindings     = _macrotextBindings;
Rebuild.switches              = _switches;
Rebuild.unitsSeen             = _unitsSeen;
Rebuild.sortedKeys            = sortedKeys;
Rebuild.ResetContext          = ResetContext;
Rebuild.addSwitch             = addSwitch;
Rebuild.addMacrotext          = addMacrotext;
Rebuild.addMacrotextBinding   = addMacrotextBinding;
Rebuild.ComposedReads         = ComposedReads;
Rebuild.appendLine            = appendLine;
Rebuild.appendKeyValue        = appendKeyValue;
Rebuild.AssertSnippetCompiles = AssertSnippetCompiles;
Rebuild.BuildMacroTextEntries = BuildMacroTextEntries;
