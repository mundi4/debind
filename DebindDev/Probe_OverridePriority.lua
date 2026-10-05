-- Probe_OverridePriority.lua
-- One-shot probe: when two owners hold an override on the same key, which one does the client answer?
--
-- The self and focus chords are about to go on at priority false
-- (`handing-the-rest-of-a-key-to-the-game.md` 2-4), so that another addon's override wins over them.
-- That rests on two things nobody has measured: that priority true beats priority false whatever
-- order the two were set in, and what decides between two at the same priority. VuhDo passes `0`
-- for the priority, which Lua reads as true and the client may not. The second run adds what the
-- first could not tell apart: whether the order the owner frames were made in decides instead of the
-- priority, and whether a hidden owner's override still answers. The third asks whether the owner's
-- strata or frame level takes part.
--
-- Needs no other addon: the owners are this probe's own frames, both set from insecure code and from
-- the restricted environment (a header's `self:SetBindingClick`), which reach the same client call.
--
--   /debop          run every case, out of combat (wipes the previous log)
--   /debop show     print the log, this session's or the one saved before a reload
--
-- Answer found, delete the file and its TOC line.

local TAG = "|cffff9900[OP]|r ";
local KEY = "ALT-CTRL-SHIFT-F12";

local function Owner(name)
    local frame = CreateFrame("Frame", name, UIParent, "SecureHandlerBaseTemplate");
    return frame;
end

local function Target(name)
    return CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate");
end

local A, B, C = Owner("DebindProbeOPOwnerA"), Owner("DebindProbeOPOwnerB"), Owner("DebindProbeOPOwnerC");
local targets = { [A] = Target("DebindProbeOPTargetA"), [B] = Target("DebindProbeOPTargetB"),
    [C] = Target("DebindProbeOPTargetC") };
local letter = { [A] = "A", [B] = "B", [C] = "C" };

local function Winner()
    local action = GetBindingAction(KEY, true) or "";
    for owner, target in pairs(targets) do
        if (action == "CLICK " .. target:GetName() .. ":LeftButton") then
            return letter[owner];
        end
    end
    return action == "" and "none" or ("other:" .. action);
end

local function ClearAll()
    ClearOverrideBindings(A);
    ClearOverrideBindings(B);
    ClearOverrideBindings(C);
    for _, owner in ipairs({ A, B, C }) do
        owner:Show();
        owner:SetFrameStrata("MEDIUM");
        owner:SetFrameLevel(1);
    end
end

--- One override, from insecure code or from the restricted environment.
local function Set(owner, priority, restricted)
    local target = targets[owner]:GetName();
    if (restricted) then
        SecureHandlerExecute(owner, format("self:SetBindingClick(%s, %q, %q)", tostring(priority), KEY,
            target));
    else
        SetOverrideBindingClick(owner, priority, KEY, target);
    end
end

local log;

local function Record(line)
    log[#log + 1] = line;
    print(TAG .. line);
end

--- Sets each step in order and records who answers after the last, then after the winner is cleared.
--- A step `{ owner, "hide" }` hides that owner instead of setting an override on it.
local function Case(name, steps)
    ClearAll();
    local parts = {};
    for i = 1, #steps do
        local step = steps[i];
        if (step[2] == "hide") then
            step[1]:Hide();
            parts[#parts + 1] = format("%s:hide", letter[step[1]]);
        elseif (step[2] == "strata") then
            step[1]:SetFrameStrata(step[3]);
            parts[#parts + 1] = format("%s:%s", letter[step[1]], step[3]);
        elseif (step[2] == "level") then
            step[1]:SetFrameLevel(step[3]);
            parts[#parts + 1] = format("%s:lv%d", letter[step[1]], step[3]);
        else
            Set(step[1], step[2], step[3]);
            parts[#parts + 1] = format("%s:%s%s", letter[step[1]], tostring(step[2]),
                step[3] and "(r)" or "");
        end
    end
    local winner = Winner();
    local afterClear = "-";
    for owner, l in pairs(letter) do
        if (l == winner) then
            ClearOverrideBindings(owner);
            afterClear = Winner();
        end
    end
    Record(format("%-34s set %-30s -> %-6s cleared -> %s", name, table.concat(parts, " then "), winner,
        afterClear));
    ClearAll();
end

local function Run()
    if (InCombatLockdown()) then
        print(TAG .. "out of combat only");
        return;
    end
    if (GetBindingAction(KEY) ~= "") then
        print(TAG .. KEY .. " is bound in the game; clear it or change KEY");
        return;
    end
    DebindDevDB = DebindDevDB or {};
    log = {};
    DebindDevDB.overridePriority = { at = date("%Y-%m-%d %H:%M:%S"), build = select(4, GetBuildInfo()),
        lines = log };

    Case("false then true", { { A, false }, { B, true } });
    Case("true then false", { { B, true }, { A, false } });
    Case("false then false", { { A, false }, { C, false } });
    Case("false then false, reversed", { { C, false }, { A, false } });
    Case("true then true", { { A, true }, { B, true } });
    Case("true then true, reversed", { { B, true }, { A, true } });
    Case("0 then false", { { A, 0 }, { C, false } });
    Case("false then 0", { { C, false }, { A, 0 } });
    Case("0 then true", { { A, 0 }, { B, true } });
    Case("true then 0", { { B, true }, { A, 0 } });
    Case("restricted false then true", { { A, false, true }, { B, true, true } });
    Case("restricted true then false", { { B, true, true }, { A, false, true } });
    Case("restricted false then false", { { A, false, true }, { C, false, true } });
    Case("restricted false then false, rev", { { C, false, true }, { A, false, true } });
    Case("insecure false, restricted true", { { A, false }, { B, true, true } });
    Case("restricted true, insecure false", { { B, true, true }, { A, false } });

    -- The owners were made A, B, C in that order, and every `true` above sat on B, made after A.
    -- These put `true` on the first made and `false` on the last, so creation order and priority
    -- point opposite ways.
    Case("first-made true, last-made false", { { A, true }, { C, false } });
    Case("last-made false, first-made true", { { C, false }, { A, true } });

    -- Whether an owner's override still answers while the owner frame is hidden.
    Case("true owner hidden after", { { A, false }, { B, true }, { B, "hide" } });
    Case("true owner hidden before", { { B, "hide" }, { A, false }, { B, true } });
    Case("lone owner hidden after", { { A, false }, { A, "hide" } });
    Case("lone owner hidden before", { { A, "hide" }, { A, false } });
    Case("same priority, last set hidden", { { A, false }, { C, false }, { C, "hide" } });

    -- Whether the owner frame's strata or level decides between two at the same priority, which
    -- otherwise goes to the one set last. Each pair puts the high frame first and the low one last,
    -- then the other way round.
    Case("strata HIGH set first, BG last", { { A, "strata", "HIGH" }, { C, "strata", "BACKGROUND" },
        { A, false }, { C, false } });
    Case("strata BG set first, HIGH last", { { A, "strata", "BACKGROUND" }, { C, "strata", "HIGH" },
        { A, false }, { C, false } });
    Case("level 100 set first, 1 last", { { A, "level", 100 }, { C, "level", 1 }, { A, false }, { C, false } });
    Case("level 1 set first, 100 last", { { A, "level", 1 }, { C, "level", 100 }, { A, false }, { C, false } });
    Case("strata HIGH true vs BG false", { { A, "strata", "BACKGROUND" }, { C, "strata", "HIGH" },
        { A, true }, { C, false } });

    print(TAG .. format("%d cases in DebindDevDB.overridePriority", #log));
end

local function Show()
    local saved = DebindDevDB and DebindDevDB.overridePriority;
    if (not saved or not saved.lines or #saved.lines == 0) then
        print(TAG .. "no log");
        return;
    end
    print(TAG .. format("%s build %s, %d lines", saved.at or "?", tostring(saved.build), #saved.lines));
    for i = 1, #saved.lines do
        print(saved.lines[i]);
    end
end

SLASH_DEBINDOP1 = "/debop";
SlashCmdList.DEBINDOP = function(msg)
    msg = strlower(strtrim(msg or ""));
    if (msg == "show") then
        Show();
    else
        Run();
    end
end;
