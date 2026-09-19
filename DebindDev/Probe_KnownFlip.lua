-- Probe_KnownFlip.lua
-- One-shot probe: can `[known:]` change its answer **inside a fight**, and does any event say so?
--
-- `Void Volley` is the case. It replaces another spell dynamically while a buff stands, so the
-- spell a press would reach moves mid-combat. Everything baked out of the level table assumes the
-- opposite: `baking-the-known-condition.md` §3 rests on "a learned spell cannot be
-- forgotten and a talent cannot be taken in combat", and `UpdateBindings.lua` settles the axis away
-- on the strength of it. One spell that flips under a buff is a counterexample to the whole table.
--
-- **The events are the second half of the question.** The state loop only re-measures `known` on
-- `SPELLS_CHANGED` (`UpdateBindings.lua`'s `CollectEvents`), so a flip carrying no event it listens
-- to is a key that goes quietly wrong until the next rebuild.
--   SPELLS_CHANGED               what we listen to today
--   LEARNED_SPELL_IN_SKILL_LINE  the spellbook's own "a spell was learned" (`Blizzard_SpellBookFrame.lua`)
--   COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED
--                                a base spell gaining or losing an override, which is what a
--                                buff-driven replacement *is*. Its payload names both ids, so the
--                                line says which spell moved. Owned by the cooldown viewer in name
--                                only; it is a game event like any other.
--   SPELL_UPDATE_ICON            what the action bar redraws an overridden button on
--                                (`ActionButton.lua`), in case the one above is the viewer's alone
--
-- **There is no `SPELL_OVERRIDE_UPDATED`.** Registering it raises, and the name came out of a grep
-- that had cut the `COOLDOWN_VIEWER_` off the front of the real one (2026-09-12).
--
-- **A poll runs beside them, and that is what makes a silent flip visible.** Without it "no event
-- fired" and "nothing changed" print the same thing, which is nothing. The poll prints only when
-- the measured values move, so a line tagged `(poll)` with no event line next to it is the answer
-- this probe was written to catch.
--
-- `combat` is inside the measured tuple rather than on two more events: a combat boundary that
-- changes nothing still prints one line, which is what dates the rest of the log.
--
-- Answer found, delete the file and its TOC line.

--- The spell under the glass. A name or an id; `/kf <이름 또는 id>` retargets without a reload,
--- because this client's own name is what `[known:<이름>]` has to be given.
local TARGET = "Void Volley";

local SAMPLE_PERIOD = 0.1;

local PLAYER_BANK = Enum.SpellBookSpellBank.Player;

--- `spellID -> cooldownID` for every spell the cooldown viewer's own table holds, learned or not,
--- across every category. **Turning the viewer off is not the same question as the table not
--- holding the spell**, and only the second one would explain the event never firing: the name is
--- the viewer's but the table is the client's. `linkedSpellIDs` and `overrideSpellID` are in here
--- too, because a base spell and the thing that replaces it are separate ids and either one could
--- be what the event names.
---
--- Built on demand and dropped on the two events that can move it, rather than per sample: the walk
--- is a call per cooldown id and the poll runs ten times a second.
local cooldownIDs;

local function CooldownViewerTable()
    if (cooldownIDs ~= nil) then
        return cooldownIDs;
    end
    cooldownIDs = {};
    if (C_CooldownViewer == nil) then
        return cooldownIDs;
    end
    for _, category in pairs(Enum.CooldownViewerCategory) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(category, true) or {};
        for i = 1, #ids do
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(ids[i]);
            if (info) then
                local linked = info.linkedSpellIDs or {};
                for j = 1, #linked do
                    cooldownIDs[linked[j]] = ids[i];
                end
                if (info.overrideSpellID) then
                    cooldownIDs[info.overrideSpellID] = ids[i];
                end
                if (info.spellID) then
                    cooldownIDs[info.spellID] = ids[i];
                end
            end
        end
    end
    return cooldownIDs;
end

local function Mark(value)
    if (value == nil) then
        return "-";
    end
    return value and "T" or "F";
end

--- The name and the id the probe is asking about, off whatever `TARGET` is. **Resolved every
--- sample and not once**: `GetSpellIDForSpellIdentifier` is documented to follow the override when
--- it is handed a name, so the id it answers is itself one of the things that can move.
local function Resolve()
    if (type(TARGET) == "number") then
        return C_Spell.GetSpellName(TARGET), TARGET;
    end
    return TARGET, C_Spell.GetSpellIDForSpellIdentifier(TARGET);
end

--- One sample, as the line it prints. **Both spellings of the conditional**, because the plan on
--- the table is to bake the name and everything measured so far was baked from an id
--- (`resolving-a-stored-spell-id.md`).
---
--- The three book questions are not one question asked three times. The client's own documentation
--- parts them: `IsSpellInSpellBook` "can also return true for spells that aren't known, such as
--- override spells granted by an aura linked to class talents", and `IsSpellKnown` "can also return
--- true for spells that aren't in the spellbook, such as temporarily-granted abilities". A spell
--- that arrives under a buff is exactly what those two sentences are about.
local function Sample()
    local name, id = Resolve();

    local byName = name and SecureCmdOptionParse("[known:" .. name .. "]");
    local byID = id and SecureCmdOptionParse("[known:" .. id .. "]");

    local known, book, bookNoOverride, knownOrBook, slot, base, override;
    if (id) then
        known = C_SpellBook.IsSpellKnown(id, PLAYER_BANK);
        book = C_SpellBook.IsSpellInSpellBook(id, PLAYER_BANK, true);
        bookNoOverride = C_SpellBook.IsSpellInSpellBook(id, PLAYER_BANK, false);
        knownOrBook = C_SpellBook.IsSpellKnownOrInSpellBook(id, PLAYER_BANK, true);
        slot = C_SpellBook.FindSpellBookSlotForSpell(id) ~= nil;
        base = C_SpellBook.FindBaseSpellByID(id);
        override = C_SpellBook.FindSpellOverrideByID(id);
    end

    return format(
        "%s combat=%s | name=%s id=%s(%s) known=%s book=%s bookNoOvr=%s knownOrBook=%s slot=%s base=%s ovr=%s",
        tostring(name), Mark(InCombatLockdown() and true or false),
        Mark(byName and true or false), Mark(byID and true or false), tostring(id),
        Mark(known), Mark(book), Mark(bookNoOverride), Mark(knownOrBook), Mark(slot),
        tostring(base), tostring(override));
end

local last;

--- `onlyOnChange` is what keeps the log readable. `SPELL_UPDATE_ICON` fires on a great deal more
--- than an override (`ActionButton.lua` redraws every button on it, and a nil payload means "all of
--- them"), so it prints only when it moved something this probe is measuring. The other two are
--- rare enough to be worth a line even when they changed nothing, because "it fired and the answer
--- did not move" is itself a finding.
local function Report(tag, onlyOnChange)
    local line = Sample();
    if (onlyOnChange and line == last) then
        return;
    end
    last = line;
    print(format("[KF] %.3f %s %s", GetTime(), tag, line));
end

local QUIET = {
    SPELL_UPDATE_ICON = true,
};

local frame = CreateFrame("Frame");
frame:RegisterEvent("SPELLS_CHANGED");
frame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE");
frame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED");
frame:RegisterEvent("SPELL_UPDATE_ICON");
frame:SetScript("OnEvent", function(_, event, a, b)
    -- The payload rides in the tag: both of the events that carry one name spell ids, and which id
    -- moved is half of what separates "our spell flipped" from "something else in the book did".
    local tag = event;
    if (a ~= nil or b ~= nil) then
        tag = format("%s(%s,%s)", event, tostring(a), tostring(b));
    end
    Report(tag, QUIET[event]);
end);

local elapsed = 0;
frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta;
    if (elapsed < SAMPLE_PERIOD) then
        return;
    end
    elapsed = 0;
    Report("(poll)", true);
end);

SLASH_DEBINDKF1 = "/kf";
SlashCmdList.DEBINDKF = function(msg)
    local arg = msg and strtrim(msg);
    if (arg and arg ~= "") then
        TARGET = tonumber(arg) or arg;
    end
    Report("(ask)");
end;
