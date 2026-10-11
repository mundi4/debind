local _, Dev = ...

local DebindPrivate, Constants, LLL
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants, LLL = private, private.Constants, private.L
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail

-----------------------------------------------------------
-- Per-game-type files
-----------------------------------------------------------

-- **The client decides which files load, so only the client can say.** `Debind.toc` loads
-- `Locales/Camelot/enUS.lua` behind game type conditions; headless loads no locale at all.
-- The interface number is how this case knows which client it is on: camelot's is 16001.
--
-- **What it reads is the menu row and the tooltip heading coming out the same.** They differ in every
-- base locale ("Classes/Specializations" over "Specializations") and camelot's file gives both one
-- word, so the pair answers without this case holding a copy of the strings.
RegisterTest("Locales: camelot's own files load on camelot and nowhere else", {
    description = "On camelot the class condition's row and its tooltip heading share one word; on retail they do not",
    run = function()
        local NAME = "camelot locale files"
        local camelot = select(4, GetBuildInfo()) < 100000
        local row, heading = LLL["CONDITION_SPEC"], LLL["CONDITION_SPECS"]
        if camelot and row ~= heading then
            return Fail(NAME, format("camelot has %q over %q, so the files did not load", row, heading))
        end
        if not camelot and row == heading then
            return Fail(NAME, format("this client is not camelot and still has %q for both", row))
        end
        return Pass(NAME, row)
    end,
})

-- **The spell data is the other file the client picks** (`SpecSpells.lua`), and a retail client
-- that skipped `SpecSpells_Mainline.lua` would leave every Dispel, Raid Buff and Resurrect with
-- nothing to cast, raising nothing. Druid ids are asked because both files carry one.
RegisterTest("Spec spells: this client's own data file loads", {
    description = "Retail has retail's specialization ids in the spell data, camelot has camelot's, and never both",
    run = function()
        local NAME = "spec spell data"
        local camelot = select(4, GetBuildInfo()) < 100000
        local data = DebindPrivate.SpecSpellData
        if not data then
            return Fail(NAME, "no spell data file loaded at all")
        end
        local retailDruid, camelotDruid = data[102] ~= nil, data[1484] ~= nil
        if camelot and (not camelotDruid or retailDruid) then
            return Fail(NAME, format("camelot has camelot's %s and retail's %s", tostring(camelotDruid),
                tostring(retailDruid)))
        end
        if not camelot and (not retailDruid or camelotDruid) then
            return Fail(NAME, format("retail has retail's %s and camelot's %s", tostring(retailDruid),
                tostring(camelotDruid)))
        end
        return Pass(NAME)
    end,
})

