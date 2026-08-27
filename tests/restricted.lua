-- The restricted environment, run headless.
--
-- **What it runs is the recording, not a copy of it.** Every snippet body the addon handed to
-- `SecureHandlerExecute` or stored in an attribute is replayed here in the order it crossed --
-- login setup first, then the rebuild -- so the tables the click path reads are the ones the game
-- would have built. Writing the setup out here instead would be a second copy of it, and a second
-- copy is the one thing that can drift (`devdocs/legacy/going-headless-outside-the-ui.md` §5).
--
-- **Only the binding driver's environment.** In the game each header frame gets its own managed
-- environment, and the click path lives entirely in the driver's -- what `UnitWatch` and the
-- flyout screen do reaches it through `SetUnit`, which is a driver attribute like any other. So
-- bodies executed on other frames are not replayed, and the boundary is the game's own.
--
-- **This does not stand in for the sandbox.** What it cannot see is exactly §8's list: whether
-- `BuildRestrictedClosure` would accept the body at all (`check:snippets` and the golden watch
-- that, and a body it accepts the game may still refuse), taint, combat lockdown, and what
-- `SecureActionButtonTemplate` does once an attribute is stamped. It answers one question --
-- **given these records and this world, which one wins** -- and that question had no answer
-- outside the game before.

local M = {};

local frames = require("wow_frames");

--- Compiles one body with the signature the game would give it.
local function compile(body, signature, env)
    local source = "return function(" .. signature .. ") " .. body .. "\nend";
    local chunk = assert(loadstring(source));
    setfenv(chunk, env);
    return chunk();
end

---------------------------------------------------------------------------
-- Macro conditionals
---------------------------------------------------------------------------

--- What `SecureCmdOptionParse` answers for the conditionals this addon actually builds.
---
--- **The empty string is a match.** The client answers with the text after the clause that
--- matched, which is empty for every clause here, and `""` is true in Lua -- so a stand-in
--- returning `true` and one returning `""` are the same to every caller, while one returning
--- `false` where the client says `nil` is not.
---
--- **Anything outside the grammar raises**, rather than being read as no match. A condition this
--- does not know is a spec measuring something other than what it says.
local function parseCondition(interp, expr)
    -- Counted before the early return, so an expression that is skipped and one that is answered
    -- trivially still read apart. `Interp:parseCount` is the reader.
    interp.parses[expr or ""] = (interp.parses[expr or ""] or 0) + 1;

    if (expr == nil or expr == "") then
        return "";
    end

    for clause in expr:gmatch("%[([^%]]*)%]") do
        local matched = true;
        for term in clause:gmatch("[^,]+") do
            term = term:match("^%s*(.-)%s*$");
            local negated = false;
            if (term:sub(1, 2) == "no") then
                negated, term = true, term:sub(3);
            end

            local name, argument = term:match("^([%w_]+):(.+)$");
            name = name or term;

            local value;
            if (name == "") then
                value = true;
            elseif (name:sub(1, 1) == "@") then
                -- **A target selector is not a test.** `[@focus]` picks who the clause aims at
                -- and the clause matches either way; what the client answers with is the target
                -- name alongside the text, and every caller in this addon reads the text only.
                value = true;
            elseif (name == "combat") then
                value = interp.state.combat;
            elseif (name == "stealth") then
                value = interp.state.stealth;
            elseif (name == "petbattle") then
                value = interp.state.petbattle;
            elseif (name == "mounted") then
                value = interp.state.mounted;
            elseif (name == "indoors") then
                value = interp.state.indoors;
            elseif (name == "flyable") then
                value = interp.state.flyable;
            elseif (name == "advflyable") then
                value = interp.state.advflyable;
            elseif (name == "outdoors") then
                value = interp.state.outdoors;
            elseif (name == "group") then
                value = interp.state.group ~= "none";
            elseif (name == "known") then
                value = interp.state.known[tonumber(argument) or argument] and true or false;
            elseif (name == "form") then
                value = interp.state.form == (tonumber(argument) or -1);
            else
                error("the interpreter has no answer for the macro condition '" .. term .. "'", 0);
            end

            if (negated) then
                value = not value;
            end
            if (not value) then
                matched = false;
                break;
            end
        end

        if (matched) then
            return "";
        end
    end

    -- A conditional with no bracketed clause at all is an unconditional match.
    if (not expr:find("[", 1, true)) then
        return expr;
    end
    return nil;
