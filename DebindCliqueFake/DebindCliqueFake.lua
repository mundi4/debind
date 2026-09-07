local DebindPublic = DebindPublic;
local DebindPrivate = DebindPrivate;

-- Clique 5.0 renamed RegisterFrame/UnregisterFrame to RegisterUnitFrame/UnregisterUnitFrame,
-- so addons written against it call the new names. Answer to both, and expose 'ccframes'
-- because some of those addons check for it before they call anything at all.
_G.Clique = setmetatable({
    ccframes = DebindPrivate.ccframes,
    hccframes = DebindPrivate.hccframes,

    RegisterUnitFrame = function(_, button)
        DebindPrivate.RegisterFrame(button);
    end,

    UnregisterUnitFrame = function(_, button)
        DebindPrivate.UnregisterFrame(button);
    end,
}, { __index = DebindPublic, __newindex = function() end });

--- **These two stay at load time and must not move.** An addon decides whether to give its group
--- header a `clickcast_header` by testing whether Clique is there, and it tests at the moment it
--- builds the header. That runs well after this file, but a build where it ran first would take
--- the plain path and never register through the header at all.
_G.ClickCastHeader = DebindPublic.header;

--- What the table has been told, kept beside it rather than in it.
---
--- **Reading it back has to answer.** Clique's own `ClickCastFrames` is a plain table, so an addon
--- that asks whether a frame is registered gets a real answer there and got `nil` from us. That is
--- not cosmetic: an addon that hands its frames over and later takes them back does it with
--- `if ClickCastFrames[frame] then ClickCastFrames[frame] = nil end`, and against us that test was
--- always false - so it never took them back and we went on routing frames it had reclaimed.
---
--- **Kept outside the table because `__newindex` only fires for a key that is not there.** Storing
--- the frame in the table itself would silence every repeat write, and the repeats are the ones
--- that carry the answer: a frame library registers a frame from its styling pass and writes the
--- unit attribute afterwards, so the second registration is the first one that can be read
--- (`FrameRegistry.lua`). The cost is that `pairs` over this table still shows nothing, and Lua
--- 5.1 has no `__pairs` to fix that with.
local registered = {};

local ccframesMeta = {
    __index = function(_, frame)
        return registered[frame];
    end,

    __newindex = function(_, frame, value)
        if (value == nil or value == false) then
            registered[frame] = nil;
            DebindPublic:UnregisterFrame(frame);
        else
            registered[frame] = value;
            DebindPublic:RegisterFrame(frame, value);
        end
    end,
};

--- Clique adopts what was registered before it loaded instead of dropping it; do the same.
local function Adopt(previous)
    if (type(previous) ~= "table") then
        return;
    end
    for frame, options in pairs(previous) do
        if (options ~= false) then
            DebindPublic:RegisterFrame(frame, options);
        end
    end
end

---------------------------------------------------------------------------
-- Somebody else holding the name
---------------------------------------------------------------------------

--- What was written for a frame, kept whether or not we ended up taking it. A re-ask that finds
--- the holder has let go registers with the value the frame's owner offered rather than with a
--- stand-in for it.
local offered = setmetatable({}, { __mode = "k" });

--- The frames the holder answered for, so we stood down. These are what a re-ask walks: a holder
--- can let one go later (its own setting moves, its engine is turned off) and nothing tells us.
local deferred = setmetatable({}, { __mode = "k" });

--- The metatables we have already put ourselves after, so a second pass over the same proxy does
--- not stack a second wrapper on it. Each entry keeps that metatable's `__index` as it was before
--- we wrapped it, which is the only thing that can still say what the holder decided.
local hooked = setmetatable({}, { __mode = "k" });

--- The foreign table under the name, or nil while the name is ours.
local holder;

--- The `hooked` entry for the metatable `holder` is under.
local holderHook;

