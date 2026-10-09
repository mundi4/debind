-- Probe_PetBattleButtons.lua
-- Probe: what is the earliest moment the pet battle buttons can be put on a secure button as
-- `*clickbutton-`, insecurely and out of lockdown, on a first battle and on a `/reload` in the
-- middle of one? An action button action is to press them through `SECURE_ACTIONS.click` the way
-- `Probe_ActionBars.lua` did on 2026-09-14.
--
-- The five buttons are `PetBattleFrame.BottomFrame.abilityButtons[1..3]`, `SwitchPetButton` and
-- `CatchButton`. Read in `Blizzard_PetBattleUI.lua`, not measured: the last two come with the XML,
-- the first three are made by `PetBattleFrame_UpdateActionBarLayout`, which only
-- `PET_BATTLE_OPENING_START` reaches, and nothing ever clears them.
--
-- No slash command. It records from load to logout into `DebindDevDB.petBattleButtons`, one entry
-- per session, the last `KEEP` sessions kept. Each line is
--   <frame> <GetTime> <point> | <values>
-- where a point is an event, a post-hook on one of Blizzard's functions, the next frame after
-- `PET_BATTLE_OPENING_START`, or `(sample)`, written only on a frame where a value moved. A point
-- tries the stamp on this probe's own button; a sample only looks.
--
-- Values: `lock` `InCombatLockdown()`, `battle` `C_PetBattles.IsInBattle()`, `[petbattle]` the
-- macro conditional, `PBF` whether `PetBattleFrame` is shown, then per button
--   <id>:<S|s shown><E|e enabled>:<stamp>
-- `<id>` is `#n`, numbered by this session in the order first seen, so the same number in two
-- battles is the same frame. `<stamp>` is `ok` (the attribute read back as that frame), `L`
-- (lockdown, not tried), `ERR ...`, or `-` on a sample. `x` is a button that does not exist.
--
-- To run: enter a pet battle, play a turn, finish it; enter another; `/reload` in the middle of a
-- third and play it out. Then log out or `/reload` once more so the session is written.
--
-- To read: the first line where each of the five shows `ok`, and what point it is; whether the
-- hook lines come before or after this probe's own `PET_BATTLE_OPENING_START` line, which is the
-- order of Blizzard's handler against an addon's; after the `/reload`, whether
-- `PET_BATTLE_OPENING_START` and the layout hook come again; and whether `#n` repeats across
-- battles.

local KEEP = 5;

--- Per session. Samples are written only on a change, so this guards against something flapping
--- every frame rather than budgeting an ordinary session.
local LIMIT = 20000;

local EVENTS = {
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PET_BATTLE_OPENING_START",
    "PET_BATTLE_OPENING_DONE",
    "PET_BATTLE_OVER",
    "PET_BATTLE_CLOSE",
};

local BUTTONS = { "a1", "a2", "a3", "sw", "ca" };

local function Buttons()
    local bottom = PetBattleFrame and PetBattleFrame.BottomFrame;
    if (not bottom) then
        return {};
    end
    local ability = bottom.abilityButtons or {};
    return { a1 = ability[1], a2 = ability[2], a3 = ability[3],
        sw = bottom.SwitchPetButton, ca = bottom.CatchButton };
end

local ids = setmetatable({}, { __mode = "k" });
local nextId = 0;

local function Id(frame)
    local id = ids[frame];
    if (not id) then
        nextId = nextId + 1;
        id = nextId;
        ids[frame] = id;
    end
    return "#" .. id;
end

--- Built the way `DefaultClickFrame` is, so a stamp that takes here takes there.
local stampButton = CreateFrame("Button", "DebindDevPetBattleStamp", UIParent, "SecureActionButtonTemplate");

local function Stamp(key, frame)
    if (InCombatLockdown()) then
        return "L";
    end
    local attribute = "*clickbutton-pb" .. key;
    local ok, err = pcall(stampButton.SetAttribute, stampButton, attribute, frame);
    if (not ok) then
        return "ERR " .. tostring(err);
    end
    if (stampButton:GetAttribute(attribute) ~= frame) then
        return "ERR readback " .. tostring(stampButton:GetAttribute(attribute));
    end
    return "ok";
end

local function Flag(value)
    return value and "T" or "F";
end