end

---------------------------------------------------------------------------
-- Frame handles
---------------------------------------------------------------------------

local handleMethods = {};
local handleMeta = {
    __index = function(_, key)
        local method = handleMethods[key];
        if (method) then
            return method;
        end
        error("the interpreter's frame handle has no " .. tostring(key)
            .. "; add it deliberately rather than letting a body find nothing", 0);
    end,
};

--- The handle a body sees as `self`, memoized so two bodies naming the same frame get the same
--- table -- `ccframes[button]` and `DelegateFrames[frame]` are keyed by it.
local function handleFor(interp, frame)
    if (not frame) then
        return nil;
    end
    local handle = interp.handles[frame];
    if (not handle) then
        handle = setmetatable({ __frame = frame, __interp = interp, __refs = {} }, handleMeta);
        interp.handles[frame] = handle;
    end
    return handle;
end
M.handleFor = handleFor;

function handleMethods:GetName() return self.__frame:GetName(); end
function handleMethods:IsProtected() return true, true; end
function handleMethods:IsForbidden() return false; end
function handleMethods:IsShown() return self.__frame:IsShown(); end
function handleMethods:Show() self.__frame:Show(); end
function handleMethods:Hide() self.__frame:Hide(); end

function handleMethods:GetAttribute(name) return self.__frame:GetAttribute(name); end
function handleMethods:GetEffectiveAttribute(name) return self.__frame:GetAttribute(name); end

--- **Setting an attribute is what drives the state pass**, so this is where the handler fires.
--- The game calls `_onattributechanged` only when the value actually changes, and the emitted
--- handler leans on that: `state-unitexists` is deliberately set to 1 and then 0 so a second
--- rebuild can set 1 again and be noticed.
function handleMethods:SetAttribute(name, value)
    local frame = self.__frame;
    local previous = frame:GetAttribute(name);
    frame.__attributes[name] = value;
    if (previous == value or name:sub(1, 1) == "_") then
        return;
    end
    local body = frame:GetAttribute("_onattributechanged");
    if (body) then
        self.__interp:run(body, self, "self,name,value", name, value);
    end
end

function handleMethods:GetFrameRef(name)
    return self.__refs[name];
end

function handleMethods:RunAttribute(name, ...)
    local body = self.__frame:GetAttribute(name);
    if (type(body) ~= "string") then
        return;
    end
    if (name == "UpdateBindings") then
        self.__interp.rebuilds = self.__interp.rebuilds + 1;
    end
    return self.__interp:run(body, self, "self,...", ...);
end

function handleMethods:RunFor(other, body, ...)
    return self.__interp:run(body, other, "self,...", ...);
end

--- The one door out of the restricted environment, and the addon uses it for reporting only.
--- The methods are plain fields on the frame, so this is the same call the game makes.
function handleMethods:CallMethod(name, ...)
    local method = self.__frame[name];
    if (type(method) == "function") then
        method(self.__frame, ...);
    end
end

--- What the state loop and the fixed-wiring branch use to take a key. In the game these reach
--- `SetOverrideBindingClick` on the header, so what they write is the override table itself
--- (`wow_frames.lua`) and not a record of having written -- which is what lets `GetBindingAction`
--- answer headless at all.
---
--- `owner` is the driver, because the header the restricted call runs on is what owns the override
--- in game. A rebuild's `ClearOverrideBindings(BindingDriver)` is what takes these back off.
function handleMethods:SetBindingClick(priority, key, buttonName, mouseButton)
    self.__interp.bindings[key] = {
        owner = self.__interp.driver, buttonName = buttonName, mouseButton = mouseButton,
    };
end

function handleMethods:SetBinding(priority, key, command)
    self.__interp.bindings[key] = { owner = self.__interp.driver, command = command };
end

function handleMethods:ClearBinding(key)
    self.__interp.bindings[key] = nil;
end

---------------------------------------------------------------------------
-- The environment
---------------------------------------------------------------------------

