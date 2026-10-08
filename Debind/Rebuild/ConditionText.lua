local _, DebindPrivate = ...;
local Constants               = DebindPrivate.Constants;

local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;

local tconcat                            = table.concat;
local ipairs, tinsert                    = ipairs, tinsert;
local band, bor                          = bit.band, bit.bor;

local Rebuild                 = DebindPrivate.Rebuild;

local MEASURED_BY = Constants.MEASURED_BY;

--- **The kinds measured some other way whose answer was seen to be the macro word's.** The watch
--- asks in macro conditionals (`WatchFragments`), and the user reads the condition as one, so a
--- kind not in here and not parsed is measured on every beat instead.
local ANSWERS_AS_THE_WORD = {
    -- `form` and `GetShapeshiftForm()` moved together and never apart in the `/debgw` run of
    -- 2026-10-05 17:08, xptr 120105 (`implementing-the-trimmed-tail-key-beat.md`).
    forms = true,
};

--- **The state axes, in the order the press's expression asks them**, each as what a value of it is
--- in macro conditionals: a list of alternatives, each a list of tokens that must all hold. A
--- record's `expr` is the product of the lists of its axes that are parsed (`StateExpression`); the
--- rest go out as fields.
---
--- **The expensive two go last in every group**, so a group already lost on a cheaper token never
--- judges them (7-1: `[<false>,flyable]` 0.23 against `[flyable,<false>]` 5.16).
local STATE_AXIS_ORDER = {
    "groups", "combat", "stealth", "mounted", "indoors", "flying", "skyriding", "forms", "bonusbars",
    "bartakeover", "extrabar", "flyable", "advflyable",
};
local STATE_AXES = {};
for _, axis in ipairs(STATE_AXIS_ORDER) do
    STATE_AXES[axis] = true;
end
--- **The state axes a call is written for**, in `EVAL_SNIPPET` and in `BuildJudgeSnippet`'s
--- `otherCell`. A row set to `call` anywhere else would go out as a field the press never reads.
local CALLED_STATE_AXES = { forms = true };

--- Asked at every rebuild rather than kept, so a row a spec sets is the one the rebuild reads.
local function ParsedStateAxis(field)
    if (not STATE_AXES[field]) then
        return false;
    end
    local by = MEASURED_BY[field];
    assert(by == "parse" or CALLED_STATE_AXES[field], "no call is written for the state " .. field);
    return by == "parse";
end