--- **What the holder alone answers, read the way the table read before we wrapped it.** Our own
--- `__index` wrapper answers for frames we took, so asking through it would report every one of
--- them as the holder's -- and a re-ask with the option off would hand each one straight back.
local function HolderAnswer(frame)
    if (not holder) then
        return nil;
    end
    local value = rawget(holder, frame);
    if (value ~= nil) then
        return value;
    end
    local index = holderHook and holderHook.index;
    if (type(index) == "function") then
        return index(holder, frame);
    elseif (index ~= nil) then
        return index[frame];
    end
end

--- **The holder answers and we take what it did not.** `__index` is the question every addon
--- already asks of this table, so asking it back is asking the holder what it decided rather than
--- guessing from its name or its settings. Truthy is "mine": we stand down, and remember the frame
--- so a later pass can ask again. Nil is a write it filed and dropped, which leaves the frame with
--- nobody answering its clicks, and that is the one we take.
--- **A frame the holder kept is registered too, while the option is on.** Standing down was for
--- one fault: two engines on one frame meant whoever wrapped last took the leave and the other's
--- hover died. That is gone -- we take the top and replay what was above us
--- (`FrameRegistry.Reassemble`) -- so both engines work on the frame and there is nothing left to
--- stand down for. Turned off, this is the narrower behaviour again: the holder's frames are its
--- own and only what it dropped comes to us.
---
--- The `deferred` row is still written while the option is off, because that is what a later
--- re-ask walks.
local function AskHolder(frame)
    if (not holder) then
        return;
    end
    if (HolderAnswer(frame) and not DebindPrivate.TakesUnregisteredFrames()) then
        deferred[frame] = true;
        DebindPublic:UnregisterFrame(frame);
    else
        deferred[frame] = nil;
        DebindPublic:RegisterFrame(frame, offered[frame] or true);
    end
end

--- **After the holder, never instead of it.** The original runs first and gets the value
--- untouched, so whatever the holder does with a registration it still does; the question is only
--- asked of what it left behind.
---
--- A `nil` or `false` write is a deregistration, and one is honoured wherever it comes from -- the
--- frame's owner is asking for it back and we have no claim on it.
---
--- **Only ever wrapped where there was a `__newindex` to wrap** (`Hook`), so the original always
--- has somewhere to put the write and we never put one in the table ourselves. Doing that once
--- meant the read below found our own value sitting there and every frame came back "theirs".
local function WrapNewIndex(mt)
    local original = mt.__newindex;
    mt.__newindex = function(t, frame, value)
        if (type(original) == "function") then
            original(t, frame, value);
        else
            original[frame] = value;
        end

        if (value == nil or value == false) then
            offered[frame] = nil;
            deferred[frame] = nil;
            DebindPublic:UnregisterFrame(frame);
            return;
        end

        offered[frame] = value;
        AskHolder(frame);
    end;
end

--- **A frame we took has to read back as taken, behind a holder too.** The owner of a frame takes
--- it back with `if ClickCastFrames[frame] then ClickCastFrames[frame] = nil end`, and a holder
--- answers nil for a frame it never kept -- so against a holder that reclaim never wrote anything,
--- no `__newindex` ran, and we went on routing a frame its owner had asked for back. That is the
--- fault `registered` was put beside our own table for, reappearing one layer up.
---
--- **The holder answers first and is never contradicted.** Only its nil is filled in, and only for
--- a frame it dropped and we then took; a frame it kept is its own answer, which is already true.
local function WrapIndex(mt, record)
    mt.__index = function(t, frame)
        local original = record.index;
        local answer;
        if (type(original) == "function") then
            answer = original(t, frame);
        elseif (original ~= nil) then
            answer = original[frame];
        end

        if ((answer == nil or answer == false)
                and offered[frame] ~= nil
                and type(DebindPrivate.ccframes[frame]) == "table") then
            return offered[frame];
        end
        return answer;
    end;
end