local function buildEnv(interp)
    local env = {};

    --- **The names come from Blizzard's own list**
    --- (`Blizzard_RestrictedAddOnEnvironment/RestrictedEnvironment.lua`), not from what happens to
    --- be handy: `RESTRICTED_FUNCTIONS_SCOPE` plus the table library that is bound in separately
    --- because a body may not write `{}`. What is here is the part of that list this addon
    --- reaches, and anything outside it raises rather than answering nil.
    env.newtable = function() return {}; end
    env.wipe = function(t)
        for k in pairs(t) do t[k] = nil; end
        return t;
    end
    env.pairs = pairs;
    env.ipairs = ipairs;
    env.next = next;
    env.rawtype = type;
    env.tostring = tostring;
    env.tonumber = tonumber;
    env.select = select;
    env.unpack = _G.unpack;
    env.tinsert = table.insert;
    env.tremove = table.remove;
    env.format = string.format;
    env.strsub = string.sub;
    env.strfind = string.find;
    env.strmatch = string.match;
    env.strlen = string.len;
    env.strjoin = function(sep, ...) return table.concat({ ... }, sep); end
    env.min = math.min;
    env.max = math.max;
    env.floor = math.floor;
    env.ceil = math.ceil;
    env.abs = math.abs;
    env.math = math;
    env.string = string;
    env.print = function() end;

    --- **`table` is bound in apart from the rest**, because a snippet cannot write `{}` -- the
    --- restricted one hands out proxies instead. What the bodies here use of it is `concat`, in
    --- the macro text rebuild.
    env.table = {
        concat = table.concat,
        insert = table.insert,
        remove = table.remove,
        sort = table.sort,
        newtable = env.newtable,
        wipe = env.wipe,
    };

    -- Substituted at bake time for the bodies that are baked, and left standing in the ones that
    -- are not, so the environment has to carry it either way.
    env.CONSTANTS = interp.Constants;

    local state = interp.state;

    --- **The restricted environment's own names for what the world is.** These are not the
    --- insecure API: `PlayerInCombat` and `PlayerPetSummary` exist only in here, which is half
    --- the reason the click path could not be measured from outside the game.
    env.PlayerInCombat = function() return state.combat; end
    env.IsStealthed = function() return state.stealth; end
    env.IsMounted = function() return state.mounted; end
    env.IsIndoors = function() return state.indoors; end
    env.IsFlyableArea = function() return state.flyable; end
    env.IsAdvancedFlyableArea = function() return state.advflyable; end
    env.PlayerPetSummary = function() return state.pet; end
    env.HasExtraActionBar = function() return state.extrabar; end
    env.HasVehicleActionBar = function() return state.vehiclebar; end
    env.HasOverrideActionBar = function() return state.overridebar; end
    env.HasTempShapeshiftActionBar = function() return state.shapeshiftbar; end
    env.GetShapeshiftForm = function() return state.form; end
    env.GetBonusBarOffset = function() return state.bonusbar; end
    env.PlayerIsChanneling = function() return state.channeling; end
    env.UnitPlayerOrPetInRaid = function() return state.group == "raid"; end
    env.UnitPlayerOrPetInParty = function() return state.group == "party"; end
    env.IsAltKeyDown = function() return state.alt; end
    env.IsControlKeyDown = function() return state.ctrl; end
    env.IsShiftKeyDown = function() return state.shift; end
    env.SecureCmdOptionParse = function(expr) return parseCondition(interp, expr); end

    --- The unit queries, **forwarded to the same functions the insecure side calls**. Blizzard's
    --- own list has them in `DIRECT_MACRO_CONDITIONAL_NAMES` for the same reason: they are the
    --- ones a macro conditional would ask, and the answer has to be one answer.
    env.UnitExists = function(unit) return _G.UnitExists(unit); end
    env.UnitIsUnit = function(a, b) return _G.UnitIsUnit(a, b); end
    env.UnitIsDead = function(unit) return _G.UnitIsDead(unit); end
    env.UnitIsGhost = function(unit) return _G.UnitIsGhost(unit); end
    env.PlayerCanAssist = function(unit) return _G.PlayerCanAssist(unit); end
    env.PlayerCanAttack = function(unit) return _G.PlayerCanAttack(unit); end

    --- **Raise on anything else.** A body reaching for a name the environment does not carry
    --- would silently be reaching for nil, and the failure would land somewhere unrelated -- which
    --- is exactly how the restricted environment fails in the game and exactly what a harness is
    --- for avoiding.
    setmetatable(env, {
        __index = function(_, key)
            error("the restricted environment has no " .. tostring(key), 0);
        end,
    });

    return env;
