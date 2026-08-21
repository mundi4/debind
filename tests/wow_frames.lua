-- The frame shell and the secure-handler recorder, the two things the emission golden rests on
-- (`devdocs/going-headless-outside-the-ui.md` §6).
--
-- **Neither of these interprets anything.** A snippet body handed to `SecureHandlerExecute` is
-- recorded as the string it is and never run; locking what gets emitted needs no execution, which
-- is why the golden can stand up before there is any restricted-environment interpreter (§5).
--
-- The two have different lifetimes. The recorder stays -- "what did it execute" is the answer this
-- side of the addon is asked for, so a mock is the cheap shape (§4). The frame shell is here
-- because `Debind.lua`, `SecureBindings.lua` and the rest build frames when they are read, and it
-- gets looked at again once `BuildBindingPlan` no longer meets a frame (§6).

local M = {};

-- Captured at load, before `wow_shim` swaps the global out for the positional stand-in. Nothing
-- here formats a client string, so the stock one is the right one and stays right whatever the
-- shim does to `format` afterwards.
local sformat = string.format;

---------------------------------------------------------------------------
-- The recorder
---------------------------------------------------------------------------

--- Everything that crossed to the secure side while the recorder was armed, in the order it
--- crossed. One entry per call; `body` is the snippet source verbatim where there is one.
---
--- **Armed rather than always on.** Loading the addon files emits a few hundred lines of setup
--- that no rebuild ever repeats, and a golden that carried them would move whenever an unrelated
--- file gained a `SetAttribute` at load.
local recorder = { armed = false, entries = {} };
M.recorder = recorder;

local function record(kind, target, name, body)
    if (not recorder.armed) then
        return;
    end
    recorder.entries[#recorder.entries + 1] = {
        kind = kind,
        target = target,
        name = name,
        body = body,
    };
end
M.record = record;

function M.arm()
    recorder.armed = true;
    for i = #recorder.entries, 1, -1 do
        recorder.entries[i] = nil;
    end
end

function M.disarm()
    recorder.armed = false;
    return recorder.entries;
end

---------------------------------------------------------------------------
-- The frame shell
---------------------------------------------------------------------------

local frameMethods = {};
local frameMeta = { __index = frameMethods };

--- What `GetName()` answers for a frame the addon did not name. The game answers nil there, and so
--- does this -- but the recorder still has to say which frame a call landed on, so it falls back
--- to a per-frame label. A `table.tostring` address would be a different string on every run and
--- the golden would never hold still.
local function label(frame)
    return frame.__name or frame.__label;
end
M.label = label;

local _nextAnon = 0;

