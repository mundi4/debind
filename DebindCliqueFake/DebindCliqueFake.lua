local DebindPublic = DebindPublic;
local DebindPrivate = DebindPrivate;

-- Clique 5.0 renamed RegisterFrame/UnregisterFrame to RegisterUnitFrame/UnregisterUnitFrame,
-- so addons written against it call the new names. Answer to both, and expose 'ccframes'
-- because some of those addons check for it before they call anything at all.
_G.Clique = setmetatable({
    ccframes = DebindPrivate.ccframes,

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

--- **Taking the global back.** The name belongs to whoever is answering for Clique, and a unit
--- frame addon that puts its own table over it is not Clique, and the ones that do it do it from
--- their own login handler. From then on every registration goes there and never reaches here,
--- theirs and every other addon's alike.
---
--- **The sweep only ever finds anything on the first call.** A table someone else is holding is
--- their proxy, and a proxy keeps its frames in its own upvalues, so `pairs` over it yields
--- nothing. Real entries exist only in the plain table that was sitting under the name when this
--- file loaded, which is out of combat by definition. So no call after the first has protected
--- work to do, and there is nothing about lockdown for this to handle.
local function Claim()
    local previous = _G.ClickCastFrames;
    if (getmetatable(previous) == ccframesMeta) then
        return;
    end

    _G.ClickCastFrames = setmetatable({}, ccframesMeta);
    Adopt(previous);
end

Claim();

DebindPrivate.ReclaimClickCastFrames = Claim;