end

---------------------------------------------------------------------------
-- The interpreter
---------------------------------------------------------------------------

local Interp = {};
Interp.__index = Interp;

--- Runs one body. `signature` is the game's, per caller: `self,...` for an execute or an attribute
--- and `self,name,value` for the attribute-changed handler.
function Interp:run(body, selfHandle, signature, ...)
    local key = signature .. "\0" .. body;
    local closure = self.closures[key];
    if (not closure) then
        closure = compile(body, signature, self.env);
        self.closures[key] = closure;
    end
    return closure(selfHandle, ...);
end

--- Replays everything the driver was handed, in order.
---
--- **Only the driver's own.** Every other frame has its own managed environment in the game, so
--- replaying its bodies here would put their globals in the wrong table.
function Interp:replay(entries)
    local driver = self.driver;
    for i = 1, #entries do
        local entry = entries[i];
        if (entry.frame == driver) then
            if (entry.kind == "Execute") then
                self:run(entry.body, self.driverHandle, "self,...");
            elseif (entry.kind == "SetFrameRef") then
                self.driverHandle.__refs[entry.name] = handleFor(self, entry.ref);
            elseif (entry.kind == "ClearOverrideBindings") then
                --- **A rebuild's prologue, replayed in its place in the order.** Without it a key
                --- this rebuild stopped mentioning keeps the binding the last one gave it, and
                --- every "and then the key goes away again" reads as a pass.
                ClearOverrideBindings(entry.frame);
            elseif (entry.kind == "SetOverrideBinding") then
                --- **The insecure side sets as well as clears now**, for the keys a rebuild has
                --- settled on a command (`ApplyBindingPlan`). That call already wrote the override
                --- when it crossed, which is what the game does; here it has to be put back in its
                --- place in the order, because the prologue's clear above it is replayed and would
                --- otherwise land on top of a binding that was filed before it.
                SetOverrideBinding(entry.frame, true, entry.name, entry.body);
            end
        end
    end
end

--- Puts the world the restricted side answers for back to its opening state. A spec that leaves
--- combat on hands the next one a client in combat, and nothing in the pass would say so.
function Interp:resetState()
    local state = self.state;
    for key, value in pairs(state) do
        if (type(value) == "boolean") then
            state[key] = false;
        elseif (type(value) == "number") then
            state[key] = 0;
        elseif (type(value) == "table") then
            for k in pairs(value) do value[k] = nil; end
        end
    end
    state.group = "none";
end

--- The records this rebuild handed the click path for one key, or nil where it handed none.
function Interp:recordsFor(key)
    return self.env.ClickTimeKeys[self.Constants.CLICKTIME_BUTTON_PREFIX .. key];
end

--- Runs the click-time decision for a key and answers **which record won**, by index, plus the
--- button name it would click. nil where nothing matched.
---
--- This is `EvalClickTimeKey`, the same body `/debtest` drives -- the wrapper's prologue replaced
--- by an argument, with `EVAL_SNIPPET` itself untouched. What it cannot answer is that a real
--- press arrives and arrives under this button name; that half stays in the game (§8).
function Interp:evalKey(key)
    local button = self.Constants.CLICKTIME_BUTTON_PREFIX .. key;
    local clickbutton = self.driverHandle:RunAttribute("EvalClickTimeKey", button);
    if (not clickbutton) then
        return nil;
    end

    local records = self.env.ClickTimeKeys[button];
    for i = 1, #records do
        if (records[i].holdsKey and records[i].clickbutton == clickbutton) then
            return i, clickbutton, records[i];
        end
    end
    return nil, clickbutton;
end

--- The same for a click that arrives on a unit frame. `n` is the mouse button number and `mod`
--- the modifier index, which is what the wrapper recovers the key from -- a click-cast click
--- carries no button name of its own.
function Interp:evalClickCast(frame, n, mod)
    return self.driverHandle:RunFor(handleFor(self, frame),
        self.driver:GetAttribute("EvalClickCastFrame"), n, mod);
end

