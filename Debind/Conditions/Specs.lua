local _, DebindPrivate = ...;
local L         = DebindPrivate.L;
local Constants = DebindPrivate.Constants;

local band      = bit.band;

--- Every specialization one class has, in the client's order, as `{ id = , index = , name = }`.
---
--- **The index is what the condition stores** and the id is what names a row
--- (`legacy/giving-the-spec-condition-a-class-key.md` §3). They part on a class of
--- two: its third row is index 5, not 3.
---
--- **The initial specialization is visited on top of the count, not inside it.** The count stops
--- at the named ones, and a class with two of those has its initial one at index 5 all the same
--- (`Constants.INITIAL_SPEC_INDEX`), so a loop that ran to the count would drop it and a loop that
--- ran to 5 would ask for two specializations that do not exist.
---
--- **The initial one has an id and no name**, and its row carries `name = nil` rather than a word
--- picked here. What a nameless specialization is called on screen is the drawing side's to say,
--- and it says it twice already (`ActionMenuNodes.lua`, `ActionTooltip.lua`).
---
--- `GetSpecializationInfoForClassID` is a global rather than one of `C_SpecializationInfo`'s, and
--- it is the only way to name a specialization of a class that is not this character's.
function DebindPrivate.EnumerateClassSpecs(classID, out)
    out = out or {};
    local count = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0;
    for index = 1, count do
        local id, name = GetSpecializationInfoForClassID(classID, index);
        if (id) then
            out[#out + 1] = { id = id, index = index, name = name };
        end
    end
    local initialID = GetSpecializationInfoForClassID(classID, Constants.INITIAL_SPEC_INDEX);
    if (initialID) then
        out[#out + 1] = { id = initialID, index = Constants.INITIAL_SPEC_INDEX };
    end
    return out;
end

local specCatalog, specMaskByClassID;

--- Every class somebody can play, in the client's own order, each carrying its specializations
--- (`EnumerateClassSpecs`). The one enumeration behind both places that draw specializations by
--- name: the condition menu groups it and the tooltip flattens it.
---
--- **Not `Constants.CLASS_IDS`, which holds more than the playable classes.** That table is built
--- from `C_CreatureInfo.GetClassInfo` over a range of ids, and ids nobody can play answer it too:
--- `Adventurer` came out as a class of its own in the condition menu. The playable ones are what
--- the client's own class menu walks, which is `Client.PlayableClasses`.
---
--- **Built once and kept.** Nothing in it moves while the client is up, and both readers are on a
--- path that runs per draw.
---
--- **The order is the client's own, and it is what makes a tooltip line stable.** Walking the
--- stored set with `pairs` instead would name the same specializations in a different order on two
--- draws of one action.
function DebindPrivate.ClassSpecCatalog()
    if (specCatalog) then
        return specCatalog;
    end
    specCatalog = {};
    specMaskByClassID = {};
    for _, class in ipairs(DebindPrivate.Client.PlayableClasses()) do
        local entry = {
            id = class.id,
            classFile = class.classFile,
            specs = DebindPrivate.EnumerateClassSpecs(class.id),
        };
        specCatalog[#specCatalog + 1] = entry;
        -- **Summed here rather than where it is asked.** The specialization judgment asks for it
        -- once per binding per rebuild, and a second table with a life of its own is a second
        -- thing to drop.
        local mask = 0;
        for i = 1, #entry.specs do
            mask = mask + Constants.SpecIndexFlag(entry.specs[i].index);
        end
        specMaskByClassID[class.id] = mask;
    end
    return specCatalog;
end

local SPEC_LINE_NAME_LIMIT = 3;


--- The bits one class actually carries. **The initial specialization is one of them**: it is a
--- state a character of that class can be sitting in, so leaving it out would make "while I am a
--- druid" false in one of the worlds it names.
---
--- **One mask per class and not one for all of them.** A class of two specializations has 1, 2 and
--- 5 and nothing at 3 or 4, so a shared mask would hold bits that stand for nothing there, and a
--- stored value carrying one of them would read as a specialization that does not exist.
---
--- Off the catalog, which is where it is summed. 0 for a class nobody plays, which is a class the
--- catalog does not carry.
function DebindPrivate.ClassSpecMask(classID)
    if (specMaskByClassID == nil) then
        DebindPrivate.ClassSpecCatalog();
    end
    return specMaskByClassID[classID] or 0;
end

--- One class's mask off a stored condition. nil where the class holds nothing, and **0 where what
--- is stored is not a mask at all.**
---
--- **The wire does not reach this deep.** `ConditionAllowed` types the condition itself and stops
--- (`DebindStorage/Import.lua`), the way it does for `units` and `talents`, so a hand-made string
--- can leave anything under a class id. It used to be read by indexing and anything was harmless;
--- it is arithmetic now, and `band` on a boolean raises inside the rebuild. 0 rather than nil,
--- because a value nobody can read must make the condition true less often rather than more: the
--- direction a keybinding addon must not fail in is the one that takes somebody else's key.
local function MaskFor(specs, classID)
    local mask = specs[classID];
    if (mask == nil) then
        return nil;
    end
    if (type(mask) ~= "number") then
        return 0;
    end
    return mask;
end

--- Does this condition hold **every** specialization of one class.
---
--- **What is stored is what is picked.** A class with no key holds nothing, and the whole condition
--- being absent holds nothing at all: `nil` is the axis switched off, which the menu draws with
--- every box clear (2026-09-22, owner).
---
--- **One answer for the two places that ask.** The menu's class box is ticked by it and the tooltip
--- line folds a class to its name by it, so neither can disagree about what a whole class is.
function DebindPrivate.SpecSetHoldsClass(specs, classID)
    if (specs == nil) then
        return false;
    end
    local mask = MaskFor(specs, classID);
    if (mask == nil) then
        return false;
    end
    local classMask = DebindPrivate.ClassSpecMask(classID);
    if (classMask == 0) then
        return false;
    end
    return band(mask, classMask) == classMask;
end

--- Does this condition hold **one** specialization of one class.
function DebindPrivate.SpecSetHoldsIndex(specs, classID, index)
    if (specs == nil) then
        return false;
    end
    local mask = MaskFor(specs, classID);
    if (mask == nil) then
        return false;
    end
    if (index == nil) then
        return false;
    end
    return band(mask, Constants.SpecIndexFlag(index)) ~= 0;
end

--- Put one whole class in, or take it out. **Out is written as no key at all**, which is the one
--- shape a class holding nothing has, so an empty mask never has to be told from a missing one.
function DebindPrivate.SetClassInSpecSet(specs, classID, turnOn)
    if (turnOn) then
        specs[classID] = DebindPrivate.ClassSpecMask(classID);
    else
        specs[classID] = nil;
    end
    return specs;
end

--- One class's mask, guarded, for a caller outside this file. **Every reader of a stored mask goes
--- through `MaskFor`**, because the value under a class id is whatever a shared string put there
--- and `band` on a boolean raises inside the rebuild.
function DebindPrivate.SpecSetMaskFor(specs, classID)
    if (specs == nil) then
        return nil;
    end
    return MaskFor(specs, classID);
end

--- Does this condition hold **any** specialization of one class, which is what paints that class's
--- row in the menu. A class whose box is ticked answers yes and so does one with a single
--- specialization under it ticked; the two are told apart by the box, not by this.
function DebindPrivate.SpecSetHoldsAnyOfClass(specs, classID)
    if (specs == nil) then
        return false;
    end
    local mask = MaskFor(specs, classID);
    if (mask == nil) then
        return false;
    end
    return band(mask, DebindPrivate.ClassSpecMask(classID)) ~= 0;
end

--- Is there a specialization this condition holds. **A condition holding none says the same thing
--- as no condition at all**, so the menu drops it rather than keeping two ways to say it.
function DebindPrivate.SpecSetHoldsAnything(specs)
    if (specs == nil) then
        return false;
    end
    local catalog = DebindPrivate.ClassSpecCatalog();
    for i = 1, #catalog do
        if (DebindPrivate.SpecSetHoldsAnyOfClass(specs, catalog[i].id)) then
            return true;
        end
    end
    return false;
end

--- Does a condition that is there hold no specialization at all, which is the error the reader is
--- meant to see (`BINDING_ISSUE_SPECS_NONE_SELECTED`).
---
--- **Unticking the last box is how the reader reaches it**, and the table is left standing for
--- exactly that (`NormalizeSpecCondition`): switching the axis off is the `Off` radio, and a
--- key that fires nowhere is told so rather than quietly becoming a key with no condition.
function DebindPrivate.SpecSetIsEmpty(specs)
    if (specs == nil) then
        return false;
    end
    return not DebindPrivate.SpecSetHoldsAnything(specs);
end

--- One `conditions.specs` set as a line to read, in one sentence: **this character's class is
--- described by specialization and every other class by class.**
---
--- The reader plays one class, so those are the only specializations that can ever fire for them
--- and the only ones worth a name. What the rest of the set answers is "who else is this for",
--- which the class name says in a fraction of the room.
---
--- **A class picked whole is the class, not its specializations.** Ticking every box under one is
--- what "while I am a priest" is, and spelling that out as four names takes four times the space
--- to say something less. It is also what keeps the nameless initial specialization out of the
--- middle of a list, where it would read as a specialization called "None chosen".
---
--- **This character's own are never dropped**, however many they run to: they are the half
--- the reader can act on. What the overflow eats is other classes.
---
--- **Each name carries its class colour.** Specialization names repeat across classes -- Frost is
--- a mage's and a death knight's, Holy is a priest's and a paladin's -- so a name on its own does
--- not say which one was picked.
---
--- **No count on the overflow.** The named part is specializations on one side and classes on the
--- other, so a number after it would be counting two different things at once.
---
--- **Walked class by class rather than over the set.** `pairs` over the ids would order the names
--- differently between two draws of one action, an id this build cannot name would have nothing
--- to print, and the class a colour comes from is not in the set at all.
function DebindPrivate.DescribeSpecCondition(specs)
    local mine, others = {}, {};
    local catalog = DebindPrivate.ClassSpecCatalog();
    for i = 1, #catalog do
        local class = catalog[i];
        local classSpecs = class.specs;
        local color = GetClassColorObj(class.classFile) or NORMAL_FONT_COLOR;
        local className = Constants.CLASS_NAMES[class.classFile];

        local picked = {};
        for j = 1, #classSpecs do
            if (DebindPrivate.SpecSetHoldsIndex(specs, class.id, classSpecs[j].index)) then
                picked[#picked + 1] = classSpecs[j].name or L["NO_SPECIALIZATION"];
            end
        end
        local whole = DebindPrivate.SpecSetHoldsClass(specs, class.id);

        if (#picked > 0) then
            local out = (class.classFile == Constants.PLAYER_CLASS) and mine or others;
            if (out == others or whole) then
                out[#out + 1] = color:WrapTextInColorCode(className);
            else
                for j = 1, #picked do
                    out[#out + 1] = color:WrapTextInColorCode(picked[j]);
                end
            end
        end
    end

    local shown = {};
    for i = 1, #mine do
        shown[i] = mine[i];
    end
    -- **Only the other classes are counted against the limit.** This character's are all in
    -- `shown` before the loop starts, so a class of five picked whole leaves the loop with nothing
    -- to add rather than pushing one of them out.
    for i = 1, #others do
        if (#shown >= SPEC_LINE_NAME_LIMIT) then
            break;
        end
        shown[#shown + 1] = others[i];
    end

    local line = table.concat(shown, ", ");
    if (#shown < #mine + #others) then
        return format(L["LINE_TOOLTIP_SPEC_OVERFLOW"], line);
    end
    return line;
end

--- The id of one of **this character's** specializations, by index. nil where the index names
--- nothing, which is what a class with fewer specializations answers for the indices it skips.
function DebindPrivate.SpecIDForIndex(index)
    if (index == nil) then
        return nil;
    end
    return (C_SpecializationInfo.GetSpecializationInfo(index));
end

--- Whether this binding's specialization condition holds for the character right now.
---
--- **The one condition answered out here instead of on the restricted side.** A specialization
--- cannot change in combat and the change rebuilds everything
--- (`Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED`), so a binding that fails this is left out of
--- the build rather than given a state driver, a solver column and a snippet line
--- (`.zzz/clique-savedvars.md`, the `sets.specN` row).
---
--- **A nil index takes the binding out, not in.** `CanBuildBindings` refuses to build at all in
--- that window (`UpdateBindings.lua`), so this is reached only by a caller that builds the key map
--- on its own, and the safe answer there is the one that binds nothing, since the alternative is
--- a key that fires the wrong action for as long as the window lasts.
---
--- **`spec` is the world being asked about, and the rebuild is not the only caller.** The window
--- draws another specialization's order on request (`Profile.lua`'s `MakeRow`), and asking there
--- with the index the character happens to be on would mark the rows of the very specialization
--- the reader opened.
--- **An action answers this as well as a binding does.** What it reads is `conditions.specs`, and
--- `FillBinding` carries that field across untouched. The tooltip has the action in hand and
--- rebuilding a binding there would cost one per row per draw (`GetBindingInfoForAction`).
function DebindPrivate.SpecConditionHolds(actionOrBinding, spec)
    local conditions = actionOrBinding.conditions;
    local specs = conditions and conditions.specs;
    if (specs == nil) then
        return true;
    end
    -- **A condition holding nothing at all is not another specialization's.** No specialization
    -- satisfies it, so a reader waiting for the right one to come round will wait forever: the
    -- action is wrong, and it already has a word for that
    -- (`BINDING_ISSUE_SPECS_NONE_SELECTED`).
    --
    -- Every caller here is asking the same question, "does this belong to a world other than the
    -- one on screen", and for that shape the answer is no. Answering `false` instead put it in
    -- the same bucket as an off-specialization action three times over: `BuildKeyMap` left it out
    -- of `ActiveActions`, so the key heading -- which asks only active rows whether one is broken
    -- -- drew plain over a dead key while the row under it showed the error; and the tooltip added
    -- "not the one being played" beside a line already saying nothing was chosen.
    --
    -- **The error gate is what keeps it off the key**, the same gate every other ERROR goes
    -- through (`Debind.lua`). Nothing is lost by letting it past this one.
    --
    -- **A set whose masks are unreadable arrives here as an empty one and takes the same road.**
    -- `MaskFor` turns a value a shared string left under a class id into 0, so it holds nothing,
    -- and `SPECS_NONE_SELECTED` is an OMIT outcome (`Constants.BINDING_ISSUE_OUTCOMES`): the key
    -- is kept clear by the gate rather than by this answer. Answering `false` for it instead would
    -- set `specExcluded` on a row that is also carrying the error, which is the one pair
    -- `MakeRow` is written to prevent (`Profile.lua`).
    if (DebindPrivate.SpecSetIsEmpty(specs)) then
        return true;
    end
    local classID = Constants.CLASS_IDS[Constants.PLAYER_CLASS];
    if (classID == nil) then
        -- The same direction a specialization that is not settled yet takes, and for the same
        -- reason: a class nobody can name is a condition nobody can judge, and the answer that
        -- binds nothing beats the one that fires the wrong thing.
        return false;
    end
    local mask = MaskFor(specs, classID);
    if (mask == nil) then
        -- **A class with no key is a class nobody picked.** The condition names who it is for, so
        -- a class left out of it is one the key is not for.
        return false;
    end
    if (spec == nil) then
        spec = C_SpecializationInfo.GetSpecialization();
    end
    if (spec == nil) then
        return false;
    end
    return band(mask, Constants.SpecIndexFlag(spec)) ~= 0;
end