--- **The rows we were holding, handed to the holder that arrived after them.** A holder builds its
--- store by walking the table it finds under the name, and ours yields nothing to `pairs` because
--- the rows sit beside the table rather than in it -- so those frames, which any plain table would
--- have passed on, were the ones its store never learned about.
---
--- **Written as ordinary registrations, after `Hook`.** The write runs the holder's `__newindex`
--- and then ours, so the holder files it and the frame comes back through `AskHolder`; written
--- before the wrapper is on, our side would never hear it again and a later drop by the holder
--- would not reach us. `RegisterFrame` returns the row a frame already has, so nothing registers
--- twice.
local function HandOver(target)
    for frame, value in pairs(registered) do
        target[frame] = value;
    end
end

--- **A proxy is not taken back, it is listened to.** The name belongs to whoever is answering for
--- Clique, and a unit frame addon that puts its own table over it has said it is answering. Taking
--- the name back does not bring the frames already written into the other table with it, and it
--- leaves that addon writing into a table nobody reads -- so both engines end up on the same frame
--- or neither does.
local function Hook(previous)
    local mt = getmetatable(previous);
    if (type(mt) ~= "table") then
        return;
    end

    -- **Set before the wrapped-already check, because the table can be replaced under one
    -- metatable.** A holder that rebuilds its store hands us a new table on the same `mt`, and
    -- returning early with `holder` left on the dead one asks a table nobody writes to any more.
    holder = previous;
    local record = hooked[mt];
    if (record) then
        holderHook = record;
        return;
    end
    record = { index = mt.__index };
    hooked[mt] = record;
    holderHook = record;
    WrapIndex(mt, record);
    WrapNewIndex(mt);

    -- Rows already in the table, put through the same question as a fresh write. A proxy that
    -- keeps its store in an upvalue yields nothing here; one that files its writes in the table
    -- itself yields the registrations that arrived before we were listening.
    for frame in pairs(previous) do
        AskHolder(frame);
    end
end

--- **The name is taken only where nobody is holding it.** A plain table under the name is what
--- Clique itself would have left, or nothing at all, and there is no other engine behind it to
--- disagree with.
---
--- **A `__newindex` is what says somebody is holding it**, not a metatable. A table that carries
--- one is intercepting every registration and therefore deciding about it, which is the thing
--- `Hook` asks. A metatable without one intercepts nothing, so its writes were landing in the
--- table anyway and there is no opinion to ask for: it is taken over like the plain table it
--- behaves as.
---
--- **What `Adopt` sweeps is only ever a plain table.** A proxy keeps its frames in its own
--- upvalues, so `pairs` over it yields nothing; real entries exist only in the table that was
--- sitting under the name when this file loaded, which is out of combat by definition.
local function AttachClickCastFrames()
    local previous = _G.ClickCastFrames;
    if (getmetatable(previous) == ccframesMeta) then
        return;
    end

    -- **A table locked with `__metatable` is left entirely alone.** Its metamethods cannot be read,
    -- and replacing what we cannot read is the reclaim under another name.
    --
    -- **The lock is probed, not recognised by the shape of what `getmetatable` hands back.** That
    -- value is whatever `__metatable` was set to, so a holder that locks with a table (`{}` is as
    -- valid a sentinel as `false`) read as an ordinary metatable with no `__newindex` in it, and
    -- the branch below took the name out from under a live engine. `setmetatable` is the one thing
    -- that can tell: it raises on a locked table and is a no-op on an unlocked one, since what goes
    -- back is what was already there.
    local mt;
    if (type(previous) == "table") then
        if (not pcall(setmetatable, previous, getmetatable(previous))) then
            return;
        end
        mt = getmetatable(previous);
    end

    if (type(mt) == "table" and mt.__newindex ~= nil) then
        -- **"The first time we meet this table", not this metatable.** A holder that rebuilds its
        -- store hands us a new table on the same `mt`, and the new one knows nothing of the old
        -- one's rows either.
        local fresh = (holder ~= previous);
        Hook(previous);
        if (fresh) then
            HandOver(previous);
        end
        return;
    end

    holder = nil;
    holderHook = nil;
    _G.ClickCastFrames = setmetatable({}, ccframesMeta);
    Adopt(previous);
