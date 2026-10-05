-- Probe_FormNil.lua
-- One-shot probe: does GetShapeshiftForm() return nil while the client is loading?
--
--   /debform        print what was recorded
--   /debform wipe   clear the record
--
-- Records only the transitions between nil and non-nil, so a long nil run is two lines, with the
-- number of frames it lasted. Each line carries the last loading event seen before it.

local T0 = GetTimePreciseSec()
local frameIndex = 0
local lastEvent = "(file load)"
local log = {}

local wasNil = nil
local nilSince = nil

local function Record(text)
    log[#log + 1] = format("%6d  %9.2f  %-32s  %s",
        frameIndex, (GetTimePreciseSec() - T0) * 1000, lastEvent, text)
end

local function Sample()
    local form = GetShapeshiftForm()
    local isNil = (form == nil)
    if (isNil == wasNil) then
        return
    end
    if (isNil) then
        nilSince = frameIndex
        Record("|cffff4444nil|r")
    else
        local span = nilSince and format(" (nil for %d frames)", frameIndex - nilSince) or ""
        Record(tostring(form) .. span)
        nilSince = nil
    end
    wasNil = isNil
end

-- The file-load sample is the first answer: it is ahead of every event and every OnUpdate.
Sample()

local probe = CreateFrame("Frame")
probe:SetScript("OnUpdate", function()
    frameIndex = frameIndex + 1
    Sample()
end)

-- Sampling in the handler too, because an event can arrive and the value can flip back before
-- the next OnUpdate sees it.
probe:SetScript("OnEvent", function(_, event, arg1)
    lastEvent = arg1 ~= nil and (event .. " " .. tostring(arg1)) or event
    Sample()
    if (event == "PLAYER_ENTERING_WORLD") then
        C_Timer.After(1, function()
            SlashCmdList["DEBFORM"]("")
        end)
    end
end)
for _, event in ipairs({
    "ADDON_LOADED",
    "VARIABLES_LOADED",
    "SPELLS_CHANGED",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "LOADING_SCREEN_ENABLED",
    "LOADING_SCREEN_DISABLED",
    "UPDATE_SHAPESHIFT_FORMS",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_SPECIALIZATION_CHANGED",
}) do
    probe:RegisterEvent(event)
end

SLASH_DEBFORM1 = "/debform"
SlashCmdList["DEBFORM"] = function(msg)
    msg = strlower(strtrim(msg or ""))
    if (msg == "wipe") then
        wipe(log)
        print("|cffff9900[FormNil]|r cleared")
        return
    end
    print(format("|cffff9900[FormNil]|r %d lines", #log))
    print("|cff808080 frame      t(ms)  last event                        form|r")
    for i = 1, #log do
        print(log[i])
    end
end
