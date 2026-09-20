-- Probe_PressHold.lua
-- One-shot probe: **does an empowered spell still charge when the press goes out through a macro?**
--
-- `StampBinding` leaves press-and-hold spells on the direct route, and the reason written
-- down is that one macro run cannot carry the two edges the gate needs. `/click` takes a third
-- token and hands it to `Click(button, down)` (`SlashCommands.lua:728-739`, 12.1), so the two edges
-- can be sent separately after all. What that does not settle is the half below Lua: the gate reads
-- `isKeyPress` but never passes it on, and `SECURE_ACTIONS.spell` is `CastSpellByID` alone
-- (`SecureTemplates.lua:393`). Whether the client counts a cast started inside a macro as one the
-- key is still holding is decided under that, where nothing is readable.
--
-- **A mouse press cannot start one at all, by the client's own design.** `isSecureMousePress` turns
-- `useOnKeyDown` off for a real mouse click, so the gate fires on the up edge and the hold never
-- begins (`SecureTemplates.lua:805-816`, and the comment above it says so in words). The button
-- below is clickable so that answer can be seen rather than taken on trust -- and it is why
-- click-casting is outside this question whichever way the rest lands.
--
-- Four routes, one key each. Every one of them ends at the same spell.
--
--   phDirect  what ships today. `*type-` on this button is the spell itself, no macro in between.
--   phOne     the shape `-nosc` bakes now: one body, `/click` with no edge token. The inner click
--             arrives as up, so this is what "one run cannot carry two edges" looks like.
--   phSplit   the down edge sends `/click ... true` and the up edge `/click ... false`, each from a
--             body the wrapper writes at that edge.
--   phCvar    phSplit with the CVar lines around it, which is the shape the four casting values
--             would actually bake.
--
-- **The answer is one line in the log**: `EMPOWER_START` after the down edge. It charges, or it
-- does not.
--
--   /ph            print the spell and the key map
--   /ph bind       take CTRL-1..CTRL-4 for the four routes
--   /ph unbind     give them back
--   /ph spell <name or id>   aim at a different spell
--
-- Answer found, delete the file and its TOC line.

local TAG = "|cff66ccff[PH]|r ";

local CAST_FRAME = "DebindDevPHCast";
local INNER_BUTTON = "phCast";

local ROUTES = { "phDirect", "phOne", "phSplit", "phCvar" };
local KEYS = { "CTRL-F1", "CTRL-F2", "CTRL-F3", "CTRL-F4" };

local spellID, spellName;
local bound = false;
local lastEdge;

local function Say(...)
    print(TAG .. strjoin(" ", tostringall(...)));
end

--- **Each step says whether it took.** A snippet that fails to compile and a wrap that never
--- happened both end as a key that does nothing, with no error anywhere, which is the one state
--- this probe cannot tell apart from the answer it is looking for.
local function Step(what, fn, ...)
    local ok, err = pcall(fn, ...);
    if (not ok) then
        Say("|cffff4444" .. what .. " failed:|r", err);
    end
    return ok;
end

--- Seconds since the edge that started this press, so the log reads as one press rather than a
--- column of timestamps. Nil before the first press.
local function Since()
    if (not lastEdge) then
        return "-";
    end
    return format("%.3f", GetTime() - lastEdge);
end

---------------------------------------------------------------------------------------------------
-- The spell
---------------------------------------------------------------------------------------------------

--- The first spell in the book the client calls press-and-hold. Same walk `Misc.lua` makes over the
--- player bank.
local function FindEmpoweredSpell()
    local bank = Enum.SpellBookSpellBank.Player;
    for lineIndex = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex);
        if (line) then
            for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, bank);
                if (info and info.spellID and C_Spell.IsPressHoldReleaseSpell(info.spellID)) then
                    return info.spellID;
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------
-- The frames
---------------------------------------------------------------------------------------------------

local header = CreateFrame("Frame", "DebindDevPHHeader", UIParent, "SecureHandlerBaseTemplate");

local button = CreateFrame("Button", "DebindDevPHButton", UIParent, "SecureActionButtonTemplate");
button:SetSize(120, 36);
button:SetPoint("TOP", 0, -140);
button:RegisterForClicks("AnyUp", "AnyDown");
button:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up");
button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal");
button.label:SetPoint("CENTER");
button.label:SetText("PH mouse");

