local DebouncePublic = DebouncePublic;
local DebouncePrivate = DebouncePrivate;

-- Clique 5.0 renamed RegisterFrame/UnregisterFrame to RegisterUnitFrame/UnregisterUnitFrame,
-- so addons written against it call the new names. Answer to both, and expose 'ccframes'
-- because some of those addons check for it before they call anything at all.
_G.Clique = setmetatable({
    ccframes = DebouncePrivate.ccframes,

    RegisterUnitFrame = function(_, button)
        DebouncePrivate.RegisterFrame(button);
    end,

    UnregisterUnitFrame = function(_, button)
        DebouncePrivate.UnregisterFrame(button);
    end,
}, { __index = DebouncePublic, __newindex = function() end });

_G.ClickCastHeader = DebouncePublic.header;

-- Whatever registered before we loaded lives in the plain table it created.
local oldClickCastFrames = _G.ClickCastFrames;

_G.ClickCastFrames = setmetatable({}, {
    __newindex = function(t, k, v)
        if v == nil or v == false then
            DebouncePublic:UnregisterFrame(k);
        else
            DebouncePublic:RegisterFrame(k, v);
        end
    end
});

-- Clique adopts those frames instead of dropping them; do the same.
if (oldClickCastFrames) then
    for frame, options in pairs(oldClickCastFrames) do
        if (options ~= false) then
            DebouncePublic:RegisterFrame(frame, options);
        end
    end
end