--- The offsets of a mask, `2 ^ n` per offset `n`, from `from` up to `to`.
local function MaskOffsets(mask, from, to)
    local out = {};
    for n = from, to do
        if (band(mask, 2 ^ n) ~= 0) then
            out[#out + 1] = n;
        end
    end
    return out;
end

--- The words `BARTAKEOVER_REPLACED` is, any one of them holding.
local REPLACED_BAR_WORDS = { "vehicleui", "possessbar", "overridebar", "shapeshift" };

--- One axis's value as alternatives of tokens.
local function StateAlternatives(axis, value)
    if (axis == "groups") then
        -- `[group:party]` holds in a raid as well (measured 2026-10-05), so a party that is not a
        -- raid needs `nogroup:raid` beside it.
        local none = band(value, Constants.GROUP_NONE) ~= 0;
        local party = band(value, Constants.GROUP_PARTY) ~= 0;
        local raid = band(value, Constants.GROUP_RAID) ~= 0;
        if (party and raid) then
            return none and {} or { { "group" } };
        elseif (none and party) then
            return { { "nogroup:raid" } };
        elseif (none and raid) then
            return { { "nogroup" }, { "group:raid" } };
        elseif (none) then
            return { { "nogroup" } };
        elseif (party) then
            return { { "group:party", "nogroup:raid" } };
        end
        return { { "group:raid" } };
    elseif (axis == "forms") then
        return { { "form:" .. tconcat(MaskOffsets(value, 0, Constants.MAX_FORM), "/") } };
    elseif (axis == "bonusbars") then
        -- Offset 0 is `[nobonusbar:1/2/3/4/5]`: `[bonusbar:0]` does not match it and a bare
        -- `[nobonusbar]` is always true (measured 2026-10-05).
        local alternatives = {};
        if (band(value, 1) ~= 0) then
            alternatives[#alternatives + 1] = {
                "nobonusbar:" .. tconcat(MaskOffsets(Constants.BONUSBAR_ALL, 1, Constants.MAX_BONUSBAR_OFFSET), "/"),
            };
        end
        local offsets = MaskOffsets(value, 1, Constants.MAX_BONUSBAR_OFFSET);
        if (#offsets > 0) then
            alternatives[#alternatives + 1] = { "bonusbar:" .. tconcat(offsets, "/") };
        end
        return alternatives;
    elseif (axis == "skyriding") then
        return { { (value and "" or "no") .. "bonusbar:" .. Constants.BONUSBAR_SKYRIDING } };
    elseif (axis == "bartakeover") then
        -- A pet battle is asked first (`BARTAKEOVER_*`), so the other two cells carry `nopetbattle`
        -- unless the battle is in the set as well.
        local battle = band(value, Constants.BARTAKEOVER_PETBATTLE) ~= 0;
        local replaced = band(value, Constants.BARTAKEOVER_REPLACED) ~= 0;
        local none = band(value, Constants.BARTAKEOVER_NONE) ~= 0;
        local guard = battle and {} or { "nopetbattle" };
        local alternatives = {};
        if (none and replaced) then
            if (battle) then
                return {};
            end
            return { guard };
        elseif (replaced) then
            for _, word in ipairs(REPLACED_BAR_WORDS) do
                local tokens = { word };
                for _, token in ipairs(guard) do
                    tokens[#tokens + 1] = token;
                end
                alternatives[#alternatives + 1] = tokens;
            end
        elseif (none) then
            local tokens = {};
            for i, word in ipairs(REPLACED_BAR_WORDS) do
                tokens[i] = "no" .. word;
            end
            for _, token in ipairs(guard) do
                tokens[#tokens + 1] = token;
            end
            alternatives[1] = tokens;
        end
        if (battle) then
            alternatives[#alternatives + 1] = { "petbattle" };
        end
        return alternatives;
    end
    return { { (value and "" or "no") .. axis } };
end

--- Every token a `StateExpression` has written since load. The kit reads it to hold a state at the
--- press, since a parsed word can only be held by rewriting the token (`DebindTest.lua`, `MockBody`).
local _stateTokens = {};
function DebindPrivate.StateExpressionTokens()
    return _stateTokens;
end

--- The record's state axes as one macro conditional, or nil where it has none. Parsed at the press
--- in one call (`EVAL_SNIPPET`).
local function StateExpression(record)
    local values = {};
    for i = 1, record.fieldCount do
        if (ParsedStateAxis(record.fieldNames[i])) then
            values[record.fieldNames[i]] = record.fieldValues[i];
        end
    end
    local groups = { {} };
    local any = false;
    for _, axis in ipairs(STATE_AXIS_ORDER) do
        local value = values[axis];
        if (value ~= nil) then
            any = true;
            local alternatives = StateAlternatives(axis, value);
            if (#alternatives > 0) then
                local product = {};
                for _, group in ipairs(groups) do
                    for _, alternative in ipairs(alternatives) do
                        local tokens = {};
                        for _, token in ipairs(group) do tokens[#tokens + 1] = token; end
                        for _, token in ipairs(alternative) do tokens[#tokens + 1] = token; end
                        product[#product + 1] = tokens;
                    end
                end
                groups = product;
            end
        end
    end
    if (not any) then
        return nil;
    end
    local parts = {};
    for i, group in ipairs(groups) do
        for _, token in ipairs(group) do
            _stateTokens[token] = true;
        end
        parts[i] = "[" .. tconcat(group, ",") .. "]";
    end
    return tconcat(parts);
end

--- A set of reactions (`REACTION_*` bits) as alternatives of tokens, read the way the cell is read:
--- assist first, then attack, else other. So harm is `nohelp,harm`, and help with other is
--- `[help][noharm]` rather than `noharm`, for a unit the two predicates both take.
local REACTION_ALTERNATIVES = {
    [Constants.REACTION_HELP] = { { "help" } },
    [Constants.REACTION_HARM] = { { "nohelp", "harm" } },
    [Constants.REACTION_OTHER] = { { "nohelp", "noharm" } },
    [Constants.REACTION_HELP + Constants.REACTION_HARM] = { { "help" }, { "harm" } },
    [Constants.REACTION_HELP + Constants.REACTION_OTHER] = { { "help" }, { "noharm" } },
    [Constants.REACTION_HARM + Constants.REACTION_OTHER] = { { "nohelp" } },
    [Constants.REACTION_ALL] = { {} },
};

--- Each cell a unit can be in while it exists, as its reaction and life.
local PRESENT_CELLS = {
    { Constants.UNITSTATE_HELP_ALIVE, Constants.REACTION_HELP, false },
    { Constants.UNITSTATE_HELP_DEAD, Constants.REACTION_HELP, true },
    { Constants.UNITSTATE_HARM_ALIVE, Constants.REACTION_HARM, false },
    { Constants.UNITSTATE_HARM_DEAD, Constants.REACTION_HARM, true },
    { Constants.UNITSTATE_OTHER_ALIVE, Constants.REACTION_OTHER, false },
    { Constants.UNITSTATE_OTHER_DEAD, Constants.REACTION_OTHER, true },
};

--- Does a parse ask this unit `exists`? **Only where the beat would call `UnitExists`.** A map-only
--- alias and the pointed frame are there when their token is, which is decided before any parse;
--- asking the client would part from the beat until `exists` goes in on both sides at once (P3-2 of
--- `implementing-the-trimmed-tail-key-beat.md`). The player is never asked: in a vehicle on xptr
--- 120105 `[@player,exists]` stayed false the whole ride while `UnitExists("player")` held.
local function UnitAsksExists(unit)
    return unit ~= "player" and not (SPECIAL_UNITS[unit] and not DebindPrivate.ALIAS_NEEDS_EXISTS[unit]);
end

--- A unit's cells (`UNITSTATE_*` mask, not all of them) as alternatives of tokens, without the
--- `@unit`. **The press and the beat both take theirs from here**, so the two parse one text.
---
--- For a unit that does not ask `exists`, the absent cell is not in the text: the caller decides it
--- from the token. With no present cell left the alternative is the fixed false `known:0`.
local function UnitAlternatives(unit, mask)
    local deadSet, aliveSet = 0, 0;
    for _, cell in ipairs(PRESENT_CELLS) do
        if (band(mask, cell[1]) ~= 0) then
            if (cell[3]) then
                deadSet = bor(deadSet, cell[2]);
            else
                aliveSet = bor(aliveSet, cell[2]);
            end
        end
    end
    local alternatives = {};
    local function add(set, life)
        if (set == 0) then
            return;
        end
        for _, tokens in ipairs(REACTION_ALTERNATIVES[set]) do
            local alternative = {};
            for _, token in ipairs(tokens) do
                alternative[#alternative + 1] = token;
            end
            alternative[#alternative + 1] = life;
            alternatives[#alternatives + 1] = alternative;
        end
    end
    if (deadSet == aliveSet) then
        add(deadSet, nil);
    else
        add(deadSet, "dead");
        add(aliveSet, "nodead");
    end

    if (UnitAsksExists(unit)) then
        if (band(mask, Constants.UNITSTATE_NONE) ~= 0) then
            tinsert(alternatives, 1, { "noexists" });
        else
            for _, alternative in ipairs(alternatives) do
                tinsert(alternative, 1, "exists");
            end
        end
    elseif (#alternatives == 0) then
        alternatives[1] = { "known:0" };
    end
    return alternatives;
end

--- One unit's condition as the macro conditional the press parses (`EVAL_SNIPPET`): existence,
--- reaction and life. Answers `expr` for a fixed unit, or `tail` and `tail2` for an alias and the
--- pointed frame, whose token the press puts in front of each (`"[@" .. unit .. tail .. unit ..
--- tail2`). Nothing where there is nothing to parse: a condition on every present cell of a unit
--- whose presence is its existence, or `false` on one.
local function UnitExpression(unit, condition)
    local mask = DebindPrivate.UnitConditionToState(condition);
    if (not UnitAsksExists(unit) and band(mask, Constants.UNITSTATE_EXISTS) == 0) then
        return nil;
    end
    local groups = UnitAlternatives(unit, mask);
    if (#groups[1] == 0) then
        return nil;
    end
    -- A condition is one reaction set and at most one life, so two groups at most.
    assert(#groups <= 2, "a unit condition took more than two groups");
    if (SPECIAL_UNITS[unit]) then
        local tail = "," .. tconcat(groups[1], ",") .. "]";
        if (groups[2]) then
            return nil, tail .. "[@", "," .. tconcat(groups[2], ",") .. "]";
        end
        return nil, tail;
    end
    local parts = {};
    for i, group in ipairs(groups) do
        parts[i] = "[@" .. unit .. "," .. tconcat(group, ",") .. "]";
    end
    return tconcat(parts);
end

Rebuild.ANSWERS_AS_THE_WORD = ANSWERS_AS_THE_WORD;
Rebuild.ParsedStateAxis     = ParsedStateAxis;
Rebuild.REPLACED_BAR_WORDS  = REPLACED_BAR_WORDS;
Rebuild.StateAlternatives   = StateAlternatives;
Rebuild.stateTokens         = _stateTokens;
Rebuild.StateExpression     = StateExpression;
Rebuild.UnitAsksExists      = UnitAsksExists;
Rebuild.UnitAlternatives    = UnitAlternatives;
Rebuild.UnitExpression      = UnitExpression;
