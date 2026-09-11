-- Probe_SpellDisposition.lua
-- One-shot probe: what the three disposition questions answer for every spell in the book and in
-- the talent tree, and for every override those spells can reach.
--
-- `IsSpellHelpful` / `IsSpellHarmful` answered false to both for Penance (47540) and for
-- Resurrection (2006) on a priest (2026-09-11, owner), which is what `adding-hover-and-mouseover-cast.md`
-- §1 was built on. `C_ClickBindings.CanSpellBeClickBound` is the predicate Blizzard's own spellbook
-- highlights with (`Blizzard_SpellBookItem.lua:469`), so it goes in the same row for comparison.
--
-- **Overrides are listed under their base, one per line, opening with `--`.** `onlyKnown=false`
-- asks for the candidates no form or buff has brought up yet, and `ignoreOverrideSpellID` walks the
-- chain by taking the last answer out of the running.
--
-- **The talent tree is where most of the overrides live**, so it is swept first and every spell it
-- names is remembered. A spellbook row whose spell came from the tree carries `*talent`.
--
-- **The output goes into the copy dialog, not the chat frame.** A paste out of chat arrived with
-- the first 121 talent rows already gone. `DebindCopyFrame:ShowText` is the box the export side
-- hands its string over in (`StorageUI.lua`), and it comes up selected with the cursor in it.
--
-- Answer found, delete the file and its TOC line.

local MAX_CHAIN = 8;

--- Which spells the talent tree names, as `spellID -> true`. Filled before the book is walked.
local TalentSpells = {};

--- Every line the sweep makes. Joined once at the end.
local Lines = {};

