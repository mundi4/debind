-- Probe_InitialSpecs.lua
-- At login, every class's specializations and its initial one, into `DebindDevDB.initialSpecs`.
--
-- **What it is for.** `SpecSpells.lua`'s data goes by specialization id alone, so a class-wide
-- spell has to be written under every specialization of the class, the initial one included: a
-- character that has not picked one yet stands in it. `GetSpecializationInfoForClassID` answers for
-- any class, so one login on any character reads all of them.

local function Sweep()
    local classes = {};
    for index = 1, GetNumClasses() do
        local _, classFile, classID = GetClassInfo(index);
        if (classID) then
            local specs = {};
            for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0 do
                local id, name = GetSpecializationInfoForClassID(classID, i);
                specs[#specs + 1] = format("%s=%s", tostring(id), tostring(name));
            end
            classes[classFile] = {
                id = classID,
                specs = table.concat(specs, " "),
                initial = (GetSpecializationInfoForClassID(classID, 5)),
            };
        end
    end
    return classes;
end

local probe = CreateFrame("Frame");
probe:RegisterEvent("PLAYER_LOGIN");
probe:SetScript("OnEvent", function()
    local ok, classes = pcall(Sweep);
    if (not ok) then
        print("|cffff4444Debind|r initialSpecs raised: " .. tostring(classes));
        return;
    end
    local version, build = GetBuildInfo();
    DebindDevDB = DebindDevDB or {};
    DebindDevDB.initialSpecs = {
        at = date("%Y-%m-%d %H:%M:%S"),
        build = version .. "." .. build,
        classes = classes,
    };
end);