local function Sample(stamp)
    local parts = { format("lock=%s battle=%s [petbattle]=%s PBF=%s",
        Flag(InCombatLockdown()),
        Flag(C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()),
        Flag(SecureCmdOptionParse("[petbattle] 1") == "1"),
        PetBattleFrame and Flag(PetBattleFrame:IsShown()) or "x") };
    local buttons = Buttons();
    for _, key in ipairs(BUTTONS) do
        local frame = buttons[key];
        if (frame) then
            parts[#parts + 1] = format("%s=%s:%s%s:%s", key, Id(frame),
                frame:IsShown() and "S" or "s", frame:IsEnabled() and "E" or "e",
                stamp and Stamp(key, frame) or "-");
        else
            parts[#parts + 1] = key .. "=x";
        end
    end
    return table.concat(parts, " ");
end

--- Bumped once per `OnUpdate`, which runs exactly once a frame, so a point line carrying N arrived
--- after sample N. Whether it shares a frame with sample N or N+1 is read off `GetTime()`, which
--- holds one value for a whole frame.
local frameIndex = 0;

--- Filled from load, before `DebindDevDB` exists; `ADDON_LOADED` hands it to the saved table.
local lines = {};
local last;

local function Record(point, sample)
    if (#lines >= LIMIT) then
        return;
    end
    lines[#lines + 1] = format("%d %.3f %s | %s", frameIndex, GetTime(), point, sample);
end

local function Point(point)
    local sample = Sample(true);
    last = Sample(false);
    Record(point, sample);
end

--- `hooksecurefunc` on the global, so a caller that looks the name up when it runs reaches the
--- hook. Which of these the XML's `function=` attribute reaches is part of what is read.
local hooksAt;

local function InstallHooks(point)
    if (hooksAt or type(PetBattleFrame_UpdateActionBarLayout) ~= "function") then
        return;
    end
    hooksAt = point;
    Record("hooks installed at " .. point, Sample(false));
    hooksecurefunc("PetBattleFrame_Display", function()
        Point("post PetBattleFrame_Display");
    end);
    hooksecurefunc("PetBattleFrame_UpdateActionBarLayout", function()
        Point("post PetBattleFrame_UpdateActionBarLayout");
    end);
    hooksecurefunc("PetBattleFrame_UpdateActionButtonLevel", function(_, button)
        Point("post PetBattleFrame_UpdateActionButtonLevel(" .. (button and Id(button) or "nil") .. ")");
    end);
    -- Inside `CreateFrame`, before `abilityButtons[i]` is assigned, so the button is stamped from
    -- the argument: the earliest a frame can be had at all.
    hooksecurefunc("PetBattleAbilityButton_OnLoad", function(button)
        Point(format("post PetBattleAbilityButton_OnLoad(%s id=%s stamp=%s)",
            button and Id(button) or "nil", button and tostring(button:GetID()) or "-",
            button and Stamp("onload", button) or "-"));
    end);
    -- Whatever plays the turn, so a turn played after the `/reload` shows whether it went out.
    for _, name in ipairs({ "UseAbility", "UseTrap", "ChangePet", "SkipTurn" }) do
        if (C_PetBattles[name]) then
            hooksecurefunc(C_PetBattles, name, function(...)
                local args = {};
                for i = 1, select("#", ...) do
                    args[i] = tostring((select(i, ...)));
                end
                Record("C_PetBattles." .. name .. "(" .. table.concat(args, ",") .. ")", Sample(false));
            end);
        end
    end
end

local probe = CreateFrame("Frame");

probe:SetScript("OnUpdate", function()
    frameIndex = frameIndex + 1;
    local sample = Sample(false);
    if (sample ~= last) then
        last = sample;
        Record("(sample)", sample);
    end
end);

probe:SetScript("OnEvent", function(_, event, ...)
    if (event == "ADDON_LOADED") then
        local name = ...;
        if (name == "DebindDev") then
            DebindDevDB = DebindDevDB or {};
            local sessions = DebindDevDB.petBattleButtons;
            if (type(sessions) ~= "table") then
                sessions = {};
                DebindDevDB.petBattleButtons = sessions;
            end
            sessions[#sessions + 1] = { at = date("%Y-%m-%d %H:%M:%S"),
                build = select(2, GetBuildInfo()), lines = lines };
            while (#sessions > KEEP) do
                table.remove(sessions, 1);
            end
        end
        -- Every addon, so the line for `Blizzard_PetBattleUI`, if one comes, says whether it
        -- loaded after this file.
        Point("ADDON_LOADED(" .. tostring(name) .. ")");
        InstallHooks("ADDON_LOADED(" .. tostring(name) .. ")");
        return;
    end
    Point(event);
    if (event == "PET_BATTLE_OPENING_START") then
        C_Timer.After(0, function()
            Point("next frame after PET_BATTLE_OPENING_START");
        end);
    end
end);

probe:RegisterEvent("ADDON_LOADED");
for _, event in ipairs(EVENTS) do
    probe:RegisterEvent(event);
end

Point("load");
InstallHooks("load");
