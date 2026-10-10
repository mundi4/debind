local _, DebindPrivate = ...;
local Constants               = DebindPrivate.Constants;

local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;
local SWITCH_MODES            = Constants.SWITCH_MODES;

local luatype                            = type;
local format, tostring, select           = format, tostring, select;
local tconcat                            = table.concat;
local wipe, ipairs, pairs, tinsert, sort = wipe, ipairs, pairs, tinsert, sort;
local band                               = bit.band;

local Rebuild               = DebindPrivate.Rebuild;
local _macrotexts           = Rebuild.macrotexts;
local _switches             = Rebuild.switches;
local sortedKeys            = Rebuild.sortedKeys;
local ComposedReads         = Rebuild.ComposedReads;
local appendLine            = Rebuild.appendLine;
local AssertSnippetCompiles = Rebuild.AssertSnippetCompiles;
local ANSWERS_AS_THE_WORD   = Rebuild.ANSWERS_AS_THE_WORD;
local StateAlternatives     = Rebuild.StateAlternatives;
local REPLACED_BAR_WORDS    = Rebuild.REPLACED_BAR_WORDS;
local _stateTokens          = Rebuild.stateTokens;
local UnitAsksExists        = Rebuild.UnitAsksExists;
local UnitAlternatives      = Rebuild.UnitAlternatives;
local BLOCKS                = Rebuild.BLOCKS;

local MEASURED_BY = Constants.MEASURED_BY;

local _sortedB           = {};

--- The attribute Blizzard's driver writes `"a"` to, once per manager tick while a key holds a tail
--- (`trimming-the-tail-key-beat.md` 5-1). The handler puts it back to `0` so the next tick writes
--- again.
local JUDGE_BEAT_ATTRIBUTE = "judgebeat";
DebindPrivate.JUDGE_BEAT_ATTRIBUTE = JUDGE_BEAT_ATTRIBUTE;
--- The loop's bodies the last rebuild generated besides the beat (`BuildJudgeSnippet`): the pass the
--- rebuild runs itself, and one per wake as `{ attribute = , body = }`.
local _judgePassBody;
local _judgeWakeBodies = {};
--- A development build's check of the watch (`PROBE.WatchCheck`), nil where there is none.
local _judgeWatchCheckBody;
--- A development build's beat body, run from the handler's branch rather than spliced into it, nil
--- in a shipped one.
local _judgeBeatBody;
--- Does the beat measure any column of this rebuild (`JudgedOnBeat`)?
local _judgeBeats = false;
--- What carries the beat in this rebuild: `"visibility"` where the login's check found the manager
--- writing `statehidden` on every tick (`BeatSignal.lua`), `"attribute"` otherwise. Decided once
--- per rebuild, since the handler's branch and the driver `ApplyBindingPlan` registers have to
--- agree.
local _judgeBeatSignal = "attribute";

--- **Each key some state lets go of or binds elsewhere, and each chord made from one, by its binding
--- string -> its judgment item** (`Judgment.lua`). That is a key holding a tail, or with
--- `giveBackWhenNoActionRuns` on one whose actions can all fail. A key with no item is ours in
--- every state, and so are its chords. Rebuilt whole by every rebuild.
DebindPrivate.JudgmentItems = {};

--- What a record winning a press means for the key. A tier's own closing BLOCK means nothing of its
--- own on a chord: the chord then lands where its base key does (`handing-the-rest-of-a-key-to-the-game.md`
--- 2-3).
local function JudgmentEntryFor(binding, record, tier)
    local Judgment = DebindPrivate.Judgment;
    local outcome = Judgment.OURS;
    if (binding.tail == Constants.COMMAND) then
        outcome = Judgment.COMMAND;
    elseif (binding.tail == Constants.GIVEBACK) then
        outcome = Judgment.RELEASE;
    elseif (tier ~= Constants.CASTMOD_NONE and binding == BLOCKS[tier]) then
        outcome = Judgment.BASE;
    end
    return Judgment.Entry(record, outcome, record.command);
end

--- The attribute holding a wake's body: this, then the wake's name (`JudgeWakes`).
local JUDGE_WAKE_PREFIX = "judge-";

