-- The frame shell and the secure-handler recorder, the two things the emission golden rests on
-- (`devdocs/legacy/going-headless-outside-the-ui.md` §6).
--
-- **Neither of these interprets anything.** A snippet body handed to `SecureHandlerExecute` is
-- recorded as the string it is and never run, which is why the golden could stand up before there
-- was anything that could run one. What does run them is `tests/restricted.lua`, and it runs **this
-- recording** -- so what it ends up holding is what the game would have built, rather than a second
-- copy of the setup written out by hand.
--
-- The frame shell is here because `Debind.lua`, `SecureBindings.lua` and the rest build frames when
-- they are read. §6 said to look at it again once `BuildBindingPlan` no longer met a frame; the
-- answer is that it stays -- `StampBinding` still builds delegate frames, and both the interpreter
-- and the click-cast registration specs need real ones to key their tables by.

local M = {};

-- Captured at load, before `wow_shim` swaps the global out for the positional stand-in. Nothing
-- here formats a client string, so the stock one is the right one and stays right whatever the
-- shim does to `format` afterwards.
local sformat = string.format;

---------------------------------------------------------------------------
-- The recorder
---------------------------------------------------------------------------

--- Everything that has ever crossed to the secure side, in the order it crossed. One entry per
--- call; `body` is the snippet source verbatim where there is one.
---
--- **It records from the first line of the first file and never stops.** Two readers want
--- different windows onto it and neither wants the other's:
---
---   the emission golden   one rebuild, from a mark. Loading the addon emits a few hundred lines
---                         of setup no rebuild repeats, and a golden carrying those would move
---                         whenever an unrelated file gained a `SetAttribute` at load
---   the interpreter       **everything**, load included. What it runs is the recording itself,
---                         so the environment it ends up with is the one the game would have --
---                         rather than a second copy of the setup written out here, which is the
---                         one thing that could drift
local recorder = { entries = {} };
M.recorder = recorder;

--- `frame` and `ref` are the objects behind the labels, and **only the interpreter reads them**.
--- The golden renders `kind`, `target`, `name` and `body` and nothing else, so carrying a table
--- here cannot move it.
local function record(kind, target, name, body, frame, ref)
    recorder.entries[#recorder.entries + 1] = {
        kind = kind,
        target = target,
        name = name,
        body = body,
        frame = frame,
        ref = ref,
    };
end
M.record = record;

--- The override bindings in force right now, keyed by the key they are on.
---
--- **The recording cannot answer this one.** Every other call crosses once and a reader walks the
--- entries back; an override is *state* -- put on by one rebuild and taken off by the next -- and
--- the question `GetBindingAction` answers is what is in force now, not what once crossed. So it
--- is kept here beside the recording rather than derived from it.
---
--- **Both sides write here, because in the game both sides write the same table.** The insecure
--- side only ever clears (`UpdateBindings.lua`, the prologue); every set comes from the restricted
--- `SetBindingClick`/`SetBinding`, which is why `restricted.lua` takes this table as its own
--- `interp.bindings` instead of keeping a second one. `owner` is the frame that would own the
--- override in game, so a clear takes its own and leaves everyone else's.
local overrides = {};
M.overrides = overrides;

--- What the game reports the key is bound to, or `nil` where no override holds it. The two shapes
--- are the two calls that make one: a click override answers `CLICK <button>:<mousebutton>`, and a
--- command override answers the command verbatim.
function M.overrideAction(key)
    local entry = overrides[key];
    if (not entry) then return nil; end
    if (entry.command) then return entry.command; end
    return sformat("CLICK %s:%s", entry.buttonName, entry.mouseButton or "LeftButton");
end

--- Everything recorded so far, oldest first. The interpreter's window.
--- Puts the recorder, the overrides and the anonymous-frame counter back where they start.
---
--- **The counter is the reason this exists.** A frame the addon does not name is labelled
--- `<Frame#N>` off a running number, and the emission golden records those labels -- so a spec
--- that stood a frame up before the golden's rebuild shifted every one of them, and the failure
--- read as "the emission moved" when nothing about the addon had. `run.lua` calls this between
--- specs, which is the harness half of giving each one a clean addon (§10-1).
function M.reset()
    recorder.entries = {};
    for key in pairs(overrides) do overrides[key] = nil; end
    M.__clearTimers();
    M.__clearListeners();
    M.__resetAnon();