-- **Every id in camelot's dispel and buff lists is a spell that client has** (`SpecSpells_Camelot.lua`).
-- The ids were read off trainer records and wowhead; one mistyped passes every headless spec, which
-- takes the table as given, and the action then casts nothing on that class. Retail is left out:
-- the shadow priest's 213634 is a talent and answers nothing on a character without it
-- (`SpecSpells_Mainline.lua`), so a name check there fails on a correct id.
RegisterTest("Spec spells: every camelot dispel and buff id is a spell", {
    description = "Each entry of every class's dispel, dispel2 and raidbuff list in camelot's table has a spell name",
    applies = function()
        if select(4, GetBuildInfo()) >= 100000 then
            return false, "not the camelot client"
        end
        return true
    end,
    run = function()
        local NAME = "camelot spec spell ids"
        local data = DebindPrivate.SpecSpellData
        local missing, count = {}, 0
        for spec, fields in pairs(data) do
            for _, field in ipairs({ "dispel", "dispel2", "raidbuff" }) do
                for _, entry in ipairs(fields[field] or {}) do
                    for _, spellID in ipairs({ entry.cast, entry.known }) do
                        count = count + 1
                        if not DebindPrivate.GetSpellNameAndIconID(spellID) then
                            missing[#missing + 1] = format("%d %s %d", spec, field, spellID)
                        end
                    end
                end
            end
        end
        if #missing > 0 then
            return Fail(NAME, "no spell for " .. table.concat(missing, ", "))
        end
        if count == 0 then
            return Fail(NAME, "the table had no entries to ask about")
        end
        return Pass(NAME, format("%d ids", count))
    end,
})

-- **`Constants.GAME_TYPE` is a third file the client picks** (`GameType_*.lua`), and a payload made
-- on a client that loaded neither, or both, carries the wrong answer about where it was made.
RegisterTest("Game type: this client's own file loads", {
    description = "Retail says standard and camelot says camelot, read off the file the TOC let in",
    run = function()
        local NAME = "game type"
        local expected = select(4, GetBuildInfo()) < 100000 and "camelot" or "standard"
        if Constants.GAME_TYPE ~= expected then
            return Fail(NAME, format("expected %q, got %q", expected, tostring(Constants.GAME_TYPE)))
        end
        return Pass(NAME, Constants.GAME_TYPE)
    end,
})

-- **A fourth file the client picks** (`ClassSpells_Camelot.lua`). Loaded on retail it would fold
-- the spec lines into one class group and add unlearned rows beside the book's own `FutureSpell`
-- ones; missing on camelot, the unlearned rows are gone and nothing says so.
RegisterTest("Unlearned spells: the generated table loads on camelot and nowhere else", {
    description = "The generated spell table is there on camelot and absent on retail",
    run = function()
        local NAME = "generated spell table"
        local camelot = select(4, GetBuildInfo()) < 100000
        local loaded = DebindPrivate.CamelotSpells ~= nil
        if loaded ~= camelot then
            return Fail(NAME, format("camelot %s, file loaded %s", tostring(camelot), tostring(loaded)))
        end
        return Pass(NAME, tostring(loaded))
    end,
})

-- **The client answers a spell the character has not learned**, which no headless spec can say:
-- the world there is whatever the spec stood up. A candidate the client cannot name is dropped from
-- the list without a word (`AddUnlearnedSpellEntries`), so an id the generated table carries from
-- an older build would simply never show. Every first rank in the table is asked, every class's.
local function UnlearnedCandidates()
    local candidates = {}
    for spellID, entry in pairs(DebindPrivate.CamelotSpells) do
        if type(entry) == "table" then
            candidates[#candidates + 1] = spellID
        end
    end
    return candidates
end

-- **A pinned rank goes out as `Name(Rank N)`** (`pinnedSpell`, `ComposeSpellCastName`), and the press
-- casts whatever the client resolves that text to. No headless spec can say whether the client
-- resolves it to that rank's own id rather than the highest, so it is asked of every rank of every
-- spell in this character's book.
local function RankedBookSpells()
    local ranked, seen = {}, {}
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
            local ranks = item and item.spellID and not seen[item.name]
                and DebindPrivate.Client.SpellRanks(item.spellID)
            if ranks and #ranks > 1 then
                seen[item.name] = true
                ranked[#ranked + 1] = ranks
            end
        end
    end
    return ranked
end

RegisterTest("Spell ranks: a pinned rank's cast text is that rank", {
    description = "Name(Rank N) resolves to rank N's own id, for every spell in the book with ranks",
    applies = function()
        if not DebindPrivate.Client.SPELLS_HAVE_RANKS then
            return false, "spells have no ranks on this client"
        end
        if #RankedBookSpells() == 0 then
            return false, "no spell in this character's book has two ranks"
        end
        return true
    end,
    run = function()
        local NAME = "pinned rank cast text"
        local wrong, count = {}, 0
        for _, ranks in ipairs(RankedBookSpells()) do
            for _, rank in ipairs(ranks) do
                local text = DebindPrivate.PinnedCastName(rank.id)
                local info = text and C_Spell.GetSpellInfo(text)
                count = count + 1
                if not (info and info.spellID == rank.id) then
                    wrong[#wrong + 1] = format("%s -> %s (wanted %d)", tostring(text),
                        tostring(info and info.spellID), rank.id)
                end
            end
        end
        if #wrong > 0 then
            return Fail(NAME, table.concat(wrong, ", "))
        end
        return Pass(NAME, format("%d ranks", count))
    end,
})

RegisterTest("Unlearned spells: the client names every candidate", {
    description = "Each first rank in the generated table has a spell name and icon",
    applies = function()
        if not DebindPrivate.CamelotSpells then
            return false, "not the camelot client"
        end
        return true
    end,
    run = function()
        local NAME = "unlearned spell ids"
        local candidates = UnlearnedCandidates()
        local missing = {}
        for _, spellID in ipairs(candidates) do
            local info = C_Spell.GetSpellInfo(spellID)
            if not (info and info.name and info.iconID) then
                missing[#missing + 1] = spellID
            end
        end
        if #missing > 0 then
            table.sort(missing)
            return Fail(NAME, "no spell for " .. table.concat(missing, ", "))
        end
        return Pass(NAME, format("%d ids", #candidates))
    end,
})