--- Drives the real `OnClick` wrapper the way a click arriving on a registered unit frame does,
--- and answers the button name it hands back: `debind1` where one of our bindings took the click,
--- `debindnull` where the click was already spent, nil where the name is left alone and the click
--- carries on into the frame's own handler.
---
--- **The shipped body, not a stand-in for it.** `evalClickCast` above runs `EVAL_SNIPPET` with the
--- wrapper's prologue replaced by arguments, so the prologue is the one part of the click path it
--- cannot see -- and the prologue is where the edges are decided. Which edges even arrive is the
--- frame's state rather than ours, so getting that wrong leaves a key that raises nothing and does
--- nothing. `UnitFrameClickPre` is the baked body itself, kept where the re-wrap can reach it.
function Interp:clickFrame(frame, button, down)
    return self:run(self.Private.UnitFrameClickPre, handleFor(self, frame), "self, button, down",
        button, down);
end

--- Runs one pass of the state loop, the way the 0.2s poll does. Whatever it decides to bind lands
--- in `interp.bindings`.
--- **`true`, because that is what the poll writes.** `SecureStateDriverManager_UpdateUnitWatch`
--- hands the driver `exists or false`, and the driver carries `unit = "player"`, so every tick
--- arrives as `true`. The handler reads that value now to decide how much to measure
--- (`UpdateAttrChangedHandler`), so a stand-in that wrote a number would be driving the wrong half
--- of the pass and every case here would be measuring it.
function Interp:pollStates()
    self.driverHandle:SetAttribute("state-unitexists", true);
end
--- How many times the restricted `UpdateBindings` has run.
---
--- **Some questions are only about whether it ran at all.** A rebuild that re-decides every key
--- to the value it already held changes no binding, so `interp.bindings` answers the same either
--- way and the count is the only thing left to ask. Snapshot it, do the thing, compare.
function Interp:rebuildCount()
    return self.rebuilds;
end

--- How many times `SecureCmdOptionParse` has been handed this exact string.
---
--- **The state loop skipping a parse is not visible in any value it leaves behind** -- a switch
--- whose answer did not move reads the same whether the loop worked it out again or let it stand.
--- So the count is the only thing left to ask, the way `rebuildCount` is for a rebuild that
--- re-decided every key to what it already held. Snapshot it, poll, compare.
function Interp:parseCount(expr)
    return self.parses[expr] or 0;
end

--- Drives the real `setup_onenter` for a frame, the way the wrapped `OnEnter` script does.
---
--- The frame has to be one `RegisterFrame` took, or `ccframes` has no row for it and the body
--- has nothing to fill in.
function Interp:hoverEnter(frame)
    return self.driverHandle:RunFor(handleFor(self, frame),
        self.driver:GetAttribute("setup_onenter"));
end

--- The other half. Takes no frame: `setup_onleave` clears whatever is in the hover slot, which
--- is what makes it the cleanup for an `OnLeave` that never arrived.
function Interp:hoverLeave(frame)
    return self.driverHandle:RunFor(handleFor(self, frame),
        self.driver:GetAttribute("setup_onleave"));
end

--- Stands an interpreter up on everything recorded so far.
---
--- `world` is the shim's, so the units the insecure side sees are the ones in here. `state` is the
--- restricted side's own -- combat, stealth, the bars -- which nothing outside the sandbox can
--- answer for.
function M.new(DebindPrivate, world)
    local interp = setmetatable({}, Interp);

    interp.Constants = DebindPrivate.Constants;
    interp.Private = DebindPrivate;
    interp.world = world;
    interp.handles = {};
    interp.closures = {};
    --- **The override table itself, not a copy.** `GetBindingAction` reads the same one
    --- (`wow_frames.lua`), so a spec that asks the interpreter and a spec that asks the client
    --- cannot be told two different things about the same key.
    interp.bindings = frames.overrides;
    interp.rebuilds = 0;
    interp.parses = {};
    interp.state = {
        combat = false,
        stealth = false,
        pet = false,
        petbattle = false,
        extrabar = false,
        vehiclebar = false,
        overridebar = false,
        shapeshiftbar = false,
        mounted = false,
        indoors = false,
        outdoors = false,
        flyable = false,
        advflyable = false,
        channeling = false,
        form = 0,
        bonusbar = 0,
        group = "none",
        known = {},
        alt = false,
        ctrl = false,
        shift = false,
    };

    interp.driver = DebindPrivate.BindingDriver;
    interp.env = buildEnv(interp);
    interp.driverHandle = handleFor(interp, interp.driver);

    interp:replay(frames.all());

    return interp;
end

return M;