local function newFrame(frameType, name, parent, template)
    _nextAnon = _nextAnon + 1;
    local frame = setmetatable({}, frameMeta);
    frame.__frameType = frameType;
    frame.__name = name;
    frame.__label = sformat("<%s#%d>", frameType or "Frame", _nextAnon);
    frame.__parent = parent;
    frame.__template = template;
    frame.__attributes = {};
    frame.__scripts = {};
    frame.__events = {};
    frame.__children = {};
    if (parent and parent.__children) then
        parent.__children[#parent.__children + 1] = frame;
    end
    record("CreateFrame", label(frame), template);
    return frame;
end
M.newFrame = newFrame;

function frameMethods:GetName() return self.__name; end
function frameMethods:GetObjectType() return self.__frameType; end
function frameMethods:GetParent() return self.__parent; end
function frameMethods:GetChildren() return (table.unpack or unpack)(self.__children); end
function frameMethods:IsForbidden() return false; end
function frameMethods:IsProtected() return true, true; end
function frameMethods:IsAnchoringRestricted() return false; end
function frameMethods:HasAccessConstraints() return false; end

--- **Recorded, and every frame, not only the driver.** `SetBindingAttributes` stamps the click
--- frame and its delegates, and those attributes are half of what a rebuild produces -- a golden
--- that watched only the driver would not notice a spell name going out under the wrong button.
function frameMethods:SetAttribute(name, value)
    self.__attributes[name] = value;
    record("SetAttribute", label(self), name, value);
end

function frameMethods:GetAttribute(name) return self.__attributes[name]; end

--- The game walks up through `useparent-<name>` / `useparent*` to answer this. Nothing headless
--- reads an inherited one yet, so the shell answers from the frame itself and will need the walk
--- the day something does.
function frameMethods:GetEffectiveAttribute(name) return self.__attributes[name]; end

function frameMethods:SetScript(script, handler) self.__scripts[script] = handler; end
function frameMethods:GetScript(script) return self.__scripts[script]; end
function frameMethods:HookScript(script, handler) self.__scripts[script] = handler; end

function frameMethods:RegisterEvent(event)
    self.__events[event] = true;
    record("RegisterEvent", label(self), event);
end

function frameMethods:RegisterUnitEvent(event, unit)
    self.__events[event] = unit or true;
    record("RegisterUnitEvent", label(self), event, unit);
end

function frameMethods:UnregisterEvent(event)
    self.__events[event] = nil;
    record("UnregisterEvent", label(self), event);
end

function frameMethods:UnregisterAllEvents()
    for k in pairs(self.__events) do self.__events[k] = nil; end
end

function frameMethods:IsEventRegistered(event) return self.__events[event] ~= nil; end

function frameMethods:RegisterForClicks(...) self.__clicks = { ... }; end

--- Clicking a shell does nothing. What a click would reach is the restricted side, and that is the
--- one thing this file does not stand in for.
function frameMethods:Click() end

function frameMethods:Show() self.__shown = true; end
function frameMethods:Hide() self.__shown = false; end
function frameMethods:IsShown() return self.__shown and true or false; end
function frameMethods:IsVisible() return self.__shown and true or false; end
function frameMethods:SetShown(shown) self.__shown = shown and true or false; end

function frameMethods:CreateTexture() return newFrame("Texture"); end
function frameMethods:CreateFontString() return newFrame("FontString"); end

--- Geometry. Nothing headless asks a shell where it ended up, so these keep no state; the day one
--- does, the answer has to be built rather than guessed at.
local function noop() end
for _, name in ipairs({
    "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight",
    "SetFrameStrata", "SetFrameLevel", "SetParent", "EnableMouse", "EnableMouseWheel",
    "SetPropagateMouseMotion", "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture",
    "SetTexture", "SetAtlas", "SetVertTile", "SetText", "SetEnabled", "SetAlpha", "SetScale",
    "SetClampedToScreen", "SetToplevel", "SetMovable", "SetHitRectInsets", "SetTexCoord",
    "SetVertexColor", "SetDrawLayer", "SetBlendMode", "SetDesaturated", "RegisterForDrag",
}) do
    frameMethods[name] = noop;
end

function frameMethods:GetFrameLevel() return 1; end
function frameMethods:GetRect() return 0, 0, 100, 100; end
function frameMethods:GetWidth() return 100; end
function frameMethods:GetHeight() return 100; end
function frameMethods:GetEffectiveScale() return 1; end

---------------------------------------------------------------------------
-- Installing the globals
---------------------------------------------------------------------------

function M.install()
    _G.UIParent = newFrame("Frame", "UIParent");

    --- Blizzard's own driver frame. The addon only ever registers events on it and sets
    --- `updatetime`, and both of those are answers the golden wants, so the shell records them
    --- like any other frame.
    _G.SecureStateDriverManager = newFrame("Frame", "SecureStateDriverManager");

    _G.CreateFrame = function(frameType, name, parent, template)
        return newFrame(frameType, name, parent, template);
    end

    _G.SecureHandlerExecute = function(frame, body)
        record("Execute", label(frame), nil, body);
    end
    _G.SecureHandlerWrapScript = function(frame, script, header, preBody, postBody)
        record("WrapScript", label(frame), script, preBody);
        if (postBody) then
            record("WrapScriptPost", label(frame), script, postBody);
        end
    end
    _G.SecureHandlerUnwrapScript = function(frame, script)
        record("UnwrapScript", label(frame), script);
    end
    _G.SecureHandlerSetFrameRef = function(frame, refName, ref)
        record("SetFrameRef", label(frame), refName, ref and label(ref) or nil);
    end

    _G.RegisterUnitWatch = function(frame) record("RegisterUnitWatch", label(frame)); end
    _G.UnregisterUnitWatch = function(frame) record("UnregisterUnitWatch", label(frame)); end
    _G.RegisterStateDriver = function(frame, state, values)
        record("RegisterStateDriver", label(frame), state, values);
    end
    _G.UnregisterStateDriver = function(frame, state)
        record("UnregisterStateDriver", label(frame), state);
    end

    _G.ClearOverrideBindings = function(frame) record("ClearOverrideBindings", label(frame)); end
    _G.SetOverrideBindingClick = function(frame, priority, key, button, buttonName)
        record("SetOverrideBindingClick", label(frame), key, button, buttonName);
    end
    _G.SetOverrideBinding = function(frame, priority, key, command)
        record("SetOverrideBinding", label(frame), key, command);
    end

    --- `hooksecurefunc` on a table method. The addon uses it on frames (`Debind.lua` logs every
    --- attribute a DEBUG build stamps), so the shell wires the post-hook the same way the game
    --- does rather than dropping it -- a hook nobody runs is a hook nobody notices going missing.
    _G.hooksecurefunc = function(tbl, method, hook)
        if (type(tbl) == "string") then
            tbl, method, hook = _G, tbl, method;
        end
        local original = tbl[method];
        tbl[method] = function(...)
            local a, b, c, d = original(...);
            hook(...);
            return a, b, c, d;
        end
    end

    --- The clock. `C_Timer.After` queues rather than fires, and the spec drains it -- the four
    --- zero-second calls in the addon are "next frame", and running one inside the call that
    --- scheduled it would be a different order than the game's.
    local timers = {};
    M.timers = timers;
    _G.C_Timer = {
        After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn }; end,
        NewTimer = function(delay, fn)
            timers[#timers + 1] = { delay = delay, fn = fn };
            return { Cancel = noop };
        end,
        NewTicker = function(_, _) return { Cancel = noop }; end,
    };

    --- Runs every queued callback once, in the order they were queued. Anything one of them
    --- queues in turn is left for the next drain, so a callback that reschedules itself cannot
    --- spin here.
    function M.drainTimers()
        local pending = {};
        for i = 1, #timers do
            pending[i] = timers[i];
            timers[i] = nil;
        end
        for i = 1, #pending do
            pending[i].fn();
        end
        return #pending;
    end
end

return M;