--- **The insecure witness.** The wrapper reports through `CallMethod`, so a restricted environment
--- that never ran and a key that never arrived print the same nothing. This one runs outside that
--- environment and after the click either way.
button:HookScript("OnClick", function(_, arrived, down)
    Say(format("|cff888888hook|r arrived=%s down=%s", tostring(arrived), tostring(down)));
end);

--- Where the inner `/click` lands. No wrapper on it, the way `DebindCastButton` has none, so what
--- the body writes stands until the cast reads it.
---
--- **`pressAndHoldAction` is set here and left set.** It is read bare (`SecureButton_GetAttribute`,
--- `SecureTemplates.lua:812`), so it cannot be told apart per button anyway, and with it on the
--- down click takes `type` and the up click takes `typerelease`.
local castFrame = CreateFrame("Button", CAST_FRAME, nil, "SecureActionButtonTemplate");
castFrame:RegisterForClicks("AnyUp", "AnyDown");
castFrame:SetAttribute("pressAndHoldAction", true);

--- The bodies, as the routes that use one would bake them. Written at the edge by the wrapper, not
--- here: one attribute holds both edges and only the press knows which one it is on.
local DOWN_BODY = "/click " .. CAST_FRAME .. " " .. INNER_BUTTON .. " true";
local UP_BODY = "/click " .. CAST_FRAME .. " " .. INNER_BUTTON .. " false";
local CVAR_DOWN_BODY =
    '/run DebindDevPHSave=GetCVar("autoSelfCast");SetCVar("autoSelfCast","0")\n'
    .. DOWN_BODY .. '\n'
    .. '/run SetCVar("autoSelfCast",DebindDevPHSave)';

local function Stamp()
    local castName = spellName;

    button:SetAttribute("*type-phDirect", "spell");
    button:SetAttribute("*spell-phDirect", castName);
    button:SetAttribute("*typerelease-phDirect", "spell");

    button:SetAttribute("*type-phOne", "macro");
    button:SetAttribute("*macrotext-phOne", "/click " .. CAST_FRAME .. " " .. INNER_BUTTON);

    for _, route in ipairs({ "phSplit", "phCvar" }) do
        button:SetAttribute("*type-" .. route, "macro");
        button:SetAttribute("*typerelease-" .. route, "macro");
    end

    castFrame:SetAttribute("*type-" .. INNER_BUTTON, "spell");
    castFrame:SetAttribute("*spell-" .. INNER_BUTTON, castName);
    castFrame:SetAttribute("*typerelease-" .. INNER_BUTTON, "spell");
end

---------------------------------------------------------------------------------------------------
-- The wrapper
---------------------------------------------------------------------------------------------------

--- Follows `SecureBindings.lua`'s wrapper where the shapes are the same: the bare
--- `pressAndHoldAction` written at the press, the held record settled on the down edge whether or
--- not an up edge ever arrives, and the release going back to what was started rather than picking
--- again. The `PlayerIsChanneling` guard is there for the same measured reason -- `typerelease` is
--- the spell cast a second time, so releasing after the cast has finished fires it again.
local PRESS_BODY = [==[
    owner:CallMethod("Edge", tostring(button), down and 1 or 0)

    local route = button
    if (route ~= "phOne" and route ~= "phSplit" and route ~= "phCvar") then
        route = "phDirect"
    end

    if (not down) then
        if (not (Held and Held[route])) then
            owner:CallMethod("Note", "nothing held on this route")
            return false
        end
        Held[route] = nil
        if (not PlayerIsChanneling()) then
            owner:CallMethod("Note", "release skipped, not channeling")
            return false
        end
        self:SetAttribute("pressAndHoldAction", true)
        if (route == "phSplit" or route == "phCvar") then
            self:SetAttribute("*macrotext-" .. route, UpBody)
        end
        return route
    end

    Held[route] = true
    self:SetAttribute("pressAndHoldAction", true)
    if (route == "phSplit") then
        self:SetAttribute("*macrotext-" .. route, DownBody)
    elseif (route == "phCvar") then
        self:SetAttribute("*macrotext-" .. route, CvarDownBody)
    end
    return route
]==];

--- **The bare name has to go**, for the reason the shipped wrapper says: it is read bare by the
--- gate and inherited by anything that reads through this frame.
local POST_BODY = [==[
    self:SetAttribute("pressAndHoldAction", nil)
]==];

function header:Edge(arrived, down)
    if (down == 1) then
        lastEdge = GetTime();
    end
    Say(format("|cffffff00%s|r  edge=%s  +%s", arrived, down == 1 and "down" or "up", Since()));
end

function header:Note(text)
    Say("  " .. text);
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

