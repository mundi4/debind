local _, DebindPrivate = ...;

--- Listening to `ClickCastFrames`, the table every click-casting-aware unit frame addon writes its
--- frames into.
---
--- **This has nothing to do with standing in for Clique and used to live in `DebindCliqueFake`.**
--- That addon may not load while the real Clique is installed: its XML declares
--- `ClickCastUnitTemplate`, a virtual template Clique's own XML already declares, and a second
--- declaration of one raises. So everything here that is about the table rather than about Clique's
--- name had to come out to run at all while Clique is there.

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
            DebindPrivate.UnregisterFrame(frame);
        else
            registered[frame] = value;
            DebindPrivate.RegisterFrame(frame, value);
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
            DebindPrivate.RegisterFrame(frame, options);
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

--- The table Clique put under the name, or nil where Clique is not installed.
local cliqueTable;

--- Reads Clique's table off the global, and is called from `InitDB` because that is the one moment
--- it is certainly Clique's: Clique installs it at its own `ADDON_LOADED`, which is ahead of ours,
--- and the packs that wrap a proxy of their own over it load after us. Read later, the name may
--- already be under somebody else's proxy; read at our file scope, Clique's is not there yet.
function DebindPrivate.RememberCliqueTable()
    local current = _G.ClickCastFrames;
    local mt = type(current) == "table" and getmetatable(current);
    if (DebindPrivate.CliqueDetected and type(mt) == "table" and mt.__newindex ~= nil) then
        cliqueTable = current;
    else
        cliqueTable = nil;
    end
end

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
    --- **Clique as the holder is not asked.** A frame written into Clique's table was handed to
    --- Clique, and the option above is about frames handed to nobody, so every one of them is ours
    --- as well. Asking would also answer wrong: Clique's proxy files its rows in `Clique.ccframes`
    --- and answers nothing through `__index`, so the question read every frame as dropped, and a
    --- Clique release that adds an `__index` would have turned that into standing down
    --- (code review, 2026-09-08). Clique is known by its table (`RememberCliqueTable`), not by
    --- being installed: a pack whose own click casting was on before Clique arrived still puts
    --- its proxy over the name, and that holder is asked like any other.
    if (HolderAnswer(frame) and holder ~= cliqueTable
            and not DebindPrivate.TakesUnofferedFrame(frame)) then
        deferred[frame] = true;
        DebindPrivate.UnregisterFrame(frame);
    else
        deferred[frame] = nil;
        DebindPrivate.RegisterFrame(frame, offered[frame] or true);
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
            DebindPrivate.UnregisterFrame(frame);
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
    if (DebindPrivate.StandsAsideForClique()) then
        return;
    end

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
    -- **Asked before anything else, because the real Clique wraps its frames by the dozen.** Every
    -- one of those would otherwise book a name check for a table we are not going to touch.
    if (DebindPrivate.StandsAsideForClique()) then
        return;
    end
    if (header == DebindPrivate.BindingDriver or DebindPrivate.unwrappingOwnScripts) then
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

---------------------------------------------------------------------------
-- The header door, while Clique is holding it
---------------------------------------------------------------------------

--- **Clique's header protocol, read off Clique's own header.** An addon gives its group header a
--- `clickcast_header` and the header registers each child from inside the restricted environment,
--- which is a road no insecure hook can stand on. Clique gets off it the same way we do: its
--- `clickcast_register` body writes the child into an `export_register` attribute and its own
--- `OnAttributeChanged` picks it up (`Clique/core/core.lua`). Hooking that script reads the same
--- value at the same moment, by name, and touches nothing restricted.
---
--- **Only ever hooked, never replaced.** `HookScript` runs after Clique's own handler, so whatever
--- Clique does with the registration it still does, and the frame reaches `RegisterFrame` the way
--- every other door's frame does.
---
--- **`export_register` is not a promise Clique made us.** It is that addon's internal wiring, and a
--- release that renames it leaves this hook silent with nothing raised anywhere. Nothing else
--- breaks when it goes: the frames simply stop arriving through this door.
---
--- **Told group, never read.** Every frame that comes this way is a secure group header's child, so
--- the token on one says which slot it is filling and not what the frame is
--- (`SecureBindings.lua`'s own half of this protocol says the same).
--- **Handed to our own header door by name**, because that is the same registration arriving by
--- another road: `OnClickCastRegister` waits a tick for the header to finish configuring the child
--- it is registering from inside, and marks the row as the header's so that only a header takes it
--- back. Registering here on the spot did neither (code review, 2026-09-08).
local function TakeExported(value, register)
    local name = value and value.GetName and value:GetName();
    if (type(name) ~= "string") then
        return;
    end
    if (register) then
        DebindPrivate.BindingDriver:OnClickCastRegister(name);
    else
        DebindPrivate.BindingDriver:OnClickCastUnregister(name);
    end
end

--- The headers already hooked, so a second call does not stack a second handler on one. Keyed by
--- the header rather than by "have we run", because what may not be hooked twice is the frame.
local cliqueHeaderHooked = setmetatable({}, { __mode = "k" });

function DebindPrivate.AttachCliqueHeader()
    local clique = _G.Clique;
    local header = type(clique) == "table" and clique.header;
    if (not header or not header.HookScript or cliqueHeaderHooked[header]) then
        return;
    end
    cliqueHeaderHooked[header] = true;

    header:HookScript("OnAttributeChanged", function(_, name, value)
        if (name == "export_register") then
            TakeExported(value, true);
        elseif (name == "export_unregister") then
            TakeExported(value, false);
        end
    end);

    --- **What registered before the hook was on.** Clique keeps the header door's frames by name
    --- in `hccframes`, and everything in it at this moment arrived while we were not listening.
    if (type(clique.hccframes) == "table") then
        for name in pairs(clique.hccframes) do
            if (type(name) == "string") then
                DebindPrivate.BindingDriver:OnClickCastRegister(name);
            end
        end
    end

    --- **And the table door's twin.** A frame written into `ClickCastFrames` before we wrapped
    --- Clique's proxy went through Clique's `__newindex` into `Clique.ccframes` and nowhere else:
    --- the proxy never holds a row of its own, so the walk that adopts a plain table finds nothing
    --- there. Handed over the way the table hands one over (code review, 2026-09-08).
    if (type(clique.ccframes) == "table") then
        for button in pairs(clique.ccframes) do
            if (type(button) == "table") then
                DebindPrivate.RegisterFrame(button, true);
            end
        end
    end
end
