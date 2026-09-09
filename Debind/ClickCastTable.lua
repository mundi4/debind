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
--- not cosmetic: an addon takes its frames back with
--- `if ClickCastFrames[frame] then ClickCastFrames[frame] = nil end`, and against us that test was
--- always false - so its own bookkeeping never came off the frame either.
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

    --- **A write taking a frame back is filed and nothing else.** The table says what it has been
    --- told, so the row goes; the frame stays ours, because being ours is the blacklist's answer
    --- and not the frame owner's
    --- (`devdocs/legacy/taking-every-unit-frame-with-one-blacklist.md` §1-5).
    __newindex = function(_, frame, value)
        if (value == nil or value == false) then
            registered[frame] = nil;
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

--- The metatables we have already put ourselves after, so a second pass over the same proxy does
--- not stack a second wrapper on it.
local hooked = setmetatable({}, { __mode = "k" });

--- The foreign table under the name, or nil while the name is ours.
local holder;

--- **After the holder, never instead of it.** The original runs first and gets the value
--- untouched, so whatever the holder does with a registration it still does; we only hear that one
--- arrived.
---
--- **The holder is not asked what it decided.** Every unit frame is ours whatever anybody else is
--- doing with it, and standing on top of what that engine wraps is what makes both of them work on
--- the one frame (`FrameRegistry.Reassemble`). What is left to hear is the write itself.
---
--- A write taking a frame back is filed by the holder and nothing else, for the reason
--- `ccframesMeta` gives.
---
--- **Only ever wrapped where there was a `__newindex` to wrap** (`Hook`), so the original always
--- has somewhere to put the write and we never put one in the table ourselves.
local function WrapNewIndex(mt)
    local original = mt.__newindex;
    mt.__newindex = function(t, frame, value)
        if (type(original) == "function") then
            original(t, frame, value);
        else
            original[frame] = value;
        end

        if (value ~= nil and value ~= false) then
            DebindPrivate.RegisterFrame(frame, value);
        end
    end;
end

--- **The rows we were holding, handed to the holder that arrived after them.** A holder builds its
--- store by walking the table it finds under the name, and ours yields nothing to `pairs` because
--- the rows sit beside the table rather than in it -- so those frames, which any plain table would
--- have passed on, were the ones its store never learned about.
---
--- **Written as ordinary registrations, after `Hook`.** The write runs the holder's `__newindex`
--- and then ours, so the holder files it and we hear it; written before the wrapper is on, our
--- side would never hear it again. `RegisterFrame` returns the row a frame already has, so nothing
--- registers twice.
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
    if (hooked[mt]) then
        return;
    end
    hooked[mt] = true;
    WrapNewIndex(mt);

    -- Rows already in the table, taken the way a fresh write is. A proxy that keeps its store in an
    -- upvalue yields nothing here; one that files its writes in the table itself yields the
    -- registrations that arrived before we were listening.
    for frame, value in pairs(previous) do
        DebindPrivate.RegisterFrame(frame, value);
    end
end

--- **The name is taken only where nobody is holding it.** A plain table under the name is what
--- Clique itself would have left, or nothing at all, and there is no other engine behind it to
--- disagree with.
---
--- **A `__newindex` is what says somebody is holding it**, not a metatable. A table that carries
--- one is intercepting every registration, and that interception is what has to be listened to
--- rather than replaced. A metatable without one intercepts nothing, so its writes were landing in
--- the table anyway: it is taken over like the plain table it behaves as.
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
    _G.ClickCastFrames = setmetatable({}, ccframesMeta);
    Adopt(previous);
end

--- **Wrapping a script is a click-casting engine attaching to a frame**, so hooking it is hearing
--- the moment one puts its proxy over the name without reading anybody's settings. The method form
--- (`header:WrapScript`) reaches the same globals: `SecureHandlerMethod_WrapScript` calls them by
--- name at the call (`SecureHandlers.lua`).
---
--- **A tick later, because the holder is mid-call.** The hook runs before the holder has finished
--- putting itself up.
---
--- **Out of combat only.** Attaching registers whatever the proxy already holds, and registering
--- writes through the API frame, which is protected; under lockdown every one of those frames would
--- go to the queue and put out "cannot register a unit frame in combat" over something the reader
--- never did. Nothing is lost: `PLAYER_REGEN_ENABLED` attaches again.
---
--- **A holder puts its proxy up and then wraps its own frames, and every one of those is a frame we
--- know nothing about.** A registration a third addon wrote into that proxy in the meantime is
--- never heard otherwise -- a proxy keeps its store in an upvalue, so no later pass can find it
--- either. Looking at the name on any foreign wrap is what shortens that window to one tick.
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

--- **`header` is the wrap hook's argument and the unwrap hook has none.**
--- `SecureHandlerUnwrapScript(frame, script)` takes two (`SecureHandlers.lua`), so the comparison
--- below sees nil on every unwrap and the self-filter does nothing there. The flag is what stands
--- in: our own unwrapping says so before it starts (`FrameRegistry.RewrapUnitFrames`), because
--- nothing in the arguments can say it.
local function OnHolderWrap(_, _, header)
    if (header == DebindPrivate.BindingDriver or DebindPrivate.unwrappingOwnScripts) then
        return;
    end
    if (InCombatLockdown()) then
        return;
    end
    QueueNameCheck();
end

hooksecurefunc("SecureHandlerWrapScript", OnHolderWrap);
hooksecurefunc("SecureHandlerUnwrapScript", OnHolderWrap);

AttachClickCastFrames();

DebindPrivate.AttachClickCastFrames = AttachClickCastFrames;

--- 남이 이름을 들고 있으면 그 표, 이름이 우리 것이면 nil.
---
--- **모양으로는 못 가른다.** 밖에서 보이는 것은 메타테이블뿐인데, `__index`를 다는 프록시가
--- 우리만이 아니다. EllesmereUI의 엔진은 자기 `registeredFrames`에서 답하는 `__index`를 달고,
--- Clique가 깔린 판에서도 저장된 설정이 켜져 있으면 그 프록시가 Clique의 표 위에 앉는다
--- (`devdocs/how-unit-frames-reach-us.md`의 EllesmereUI 절). 그래서 그 모양을 우리 것이라고
--- 읽으면 남의 프록시를 우리 것으로 세는데, 실제로 `/debtest`가 그렇게 읽고 실패를 냈다.
--- 신원은 이 안에서만 답할 수 있어서 문을 하나 낸다.
function DebindPrivate.ClickCastTableHolder()
    return holder;
end

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
--- it is registering from inside, and marks the row as the header's. Registering here on the spot
--- did neither (code review, 2026-09-08).
local function TakeExported(value)
    local name = value and value.GetName and value:GetName();
    if (type(name) ~= "string") then
        return;
    end
    DebindPrivate.BindingDriver:OnClickCastRegister(name);
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

    --- **`export_unregister` is listened to by nobody.** A header taking a child back is a
    --- deregistration arriving from outside, and one of those means nothing here
    --- (`devdocs/legacy/taking-every-unit-frame-with-one-blacklist.md` §1-5).
    header:HookScript("OnAttributeChanged", function(_, name, value)
        if (name == "export_register") then
            TakeExported(value);
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
