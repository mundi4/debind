-- Probe_RaidRoster.lua
-- Question: what name does a raid header compare a member by (`GetRaidRosterInfo`), does that
-- name tell two people apart, and does `UnitInRaid` give the index `GetRaidRosterInfo` and
-- `raidN` take? `HeaderNameList` in `UnitWatch.lua` rests on all three.
--
--   /debroster   in a raid, out of combat. Saved in DebindDevDB.raidRoster.

local VERSION = "roster-1";
local TAG = "|cffff9900[ROSTER]|r ";

local function plain(v)
    if (issecretvalue and issecretvalue(v)) then
        return "<secret>";
    end
    return v;
end

local function q(v)
    v = plain(v);
    if (type(v) == "string") then
        return format("%q", v);
    end
    return tostring(v);
end

local function bytes(s)
    if (type(s) ~= "string") then
        return tostring(s);
    end
    local t = {};
    for i = 1, #s do
        t[i] = tostring(s:byte(i));
    end
    return table.concat(t, " ");
end

local probeHeader;
local function ProbeHeader()
    if (probeHeader) then
        return probeHeader;
    end
    local header = CreateFrame("Frame", nil, nil, "SecureGroupHeaderTemplate");
    header:Hide();
    local private = _G.DebindPrivate;
    if (private and private.OwnGroupHeaders) then
        private.OwnGroupHeaders[header] = true;
    end
    header:SetAttribute("showParty", true);
    header:SetAttribute("showRaid", true);
    header:SetAttribute("showPlayer", true);
    header:SetAttribute("showSolo", true);
    header:SetAttribute("sortMethod", "NAME");
    header:SetAttribute("maxColumns", 1);
    header:SetAttribute("unitsPerColumn", 40);
    header:SetAttribute("template", "");
    header:SetAttribute("templateType", "Frame");
    for i = 1, 40 do
        header:SetAttribute("child" .. i, CreateFrame("Frame", nil, header));
    end
    probeHeader = header;
    return header;
end

--- Every unit the header filled for this list, so a name two people answer to shows as two.
local function Filled(nameList)
    local header = ProbeHeader();
    header:Hide();
    header:SetAttribute("nameList", nameList);
    header:Show();
    local t = {};
    for i = 1, 40 do
        local unit = header:GetAttribute("child" .. i):GetAttribute("unit");
        if (unit) then
            t[#t + 1] = unit;
        end
    end
    header:Hide();
    return #t > 0 and table.concat(t, ",") or "nobody";
end

SLASH_DEBINDROSTER1 = "/debroster";
SlashCmdList.DEBINDROSTER = function()
    local lines = {};
    local function add(fmt, ...)
        local line = format(fmt, ...);
        lines[#lines + 1] = line;
        print(TAG .. line);
    end

    add("version %s  build %s  IsInRaid %s  IsInGroup %s  GetNumGroupMembers %s  GetNumSubgroupMembers %s",
        VERSION, select(2, GetBuildInfo()), tostring(IsInRaid()), tostring(IsInGroup()),
        tostring(GetNumGroupMembers()), tostring(GetNumSubgroupMembers()));
    local consts = Constants and Constants.CharacterNameSeparatorConsts;
    add("FULL_PLAYER_NAME %s  bytes %s", q(FULL_PLAYER_NAME), bytes(FULL_PLAYER_NAME));
    add("CHARACTERNAME_SURNAME_SEPARATOR %s  bytes %s", q(consts and consts.CHARACTERNAME_SURNAME_SEPARATOR),
        bytes(consts and consts.CHARACTERNAME_SURNAME_SEPARATOR));
    add("UNKNOWNOBJECT %s", q(UNKNOWNOBJECT));
    if (InCombatLockdown()) then
        add("in combat: the header matches below are skipped");
    end

    local private = _G.DebindPrivate;
    -- 1. the roster, index by index, next to the unit at that index
    for i = 1, math.max(GetNumGroupMembers(), 5) do
        local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, assignedRole =
            GetRaidRosterInfo(i);
        local unit = "raid" .. i;
        local n1, n2 = UnitName(unit);
        add("GetRaidRosterInfo(%d) name %s  subgroup %s  class %s  online %s  |  %s UnitName %s, %s  GUID %s  GetUnitFullName %s  UnitInRaid %s",
            i, q(name), q(subgroup), q(fileName), q(online), unit, q(n1), q(n2), q(UnitGUID(unit)),
            private and q(private.GetUnitFullName(unit)) or "n/a", q(UnitInRaid(unit)));
    end

    -- 2. the reader's subgroup tokens, and the raid index each one answers
    for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
        if (UnitExists(unit)) then
            local index = plain(UnitInRaid(unit));
            local same = type(index) == "number" and UnitIsUnit(unit, "raid" .. index);
            add("%s  UnitInRaid %s  UnitIsUnit(%s, raid%s) %s  UnitName %s",
                unit, q(index), unit, tostring(index), q(same), q(UnitName(unit)));
        end
    end

    -- 3. which units each form of each member's name fills, all of them
    if (not InCombatLockdown()) then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i;
            local n1, n2 = UnitName(unit);
            n1, n2 = plain(n1), plain(n2);
            local forms = {};
            local function form(label, value)
                value = plain(value);
                if (type(value) == "string" and value ~= "" and value ~= "<secret>") then
                    forms[#forms + 1] = { label, value };
                end
            end
            form("UnitName first", n1);
            if (type(n1) == "string" and type(n2) == "string" and n2 ~= "") then
                form("UnitName joined by -", n1 .. "-" .. n2);
            end
            form("GetRaidRosterInfo", (GetRaidRosterInfo(i)));
            form("GetUnitFullName", private and private.GetUnitFullName(unit));
            for _, f in ipairs(forms) do
                add("match %-7s %-22s %-32s -> %s", unit, f[1], q(f[2]), Filled(f[2]));
            end
        end
    end

    DebindDevDB = DebindDevDB or {};
    DebindDevDB.raidRoster = { at = date("%Y-%m-%d %H:%M:%S"), version = VERSION, lines = lines };
end;
