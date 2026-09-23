local _, DebindPrivate = ...;

--- **Where the clients are asked for the same thing in different ways** (`preparing-the-code-for-camelot.md`
--- §3). Each function here hands back one shape, and picks how to get it by what the client has
--- rather than by which client it is: `WOW_PROJECT_ID` answers 1 on camelot as on retail.
local Client = DebindPrivate.Client or {};
DebindPrivate.Client = Client;

--- The classes somebody can play, as `{ id =, classFile = }`, in the client's own order.
---
--- **Camelot lists them by id, with holes.** `GetNumClasses()` is 9 there while index 6 and 10 are
--- empty and Druid is at 11, so walking to the count stops before Druid. That client's own class
--- menu walks `C_SpecializationInfo.GetAllClassIDs()` instead and hands each id to `GetClassInfo`
--- (`Blizzard_ClassMenu.lua`), and only that client has the call. Retail's index is a position in
--- a list without holes.
function Client.PlayableClasses()
    local out = {};
    local ids = C_SpecializationInfo.GetAllClassIDs and C_SpecializationInfo.GetAllClassIDs();
    if (ids) then
        for i = 1, #ids do
            local _, classFile = GetClassInfo(ids[i]);
            if (classFile) then
                out[#out + 1] = { id = ids[i], classFile = classFile };
            end
        end
        return out;
    end
    for index = 1, GetNumClasses() do
        local _, classFile, classID = GetClassInfo(index);
        if (classFile and classID) then
            out[#out + 1] = { id = classID, classFile = classFile };
        end
    end
    return out;
end
