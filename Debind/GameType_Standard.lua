local _, DebindPrivate = ...;

--- `Constants.GAME_TYPE` on retail. Loaded on that client only (`Debind.toc`).
DebindPrivate.GAME_TYPE = "standard";

--- `UnitName`'s two returns as one name. Here the second is the realm, answered only for a unit
--- from another one.
function DebindPrivate.JoinUnitName(name, realm)
    if (realm and realm ~= "") then
        return FULL_PLAYER_NAME:format(name, realm);
    end
    return name;
end
