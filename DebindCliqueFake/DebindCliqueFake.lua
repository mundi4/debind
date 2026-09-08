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

--- **Listening to `ClickCastFrames` is not here and must not come back.** That table is written by
--- addons whether or not Clique's name is ours, and this addon cannot load while the real Clique
--- is installed (`DebindCliqueFake.xml` declares `ClickCastUnitTemplate`, which Clique declares
--- too, and the second declaration raises). It lives in `Debind/ClickCastTable.lua`.