--- The wakes of ours that move a column, none where only Blizzard's beat does. The pointed
--- frame's columns move with the cursor, a switch with `SetSwitch`, an alias with `SetUnit`, and
--- `bartakeover`'s pet battle cell with `SetPetBattle`.
---
--- **A computed switch moves with whatever its text reads**, through the computed switches it
--- reads as well: that wake composes the text again, so it has to measure the switch.
local function JudgmentWakesOf(column)
    local kind, arg = column.kind, column.arg;
    if (kind == "role" or kind == "frameType") then
        return { "unitframe" };
    elseif (kind == "bartakeover") then
        return { "petbattle" };
    elseif (kind == "unit" or kind == "unitgroup") then
        if (SPECIAL_UNITS[arg]) then
            return { arg };
        end
    elseif (kind == "switch") then
        local info = _switches[arg];
        if (not (info and info.mode == SWITCH_MODES.EXPR)) then
            return { arg };
        end
        local wakes, seen = {}, {};
        local function visit(name)
            for _, read in ipairs(ComposedReads(name) or {}) do
                if (not seen[read]) then
                    seen[read] = true;
                    local other = _switches[read];
                    if (other and other.mode == SWITCH_MODES.EXPR) then
                        visit(read);
                    else
                        wakes[#wakes + 1] = read;
                    end
                end
            end
        end
        seen[arg] = true;
        visit(arg);
        return wakes;
    end
    return {};
end

local _judgmentKeys = {};
local _judgmentColumns = {};
local _judgmentColumnIndex = {};
--- The columns this rebuild handed the loop, by index (`CellSlot` and `BundlesSlot`).
local _judgmentColumnOrder = {};
--- The columns the watch carries (`WatchFragments`), by column index: their place in the watch's
--- fragments.
local _watchPlace = {};
--- Each column's cell groups (`ColumnGroups`), by column key.
local _columnGroups = {};
--- Each `bartakeover` column's cells (`BarTakeoverCells`), by column key, worked out once with its
--- groups for everything that reads them.
local _barTakeoverCells = {};

--- **Where column i's two values sit in `Judge`'s array part**: its cell and the bundles that read
--- it. One array, so a body takes it into a local once (Q1 of
--- `implementing-the-cuts-inside-the-beat-handler.md`).
local function CellSlot(i)
    return 2 * i - 1;
end
local function BundlesSlot(i)
    return 2 * i;
end
--- How many of the watch's places are not units: they come first.
local _watchStatePlaces = 0;
local WatchFragments;

--- Every column the judgment items read, once each, as `column key -> column`.
local function CollectJudgmentColumns(items, out)
    wipe(out);
    for _, item in pairs(items) do
        for _, column in ipairs(item.columns) do
            out[column.key] = column;
        end
    end
    return out;
end

--- Text pieces as a template: literals and slots alternating, a literal first and last.
local function Template(pieces)
    local out, buffer = { "" }, {};
    for _, piece in ipairs(pieces) do
        if (luatype(piece) == "string") then
            buffer[#buffer + 1] = piece;
        else
            out[#out] = tconcat(buffer);
            buffer = {};
            out[#out + 1] = piece;
            out[#out + 1] = "";
        end
    end
    out[#out] = tconcat(buffer);
    return out;
end

--- What an item says, as a string two items share exactly when the loop would judge them alike:
--- the same checks on the same columns giving the same outcomes, and, for a chord, the same base
--- bundle to follow.
local function JudgmentSignature(item, baseBundle)
    local parts = { baseBundle or 0, item.rest.outcome, item.rest.command or "" };
    for _, entry in ipairs(item.entries) do
        parts[#parts + 1] = "|" .. entry.outcome .. " " .. (entry.command or "");
        for _, check in ipairs(entry.checks) do
            parts[#parts + 1] = item.columns[check.column].key .. ":" .. check.mask;
        end
    end
    return tconcat(parts, " ");
end

--- The alias and frame units the column loop classifies, `unit -> true`. Their texts are composed
--- with the unit's token when it moves (`J.classify`).
local _judgeClassified = {};
--- Does anything the loop measures or composes read the pointed frame?
local _judgeReadsFrame = false;

--- **A template as one Lua expression on the token local `token`**: `"[@" .. token .. ",help] 2; "
--- .. …`. Composed where the token moves, one concatenation and one write, where filling a table
--- of pieces and joining it cost a field write a piece and a `table.concat` (Q3 of
--- `implementing-the-cuts-inside-the-beat-handler.md`).
local function TemplateExpression(template, token)
    local parts, literal = {}, template[1];
    for k = 2, #template, 2 do
        parts[#parts + 1] = format("%q", literal .. "@");
        parts[#parts + 1] = token;
        literal = template[k].text .. template[k + 1];
    end
    parts[#parts + 1] = format("%q", literal);
    return tconcat(parts, " .. ");
end

--- The cells a classifying parse answers with, in the order the cell is read: assist first, then
--- attack, else other (`PRESENT_CELLS`). The last has no condition.
local CLASSIFY_CLAUSES = {
    { ",help,dead", Constants.UNITSTATE_HELP_DEAD },
    { ",help", Constants.UNITSTATE_HELP_ALIVE },
    { ",harm,dead", Constants.UNITSTATE_HARM_DEAD },
    { ",harm", Constants.UNITSTATE_HARM_ALIVE },
    { ",dead", Constants.UNITSTATE_OTHER_DEAD },
};

--- **A text the loop reads as a number ends in a clause with no condition** (`asNumber` in
--- `BuildJudgeSnippet`). Without one the parse answers nil where nothing holds, and `+ 0` raises in
--- the restricted environment, where nothing reports it.
local function AssertEndsInDefault(text)
    assert(text:match(";%s*%d+$") or text:match("^%d+$"), "a numbered text with no default clause: " .. text);
    return text;
end

--- The kinds whose cells are grouped (`ColumnGroups`). A form is measured by a call whose answer
--- is the cell itself, so a group there would cost a lookup on every measure; a boolean column has
--- two cells, and a check that told neither apart would not be a column.
local GROUPED_KINDS = { unit = true, groups = true, bonusbars = true, bartakeover = true };

--- **The cells of a column that no check tells apart, as one group each** (② of
--- `sizing-the-cuts-inside-the-beat-handler.md`, Q3 of
--- `implementing-the-cuts-inside-the-beat-handler.md`). `masks` is every mask a check of any item
--- puts on the column. Each group is `{ mask, rep, weight }`, by `rep`, its lowest cell, which is the
--- one the loop writes for the whole group: the masks hold it exactly where they hold any other
--- cell of the group, so the judging half answers alike, and a move inside a group moves no cell.
--- `weight` is how many of its cells a parse has to tell: an alias or frame unit's absent cell is
--- decided from the token. nil for a kind whose text is not grouped.
---
--- The absent unit cell is the lowest of all (`UNITSTATE_NONE`), so its group's `rep` is still the
--- cell the loop writes for a unit with no token.
local function ColumnGroups(column, masks)
    if (not GROUPED_KINDS[column.kind]) then
        return nil;
    end
    local list = {};
    for mask in pairs(masks or {}) do
        list[#list + 1] = mask;
    end
    sort(list);
    local noneParsed = column.kind ~= "unit" or UnitAsksExists(column.arg);
    local bySignature, groups = {}, {};
    for n = 0, 31 do
        local cell = 2 ^ n;
        if (cell > column.all) then
            break;
        end
        if (band(column.all, cell) ~= 0) then
            local signature = {};
            for i, mask in ipairs(list) do
                signature[i] = band(mask, cell) ~= 0 and "1" or "0";
            end
            signature = tconcat(signature);
            local group = bySignature[signature];
            if (not group) then
                group = { mask = 0, rep = cell, weight = 0, count = 0 };
                bySignature[signature] = group;
                groups[#groups + 1] = group;
            end
            group.mask, group.count = group.mask + cell, group.count + 1;
            if (noneParsed or cell ~= Constants.UNITSTATE_NONE) then
                group.weight = group.weight + 1;
            end
        end
    end
    return groups;
end

--- The group whose cell a text answers where no clause holds: the one with most cells to tell.
local function DefaultGroup(groups)
    local best;
    for _, group in ipairs(groups) do
        if (not best or group.weight > best.weight) then
            best = group;
        end
    end
    return best;
end

--- Did grouping merge anything? A column whose every cell stands alone keeps the text it had.
local function Merged(groups)
    if (not groups) then
        return false;
    end
    for _, group in ipairs(groups) do
        if (group.count > 1) then
            return true;
        end
    end
    return false;
end

--- **`bartakeover`'s cells as the loop writes them**: `battle`, the cell a pet battle writes, and
--- `clauses`, which tell the replaced bars from none, or nil with `plain` the one cell both write
--- where no check tells them apart. **The battle is never parsed**: it is pushed (`SetPetBattle`) and
--- taken ahead of the clauses, which is the battle being asked first. So a column whose checks only
--- ask about a battle leaves the beat nothing to measure, as the `petbattle` column it replaced did.
local function BarTakeoverCells(groups)
    local function written(cell)
        for _, group in ipairs(groups or {}) do
            if (band(group.mask, cell) ~= 0) then
                return group.rep;
            end
        end
        return cell;
    end
    local battle = written(Constants.BARTAKEOVER_PETBATTLE);
    local replaced, none = written(Constants.BARTAKEOVER_REPLACED), written(Constants.BARTAKEOVER_NONE);
    if (replaced == none) then
        return { battle = battle, plain = none };
    end
    local alternatives = {};
    for i, word in ipairs(REPLACED_BAR_WORDS) do
        alternatives[i] = { word };
    end
    return {
        battle = battle,
        clauses = { { groups = alternatives, cell = replaced }, default = none, numbered = true },
    };
end

--- Does the beat measure this column again? Everything but a switch set by hand, which nothing but
--- `SetSwitch` moves, and a `bartakeover` that only a pet battle moves (`BarTakeoverCells`). A
--- computed switch is worked out from the world, like any state.
local function JudgedOnBeat(column)
    if (column.kind == "bartakeover") then
        return _barTakeoverCells[column.key].clauses ~= nil;
    elseif (column.kind ~= "switch") then
        return true;
    end
    local info = _switches[column.arg];
    return (info and info.mode == SWITCH_MODES.EXPR) and true or false;
end

--- An alternative's tokens as they follow `@unit` in a group.
local function UnitTokensText(alternative)
    return #alternative > 0 and ("," .. tconcat(alternative, ",")) or "";
end

--- The alternatives a unit's own text has no way to hold in: `UnitAlternatives`' fixed false.
local function Never(alternatives)
    return alternatives[1] ~= nil and alternatives[1][1] == "known:0";
end

--- **One parse that answers a unit's cell** (P3-3), for the column loop's `unit` column. Its value
--- is the `UNITSTATE_*` number. `exists` is asked where `UnitAsksExists` says, so the loop reads a
--- unit's existence the way the press does. An alias or frame unit with no token is never parsed.
---
--- **With `groups` merged, one clause a group** (`ColumnGroups`), each the press's own alternatives
--- for its cells (`UnitAlternatives`) and answering its `rep`, the one with most cells as the default.
--- A group of an alias or frame unit holding no present cell has no clause: its absent cell is never
--- parsed.
local function ClassifyPieces(unit, groups)
    local pieces = {};
    local function at(text)
        if (SPECIAL_UNITS[unit]) then
            pieces[#pieces + 1] = "[";
            pieces[#pieces + 1] = { unit = unit, text = text };
            pieces[#pieces + 1] = "]";
        else
            pieces[#pieces + 1] = "[@" .. unit .. text .. "]";
        end
    end
    if (Merged(groups)) then
        local default = DefaultGroup(groups);
        for _, group in ipairs(groups) do
            local alternatives = UnitAlternatives(unit, group.mask);
            if (group ~= default and group.weight > 0 and not Never(alternatives)) then
                for _, alternative in ipairs(alternatives) do
                    at(UnitTokensText(alternative));
                end
                pieces[#pieces + 1] = " " .. group.rep .. "; ";
            end
        end
        pieces[#pieces + 1] = tostring(default.rep);
        local template = Template(pieces);
        AssertEndsInDefault(template[#template]);
        return template;
    end
    if (UnitAsksExists(unit)) then
        at(",noexists");
        pieces[#pieces + 1] = " " .. Constants.UNITSTATE_NONE .. "; ";
    end
    for _, clause in ipairs(CLASSIFY_CLAUSES) do
        at(clause[1]);
        pieces[#pieces + 1] = " " .. clause[2] .. "; ";
    end
    pieces[#pieces + 1] = tostring(Constants.UNITSTATE_OTHER_ALIVE);
    local template = Template(pieces);
    AssertEndsInDefault(template[#template]);
    return template;
end
DebindPrivate.ClassifyPieces = ClassifyPieces;

local function Negated(token)
    if (token:sub(1, 2) == "no") then
        return token:sub(3);
    end
    return "no" .. token;
end

--- A fixed unit's fragment from its alternatives (`UnitWatchAlternatives`).
local function UnitFragmentText(unit, alternatives)
    local groups = {};
    for i, alternative in ipairs(alternatives) do
        groups[i] = "[@" .. unit .. UnitTokensText(alternative) .. "]";
    end
    return tconcat(groups);
end

--- Words a list of alternatives asks, `@unit` counted as one in each (7-1's N prices it so).
local function UnitWords(alternatives)
    local words = 0;
    for _, alternative in ipairs(alternatives) do
        words = words + #alternative + 1;
    end
    return words;
end

--- Each alias or frame unit the watch carries: its place, and its alternatives by cell.
local _unitWatch = {};

--- **What the watch asks for a unit column, by the cell its group writes**: alternatives that hold
--- exactly once the unit has left the group (Q3 of
--- `implementing-the-cuts-inside-the-beat-handler.md`). An empty list carries nothing: no present
--- cell is left to move to, and the absent one comes with the token, through its wake.
---
--- **Two exact ways, and the one with fewer words is written.** The cells outside the group, as
--- `UnitAlternatives` writes them for the press, are always one. Where the group's own text is one
--- group, its tokens turned over one to a group are the other (`[@u,noharm][@u,dead]` for an enemy
--- alive). A unit word on a unit that is there costs about three a state word does (7-1), so the
--- count matters. Neither brings an `exists` the press does not ask: both come from `UnitAlternatives`.
local function UnitWatchAlternatives(column, groups)
    if (MEASURED_BY.unit ~= "parse" and not ANSWERS_AS_THE_WORD.unit) then
        return nil;
    end
    local unit = column.arg;
    local out = {};
    for _, group in ipairs(groups) do
        local best = UnitAlternatives(unit, column.all - group.mask);
        if (Never(best)) then
            best = {};
        end
        local own = UnitAlternatives(unit, group.mask);
        if (#own == 1 and not Never(own)) then
            local turned = {};
            for i, token in ipairs(own[1]) do
                turned[i] = { Negated(token) };
            end
            if (UnitWords(turned) < UnitWords(best)) then
                best = turned;
            end
        end
        out[group.rep] = best;
    end
    return out;
end

--- **The items, handed to the loop**: every column once, then each distinct item once as a bundle,
--- and each key's row pointing at its bundle (§3-3). The bare keys go ahead of the chords made from
--- them, since a chord's `base` answer is its base key's bundle's of the same pass.
local function EmitJudgmentItems(items)
    wipe(_judgeClassified);
    CollectJudgmentColumns(items, _judgmentColumns);
    wipe(_judgmentColumnIndex);
    wipe(_judgmentColumnOrder);
    wipe(_watchPlace);
    wipe(_columnGroups);
    wipe(_barTakeoverCells);
    wipe(_unitWatch);

    local masks = {};
    for _, item in pairs(items) do
        for _, entry in ipairs(item.entries) do
            for _, check in ipairs(entry.checks) do
                local key = item.columns[check.column].key;
                masks[key] = masks[key] or {};
                masks[key][check.mask] = true;
            end
        end
    end

    -- **Places go to the states first, then the units, the ones that move most last**: the pointed
    -- frame, then `mouseover`, then `target`. A hit at the last place ends the beat in that one
    -- parse (`BuildJudgeSnippet`), so the moves that come most often do; a hit anywhere else is
    -- confirmed by the whole text asked again. A development build parses the units one at a time
    -- after the states, in this same order.
    local order = sortedKeys(_judgmentColumns, _sortedB);
    for _, key in ipairs(order) do
        _columnGroups[key] = ColumnGroups(_judgmentColumns[key], masks[key]);
        if (_judgmentColumns[key].kind == "bartakeover") then
            _barTakeoverCells[key] = BarTakeoverCells(_columnGroups[key]);
        end
    end
    -- An expensive word whose gate can close is measured behind it instead of watched
    -- (`MeasureGates`). The gates' tests read the columns' places, so those come first.
    for i, key in ipairs(order) do
        _judgmentColumnIndex[key] = i;
    end
    local gates = DebindPrivate.MeasureGates(items);
    local fragmentsOf, states, units = {}, {}, {};
    for i, key in ipairs(order) do
        local column = _judgmentColumns[key];
        column.gate = gates[key];
        if (column.kind == "unit") then
            fragmentsOf[i] = UnitWatchAlternatives(column, _columnGroups[key]);
            if (fragmentsOf[i]) then
                units[#units + 1] = i;
            end
        elseif (column.gate == nil or column.gate == true) then
            fragmentsOf[i] = WatchFragments(column);
            if (fragmentsOf[i]) then
                states[#states + 1] = i;
            end
        end
    end
    local MOVES_MOST = { target = 1, mouseover = 2, unitframe = 3 };
    sort(units, function(a, b)
        local ra, rb = MOVES_MOST[_judgmentColumns[order[a]].arg] or 0, MOVES_MOST[_judgmentColumns[order[b]].arg] or 0;
        if (ra ~= rb) then
            return ra < rb;
        end
        return a < b;
    end);
    _watchStatePlaces = #states;
    local watched = 0;
    for _, list in ipairs({ states, units }) do
        for _, i in ipairs(list) do
            watched = watched + 1;
            _watchPlace[i] = watched;
        end
    end

    local wakes = {};
    for i, key in ipairs(order) do
        local column = _judgmentColumns[key];
        _judgmentColumnOrder[i] = column;
        appendLine("JudgeStaged[%d]=newtable()", BundlesSlot(i));
        local fragments, place = fragmentsOf[i], _watchPlace[i];
        if (place) then
            -- **As a clause answering its place** (Q2b): the parse names the first column that left
            -- its cell. Each ends with the separator, so the joined text ends in an empty clause:
            -- it holds unconditionally, is reached only where every place failed, and answers `""`
            -- (measured on the client's insecure side, whose `SecureCmdOptionParse` the restricted
            -- environment holds a copy of, `DIRECT_MACRO_CONDITIONAL_NAMES`). No place has to know
            -- whether it comes first.
            if (column.kind == "unit" and SPECIAL_UNITS[column.arg]) then
                -- Written from the token where it is written (`BuildJudgeSnippet`).
                _unitWatch[column.arg] = { place = place, fragments = fragments };
            else
                appendLine("w=newtable() JudgeStaged.byCell[%d]=w", place);
                for _, cell in ipairs(sortedKeys(fragments, {})) do
                    local fragment = fragments[cell];
                    if (column.kind == "unit") then
                        fragment = UnitFragmentText(column.arg, fragment);
                    end
                    appendLine("w[%d]=%q", cell, fragment == "" and "" or format("%s %d; ", fragment, place));
                end
            end
        end
        for _, wake in ipairs(JudgmentWakesOf(column)) do
            wakes[wake] = true;
        end
        if (column.kind == "unit" and SPECIAL_UNITS[column.arg]) then
            _judgeClassified[column.arg] = true;
        end
    end
    sortedKeys(items, _judgmentKeys);
    sort(_judgmentKeys, function(a, b)
        local aChord, bChord = items[a].base ~= nil, items[b].base ~= nil;
        if (aChord ~= bChord) then
            return bChord;
        end
        return a < b;
    end);

    local bundleOf, keyBundle, bundles = {}, {}, 0;
    for _, key in ipairs(_judgmentKeys) do
        local item = items[key];
        local baseBundle = item.base and keyBundle[item.base];
        local signature = JudgmentSignature(item, baseBundle);
        local n = bundleOf[signature];
        if (not n) then
            bundles = bundles + 1;
            n = bundles;
            bundleOf[signature] = n;
            -- Every key it stands for was bound by the line that put the key on, so it starts as
            -- ours.
            appendLine([[b=newtable() b.want="ours" b.keys=newtable() JudgeStaged.bundles[%d]=b]], n);
            if (baseBundle) then
                appendLine("b.base=JudgeStaged.bundles[%d]", baseBundle);
            end
            appendLine("b.restOutcome=%q", item.rest.outcome);
            if (item.rest.command) then
                appendLine("b.restCommand=%q", item.rest.command);
            end
            -- The columns its checks read, which is what has to wake it.
            local reads, seen = {}, {};
            for e, entry in ipairs(item.entries) do
                appendLine("e=newtable() e.outcome=%q b[%d]=e", entry.outcome, e);
                if (entry.command) then
                    appendLine("e.command=%q", entry.command);
                end
                for k, check in ipairs(entry.checks) do
                    local index = _judgmentColumnIndex[item.columns[check.column].key];
                    appendLine("e[%d]=%d e[%d]=%d", 2 * k - 1, CellSlot(index), 2 * k, check.mask);
                    if (not seen[index]) then
                        seen[index] = true;
                        reads[#reads + 1] = index;
                    end
                end
            end
            for _, index in ipairs(reads) do
                appendLine("tinsert(JudgeStaged[%d],b)", BundlesSlot(index));
            end
        end
        keyBundle[key] = n;
        appendLine([[j=newtable() j.key=%1$q j.slot=BoundKeys[%1$q] j.bound="ours" j.bundle=JudgeStaged.bundles[%2$d] ]]
            .. [[JudgeByKey[%1$q]=j tinsert(j.bundle.keys,j)]], key, n);
    end

    for _, wake in ipairs(sortedKeys(wakes, {})) do
        appendLine("JudgeWakes[%q]=%q", wake, JUDGE_WAKE_PREFIX .. wake);
    end
    _judgeReadsFrame = wakes.unitframe or false;
end

--- Boolean state columns, each measured by parsing what the press parses for "on".
local JUDGED_BOOL_STATES = {
    combat = true, stealth = true, mounted = true, indoors = true, flyable = true, advflyable = true,
    flying = true, skyriding = true, extrabar = true,
};

--- **The parse that answers a state column's cell on the column loop**, and whether its value is
--- the cell itself (F1 of `trimming-the-tail-key-beat.md`): a boolean column's "on" as the press
--- writes it, a mask column's clauses each worth its cell. The loop then reads what the press reads,
--- as the expressions do, and a parse is cheaper than the API it replaces (7-1, `[combat]` 0.21 to
--- `PlayerInCombat()` 0.91). nil for a column that is not a state.
---
--- A mask column falls back to the cell the press reads its value as: no form is form 0, and an
--- offset past the ones the press names is offset 0, since `[nobonusbar:1/2/3/4/5]` holds there.
---
--- **As clauses, which the text is made from** (`StateCellText`): each `{ groups, cell }`, a group
--- being its tokens, the first clause that holds answering its cell and `default` where none does.
--- A boolean column's text carries no values, since its "on" is read as the parse answering at all.
--- `exclusive` marks clauses of which at most one holds. Split from the text so that whatever else
--- has to ask what the text asks reads the same source (the watch,
--- `implementing-the-cuts-inside-the-beat-handler.md` Q2).
---
--- **With the column's cell groups merged, one clause a group** (`ColumnGroups`): the press's own
--- alternatives for its cells (`StateAlternatives`), exact, so at most one holds, answering its
--- `rep`, and the one with most cells as the default.
local function StateCellClauses(column)
    local kind, cellGroups = column.kind, _columnGroups[column.key];
    local list;
    if (kind == "bartakeover") then
        list = _barTakeoverCells[column.key].clauses;
        if (not list) then
            return nil;
        end
    elseif (Merged(cellGroups)) then
        local default = DefaultGroup(cellGroups);
        list = { default = default.rep, numbered = true, exclusive = true };
        for _, group in ipairs(cellGroups) do
            if (group ~= default) then
                list[#list + 1] = { groups = StateAlternatives(kind, group.mask), cell = group.rep };
            end
        end
    elseif (JUDGED_BOOL_STATES[kind]) then
        list = {
            { groups = StateAlternatives(kind, true), cell = Constants.JUDGMENT_TRUE },
            default = Constants.JUDGMENT_FALSE,
        };
    elseif (kind == "groups") then
        list = {
            { groups = { { "group:raid" } }, cell = Constants.GROUP_RAID },
            { groups = { { "group" } }, cell = Constants.GROUP_PARTY },
            default = Constants.GROUP_NONE, numbered = true,
        };
    elseif (kind == "forms" or kind == "bonusbars") then
        local word, last = "form", Constants.MAX_FORM;
        if (kind == "bonusbars") then
            word, last = "bonusbar", Constants.MAX_BONUSBAR_OFFSET;
        end
        -- One form, one offset at a time: the clauses never hold two at once (`exclusive`).
        list = { default = 1, numbered = true, exclusive = true };
        for n = 1, last do
            list[n] = { groups = { { word .. ":" .. n } }, cell = 2 ^ n };
        end
    else
        return nil;
    end
    for _, clause in ipairs(list) do
        for _, group in ipairs(clause.groups) do
            for _, token in ipairs(group) do
                _stateTokens[token] = true;
            end
        end
    end
    return list;
end

--- The text `SecureCmdOptionParse` is handed for a state column's cell, and whether its value is
--- the cell itself. nil for a column that is not a state.
local function StateCellText(column)
    local list = StateCellClauses(column);
    if (not list) then
        return nil;
    end
    local clauses = {};
    for i, clause in ipairs(list) do
        local groups = {};
        for g, group in ipairs(clause.groups) do
            groups[g] = "[" .. tconcat(group, ",") .. "]";
        end
        clauses[i] = tconcat(groups);
        if (list.numbered) then
            clauses[i] = format("%s %d", clauses[i], clause.cell);
        end
    end
    if (not list.numbered) then
        return clauses[1], false;
    end
    clauses[#clauses + 1] = format("%d", list.default);
    return AssertEndsInDefault(tconcat(clauses, "; ")), true;
end

--- **Groups that hold exactly where the clause does not**, or nil where that needs a product.
--- One group of tokens fails where any token fails, so each token turned over is a group of its
--- own. Several groups of one token each fail where all do, so the tokens turned over make one
--- group (`bartakeover`'s `[novehicleui,nopossessbar,nooverridebar,noshapeshift]`). Several groups
--- with more than one token would multiply out, and such a column stays off the watch.
local function NegatedGroups(clause)
    local groups = clause.groups;
    if (#groups == 1) then
        local out = {};
        for i, token in ipairs(groups[1]) do
            out[i] = { Negated(token) };
        end
        return out;
    end
    local one = {};
    for i, group in ipairs(groups) do
        if (#group ~= 1) then
            return nil;
        end
        one[i] = Negated(group[1]);
    end
    return { one };
end

--- **The expensive words' gate**, by column key: a condition on the other columns' cells, as Lua,
--- behind which `BuildJudgeSnippet` measures the column after the watch, or `true` where it measures
--- it on every beat, where the watch carries it. `slots` is the cells it reads, so a wake that moves
--- one measures behind it as well (`BuildJudgeSnippet`).
---
--- `flyable` costs 5 a parse and `advflyable` 24 where every other word costs a tenth of one (7-1).
--- **The loop reaches an entry only where every entry ahead of it failed, and an entry is an AND**,
--- so the column decides something only where some entry reading it is reached with its other checks
--- holding; elsewhere its cell may go stale with no answer moving. The gate is exactly that: over the
--- entries reading the column, their other checks and that no entry ahead of them holds.
---
--- **A check on another expensive column is read as holding**, and an entry ahead with one adds
--- nothing: that column's cell may be stale behind its own gate. Both only open the gate wider, as
--- does an entry ahead that reads this column itself.
---
--- **Past `LIMIT` cells read or terms joined it is `true`**: each cell read is a local of the beat
--- body, where Lua allows 200, and a closed gate pays a test a term, which past that many comes to
--- what the parse it spares costs.
function DebindPrivate.MeasureGates(items)
    local LIMIT = 32;
    local expensive = DebindPrivate.Judgment.EXPENSIVE;
    -- The judging half's mask test on the check's column, as an expression on the local `c<slot>`
    -- the measure takes the cell into, once a beat whatever the number of tests on it.
    local function Test(item, check, slots)
        local slot = CellSlot(_judgmentColumnIndex[item.columns[check.column].key]);
        slots[#slots + 1] = slot;
        return format("%d %% (c%d + c%d) >= c%d", check.mask, slot, slot, slot);
    end
    local gates = {};
    -- In key order, so the same items write the same text.
    local itemKeys = sortedKeys(items, {});
    for key, column in pairs(_judgmentColumns) do
        if (expensive[column.kind]) then
            local terms, seen, reads, open = {}, {}, {}, false;
            for _, itemKey in ipairs(itemKeys) do
                local item = items[itemKey];
                local readsColumn = false;
                for _, checked in ipairs(item.columns) do
                    readsColumn = readsColumn or checked.key == key;
                end
                -- Each entry ahead that failed, as `{ text, slots }`.
                local failed = {};
                for _, entry in ipairs((readsColumn and not open) and item.entries or {}) do
                    local tests, slots, reaches, certain = {}, {}, false, true;
                    for _, check in ipairs(entry.checks) do
                        local checked = item.columns[check.column];
                        if (checked.key == key) then
                            reaches = true;
                        elseif (expensive[checked.kind]) then
                            certain = false;
                        else
                            tests[#tests + 1] = Test(item, check, slots);
                        end
                    end
                    if (reaches) then
                        for _, ahead in ipairs(failed) do
                            tests[#tests + 1] = ahead.text;
                            for _, slot in ipairs(ahead.slots) do
                                slots[#slots + 1] = slot;
                            end
                        end
                        if (#tests == 0) then
                            open = true;
                            break;
                        end
                        local text = tconcat(tests, " and ");
                        if (not seen[text]) then
                            seen[text] = true;
                            terms[#terms + 1] = text;
                            for _, slot in ipairs(slots) do
                                reads[slot] = true;
                            end
                        end
                    elseif (certain) then
                        failed[#failed + 1] = { text = "not (" .. tconcat(tests, " and ") .. ")", slots = slots };
                    end
                end
            end
            local slots = sortedKeys(reads, {});
            if (open or #terms > LIMIT or #slots > LIMIT) then
                gates[key] = true;
            else
                local locals = {};
                for _, slot in ipairs(slots) do
                    locals[#locals + 1] = format("local c%d = columns[%d]", slot, slot);
                end
                gates[key] = {
                    reads = tconcat(locals, "\n"), test = "(" .. tconcat(terms, ") or (") .. ")", slots = reads,
                };
            end
        end
    end
    return gates;
end

--- **What the watch asks for one column, by cell: the groups that hold once the world has left
--- that cell** (`implementing-the-cuts-inside-the-beat-handler.md` Q2, ③ of
--- `sizing-the-cuts-inside-the-beat-handler.md`). The clauses are the ones a parse of the column is
--- made from (`StateCellClauses`), read first to last: in the k-th clause's cell, any earlier clause
--- holding or the k-th failing has moved it, and in the default's, any clause holding has. A unit's
--- are `UnitWatchAlternatives`'. nil for a column the watch does not carry, which is measured on
--- every beat as before:
---
---   a switch, the pointed frame's           nothing a conditional can ask
---   `known` with `knownID`                  the press asks the spell book too
---   not parsed, not `ANSWERS_AS_THE_WORD`   nothing says the word answers what is measured
---
--- A group another one in the same fragment is a subset of is left out: it can hold only where
--- the smaller one does. **Groups of one token that differ only in the argument are one question
--- and are written as one** (`[form:1/2/3]`), the way the press writes it, and never with the bare
--- word, since a bare `[bonusbar]` is not the same question (7-1). **Never on the `no` side**:
--- `[noform:1/2]` holds where neither does, while `[noform:1][noform:2]` holds where either fails.
--- Every token a fragment writes goes into `_stateTokens`, so the development build's mock answers
--- it the way it answers the column's own text.
local FragmentsOf;
function WatchFragments(column)
    if (MEASURED_BY[column.kind] ~= "parse" and not ANSWERS_AS_THE_WORD[column.kind]) then
        return nil;
    end
    local list;
    if (column.kind == "known") then
        if (column.knownID) then
            return nil;
        end
        -- `no` in front turns over the whole name only where the parser reads it as one word. A
        -- typed name with a `,` or `]` never gets here: the Issues panel omits its record
        -- (`KNOWN_NAME_UNPARSABLE`).
        local token = column.arg:match("^%[(.+)%]$");
        list = { { groups = { { token } }, cell = Constants.JUDGMENT_TRUE }, default = Constants.JUDGMENT_FALSE };
    else
        -- The groups the loop writes (`ColumnGroups`): a cell is a group's `rep`, and its fragment has
        -- to hold where the group is left, not where that one cell is.
        list = StateCellClauses(column);
    end
    if (not list) then
        return nil;
    end
    return FragmentsOf(list);
end

--- The fragments of a clause list (`StateCellClauses`' shape), by cell. nil where a clause cannot be
--- turned over without multiplying out.
function FragmentsOf(list)
    local fragments = {};
    local function add(cell, groups)
        local kept = {};
        for i, group in ipairs(groups) do
            local set = {};
            for _, token in ipairs(group) do
                set[token] = true;
            end
            local covered = false;
            for j, other in ipairs(groups) do
                if (j ~= i and (#other < #group or (#other == #group and j < i))) then
                    local subset = true;
                    for _, token in ipairs(other) do
                        if (not set[token]) then
                            subset = false;
                            break;
                        end
                    end
                    covered = covered or subset;
                end
            end
            if (not covered) then
                kept[#kept + 1] = group;
            end
        end
        local merged, byWord = {}, {};
        for _, group in ipairs(kept) do
            local word, argument;
            if (#group == 1 and group[1]:sub(1, 2) ~= "no") then
                word, argument = group[1]:match("^(%a+):(.+)$");
            end
            if (word and byWord[word]) then
                byWord[word][1] = byWord[word][1] .. "/" .. argument;
            elseif (word) then
                byWord[word] = { group[1] };
                merged[#merged + 1] = byWord[word];
            else
                merged[#merged + 1] = group;
            end
        end
        local rendered = {};
        for _, group in ipairs(merged) do
            for _, token in ipairs(group) do
                _stateTokens[token] = true;
            end
            rendered[#rendered + 1] = "[" .. tconcat(group, ",") .. "]";
        end
        fragments[cell] = tconcat(rendered);
    end

    local earlier = {};
    for _, clause in ipairs(list) do
        local negated = NegatedGroups(clause);
        if (not negated) then
            return nil;
        end
        local groups = {};
        -- **Where the clauses never hold two at once (`exclusive`), the k-th failing says all of it**
        -- (Q2c): an earlier one holding means the k-th does not. Asking `form` twice on a druid
        -- costs 1.07 a quiet beat (7-1). Not `group`: `group:party` holds in a raid as well.
        if (not list.exclusive) then
            for _, group in ipairs(earlier) do
                groups[#groups + 1] = group;
            end
        end
        for _, group in ipairs(negated) do
            groups[#groups + 1] = group;
        end
        add(clause.cell, groups);
        for _, group in ipairs(clause.groups) do
            earlier[#earlier + 1] = group;
        end
    end
    add(list.default, earlier);
    return fragments;
end
DebindPrivate.WatchFragmentsOf = FragmentsOf;

--- **The watch measures every column that moved one at a time, with no cap** on how many. A cap c
--- makes a beat where more than c moved pay c rounds and then every carried column on top, and the
--- bench's large shape (`--bench-beat`, "by the watch's cap") has no cap cheapest where one or two
--- move, and within 4 µs of measuring all at the first answer where three or four do. The loop
--- ends anyway: each round answers a higher place, and a place answering again measures every
--- carried column and stops (`at <= from`, `BuildJudgeSnippet`).
---
--- `nil` here. The bench sets a number to price a cap against none; a body built with one counts
--- its rounds and measures every carried column past that many.
DebindPrivate.JudgeWatchRounds = nil;

--- **The loop's bodies, written for this profile** (`handing-the-rest-of-a-key-to-the-game.md` 2-5,
--- §3). The beat's goes straight into the handler, which `UpdateAttrChangedHandler` takes as the
--- return value: a `RunAttribute` there would cost an environment swap and a `pcall` on every beat.
--- The rebuild's pass and each wake's are left in `_judgePassBody` and `_judgeWakeBodies` to be run.
--- Each body is `prepare` (the pointed frame, the classifying texts composed), the measuring half,
--- and `SecureBindings.lua`'s `JUDGE_BUNDLES_SNIPPET`, the judging half. The measuring half lists
--- each column once per body that moves it, as straight lines, and nothing in it asks what kind a
--- column is: the beat can run every frame for as long as a key holds a tail.
---
--- **Every cell is read the way the press reads it**, since an item's boxes were built from the
--- records the press walks: the states and units by the parse the press makes, the pointed frame
--- and the computed switches through the press's own splices, and an alias's existence the way
--- `UnitAsksExists` answers it. A cell read any other way binds a key to an answer the press would
--- not give; `judgment_spec.lua` holds the bound key to the item at every point.
---
---   the beat:          Blizzard's driver, `JUDGE_BEAT_ATTRIBUTE` or `statehidden` by the login's
---                      check (`_judgeBeatSignal`). Every column the world moves, the pointed
---                      frame's included: a raid frame laid out again or a unit dying under a cursor
---                      that never moved sends neither enter nor leave
---   `JudgePass`        the rebuild's own pass. Every column, a switch set by hand too
---   `judge-<name>`     one of our wakes, `unitframe`, a switch or an alias (`JudgeWakes`). Only what
---                      it names: whatever else moved has an event that already pulled the next beat
---                      in
local function BuildJudgeSnippet()
    local lines = {};
    local function add(str, ...)
        lines[#lines + 1] = select("#", ...) > 0 and format(str, ...) or str;
    end

    local TRUE, FALSE = Constants.JUDGMENT_TRUE, Constants.JUDGMENT_FALSE;

    local function computed(column)
        local info = _switches[column.arg];
        return info and info.mode == SWITCH_MODES.EXPR;
    end

    --- The computed switches `names` read, each after every computed switch its expression reads,
    --- the way the press orders them (`OrderComputedSwitch`). A cycle is cut where the walk meets it.
    ---
    --- **Over `ComposedReads`, the edges the wakes and `readers` are built from**: a switch the
    --- rebuild fixed in the text (ignored, or the switch itself) is no edge, and is worked out only
    --- where a column reads it.
    local function SwitchesToWorkOut(names)
        local order, seen = {}, {};
        local function visit(name)
            if (seen[name]) then
                return;
            end
            seen[name] = true;
            for _, read in ipairs(ComposedReads(name) or {}) do
                local other = _switches[read];
                if (other and other.mode == SWITCH_MODES.EXPR) then
                    visit(read);
                end
            end
            order[#order + 1] = name;
        end
        for _, name in ipairs(names) do
            visit(name);
        end
        return order;
    end

    --- The composed texts of the computed switches the loop works out, by each name they read
    --- (`ComposedReads`): what to clear when that name moves.
    local readers = {};
    do
        local switches = {};
        for _, column in ipairs(_judgmentColumnOrder) do
            if (column.kind == "switch" and computed(column)) then
                switches[#switches + 1] = column.arg;
            end
        end
        for _, name in ipairs(SwitchesToWorkOut(switches)) do
            -- A text can name one thing twice (`[$a,combat][$a,mounted]`).
            local seen = {};
            for _, read in ipairs(ComposedReads(name) or {}) do
                if (not seen[read]) then
                    seen[read] = true;
                    readers[read] = readers[read] or {};
                    tinsert(readers[read], name);
                end
            end
        end
    end

    --- Clears the composed text of every switch reading `name`, so the next body to work it out
    --- composes it again.
    --- `texts` is the local holding `J.switchTexts` where the body has one.
    local function clearReaders(name, texts)
        for _, reader in ipairs(readers[name] or {}) do
            add("%s[%q] = nil", texts or "J.switchTexts", reader);
        end
    end

    --- **The generation is raised by the first column that moves**, so a body where none moves
    --- writes no global. The rebuild's pass raises it up front (`body`). A column's cell and its
    --- bundles sit side by side in `columns` (`EmitJudgmentItems`).
    ---
    --- **The pass only writes the cell**: every cell starts nil there, and the judging half stamps
    --- every bundle for it (`wake == 1`).
    ---
    --- **A column the watch carries has its fragment put back to its cell wherever it moves**, in
    --- any body, and the body joins the text again at its end (`body`). A wake that moved one and
    --- left the text would have every beat after it parse the old text, find it holding, and
    --- measure again for nothing. `bartakeover` does its own (`watchBarTakeover`).
    local inPass = false;
    --- Whether the body being built writes a fragment (`body`).
    local writesWatch = false;
    --- An alias or frame unit's token, as an expression.
    local function tokenOf(unit)
        return unit == "unitframe" and "J.frameUnit" or format("UnitAliasMap[%q]", unit);
    end

    --- **An alias or frame unit's fragment, for the token in the local `token` and the cell `cellExpr`
    --- names**, written into its place. Only the fragment that place needs now is built, where it is
    --- written; `""` with no token, since a fragment around an empty token would hold
    --- unconditionally.
    local function unitFragment(unit, token, cellExpr)
        local watch = _unitWatch[unit];
        writesWatch = true;
        add([[local fragment = ""]]);
        local branches = {};
        for _, rep in ipairs(sortedKeys(watch.fragments, {})) do
            local alternatives = watch.fragments[rep];
            if (#alternatives > 0) then
                local pieces = {};
                for _, alternative in ipairs(alternatives) do
                    pieces[#pieces + 1] = "[";
                    pieces[#pieces + 1] = { unit = unit, text = UnitTokensText(alternative) };
                    pieces[#pieces + 1] = "]";
                end
                pieces[#pieces + 1] = " " .. watch.place .. "; ";
                branches[#branches + 1] = { rep, TemplateExpression(Template(pieces), token) };
            end
        end
        if (#branches > 0) then
            add("if (%s) then", token);
            for n, branch in ipairs(branches) do
                add("%s (%s == %d) then", n == 1 and "if" or "elseif", cellExpr, branch[1]);
                add("fragment = %s", branch[2]);
            end
            add("end");
            add("end");
        end
        add("frags[%d] = fragment", watch.place);
        add("dirty = true");
    end

    local function fragment(index)
        local place = _watchPlace[index];
        local column = _judgmentColumnOrder[index];
        if (not place or column.kind == "bartakeover") then
            return;
        end
        if (column.kind == "unit" and SPECIAL_UNITS[column.arg]) then
            -- `unit` is the token (`unitAndExists`).
            unitFragment(column.arg, "unit", "cell");
            return;
        end
        writesWatch = true;
        add("frags[%d] = J.byCell[%d][cell]", place, place);
        add("dirty = true");
    end
    local function mark(index)
        if (inPass) then
            add("columns[%d] = cell", CellSlot(index));
            fragment(index);
            return;
        end
        add("if (columns[%d] ~= cell) then", CellSlot(index));
        add("columns[%d] = cell", CellSlot(index));
        add("if (not moved) then");
        add("moved = true");
        add("generation = J.generation + 1");
        add("J.generation = generation");
        add("end");
        add("local bundles = columns[%d]", BundlesSlot(index));
        add("for k = 1, #bundles do");
        add("bundles[k].stamp = generation");
        add("end");
        fragment(index);
        add("end");
    end

    --- **`bartakeover`'s fragment follows the pushed battle as well as its cell.** In a battle the
    --- cell is the battle's whatever the bars do, so the watch carries nothing for it (`""`), and
    --- the battle's wake that ends it has to write the fragment back even where the cell did not
    --- move.
    local function watchBarTakeover(index)
        local place = _watchPlace[index];
        if (not place) then
            return;
        end
        writesWatch = true;
        add("local fragment = (not J.petBattle) and J.byCell[%d][cell] or \"\"", place);
        add("if (frags[%d] ~= fragment) then", place);
        add("frags[%d] = fragment", place);
        add("dirty = true");
        add("end");
    end

    --- The column index of each computed switch that is a column.
    local switchColumns = {};
    for i, column in ipairs(_judgmentColumnOrder) do
        if (column.kind == "switch" and computed(column)) then
            switchColumns[column.arg] = i;
        end
    end

    --- **Only the computed switches a column reads, and what they read**, each parsed the way
    --- `COMPUTE_SWITCHES_SNIPPET` does it at the press. That one works out every computed switch, a
    --- macro body's included, which the beat has no use for. An expression with nothing to compose
    --- is baked in as the literal the press would parse.
    ---
    --- **A text is composed only where `J.switchTexts` has none** (8-6 of
    --- `trimming-the-tail-key-beat.md`): whatever moves a name it reads clears it, a switch here
    --- included, and `SwitchesToWorkOut` puts the switch ahead of its readers.
    ---
    --- **`J.switches` and `J.switchTexts` are taken into locals once** where the body reads them.
    local function workOutSwitches(order)
        if (#order == 0) then
            return;
        end
        add("local switchValues = J.switches");
        local withTexts = false;
        for _, name in ipairs(order) do
            if (_macrotexts[_switches[name].expr] or readers[name]) then
                withTexts = true;
            end
        end
        if (withTexts) then
            add("local switchTexts = J.switchTexts");
        end
        for _, name in ipairs(order) do
            local info = _switches[name];
            add("do");
            if (_macrotexts[info.expr]) then
                add("local s = switchTexts[%q]", name);
                add("if (not s) then");
                add("local entry = SwitchEntries[%q]", name);
                add("local unitframeAlias = J.frameUnit or nil");
                add("local clickSwitches = switchValues");
                add("local pressUnit");
                lines[#lines + 1] = DebindPrivate.COMPOSE_MACROTEXT_SNIPPET;
                add("switchTexts[%q] = s", name);
                add("end");
                add("local value = SecureCmdOptionParse(s) and true or false");
            else
                add("local value = SecureCmdOptionParse(%q) and true or false", info.expr);
            end
            add("if (value ~= switchValues[%q]) then", name);
            add("switchValues[%q] = value", name);
            clearReaders(name, "switchTexts");
            -- **Its column moves here, in whichever body works it out.** A reader's wake works it
            -- out without measuring its column, and the next beat finds the value already stored.
            local index = switchColumns[name];
            if (index) then
                add("cell = value and %d or %d", TRUE, FALSE);
                mark(index);
            end
            add("end");
            add("end");
        end
    end

    --- A unit's token and whether it is there, as `unit` and `exists`. The pointed frame's is what
    --- `prepare` read; `exists` is read only by the group cell, which stays on the API.
    local function unitAndExists(unit, withExists)
        if (unit == "unitframe") then
            add("local unit = J.frameUnit");
        elseif (SPECIAL_UNITS[unit]) then
            add("local unit = UnitAliasMap[%q]", unit);
        else
            add("local unit = %q", unit);
        end
        if (not withExists) then
            return;
        end
        if (unit == "player") then
            -- Never absent, and the press does not ask (`UnitAsksExists`).
            add("local exists = true");
        elseif (SPECIAL_UNITS[unit] and not DebindPrivate.ALIAS_NEEDS_EXISTS[unit]) then
            add("local exists = unit and true or false");
        elseif (SPECIAL_UNITS[unit]) then
            add("local exists = unit and UnitExists(unit) and true or false");
        else
            add("local exists = UnitExists(unit) and true or false");
        end
    end

    --- **A parse that answers a number is read with `+ 0`, not `tonumber`**: the coercion looks no
    --- name up in the environment, and measured 0.043 µs against 0.204 (7-1). It raises where the
    --- parse answers nil or `""`, which `tonumber` would have turned into nil, so every text read
    --- this way has to end in a clause with no condition (`AssertEndsInDefault`, where each is
    --- built).
    local function asNumber(parse)
        return parse .. " + 0";
    end

    --- A unit's cell by the classifying parse (`ClassifyPieces`), into `cell`. The caller declares
    --- `unit`, the token or nil; an alias or frame unit with none is absent without a parse.
    local function unitCell(unitName)
        add("cell = %d", Constants.UNITSTATE_NONE);
        if (SPECIAL_UNITS[unitName]) then
            add("if (unit) then");
            add("cell = %s", asNumber(format("PROBE.ParseUnit(J.classify[%q])", unitName)));
            add("end");
        else
            add("cell = %s", asNumber(format("PROBE.ParseUnit(%q)",
                ClassifyPieces(unitName, _columnGroups["unit " .. unitName])[1])));
        end
    end

    local function unitGroupCell()
        add("cell = %d", Constants.UNITGROUPCELL_NEITHER);
        add("if (exists) then");
        add("local raid = UnitPlayerOrPetInRaid(unit)");
        add("local party = UnitPlayerOrPetInParty(unit)");
        add([[local group = (raid and (party and "both" or "raid")) or (party and "party") or "neither"]]);
        add("PROBE.MockUnitGroup(unit)");
        add([[if (group == "both") then]]);
        add("cell = %d", Constants.UNITGROUPCELL_BOTH);
        add([[elseif (group == "raid") then]]);
        add("cell = %d", Constants.UNITGROUPCELL_RAID);
        add([[elseif (group == "party") then]]);
        add("cell = %d", Constants.UNITGROUPCELL_PARTY);
        add("end");
        add("end");
    end

    local function otherCell(column)
        local kind = column.kind;
        local by = MEASURED_BY[kind];
        assert(by, "no way to measure a judgment column of kind " .. tostring(kind));
        local text, numbered;
        if (by == "parse") then
            text, numbered = StateCellText(column);
        end
        if (kind == "forms" and by == "call") then
            -- The press's measure (`EVAL_SNIPPET`), its bit the cell. `GetShapeshiftForm()` answers 0
            -- with no form, never nil (owner, 2026-10-06), so nothing stands before the compare.
            add("local form = GetShapeshiftForm()");
            add("PROBE.MockState(form)");
            add("if (form > %d) then", Constants.MAX_FORM);
            add("form = 0");
            add("end");
            add("cell = 2 ^ form");
        elseif (kind == "bartakeover") then
            local cells = _barTakeoverCells[column.key];
            add("cell = J.petBattle and %d or %s", cells.battle,
                text and asNumber(format("PROBE.SecureCmdOptionParse(%q)", text)) or tostring(cells.plain));
        elseif (text and numbered) then
            add("cell = %s", asNumber(format("PROBE.SecureCmdOptionParse(%q)", text)));
        elseif (text) then
            add("cell = PROBE.SecureCmdOptionParse(%q) and %d or %d", text, TRUE, FALSE);
        elseif (kind == "known") then
            -- Through the probes the press asks through. The question goes in a local first, since
            -- a probe's arguments end at the first `)` and a spell name can hold one.
            add("local asked = %q", column.arg);
            if (column.knownID) then
                add("if (PROBE.SecureCmdOptionParse(asked) or PROBE.FindSpellBookSlotBySpellID(%d)) then",
                    column.knownID);
            else
                add("if (PROBE.SecureCmdOptionParse(asked)) then");
            end
            add("cell = %d", TRUE);
            add("else");
            add("cell = %d", FALSE);
            add("end");
        elseif (kind == "switch") then
            add("local value = States[%q]", column.arg);
            add("if (value == true) then");
            add("cell = %d", TRUE);
            add("elseif (value == false) then");
            add("cell = %d", FALSE);
            add("else");
            add("cell = %d", Constants.JUDGMENT_SWITCH_UNSET);
            add("end");
        elseif (kind == "frameType") then
            add("cell = unitframeFrameType or %d", Constants.JUDGMENT_FRAMETYPE_NOFRAME);
        elseif (kind == "role") then
            add([[if (unitframeRole == "tank") then]]);
            add("cell = %d", Constants.ROLE_TANK);
            add([[elseif (unitframeRole == "healer") then]]);
            add("cell = %d", Constants.ROLE_HEALER);
            add([[elseif (unitframeRole == "damager") then]]);
            add("cell = %d", Constants.ROLE_DAMAGER);
            add([[elseif (unitframeRole == "norole") then]]);
            add("cell = %d", Constants.ROLE_NONE);
            add("else");
            add("cell = %d", Constants.JUDGMENT_ROLE_UNMEASURED);
            add("end");
        else
            error("no measurement for a judgment column of kind " .. tostring(kind));
        end
    end

    --- One branch's columns, in index order, a unit's two columns sharing what it measured.
    local function measure(list)
        local readsFrame = false;
        local switches = {};
        for _, i in ipairs(list) do
            local column = _judgmentColumnOrder[i];
            local kind = column.kind;
            if (kind == "role" or kind == "frameType"
                    or ((kind == "unit" or kind == "unitgroup") and column.arg == "unitframe")) then
                readsFrame = true;
            elseif (kind == "switch" and computed(column)) then
                switches[#switches + 1] = column.arg;
            end
        end
        -- Read off what `prepare` read at the top of the body.
        if (readsFrame) then
            add("local unitframeFrameType = J.frameType or nil");
            add("local unitframeRole = J.frameRole or nil");
        end
        workOutSwitches(SwitchesToWorkOut(switches));

        local units, unitOrder = {}, {};
        for _, i in ipairs(list) do
            local column = _judgmentColumnOrder[i];
            if (column.kind == "unit" or column.kind == "unitgroup") then
                local unit = column.arg;
                if (not units[unit]) then
                    units[unit] = {};
                    unitOrder[#unitOrder + 1] = unit;
                end
                units[unit][column.kind] = i;
            end
        end
        for _, unit in ipairs(unitOrder) do
            add("do");
            unitAndExists(unit, units[unit].unitgroup ~= nil);
            if (units[unit].unit) then
                unitCell(unit);
                mark(units[unit].unit);
            end
            if (units[unit].unitgroup) then
                unitGroupCell();
                mark(units[unit].unitgroup);
            end
            add("end");
        end

        -- A computed switch is marked where it is worked out, above.
        for _, i in ipairs(list) do
            local column = _judgmentColumnOrder[i];
            if (column.kind ~= "unit" and column.kind ~= "unitgroup"
                    and not (column.kind == "switch" and computed(column))) then
                add("do");
                otherCell(column);
                mark(i);
                if (column.kind == "bartakeover") then
                    watchBarTakeover(i);
                end
                add("end");
            end
        end
    end

    --- **What a body does before it measures anything**: the pointed frame read again where
    --- anything reads it, the classifying texts (`J.classify`) composed where `mode` moves
    --- their unit, so no parse reads a text not yet composed, and the computed switches' texts
    --- cleared where it moves a name they read.
    ---
    --- `mode` is `"beat"`, `"pass"` (compose every text), `"unitframe"`, or `"wake"` with `wake` the
    --- alias whose text is composed again.
    ---
    --- **A unit's watch fragments follow its token as well as its cell.** Composing them again leaves
    --- the place holding the old token's, so the place is written again from the cell it stands on,
    --- moved or not. Left alone, a fragment for the old token that does not hold would let the new
    --- unit's moves pass. The pass writes every place where it measures.
    local refreshed = false;
    local function refreshUnitWatch(unit)
        local watch = _unitWatch[unit];
        if (not watch) then
            return;
        end
        refreshed = true;
        add("do");
        add("local token = %s", tokenOf(unit));
        add("local cell = columns[%d]", CellSlot(_judgmentColumnIndex["unit " .. unit]));
        unitFragment(unit, "token", "cell");
        add("end");
    end

    --- **An alias or frame unit's classifying text, composed for its token** into
    --- `J.classify[unit]` (`TemplateExpression`). A unit with no token is decided absent before
    --- any parse, and its text is left as it was.
    local function composeClassify(unit)
        if (not _judgeClassified[unit]) then
            return;
        end
        add("do");
        add("local token = %s", tokenOf(unit));
        add("if (token) then");
        add("J.classify[%q] = %s", unit,
            TemplateExpression(ClassifyPieces(unit, _columnGroups["unit " .. unit]), "token"));
        add("end");
        add("end");
    end
    local function prepare(mode, wake)
        if (mode == "unitframe" or (_judgeReadsFrame and mode ~= "wake")) then
            add("do");
            add("local unitframe = States.unitframe");
            -- **Only while pointing**, on the beat: a frame laid out again under a cursor that never
            -- moved sends neither enter nor leave (F3), and nothing else needs the read.
            if (mode == "beat") then
                add("if (unitframe) then");
            end
            add("local unitframeUnit");
            lines[#lines + 1] = DebindPrivate.READ_UNITFRAME_SNIPPET;
            -- `false` for none, never nil: a global set to nil is gone, not empty.
            add("unitframeUnit = unitframeUnit or false");
            add("unitframeFrameType = unitframeFrameType or false");
            add("unitframeRole = unitframeRole or false");
            add("if (unitframeUnit ~= J.frameUnit or unitframeFrameType ~= J.frameType"
                .. " or unitframeRole ~= J.frameRole) then");
            add("J.frameUnit = unitframeUnit");
            add("J.frameType = unitframeFrameType");
            add("J.frameRole = unitframeRole");
            if (mode ~= "pass") then
                composeClassify("unitframe");
                refreshUnitWatch("unitframe");
                clearReaders("unitframe");
            end
            add("end");
            if (mode == "beat") then
                add("end");
            end
            add("end");
        end
        if (mode == "pass") then
            for _, unit in ipairs(sortedKeys(_judgeClassified, {})) do
                composeClassify(unit);
            end
        elseif (mode == "wake") then
            composeClassify(wake);
            refreshUnitWatch(wake);
            clearReaders(wake);
        end
    end

    local beat, byHand, wakes, wakeOrder = {}, {}, {}, {};
    for i, column in ipairs(_judgmentColumnOrder) do
        if (JudgedOnBeat(column)) then
            beat[#beat + 1] = i;
        else
            byHand[#byHand + 1] = i;
        end
        for _, wake in ipairs(JudgmentWakesOf(column)) do
            if (not wakes[wake]) then
                wakes[wake] = {};
                wakeOrder[#wakeOrder + 1] = wake;
            end
            local list = wakes[wake];
            list[#list + 1] = i;
        end
    end
    sort(wakeOrder);
    _judgeBeats = #beat > 0;

    --- **Is the loop being built for a development build with probes on?** The question `BakeSnippet`
    --- asks to pick its probe forms. There the watch's units are parsed one at a time, each beside
    --- the `unit` its mock is held for (`PROBE.ParseUnit`, `MockUnitWords[unit]`), which one parse
    --- of the joined text with an `@` in every group cannot be. A shipped body parses the joined text.
    local probesOn = DebindPrivate.SnippetProbes ~= nil and DebindPrivate.SnippetProbes.expand ~= nil;

    --- Joins the fragments again where one was written.
    local function rejoin()
        add("if (dirty) then");
        add("dirty = false");
        add("local text = table.concat(frags)");
        add([[if (text == "") then]]);
        add("text = false");
        add("end");
        add("J.text = text");
        add("end");
    end

    --- One body: what `build` measures, then the judging half, which reads `wake` -- `1` for the
    --- rebuild's pass, `true` for the beat, the wake's name for a wake of ours.
    ---
    --- **`Judge` is the one global the loop's own tables cost a body**, and its array part is the
    --- columns, so the body reads a cell with no field read in between (R2 of
    --- `cutting-the-beat-under-a-zero-period.md`). The pass reads `JudgeStaged`, which it hands over
    --- as `Judge` once every column is measured (`JUDGE_BUNDLES_SNIPPET`); every other body returns
    --- while there is none.
    ---
    --- **Every body that writes a fragment joins the text again at its end**, before the judging half,
    --- which may return early.
    local function body(wake, build)
        lines = {};
        inPass = wake == "1";
        writesWatch = false;
        build();
        local measuring = lines;
        lines = {};
        add("local wake = %s", wake);
        if (inPass) then
            add("local J = JudgeStaged");
            add("local generation = J.generation + 1");
            add("J.generation = generation");
            add("local moved = true");
        else
            add("local J = Judge");
            add("if (not J) then");
            add("return");
            add("end");
            add("local generation");
            add("local moved = false");
        end
        add("local columns = J");
        add("local cell");
        if (writesWatch) then
            add("local frags = J.frags");
            add("local dirty = false");
        end
        for _, line in ipairs(measuring) do
            lines[#lines + 1] = line;
        end
        if (writesWatch) then
            rejoin();
        end
        lines[#lines + 1] = DebindPrivate.JUDGE_BUNDLES_SNIPPET;
        return tconcat(lines, "\n");
    end

    --- **The beat goes in the handler and nothing else does.** It is the one that comes as an
    --- attribute write, from Blizzard's driver; the other two are run.
    ---
    --- On `"attribute"` its attribute goes back to `0` after every tick, or the driver never writes
    --- it again: the manager writes only a value that differs from the attribute's
    --- (`SecureStateDriver.lua`, `resolveDriver`). Putting it back enters the handler a second time,
    --- and the first line turns that round. On `"visibility"` the manager writes `statehidden` on
    --- every tick without comparing, so there is nothing to put back (`BeatSignal.lua`).
    ---
    --- **The columns the watch carries are measured only where the watch holds**, and never on an
    --- empty text, which `SecureCmdOptionParse` answers as holding. Everything else is measured on
    --- every beat as before. **The watch answers the place of the first column that left its cell**
    --- (Q2b), so that column alone is measured, its fragment written, the text joined, and the
    --- whole text asked again until its trailing empty clause answers (`""`): a second parse is what
    --- says nothing else moved. Where a place already answered answers again, every carried column
    --- is measured (`JudgeWatchRounds` says why there is no cap besides). A development build checks
    --- the beat after it against the columns measured again (`PROBE.WatchCheck`, `JudgeWatchCheck`).
    ---
    --- **An expensive word is measured after the watch, behind its gate** (`MeasureGates`): the gate
    --- reads other columns' cells, which have to be this beat's, and a column that moves there is
    --- marked and judged in the same beat. One whose gate always holds is watched like the rest.
    _judgeBeatSignal = DebindPrivate.BeatSignal.comes and "visibility" or "attribute";
    local unwatched, watched, gated = {}, {}, {};
    for _, i in ipairs(beat) do
        local gate = _judgmentColumnOrder[i].gate;
        if (_watchPlace[i]) then
            watched[#watched + 1] = i;
        elseif (gate and gate ~= true) then
            gated[#gated + 1] = i;
        else
            unwatched[#unwatched + 1] = i;
        end
    end
    local function measureGated(i)
        local gate = _judgmentColumnOrder[i].gate;
        add("do");
        add(gate.reads);
        add("if (%s) then", gate.test);
        measure({ i });
        add("end");
        add("end");
    end
    local beatBody = body("true", function()
        refreshed = false;
        prepare("beat");
        measure(unwatched);
        if (#watched > 0) then
            -- A frame unit's fragment written in `prepare`.
            if (refreshed) then
                rejoin();
            end
            local places = 0;
            for _, i in ipairs(watched) do
                places = math.max(places, _watchPlace[i]);
            end
            local cap = DebindPrivate.JudgeWatchRounds;
            add("local text = J.text");
            if (cap) then
                add("local rounds = 0");
            end
            -- The highest place answered so far in this beat.
            add("local from = 0");
            add("while (text) do");
            if (probesOn) then
                -- The whole text, asked a place's way at a time: the states joined and parsed once,
                -- then each unit's fragment beside its own `unit`, the first that holds answering.
                -- Each piece ends in the trailing empty clause, so `""` is "nothing here".
                add([[local hit = ""]]);
                if (_watchStatePlaces > 0) then
                    add([[local stateText = ""]]);
                    add("for p = 1, %d do", _watchStatePlaces);
                    add("stateText = stateText .. frags[p]");
                    add("end");
                    add([[if (stateText ~= "") then]]);
                    add("hit = PROBE.SecureCmdOptionParse(stateText)");
                    add("end");
                end
                local units = {};
                for _, i in ipairs(watched) do
                    if (_watchPlace[i] > _watchStatePlaces) then
                        units[#units + 1] = i;
                    end
                end
                sort(units, function(a, b) return _watchPlace[a] < _watchPlace[b]; end);
                for _, i in ipairs(units) do
                    add([[if (hit == "") then]]);
                    add("local fragment = frags[%d]", _watchPlace[i]);
                    add([[if (fragment ~= "") then]]);
                    unitAndExists(_judgmentColumnOrder[i].arg, false);
                    add("hit = PROBE.ParseUnit(fragment)");
                    add("end");
                    add("end");
                end
            else
                add("local hit = PROBE.SecureCmdOptionParse(text)");
            end
            -- The trailing empty clause: no place held. A nil would be a text that does not end in
            -- one, and `+ 0` below would raise on it with nothing to say so.
            add([[if (not hit or hit == "") then]]);
            add("break");
            add("end");
            -- Every clause but the trailing empty one answers its place's number (`WatchFragments`),
            -- so past it the answer is one, read the way `asNumber` reads one.
            add("local at = hit + 0");
            -- **The text is parsed whole every round**, because the restricted environment's
            -- `table.concat` takes no range (`RestrictedTable_concat`). So a place at or before `from`
            -- answering again is a column whose word and measure diverge (the form's word against
            -- `GetShapeshiftForm()`), and it masks every place behind it: measuring them all is the
            -- only way to reach those in this beat. Breaking there instead would leave a later move
            -- unmeasured for as long as the divergence lasts.
            if (cap) then
                add("rounds = rounds + 1");
                add("if (at <= from or rounds > %d) then", cap);
            else
                add("if (at <= from) then");
            end
            measure(watched);
            add("break");
            add("end");
            for n, i in ipairs(watched) do
                add("%s (at == %d) then", n == 1 and "if" or "elseif", _watchPlace[i]);
                measure({ i });
            end
            add("end");
            add("from = at");
            add("if (from == %d) then", places);
            add("break");
            add("end");
            rejoin();
            add("text = J.text");
            add("end");
        end
        for _, i in ipairs(gated) do
            measureGated(i);
        end
        if (#watched > 0 or #gated > 0) then
            add("PROBE.WatchCheck()");
        end
    end);

    --- What `PROBE.WatchCheck` runs in a development build: every column the watch carries, measured
    --- again and held against its cell. A column that moved where the watch did not answer is
    --- reported, and that is a key left bound on an old cell.
    _judgeWatchCheckBody = nil;
    if (Constants.DEBUG and (#watched > 0 or #gated > 0)) then
        lines = {};
        -- Run from the beat, past its own check that `Judge` is there.
        add("local J = Judge");
        add("local columns = J");
        add("local cell");
        -- A gated column's cell may stand stale while its gate is closed, so it is held to it only
        -- behind the same gate: what this asks is whether a gate stayed shut where it had to open.
        local checked = {};
        for _, i in ipairs(watched) do
            checked[#checked + 1] = i;
        end
        for _, i in ipairs(gated) do
            checked[#checked + 1] = i;
        end
        for _, i in ipairs(checked) do
            local column = _judgmentColumnOrder[i];
            local gate = not _watchPlace[i] and column.gate;
            add("do");
            if (gate) then
                add(gate.reads);
                add("if (%s) then", gate.test);
            end
            if (column.kind == "unit") then
                unitAndExists(column.arg, false);
                unitCell(column.arg);
            else
                otherCell(column);
            end
            add("if (columns[%d] ~= cell) then", CellSlot(i));
            add("self:CallMethod(\"DebindTestWatchMiss\", %d)", i);
            add("end");
            if (gate) then
                add("end");
            end
            add("end");
        end
        _judgeWatchCheckBody = DebindPrivate.BakeSnippet(tconcat(lines, "\n"));
        AssertSnippetCompiles(_judgeWatchCheckBody, "JudgeWatchCheck");
    end
    --- **A development build times the beat** (`DebindBeatStart`, `DebindBeatEnd` in `Debind.lua`).
    --- The body is run as an attribute there, because the judging half returns early on a beat
    --- where nothing moved and an end spliced after it would be skipped; the timing then holds one
    --- `RunAttribute` that a shipped build does not pay. The start goes before the turn-back, so its
    --- second entry is timed inside the first.
    local opening;
    if (_judgeBeatSignal == "visibility") then
        opening = { [[if (name == "statehidden") then]] };
    else
        opening = {
            format("if (name == %q) then", JUDGE_BEAT_ATTRIBUTE),
            "if (value == 0) then",
            "return",
            "end",
        };
    end
    if (Constants.DEBUG) then
        opening[#opening + 1] = [[self:CallMethod("DebindBeatStart")]];
    end
    if (_judgeBeatSignal ~= "visibility") then
        opening[#opening + 1] = format("self:SetAttribute(%q, 0)", JUDGE_BEAT_ATTRIBUTE);
    end
    if (Constants.DEBUG) then
        _judgeBeatBody = DebindPrivate.BakeSnippet(beatBody);
        AssertSnippetCompiles(_judgeBeatBody, "JudgeBeatBody");
        opening[#opening + 1] = [[self:RunAttribute("JudgeBeatBody")]];
        opening[#opening + 1] = [[self:CallMethod("DebindBeatEnd")]];
    else
        opening[#opening + 1] = beatBody;
    end
    opening[#opening + 1] = "return";
    opening[#opening + 1] = "end";
    local branch = DebindPrivate.BakeSnippet(tconcat(opening, "\n"));
    AssertSnippetCompiles(branch, "JudgeBeat");

    --- The rebuild's own pass: every column, a switch set by hand too.
    _judgePassBody = DebindPrivate.BakeSnippet(body("1", function()
        prepare("pass");
        measure(beat);
        measure(byHand);
    end));
    AssertSnippetCompiles(_judgePassBody, "JudgePass");

    --- A wake of ours: only what it names. Whatever else moved has an event that pulls the next
    --- beat in. **And the gated columns whose gate reads one of those**, after them: the wake judges
    --- before any beat, and a gate it opens has to have its column measured by then.
    wipe(_judgeWakeBodies);
    for _, wake in ipairs(wakeOrder) do
        local moves = {};
        for _, i in ipairs(wakes[wake]) do
            moves[CellSlot(i)] = true;
        end
        local snippet = DebindPrivate.BakeSnippet(body(format("%q", wake), function()
            prepare(wake == "unitframe" and "unitframe" or "wake", wake);
            measure(wakes[wake]);
            for _, i in ipairs(gated) do
                for slot in pairs(_judgmentColumnOrder[i].gate.slots) do
                    if (moves[slot]) then
                        measureGated(i);
                        break;
                    end
                end
            end
        end));
        AssertSnippetCompiles(snippet, JUDGE_WAKE_PREFIX .. wake);
        _judgeWakeBodies[#_judgeWakeBodies + 1] = { attribute = JUDGE_WAKE_PREFIX .. wake, body = snippet };
    end

    return branch;
end

--- Writes what the last `BuildJudgeSnippet` left besides the branch it returned into the plan. Called
--- after `plan.judges` is set, which `beats` reads.
local function FillJudgePlan(plan)
    --- Does the beat measure anything for the loop? A switch set by hand and a pet battle move only
    --- on a wake of ours, so a profile reading nothing else needs no beat.
    plan.beats = plan.judges and _judgeBeats;
    plan.beatSignal = _judgeBeatSignal;
    plan.judgePass = _judgePassBody;
    plan.judgeWakes = _judgeWakeBodies;
    plan.judgeWatchCheck = _judgeWatchCheckBody;
    plan.judgeBeatBody = _judgeBeatBody;
end

--- What a rebuild with no judgment item leaves in place of the bodies: nothing to run.
local function ClearJudgeBodies()
    _judgePassBody = nil;
    wipe(_judgeWakeBodies);
    _judgeBeats = false;
    _judgeWatchCheckBody = nil;
    _judgeBeatBody = nil;
end

Rebuild.JudgmentEntryFor  = JudgmentEntryFor;
Rebuild.EmitJudgmentItems = EmitJudgmentItems;
--- Does this `bartakeover` column of the items just emitted parse the bars? Where it does not, no
--- bar event can move it.
function Rebuild.ParsesReplacedBars(column)
    return _barTakeoverCells[column.key].clauses ~= nil;
end
Rebuild.BuildJudgeSnippet = BuildJudgeSnippet;
Rebuild.FillJudgePlan     = FillJudgePlan;
Rebuild.ClearJudgeBodies  = ClearJudgeBodies;