end

--- **Every frame we have an answer for, asked again.** A holder's decision can move without a
--- write coming through: its own hover casting is switched on or off, or a frame it had passed on
--- is picked up when the reader changes a setting. So the frames we stood down on and the frames
--- we took are both put back to the holder.
---
--- **Out of combat only, and both callers are.** Registering and deregistering write through the
--- API frame, which is protected; a re-ask under lockdown would queue every frame it touched.
local function AskHolderAgain()
    if (not holder or InCombatLockdown()) then
        return;
    end
    for frame in pairs(deferred) do
        AskHolder(frame);
    end
    for frame, row in pairs(DebindPrivate.ccframes) do
        if (type(row) == "table" and not row.hd) then
            AskHolder(frame);
        end
    end
end

--- **Wrapping a script is the holder taking a frame, and unwrapping it is the holder letting go.**
--- Those two calls are how any click-casting engine attaches and detaches, so hooking them is
--- hearing the moment a decision moves without reading anybody's settings or any frame's name.
--- The method form (`header:WrapScript`) reaches the same globals: `SecureHandlerMethod_WrapScript`
--- calls them by name at the call (`SecureHandlers.lua`).
---
--- **A tick later, because the holder is mid-call.** The hook runs before the holder has finished
--- deciding, so the answer read now is the one it is still writing.
---
--- **Combat is asked twice, once at each of those two moments.** The fight can start inside that
--- one frame, and the re-ask would then queue the registration and put out "cannot register a unit
--- frame in combat" over something the reader never did. Standing down loses nothing:
--- `PLAYER_REGEN_ENABLED` asks about that frame again.
--- **`header` is the wrap hook's argument and the unwrap hook has none.**
--- `SecureHandlerUnwrapScript(frame, script)` takes two (`SecureHandlers.lua`), so the comparison
--- below sees nil on every unwrap and the self-filter does nothing there. The flag is what stands
--- in: our own unwrapping says so before it starts (`FrameRegistry.RewrapUnitFrames`), because
--- nothing in the arguments can say it.
--- **A holder puts its proxy up and then wraps its own frames, and every one of those is a frame
--- we know nothing about.** So none of them was a reason to look at the name, and a registration a
--- third addon wrote into that proxy in the meantime was never heard -- a proxy keeps its store in
--- an upvalue, so no later pass can find it either. Looking at the name on any foreign wrap is what
--- shortens that window to one tick.
---
--- **One check per tick.** A holder wraps its frames dozens at a time and every one of them would
--- otherwise book its own.
local nameCheckQueued;

local function QueueNameCheck()
    local current = _G.ClickCastFrames;
    if (nameCheckQueued or current == holder or getmetatable(current) == ccframesMeta) then
        return;
    end
    nameCheckQueued = true;
    C_Timer.After(0, function()
        nameCheckQueued = false;
        if (InCombatLockdown()) then
            return;
        end
        AttachClickCastFrames();
    end);
end

local function OnHolderWrap(frame, _, header)
    if (header == DebindPublic.header or DebindPrivate.unwrappingOwnScripts) then
        return;
    end
    if (InCombatLockdown()) then
        return;
    end
    if (not (offered[frame] or deferred[frame] or DebindPrivate.ccframes[frame])) then
        QueueNameCheck();
        return;
    end
    C_Timer.After(0, function()
        if (InCombatLockdown()) then
            return;
        end
        AttachClickCastFrames();
        AskHolder(frame);
    end);
end

hooksecurefunc("SecureHandlerWrapScript", OnHolderWrap);
hooksecurefunc("SecureHandlerUnwrapScript", OnHolderWrap);

AttachClickCastFrames();

DebindPrivate.AttachClickCastFrames = AttachClickCastFrames;
DebindPrivate.AskHolderAgain = AskHolderAgain;