local function Emit(s)
    Lines[#Lines + 1] = s;
end

local function Ask(id)
    local bind = C_ClickBindings and C_ClickBindings.CanSpellBeClickBound(id);
    return (bind and "T" or "F"),
        (C_Spell.IsSpellHelpful(id) and "T" or "F"),
        (C_Spell.IsSpellHarmful(id) and "T" or "F");
end

local function Row(prefix, id, name, marks)
    local passive = C_Spell.IsSpellPassive(id) and "P" or "-";
    local talent = TalentSpells[id] and "T" or "-";
    local bind, help, harm = Ask(id);

    -- **Both resolvers on every row, not only on the overrides.** The first pass asked them only
    -- where `GetOverrideSpell` had answered, so five rows agreeing was the whole evidence that they
    -- agree at all. A row where they part is what this is looking for.
    local spellBase = C_SpellBook.FindBaseSpellByID(id);
    local spellBase2 = C_Spell.GetBaseSpell(id);
    local base = "";
    if (spellBase ~= spellBase2) then
        base = format(" *SPLIT findbase=%s getbase=%s", tostring(spellBase), tostring(spellBase2));
    elseif (spellBase and spellBase ~= id) then
        base = format(" *base %d %s", spellBase, tostring(C_Spell.GetSpellName(spellBase)));
    end

    Emit(format("%s%d %s | %s%s | %s %s %s%s%s",
        prefix, id, tostring(name), passive, talent, bind, help, harm, base, marks));
end

--- Every override the base can reach. The walk takes whatever comes back and asks again with that
--- one out of the running, so the order is the client's. `seen` is what stops a pair that points
--- at each other from spinning.
local function Overrides(base, applied)
    local known = C_Spell.GetOverrideSpell(base, 0, true, 0);
    local seen = {};
    local ignore = 0;

    for _ = 1, MAX_CHAIN do
        local id = C_Spell.GetOverrideSpell(base, 0, false, ignore);
        if (not id or id == base or seen[id]) then
            return;
        end
        seen[id] = true;

        local marks = "";
        if (id == applied) then
            marks = marks .. " *applied";
        end
        if (id == known) then
            marks = marks .. " *known";
        end

        -- **Does the way back land on the base we came from?** `Row` already prints what the two
        -- resolvers answered; this only says whether that answer is the id this walk started at.
        if (C_SpellBook.FindBaseSpellByID(id) ~= base) then
            marks = marks .. " *noreturn";
        end

        Row("-- ", id, C_Spell.GetSpellName(id), marks);

        ignore = id;
    end
end

--- The talent tree, walked the way `Spells.lua`'s `AddTraits` walks it: every entry of every node,
--- not only the ones with committed ranks, so a talent nobody picked is in here too.
--- `overriddenSpellID` is what the definition replaces, which is the pair this probe is after.
local function Traits()
    local configID = C_ClassTalents.GetActiveConfigID();
    local configInfo = configID and C_Traits.GetConfigInfo(configID);
    local treeIDs = configInfo and configInfo.treeIDs;
    if (not treeIDs) then
        Emit("no talent config");
        return;
    end

    local rows = 0;
    local pending = {};

    for i = 1, #treeIDs do
        local nodes = C_Traits.GetTreeNodes(treeIDs[i]) or {};
        for j = 1, #nodes do
            local node = C_Traits.GetNodeInfo(configID, nodes[j]);
            local entryIDs = node and node.entryIDs;
            for k = 1, (entryIDs and #entryIDs or 0) do
                local entry = C_Traits.GetEntryInfo(configID, entryIDs[k]);
                local definition = entry and entry.definitionID
                    and C_Traits.GetDefinitionInfo(entry.definitionID);
                local id = definition and definition.spellID;
                if (id and not TalentSpells[id]) then
                    TalentSpells[id] = true;
                    rows = rows + 1;
                    pending[rows] = {
                        id = id,
                        replaced = definition.overriddenSpellID,
                        taken = node.activeEntry and node.activeEntry.entryID == entryIDs[k],
                        -- **The three ids a condition could be written against.** The node is the
                        -- slot in the tree, the entry is one of the choices in that slot, and the
                        -- definition is what the choice grants. A talent that splits a spell into
                        -- several ids is still one node, which is the whole reason to reach for
                        -- these instead of the spell id.
                        node = nodes[j],
                        entry = entryIDs[k],
                        definition = entry.definitionID,
                        tree = treeIDs[i],
                        -- **Which of the four panels the node is drawn in.** `subTreeID` is the
                        -- hero panel and says which hero specialization
                        -- (`Blizzard_ClassTalentsFrame.lua:686-712`); class and spec are told apart
                        -- by which currency the node costs, the same split the two reset buttons
                        -- use (`:820-828`).
                        subTree = node.subTreeID,
                        -- The walk hands over both hero trees' nodes and only the chosen one
                        -- stands, so the id alone does not say whether this row is live.
                        subTreeActive = node.subTreeActive,
                        cost = C_Traits.GetNodeCost(configID, nodes[j]),
                    };
                end
            end
        end
    end

    Emit("--- talent tree ---");

    -- **The currency list is the class/spec split.** `[1]` is what the class column costs and `[2]`
    -- the specialization column, which is how the two reset buttons tell them apart
    -- (`Blizzard_ClassTalentsFrame.lua:820-828`). A hero tree carries its own in `GetSubTreeInfo`.
    for i = 1, #treeIDs do
        local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeIDs[i], false) or {};
        for j = 1, #currencies do
            Emit(format("currency tree=%d [%d] id=%s quantity=%s",
                treeIDs[i], j, tostring(currencies[j].traitCurrencyID),
                tostring(currencies[j].quantity)));
        end
    end

    for i = 1, rows do
        local row = pending[i];
        local marks = format(" tree=%d node=%d entry=%d def=%d",
            row.tree, row.node, row.entry, row.definition);
        if (row.subTree) then
            local sub = C_Traits.GetSubTreeInfo(configID, row.subTree);
            marks = marks .. format(" sub=%d%s(%s cur=%s)", row.subTree,
                row.subTreeActive and "*" or "",
                sub and tostring(sub.name) or "?",
                sub and tostring(sub.traitCurrencyID) or "?");
        end
        for _, cost in ipairs(row.cost or {}) do
            marks = marks .. format(" cur=%d", cost.ID);
        end
        if (row.taken) then
            marks = marks .. " *taken";
        end
        if (row.replaced) then
            marks = marks .. format(" *replaces %d %s", row.replaced,
                tostring(C_Spell.GetSpellName(row.replaced)));
        end
        -- No `*base` here: `Row` asks both resolvers itself and prints that.
        Row("T ", row.id, C_Spell.GetSpellName(row.id), marks);
    end

    Emit(format("%d talent rows", rows));
end

local function Sweep()
    local bank = Enum.SpellBookSpellBank.Player;
    local rows = 0;

    Emit("id name | passive talent | bind help harm");

    for index = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(index);
        if (line) then
            local first = line.itemIndexOffset + 1;
            for slot = first, first + line.numSpellBookItems - 1 do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, bank);
                local base = info and info.actionID;
                if (base and info.itemType ~= Enum.SpellBookItemType.PetAction) then
                    -- **The row's name has to come from the same id the row asks about.**
                    -- `info.name` is the override-applied name while `actionID` is the base, so
                    -- pairing the two printed 440006 as `Purify` when its own name is
                    -- `Purify Disease` and `Purify` was the override's. Where the two differ the
                    -- book's name goes in the mark instead, since that is what the reader sees on
                    -- the spellbook page.
                    local name = C_Spell.GetSpellName(base);
                    local marks = "";
                    if (info.name and info.name ~= name) then
                        marks = " *book " .. info.name;
                    end
                    Row("", base, name, marks);
                    Overrides(base, info.spellID);
                    rows = rows + 1;
                end
            end
        end
    end

    Emit(format("%d rows", rows));
end

-- **Run on demand, not at login.** The talent build is half of what this measures, so the reader
-- has to be able to respec and ask again without a reload.
SLASH_DEBINDSD1 = "/sd";
SlashCmdList.DEBINDSD = function()
    wipe(Lines);
    wipe(TalentSpells);

    Traits();
    Sweep();

    local text = table.concat(Lines, "\n");
    if (DebindCopyFrame) then
        DebindCopyFrame:ShowText(text);
    else
        print(text);
    end
end;