end

function M.all()
    return recorder.entries;
end

--- Everyone listening for something, so `fireEvent` has a list to walk.
---
--- **Cleared by `reset`, and finding out why cost an afternoon.** Every spec gets its own addon,
--- so every spec builds its own `EventFrame`; a list that survived the reset would hand the next
--- spec's event to the previous spec's frame, whose `DebindPrivate` never had `InitDB` run on it.
--- The symptom was `RunLegacyMigration` indexing a nil `db` -- which reads exactly like "the login
--- path does not work headless" and is nothing of the kind.
local listening = {};

--- Sends one event to every frame registered for it, the way the client does.
---
--- **`RegisterEvent` was kept and never delivered against.** The membership has been recorded and
--- readable since the shell was written, so a spec could ask *whether* the addon listens for
--- something -- and nothing could make it hear one. `Events.lua`'s handlers had therefore never run
--- headless at all, and everything they do was out of reach for a reason one function long.
---
--- **The list is taken before any of it runs.** A handler that registers or unregisters while this
--- one is going out must not change who gets *this* event, which is the client's own rule.
function M.fireEvent(event, ...)
    local listeners = {};
    for i = 1, #listening do
        local frame = listening[i];
        if (frame.__events[event]) then listeners[#listeners + 1] = frame; end
    end
    for i = 1, #listeners do
        local script = listeners[i]:GetScript("OnEvent");
        if (script) then script(listeners[i], event, ...); end
    end
    return #listeners;
end

--- Reached by `M.reset`, which is written above this upvalue.
function M.__clearListeners()
    for i = #listening, 1, -1 do listening[i] = nil; end
end

--- Reached by `RegisterEvent`, for the same reason.
function M.__listen(frame)
    for i = 1, #listening do
        if (listening[i] == frame) then return; end
    end
    listening[#listening + 1] = frame;
end

--- Where the recording stands. Hand it back to `since` to get what happened after it.
function M.mark()
    return #recorder.entries;
end

--- What crossed after `mark`, as a list of its own.
function M.since(mark)
    local out = {};
    for i = mark + 1, #recorder.entries do
        out[#out + 1] = recorder.entries[i];
    end
    return out;
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

--- Reached by `M.reset` above, which is declared before this upvalue exists.
function M.__resetAnon()
    _nextAnon = 0;
end

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
    record("CreateFrame", label(frame), template, nil, frame);
    return frame;
end
M.newFrame = newFrame;

function frameMethods:GetName() return self.__name; end
function frameMethods:GetObjectType() return self.__frameType; end
function frameMethods:GetParent() return self.__parent; end
function frameMethods:GetChildren() return unpack(self.__children); end
function frameMethods:IsForbidden() return false; end
function frameMethods:IsProtected() return true, true; end
function frameMethods:IsAnchoringRestricted() return false; end
function frameMethods:HasAccessConstraints() return false; end

--- **Recorded, and every frame, not only the driver.** `SetBindingAttributes` stamps the click
--- frame and its delegates, and those attributes are half of what a rebuild produces -- a golden
--- that watched only the driver would not notice a spell name going out under the wrong button.
function frameMethods:SetAttribute(name, value)
    self.__attributes[name] = value;
    record("SetAttribute", label(self), name, value, self);
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
    M.__listen(self);
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
--- Kept rather than dropped with the other setters, because the addon puts it back when another
--- addon turns it off and a spec has to be able to see that it did.
function frameMethods:EnableMouseWheel(on) self.__mouseWheel = on and true or false; end

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
    "SetFrameStrata", "SetFrameLevel", "SetParent", "EnableMouse",
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

    --- The client's own unit frames, which this addon registers on rather than replaces.
    ---
    --- **Only the two the walk cannot survive without.** `UpdateBlizzardFrames` guards every plain
    --- global with `if (frame)`, so `PlayerFrame` and the rest being absent is a client where those
    --- frames do not exist -- a real answer. The party container is different: it is **indexed**
    --- (`PartyFrame["MemberFrame"..i]`), so an absent one raises rather than degrading, and
    --- `MAX_BOSS_FRAMES` sizes a loop.
    ---
    --- A spec that wants the walk to actually find something puts frames in here itself. What this
    --- buys is that reaching the walk at all stops being an error.
    _G.PartyFrame = {};
    _G.MAX_BOSS_FRAMES = 5;

    _G.SecureHandlerExecute = function(frame, body)
        record("Execute", label(frame), nil, body, frame);
    end
    -- **The header comes along.** A wrapped script runs in the header's environment with `self`
    -- set to the wrapped frame, so an interpreter that only knew the frame could not tell which
    -- environment the body belongs to.
    _G.SecureHandlerWrapScript = function(frame, script, header, preBody, postBody)
        record("WrapScript", label(frame), script, preBody, frame, header);
        if (postBody) then
            record("WrapScriptPost", label(frame), script, postBody, frame, header);
        end
    end
    _G.SecureHandlerUnwrapScript = function(frame, script)
        record("UnwrapScript", label(frame), script, nil, frame);
    end
    _G.SecureHandlerSetFrameRef = function(frame, refName, ref)
        record("SetFrameRef", label(frame), refName, ref and label(ref) or nil, frame, ref);
    end

    --- The unit existence watch, as a set of registered frames.
    ---
    --- **The membership is kept, not only recorded.** `ApplyBindingPlan` asks
    --- `UnitWatchRegistered` before writing, so a stand-in that always answered `nil` would have
    --- every rebuild register again and the golden would record a write that the game never sees
    --- (`SecureStateDriver.lua`, `unitExistsWatchers`).
    local unitWatched = setmetatable({}, { __mode = "k" });
    _G.RegisterUnitWatch = function(frame, asState)
        unitWatched[frame] = asState and true or false;
        record("RegisterUnitWatch", label(frame));
    end
    _G.UnregisterUnitWatch = function(frame)
        unitWatched[frame] = nil;
        record("UnregisterUnitWatch", label(frame));
    end
    _G.UnitWatchRegistered = function(frame) return unitWatched[frame] ~= nil; end
    _G.RegisterStateDriver = function(frame, state, values)
        record("RegisterStateDriver", label(frame), state, values);
    end
    _G.UnregisterStateDriver = function(frame, state)
        record("UnregisterStateDriver", label(frame), state);
    end

    --- **The frame goes in the frame slot on all three.** It used to be left out on the clear and
    --- to be the mouse button on the click, which nothing noticed because the golden renders
    --- `kind`/`target`/`name`/`body` and reads none of it -- but `replay` picks entries by
    --- `entry.frame`, so a clear could never reach the interpreter.
    _G.ClearOverrideBindings = function(frame)
        record("ClearOverrideBindings", label(frame), nil, nil, frame);
        for key, entry in pairs(overrides) do
            if (entry.owner == frame) then overrides[key] = nil; end
        end
    end
    --- The parameter names are the client's: `buttonName` is the button the key is routed to and
    --- `mouseButton` is which of its clicks. Reading them the other way round is how the two got
    --- swapped in the recording above.
    _G.SetOverrideBindingClick = function(frame, priority, key, buttonName, mouseButton)
        record("SetOverrideBindingClick", label(frame), key, buttonName, frame);
        overrides[key] = { owner = frame, buttonName = buttonName, mouseButton = mouseButton };
    end
    _G.SetOverrideBinding = function(frame, priority, key, command)
        record("SetOverrideBinding", label(frame), key, command, frame);
        overrides[key] = { owner = frame, command = command };
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
    --- Throws away what is still queued, without running it.
    ---
    --- **A pending timer is a spec's, and it must not fire inside the next one.** `reset` gives each
    --- spec a clean client; a callback left over from the one before would run against an addon it
    --- was never loaded with, and the first `drainTimers` in a later spec is where it would land.
    function M.__clearTimers()
        for i = #timers, 1, -1 do timers[i] = nil; end
    end

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
