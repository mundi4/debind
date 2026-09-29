local _, DebindPrivate = ...;

--- `Constants.GAME_TYPE` on World of Warcraft: Forever. Loaded on that client only (`Debind.toc`).
DebindPrivate.GAME_TYPE = "camelot";

--- `UnitName`'s two returns as one name. **Here the second is the surname, not a realm**, and the
--- first name alone is not unique: two characters on one realm, even on one account, can share it.
--- Joined the way the client's own camelot `NameUtil.lua` joins them.
function DebindPrivate.JoinUnitName(name, surname)
    if (surname and surname ~= "") then
        return name .. _G.Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR .. surname;
    end
    return name;
end
