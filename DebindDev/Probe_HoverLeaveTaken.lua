-- Probe_HoverLeaveTaken.lua
-- One-shot probe: does the pack that wraps over our OnLeave actually do it on this board, and
-- did we notice. Delete the file and its TOC line once the answer stops being interesting.
--
-- What it prints, once, a moment after login:
--   1. whether that pack is loaded at all
--   2. whether its own click casting is switched on, which is what makes it wrap our frames
--   3. how many frames we hold, and how many we turned away
--
-- **Whether anybody actually wrapped over us is not here**, because the addon says so itself the
-- moment it happens: one line to the reader, at the moment the first frame is taken over. This is
-- the surrounding picture -- what was loaded, what it was set to, how many frames we ended up
-- holding -- which is what the line alone cannot say.

local ADDONS = { "EllesmereUI", "EllesmereUIUnitFrames", "EllesmereUIRaidFrames" };

--- **Their layout is not ours to know, so the setting is searched for rather than pathed to.**
--- `clickCast` sits somewhere under their saved variables and nothing says it stays there. A walk
--- bounded in depth finds it wherever it moved to, and answers nil rather than guessing when it is
--- gone. Depth is capped because a saved-variable table holds profiles per character and per spec.
local function FindClickCast(tbl, depth, seen)
    if (type(tbl) ~= "table" or depth > 4 or seen[tbl]) then
        return nil;
    end
    seen[tbl] = true;

    local found = rawget(tbl, "clickCast");
    if (type(found) == "table") then
        return found;
    end

    for _, v in pairs(tbl) do
        local hit = FindClickCast(v, depth + 1, seen);
        if (hit) then
            return hit;
        end
    end
    return nil;
end

local function Report()
    local DebindPrivate = _G.DebindPrivate;
    if (not DebindPrivate) then
        print("|cff88ccff[Debind/probe]|r Debind is not up, nothing to count");
        return;
    end

    local loaded = {};
    for i = 1, #ADDONS do
        if (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(ADDONS[i])) then
            loaded[#loaded + 1] = ADDONS[i];
        end
    end

    if (#loaded == 0) then
        print("|cff88ccff[Debind/probe]|r that pack is not on this board");
        return;
    end
    print(format("|cff88ccff[Debind/probe]|r loaded: %s", table.concat(loaded, ", ")));

    local cc = FindClickCast(_G.EllesmereUIDB, 1, {});
    if (not cc) then
        print("|cff88ccff[Debind/probe]|r no clickCast table in their saved variables");
    else
        print(format("|cff88ccff[Debind/probe]|r their click casting: enabled=%s allFrames=%s downClick=%s",
            tostring(cc.enabled), tostring(cc.allFrames), tostring(cc.downClick)));
    end

    -- **Counted off the insecure rows, which is where a refusal shows too.** `false` is a frame we
    -- turned away and it is not the same as a frame we never saw; a run where those two are
    -- confused reads as "we registered nothing" when we in fact refused everything.
    local rows, refused = 0, 0;
    for _, info in pairs(DebindPrivate.ccframes) do
        if (info == false) then
            refused = refused + 1;
        elseif (type(info) == "table") then
            rows = rows + 1;
        end
    end

    print(format("|cff88ccff[Debind/probe]|r frames: %d registered, %d refused",
        rows, refused));
end

--- **`PLAYER_ENTERING_WORLD` and then a tick**, because the count is the point: that pack wires its
--- frames from its own `PLAYER_LOGIN` handler, and our doors fire inside those calls. Reading on
--- the same event would report whatever had happened so far rather than the settled answer.
local watcher = CreateFrame("Frame");
watcher:RegisterEvent("PLAYER_ENTERING_WORLD");
watcher:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents();
    self:SetScript("OnEvent", nil);
    C_Timer.After(0, Report);
end);

SLASH_DEBHOVERLEAVE1 = "/debhoverleave";
SlashCmdList["DEBHOVERLEAVE"] = Report;