local EVENTS = {
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_SENT",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
};

local events = CreateFrame("Frame");
for _, event in ipairs(EVENTS) do
    events:RegisterEvent(event);
end

events:SetScript("OnEvent", function(_, event, unit, ...)
    if (unit ~= "player") then
        return;
    end
    local mark = "";
    if (event == "UNIT_SPELLCAST_EMPOWER_START") then
        mark = "  |cff00ff00<- it charges|r";
    end
    Say(format("  %s  +%s%s", event, Since(), mark));
end);

---------------------------------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------------------------------

local function SetSpell(id)
    if (not id) then
        Say("|cffff4444no press-and-hold spell in the spellbook.|r Name one: /ph spell <이름 또는 id>");
        return;
    end
    spellID = id;
    spellName = C_Spell.GetSpellName(id);
    if (not spellName) then
        Say("|cffff4444unknown spell|r", id);
        spellID = nil;
        return;
    end
    if (not C_Spell.IsPressHoldReleaseSpell(id)) then
        Say("|cffffaa00warning:|r", spellName, "is not a press-and-hold spell, so every route will "
            .. "look the same");
    end
    Stamp();
    Say("spell:", spellName, "(" .. id .. ")");
end

--- **The keys are taken from inside the header**, the way Debind takes every key it holds
--- (`SecureBindings.lua`'s `SetBindings`): `self:SetBindingClick` on the handle, not
--- `SetOverrideBindingClick` from out here. Debind's own rebuild writes the same table from the
--- same side, so this is also the only way the two are on equal footing when they want one key.
local function Bind(prefix)
    prefix = (prefix ~= "" and prefix) or "CTRL";

    local lines = { "self:ClearBindings()" };
    for i, route in ipairs(ROUTES) do
        KEYS[i] = prefix .. "-" .. i;
        lines[#lines + 1] = format("self:SetBindingClick(true, %q, %q, %q)",
            KEYS[i], "DebindDevPHButton", route);
    end

    if (not Step("bind", SecureHandlerExecute, header, table.concat(lines, "\n"))) then
        return;
    end
    bound = true;
    Say("bound.");
    for i, route in ipairs(ROUTES) do
        local action = GetBindingAction(KEYS[i], true) or "";
        local mine = strfind(action, "DebindDevPHButton", 1, true) ~= nil;
        Say(format("  %-10s %-8s %s%s|r", KEYS[i], route,
            mine and "|cff00ff00" or "|cffff4444", action ~= "" and action or "(none)"));
    end
    Say("  mouse    click the on-screen button (this one cannot start a hold, by design)");
end

local function Unbind()
    Step("unbind", SecureHandlerExecute, header, "self:ClearBindings()");
    bound = false;
    Say("unbound.");
end

SLASH_DEBINDDEVPH1 = "/ph";
SlashCmdList["DEBINDDEVPH"] = function(msg)
    local cmd, rest = strmatch(strtrim(msg or ""), "^(%S*)%s*(.*)$");
    if (cmd == "bind") then
        Bind(strtrim(rest or ""));
    elseif (cmd == "unbind") then
        Unbind();
    elseif (cmd == "keys") then
        local on = not watcher:IsKeyboardEnabled();
        watcher:EnableKeyboard(on);
        Say("key watcher:", on and "on" or "off");
    elseif (cmd == "click") then
        button:Click("phDirect", true);
    elseif (cmd == "spell") then
        SetSpell(tonumber(rest) or (rest ~= "" and select(1, C_Spell.GetSpellIDForSpellIdentifier(rest))));
    else
        Say("spell:", spellName or "-", spellID and ("(" .. spellID .. ")") or "",
            "| bound:", bound and "yes" or "no");
        Say("  /ph bind | /ph unbind | /ph spell <이름 또는 id>");
    end
end;

---------------------------------------------------------------------------------------------------

local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_LOGIN");
loader:SetScript("OnEvent", function()
    Step("execute", SecureHandlerExecute, header, [==[
        Held = newtable()
        DownBody = ]==] .. format("%q", DOWN_BODY) .. [==[

        UpBody = ]==] .. format("%q", UP_BODY) .. [==[

        CvarDownBody = ]==] .. format("%q", CVAR_DOWN_BODY) .. [==[

    ]==]);
    Step("wrap", SecureHandlerWrapScript, button, "OnClick", header, PRESS_BODY, POST_BODY);
    SetSpell(FindEmpoweredSpell());
    Say("ready. /ph bind");
end);
