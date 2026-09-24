local _, DebindPrivate = ...;
local L                       = DebindPrivate.L;
local Constants               = DebindPrivate.Constants;

local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;

local band                    = bit.band;
local tinsert                 = tinsert;
local GetMountInfoByID        = C_MountJournal.GetMountInfoByID;
local GetSpellCastName        = DebindPrivate.GetSpellCastName;
local GetSpellNameAndIconID   = DebindPrivate.GetSpellNameAndIconID;
local EquipSlotFacts          = DebindPrivate.EquipSlotFacts;
local GetBindingInfoForAction = DebindPrivate.GetBindingInfoForAction;
local UnitGroupToCells        = DebindPrivate.UnitGroupToCells;
local CellsToUnitGroup        = DebindPrivate.CellsToUnitGroup;

local SUMMON_MOUNT_MACROTEXT = SLASH_SCRIPT1 .. " C_MountJournal.SummonByID(%d)";

--- **`autoUnshift`가 이 경로에 안 닿아서 그 줄이 CVar의 일을 대신한다** (2026-09-21, 소유자가
--- 게임에서). 주문 150544를 행동단축바에 놓고 거기서 쓰면 변신 중에도 해제하고 타는데,
--- `C_MountJournal.SummonByID`로 부르면 `autoUnshift`가 켜져 있어도 해제를 안 한다.
---
--- 드루이드가 아니면 줄 자체가 없다. 다른 직업의 변신은 탈것을 막지 않는다.
local CANCEL_FORM_LINE = select(2, UnitClass("player")) == "DRUID"
    and (SLASH_CANCELFORM1 .. " [form:1/2/5/6,nocombat]\n") or nil;

--- 이 누름이 변신을 해제하는가. 켬과 끔은 그대로 답하고, 셋째 값(게임 설정 그대로)에서는 CVar가
--- 답한다.
function DebindPrivate.UnshiftsWith(value)
    if (value ~= nil) then
        return value;
    end
    return GetCVarBool("autoUnshift") and true or false;
end

function DebindPrivate.UnshiftsForAction(action)
    return DebindPrivate.UnshiftsWith(DebindPrivate.CastAutomaticOf(action, "autoUnshift"));
end

function DebindPrivate.GetMountMacroText(value, unshift)
    if (value == 268435455) then
        value = 0;
    end
    local body = SUMMON_MOUNT_MACROTEXT:format(value);
    if (unshift and CANCEL_FORM_LINE) then
        return CANCEL_FORM_LINE .. body;
    end
    return body;
end

--- The frame an on/off/toggle action clicks, by the name it answers to in a macro body.
---
--- **The string is out there in users' profiles.** `ConvertToMacroText` writes it, and `Legacy.lua`
--- repairs the pre-rename spelling of it inside bodies people typed by hand, so a body naming a
--- switch this way is a reference the same as a condition is. Written once because the readers
--- below have to be looking for exactly what the writer put down (`Switches.lua` gives the frame
--- this name).
local SWITCH_CLICK_TARGET = "DebindStates";

--- The unit key a live `"@"` has to become, and **the stored table it has to be rewritten in**.
--- Nil where it stays `"@"`; a unit with no table where there is one this cannot rewrite.
---
--- **The binding is the judge of live, not the action.** A condition `GetBindingInfoForAction` did
--- not carry onto the binding is not reaching the key, and asking the action again would resurrect it.
---
--- **`none` never moves it.** Its body names `[@none]`, which is no unit to ask, and the macro text is
--- aimed the way `none` already was, like an action with no target. `binding.unit` there can be the
--- `unitframe` a `unitframe` condition filled in, which the body does not go to.
---
--- **It moves only where the body spells the unit out.** The macro text aims at nothing, so from
--- then on its `"@"` asks `target`, or the twins' units with a key held. A body reading
--- `[@focus]` goes to the focus whatever is held, and the condition has to follow it there. A body
--- with no unit in it aims the way the action did, and its `"@"` already resolves the same way:
--- moving it to `target` would keep the press with nothing held and break every held one.
---
--- **But the binding reads units from two places and only one of them can be written back to.**
--- Where `conditions.units` is absent it falls back to the flat pre-`dbver` 6 `checkedUnits`, so a
--- live `"@"` can sit somewhere `conditions.units` has never heard of. Reaching into that shape
--- here would make this the second place that knows the old one; the caller refuses the conversion
--- instead, and it comes back once migration has run.
local function AimedUnitKeyForMacroText(action, binding)
    local live = binding.conditions.units;
    if (live == nil or live["@"] == nil) then
        return nil;
    end

    local unit = binding.unit;
    if (binding.castsAtNone or type(unit) ~= "string" or unit == ""
            or not DebindPrivate.ActionTakesUnit(action)) then
        return nil;
    end

    local stored = action.conditions and action.conditions.units;
    if (stored == nil or stored["@"] == nil) then
        return unit, nil;
    end
    return unit, stored;
end

--- Two stored conditions about one unit, folded onto the one key that can hold them.
---
--- **This has to land on the mask `BuildUnitStates` would have built.** That one narrows a unit
--- with `band` when two keys speak about it, and an intersection of a reaction subset with a life
--- half is itself one of each, so the stored shape can always say the answer.
---
--- `{ exists = true, reaction = 0 }` is the empty one: exists, and in none of the three reactions,
--- which no unit satisfies. Not a new marker -- `UnitFrameConditionFromLegacy` writes the same zero
--- mask where its two sides do not overlap, and `GetBindingIssue` already reads it that way.
---
--- **What the discarded side remembered is gone.** Storage keeps the axes of a condition switched
--- off so the menu can offer them back, and one key cannot hold two sets of them.
---
--- Both sides are tables. `ConditionsSurviveMacroText` refuses the conversion where either is a
--- value this build cannot read, because folding one would drop the mark that says so
--- (`binding.unitConditionUnreadable`).
local function IntersectStoredUnitConditions(a, b)
    if (a == nil or a.disabled) then
        return b;
    end
    if (b == nil or b.disabled) then
        return a;
    end

    local aAbsent = a.exists == false;
    local bAbsent = b.exists == false;
    if (aAbsent or bAbsent) then
        if (aAbsent and bAbsent) then
            return a;
        end
        return { exists = true, reaction = 0 };
    end

    local reaction;
    if (a.reaction == nil) then
        reaction = b.reaction;
    elseif (b.reaction == nil) then
        reaction = a.reaction;
    else
        reaction = band(a.reaction, b.reaction);
    end

    local dead;
    if (a.dead == nil) then
        dead = b.dead;
    elseif (b.dead == nil) then
        dead = a.dead;
    elseif (a.dead ~= b.dead) then
        return { exists = true, reaction = 0 };
    else
        dead = a.dead;
    end

    -- **Every axis a unit condition can carry has to be listed here.** This is the third place one
    -- axis is intersected -- `BuildUnitStates` folds for the solver and `mergeUnitConditions` folds
    -- for the snippet -- and it is the only one that writes the answer back into storage. An axis
    -- left out of the other two makes a binding look wrong; left out of this one it is **deleted
    -- from the profile**, and the conversion replaces the action in place.
    --
    -- Neither of the two below is on `unitStates`, which is what let them go missing quietly:
    -- group and role have columns of their own, so the spec that compares that mask before and
    -- after the fold stays green while the field is gone.
    --- **Folded in cells and brought back**, because the boxes do not intersect as boxes
    --- (`CellsToUnitGroup`). `ConditionsSurviveMacroText` turns away the conversion where the
    --- answer names no box, so what comes back here is never nil.
    local group;
    if (a.group == nil) then
        group = b.group;
    elseif (b.group == nil) then
        group = a.group;
    else
        group = CellsToUnitGroup(band(UnitGroupToCells(a.group), UnitGroupToCells(b.group)));
    end

    local role;
    if (a.role == nil) then
        role = b.role;
    elseif (b.role == nil) then
        role = a.role;
    else
        role = band(a.role, b.role);
    end

    return { exists = true, reaction = reaction, dead = dead, group = group, role = role };
end

--- Whether the conditions this action carries can come along into a macro body.
---
--- Two of them are about the action itself rather than about the world, and a body has nowhere to
--- put either. **Both are dropped by `GetBindingInfoForAction` the moment the type stops being what
--- they are about**, and dropped there is invisible: the row keeps drawing the condition out of
--- storage while the key fires without it.
---
--- `known` is only offered on a type that casts a spell, and nothing takes it off a type that does
--- not (`making-known-a-spell-name.md`). A body sitting in `value` is such a type, so the
--- condition would be dropped on the way out and the row would go on drawing it.
---
--- `"@"` points at the unit the action aims at, and where the body spells that unit out the key has
--- to become the unit's own name (`AimedUnitKeyForMacroText`). Where the name is already taken the
--- two fold into it
--- (`IntersectStoredUnitConditions`), which is the same fold `BuildUnitStates` was doing across
--- the two keys -- **except when a value cannot be read**. Folding one of those would drop the
--- mark that says it was not read, and that mark is what keeps the binding out of two roles it
--- would otherwise take by looking narrower than it is.
local function ConditionsSurviveMacroText(action)
    local binding = GetBindingInfoForAction(action);

    -- **The binding's copy, because it is the normalized one.** A `known` that reaches nothing is
    -- already nil here (`false`, or any type but `SPELL`), and refusing over one of those would
    -- turn away a conversion that changes nothing.
    if (binding.conditions.known) then
        return false;
    end

    -- **Twins do not keep an action from converting** (2026-09-16, owner). A twin stands whether or
    -- not the action takes a unit, and takes one (`which-action-a-key-runs.md` §3). Whether the body
    -- reads that unit is the action's business (`implementing-focus-and-self-cast.md` §4).

    local unit, units = AimedUnitKeyForMacroText(action, binding);
    if (unit) then
        if (units == nil) then
            return false;
        end
        local taken = units[unit];
        if (taken == nil) then
            return true;
        end
        local at = units["@"];
        if (type(at) ~= "table" or type(taken) ~= "table") then
            return false;
        end
        -- **The one fold whose answer may not be storable.** Two group masks whose cells meet on
        -- "in a raid and in my subgroup" name a condition no box combination writes, and every
        -- value that could be written instead is a different condition. The sides the intersection
        -- short-circuits on are asked the same way it asks them, so a conversion it would have
        -- folded cleanly is not turned away.
        --
        -- The `dead` fork is one of them: two sides that disagree there never reach the group
        -- axis at all, so refusing over it would turn away a conversion that folds cleanly.
        local deadConflict = at.dead ~= nil and taken.dead ~= nil and at.dead ~= taken.dead;
        if (at.group and taken.group and not deadConflict
                and not at.disabled and not taken.disabled
                and at.exists ~= false and taken.exists ~= false) then
            local cells = band(UnitGroupToCells(at.group), UnitGroupToCells(taken.group));
            return DebindPrivate.CellsToUnitGroup(cells) ~= nil;
        end
        return true;
    end

    return true;
end

--- Whether the menu stands [Convert to macro text] on this action.
---
--- **What enables it and what carries it out must not part company.** `ConvertToMacroText` does
--- nothing at all when it cannot build a body, and a menu item that does nothing when pressed says
--- why nowhere. A `MACRO` naming one that is not there is that case, and so is one holding no name.
---
--- **`WORLDMARKER` is offered although the body does half of what the key did** (2026-09-23,
--- owner). The action places or takes back, because the binding leaves `*action-` unwritten and the
--- client's default is `toggle` (`SECURE_ACTIONS.worldmarker`). `/wm` only places
--- (`SlashCommands.lua`), taking back is `/cwm`, no conditional tells the two apart, and
--- `PlaceRaidMarker` / `ClearRaidMarker` both carry `HasRestrictions` so `/run` cannot reach them
--- either. What is lost is written in the body the window opens on.
---
--- **`COMMAND` and `UNUSED` convert to an empty body.** Both are retired and already do nothing
--- when pressed (`BINDING_ISSUE_TYPE_RETIRED`), so there is no behaviour to carry over and nothing
--- to lose; what the conversion keeps is the key, the layer and the conditions the row was built
--- with.
function DebindPrivate.CanConvertToMacroText(action)
    if (not ConditionsSurviveMacroText(action)) then
        return false;
    end

    if (action.type == Constants.MACRO) then
        return type(action.value) == "string" and GetMacroInfo(action.value) ~= nil;
    end

    -- An on/off/toggle action that has not been told which switch yet is the same case: the body
    -- is `/click DebindStates <name>-<mode>`, and there is no name to put in it (§6-C).
    if (Constants.SETSTATE_MODES[action.type]) then
        return type(action.value) == "string";
    end

    return action.type == Constants.SPELL
        or action.type == Constants.ITEM
        or action.type == Constants.USESLOT
        or action.type == Constants.MOUNT
        or action.type == Constants.PETACTION
        or action.type == Constants.SETCUSTOM
        or action.type == Constants.WORLDMARKER
        or action.type == Constants.COMMAND
        or action.type == Constants.UNUSED;
end

function DebindPrivate.ConvertToMacroText(action)
    local macrotext, name, icon;

    --- **Where the action aims, which is not always the field.** A hover condition with no target
    --- chosen aims at the hovered unit, and that is derived rather than stored
    --- (`GetBindingInfoForAction`). Read from the field, such an action converts to a body with no
    --- target in it at all -- and a macro body is the only place a `MACROTEXT` can carry one, since
    --- `SECURE_ACTIONS.macro` never looks at the button's unit. The aiming would simply be gone.
    ---
    --- The derived answer also carries the two refusals: `""` where the reader turned hover
    --- targeting off, and nil for a pet command that takes no target.
    ---
    --- **Aiming and the `"@"` condition are two questions off one table**, and they part company on
    --- exactly the derived case (`AimedUnitKeyForMacroText`). Both are read here, before anything
    --- else asks for a binding: the table comes out of a cache and is refilled in place.
    local binding = GetBindingInfoForAction(action);
    local unit = DebindPrivate.CastUnitOf(binding);
    local atUnit, atUnits = AimedUnitKeyForMacroText(action, binding);
    if (unit == "") then
        unit = nil;
    end

    -- **No unit picked writes no target at all** (2026-09-23, owner). This used to write `@@` so the
    -- twins kept reaching the body, but `@@` falls back to `"target"` when the press carries no unit
    -- (`COMPOSE_MACROTEXT_SNIPPET`), which nails a key that followed the client's own targeting to
    -- the current target. Losing the cast keys and Hover Cast on a body the reader now owns is the
    -- smaller change.

    if (action.type == Constants.SPELL or action.type == Constants.ITEM) then
        local slashCommand, spellOrItemName;
        if (action.type == Constants.SPELL) then
            slashCommand = SLASH_CAST1;
            local spellID = C_SpellBook.FindBaseSpellByID(action.value) or action.value;
            local _, spellIcon = GetSpellNameAndIconID(spellID);
            icon = spellIcon;
            -- A pinned rank is the stored id's own, the way the button spells it (`CollectBindingFacts`).
            spellOrItemName = GetSpellCastName(action.pinRank and action.value or spellID, action.pinRank);
            name = spellOrItemName;
        else
            slashCommand = SLASH_USE1;
            spellOrItemName = format("item:%d", action.value);
            name = C_Item.GetItemNameByID(action.value);
            icon = C_Item.GetItemIconByID(action.value);
        end

        if (spellOrItemName) then
            if (unit) then
                macrotext = format("%s [@%s] %s", slashCommand, unit, spellOrItemName);
            else
                macrotext = format("%s %s", slashCommand, spellOrItemName);
            end
        end
    elseif (action.type == Constants.USESLOT) then
        -- **The slot number is the whole body.** `SecureCmdItemParse` reads one bare number as an
        -- inventory slot, which is the same reading the binding's `*item-` gets
        -- (`UpdateBindings.lua`).
        --
        -- Name and icon come from where the row draws them (`ActionDisplay.lua`), because a
        -- macro body's are read out of storage rather than resolved again -- so what is worn
        -- there today is what this row keeps showing.
        local slotName, slotTexture = EquipSlotFacts(action.value);
        if (unit) then
            macrotext = format("%s [@%s] %d", SLASH_USE1, unit, action.value);
        else
            macrotext = format("%s %d", SLASH_USE1, action.value);
        end
        name = slotName;
        icon = GetInventoryItemTexture("player", action.value) or slotTexture;
    elseif (action.type == Constants.MACRO) then
        -- Asked only when the value is a name. Anything else is the shape `GetMissingMacroName`
        -- reports, and `GetMacroInfo(nil)` raises. Leaving it unanswered is the whole handling
        -- needed: the tail below already treats a nil body as "nothing to convert", which is also
        -- the answer for a name whose macro has since been deleted.
        if (type(action.value) == "string") then
            name, icon, macrotext = GetMacroInfo(action.value);
        end
    elseif (action.type == Constants.MOUNT) then
        local spellID;
        name, spellID, icon = GetMountInfoByID(action.value);
        if (spellID) then
            local spellName = GetSpellNameAndIconID(spellID);
            if (spellName) then
                macrotext = SLASH_CAST1 .. " " .. name;
            end
        end

        if (not macrotext) then
            local value = action.value;
            if (value == 0 or value == 268435455) then
                value = 0;
                name, icon = GetSpellNameAndIconID(150544);
            end
            macrotext = DebindPrivate.GetMountMacroText(value,
                DebindPrivate.UnshiftsForAction(action));
        end
    elseif (action.type == Constants.PETACTION) then
        -- 이건 이미 매크로텍스트다 - 바인딩이 나갈 때와 **같은 함수로** 본문을 만든다.
        -- 이름과 아이콘은 액션이 들고 있는 것을 그대로 옮긴다(펫이 없으면 다시 못 푼다).
        macrotext = DebindPrivate.GetPetActionMacroText(action.value, unit);
        name = action.name;
        icon = action.icon;
    elseif (action.type == Constants.SETCUSTOM) then
        macrotext = format("/click DebindCustom%d unitframe", action.value);
        name = L["TYPE_SETCUSTOM" .. action.value];
        icon = 1505950;
    elseif (action.type == Constants.WORLDMARKER) then
        macrotext = format("/wm %d", action.value);
        name = _G["WORLD_MARKER" .. action.value];
        icon = 4238933;
    elseif (action.type == Constants.COMMAND or action.type == Constants.UNUSED) then
        -- **Empty, and that is the whole body.** Neither type does anything when pressed any more,
        -- so there is nothing to write out; the reader writes what the key should do now.
        --
        -- The name is what the row already draws (`ActionDisplay.lua`), which for `UNUSED` is a
        -- description of the retired behaviour rather than a name, so that one is left unset and
        -- draws as `UNNAMED_ACTION`. The icon is the question mark on purpose: the row resolves it
        -- out of the body once there is one (`GetMacrotextIcon`), and the red "not ready" texture
        -- these two wear is an error mark that stops being true here.
        if (action.type == Constants.COMMAND) then
            name = _G["BINDING_NAME_" .. action.value] or action.value;
        end
        macrotext = "";
        icon = Constants.QUESTION_MARK_ICON;
    elseif (Constants.SETSTATE_MODES[action.type]) then
        -- **The body needs a name and a mode, and the action already holds both** -- the name in
        -- `value`, the mode decided by the type. The locale key assembles off the type for the
        -- same reason, which is half of why the type names are underscored (`Constants.lua`).
        macrotext = format("/click %s %s-%s", SWITCH_CLICK_TARGET, action.value,
            Constants.SETSTATE_MODES[action.type]);
        name = format(L["TYPE_" .. strupper(action.type)], action.value);
        icon = 254885;
    end

    -- **nil is "nothing to convert" and `""` is a body.** The retired types convert to an empty
    -- one, so this gate has to keep telling the two apart; a truthiness test that grew an `~= ""`
    -- would turn those conversions into a menu item that does nothing when pressed.
    if (macrotext) then
        if (atUnit and atUnits) then
            atUnits[atUnit] = IntersectStoredUnitConditions(atUnits[atUnit], atUnits["@"]);
            atUnits["@"] = nil;
        end

        action.type = Constants.MACROTEXT;
        action.value = macrotext;
        action.name = name;
        action.icon = icon;
        action.unit = nil;
        return true;
    end
end

do
    local UNIT_SUFFIXES = {
        target = true,
        targettarget = true,
        targettargettarget = true,
        targettargettargettarget = true,
        pet = true,
        pettarget = true,
        pettargettarget = true,
        pettargettargettarget = true,
    };

    local _parsedMacrotextCache = {};
    local _fragments;
    local _args;

    local function appendStr(s)
        if (#_fragments % 2 == 0) then
            tinsert(_fragments, s);
        else
            _fragments[#_fragments] = _fragments[#_fragments] .. s;
        end
    end

    local function lastChar()
        if (#_fragments % 2 == 1) then
            return strsub(_fragments[#_fragments], -1);
        end
    end

    local function appendArg(name, type, sourceString, reverse)
        if (#_fragments % 2 == 0) then
            tinsert(_fragments, "");
        end
        tinsert(_fragments, sourceString or name);
        local t = { name = name, type = type, sourceString = sourceString, reverse = reverse };
        _args[#_fragments / 2] = t;
        return t;
    end

    local function parseOptions(unitsOnly, ...)
        local n = select("#", ...);
        for i = 1, n do
            if (i > 1 and lastChar() ~= ",") then
                appendStr(",");
            end

            local str = select(i, ...);
            str = strtrim(str);
            local token;
            local char = strsub(str, 1, 1);

            if (strsub(str, 1, 1) == "@") then
                token = strsub(str, 2);
                if (token == "@") then
                    appendStr("@");
                    appendArg(token, Constants.MACROTEXT_ARG_PRESS_UNIT);
                elseif (strsub(token, 1, 1) == "@" and UNIT_SUFFIXES[strsub(token, 2)]) then
                    appendStr("@");
                    appendArg("@", Constants.MACROTEXT_ARG_PRESS_UNIT);
                    appendStr(strsub(token, 2));
                elseif (SPECIAL_UNITS[token]) then
                    appendStr("@");
                    appendArg(token, Constants.MACROTEXT_ARG_UNIT);
                else
                    local success;
                    for unit in pairs(SPECIAL_UNITS) do
                        if (strsub(token, 1, unit:len()) == unit) then
                            local s = strsub(token, unit:len() + 1);
                            if (UNIT_SUFFIXES[s]) then
                                appendStr("@");
                                appendArg(unit, Constants.MACROTEXT_ARG_UNIT);
                                appendStr(s);
                                success = true;
                                break;
                            end
                        end
                    end
                    if (not success) then
                        appendStr(str);
                    end
                end
            elseif (not unitsOnly) then
                token = str;

                local arg, reverse;
                if (strsub(token, 1, 2) == "no") then
                    reverse = true;
                    token = strsub(token, 3);
                    char = strsub(token, 1, 1);
                end

                if (char == "$") then
                    if (strmatch(strsub(token, 2), "^([a-zA-Z0-9_]+)$")) then
                        arg = appendArg(token, Constants.MACROTEXT_ARG_SWITCH, str, reverse);
                    end
                end

                if (not arg) then
                    appendStr(str);
                end
            else
                appendStr(str);
            end
        end
    end

    function DebindPrivate.ParseMacroText(str, unitsOnly)
        local cached = _parsedMacrotextCache[str];

        if (cached == nil) then
            _fragments = {};
            _args = {};

            local lines = { strsplit("\n", str) };

            for lineNum, line in ipairs(lines) do
                if (lineNum > 1) then
                    appendStr("\n");
                end

                -- 명령 이름에서 `[`를 빼야 `/cast[@tank]`처럼 공백 없이 붙은 형태가
                -- 걸린다. 뒤 공백도 `%s*` -- 있어도 되고 없어도 된다.
                local slashcmd, idx = strmatch(line, "^(%s*/[^%s%[]+%s*)()");
                if (slashcmd) then
                    appendStr(slashcmd);
                else
                    idx = 1;
                end

                while (idx) do
                    local s1, nextIndex = strmatch(line, "^%s*%[([^%]]*)%]()", idx);
                    if (s1) then
                        appendStr("[")
                        parseOptions(unitsOnly, strsplit("[,]", s1));
                        appendStr("]");
                        idx = nextIndex;

                        -- 대괄호 그룹이 곧바로 이어지면 같은 절의 조건이 계속되는 것(OR).
                        -- 여기서 멈추면 두 번째 이후 그룹의 @특수유닛/$상태가 통째로
                        -- 리터럴로 새어나간다.
                        if (not strmatch(line, "^%s*%[", idx)) then
                            local body, afterBody = strmatch(line, "^([^%;]*)()", idx);
                            appendStr(strtrim(body));

                            if (strsub(line, afterBody, afterBody) == ";") then
                                appendStr(";");
                                idx = afterBody + 1;
                            else
                                break;
                            end
                        end
                    else
                        appendStr(strsub(line, idx))
                        break;
                    end
                end
            end

            -- Odd slots are text, even slots are argument slots. What sits in an even slot is
            -- **the source token itself** (`tank` for `@tank`, `no$state1`), and the restricted
            -- side overwrites those slots in its own copy before concatenating. Nothing touches
            -- the table cached here, so `table.concat` on it is the macro body as this parser
            -- read it, which is what a caller wanting the normalized text builds for itself.
            if (#_fragments > 1) then
                cached = { _fragments, _args };
            else
                cached = false;
            end

            _parsedMacrotextCache[str] = cached;
        end

        if (cached) then
            return cached[1], cached[2];
        else
            return str;
        end
    end

    function DebindPrivate.ClearMacroTextCache(excludes)
        for k in pairs(_parsedMacrotextCache) do
            if (not excludes or excludes[k] == nil) then
                _parsedMacrotextCache[k] = nil;
            end
        end
    end

    --- The same body with every `@<from>` unit token pointed at `@<to>`, suffix kept.
    ---
    --- **Written for the migration that renames a unit, and it cannot go through
    --- `ParseMacroText`.** That parser finds a unit token by asking `Constants.SPECIAL_UNITS`, and
    --- a step renaming a unit runs in a build where the old name has already left that table -- so
    --- the token it has to rewrite is exactly the one the parser has stopped recognising. The step
    --- hands the old name in, the way every frozen step in `Migration.lua` holds its own literals.
    ---
    --- **Whole tokens inside `[...]`, never substrings.** `@hovering` is not the unit `hover`, and
    --- `/say [@hover]` outside a condition position is text -- the same boundary
    --- `StripSwitchConditions` keeps, for the same reason. A suffix the parser accepts
    --- (`@hovertarget`) is part of the token and rides across onto the new name.
    function DebindPrivate.RenameUnitInMacroText(str, from, to)
        if (type(str) ~= "string" or not strfind(str, "@" .. from, 1, true)) then
            return str;
        end
        return (str:gsub("%[([^%[%]]*)%]", function(body)
            local touched = false;
            local tokens = { strsplit(",", body) };
            for i = 1, #tokens do
                local token = tokens[i];
                local trimmed = strtrim(token);
                if (strsub(trimmed, 1, 1) == "@") then
                    local rest = strsub(trimmed, 2);
                    local suffix;
                    if (rest == from) then
                        suffix = "";
                    elseif (strsub(rest, 1, from:len()) == from
                            and UNIT_SUFFIXES[strsub(rest, from:len() + 1)]) then
                        suffix = strsub(rest, from:len() + 1);
                    end
                    if (suffix) then
                        -- The spacing around the token is the user's and is kept. Only the name moves.
                        tokens[i] = (strmatch(token, "^%s*") or "") .. "@" .. to .. suffix
                            .. (strmatch(token, "%s*$") or "");
                        touched = true;
                    end
                end
            end
            if (not touched) then
                return nil;
            end
            return "[" .. table.concat(tokens, ",") .. "]";
        end));
    end
end


do
    --- 조건절에서 `$상태` 토큰만 걷어낸 사본.
    ---
    --- 아이콘을 뽑을 때 쓴다. `GetMacrotextIcon`(ActionDisplay.lua)은 매크로텍스트를 **진짜 매크로
    --- 슬롯에 써넣어서** 와우가 동적 아이콘을 계산하게 만드는데, 와우 파서는 조건을 훑다가 모르는
    --- 옵션을 만나면 대화창에 "Unknown macro option: $state1"을 찍는다. 우리 상태 토큰이 전부
    --- 여기 걸린다. 특수 유닛(`@custom1`)은 모르는 유닛이면 조건이 조용히 실패할 뿐이라 남겨둔다.
    ---
    --- 뺀 자리는 **채우지 않는다** = 그 조건을 참으로 치는 셈이고, 남은 토큰이 없으면 `[]`가
    --- 되는데 빈 조건은 와우에서 항상 참이다. 보안 스니펫이 상태가 켜졌을 때 하는 일과 같다
    --- (`SecureBindings.lua`; 꺼지면 `known:0`). 진짜 상태값은 보안 환경 안이라 못 읽으므로,
    --- 아이콘은 "그 상태가 켜졌을 때 나갈 것"을 보여준다.
    ---
    --- `ParseMacroText`를 태우지 않는 이유: 그쪽은 `$[a-zA-Z0-9_]+`만 인자로 인정해서
    --- `$foo-bar` 같은 어긋난 토큰을 리터럴로 흘려보내는데, 와우는 **그것도** 똑같이 오류를
    --- 찍는다. 여기서는 `$`로 시작하는 토큰이면 전부 버린다.
    local function isSwitchToken(token)
        token = strtrim(token);
        if (strsub(token, 1, 2) == "no") then
            token = strsub(token, 3);
        end
        return strsub(token, 1, 1) == "$";
    end

    --- `$`가 없는 그룹은 nil을 돌려준다 = gsub이 원문을 그대로 둔다. 조건이 아닌 대괄호
    --- (`/say [안녕]`)를 건드리지 않으려면 이 "손 안 댐"이 글자 단위로 지켜져야 한다.
    local function stripGroup(body)
        if (not strfind(body, "$", 1, true)) then
            return nil;
        end

        local kept = {};
        local tokens = { strsplit(",", body) };
        for i = 1, #tokens do
            if (not isSwitchToken(tokens[i])) then
                kept[#kept + 1] = tokens[i];
            end
        end
        return "[" .. table.concat(kept, ",") .. "]";
    end

    local _renameFrom, _renameTo;

    --- One condition group, with every token naming `_renameFrom` renamed. nil leaves it alone.
    local function renameGroup(body)
        if (not strfind(body, "$", 1, true)) then
            return nil;
        end

        local touched = false;
        local tokens = { strsplit(",", body) };
        for i = 1, #tokens do
            local token = tokens[i];
            local trimmed = strtrim(token);
            local prefix = "";
            if (strsub(trimmed, 1, 2) == "no") then
                prefix = "no";
                trimmed = strsub(trimmed, 3);
            end
            if (trimmed == _renameFrom) then
                -- The spacing around the token is the user's and is kept. Only the name moves.
                tokens[i] = (strmatch(token, "^%s*") or "") .. prefix .. _renameTo
                    .. (strmatch(token, "%s*$") or "");
                touched = true;
            end
        end

        if (not touched) then
            return nil;
        end
        return "[" .. table.concat(tokens, ",") .. "]";
    end

    --- Every `/click DebindStates <button>` in a body, button by button. `fn` is handed the raw
    --- button token and whatever it answers, if anything, is answered from here.
    ---
    --- **The button is one whitespace-run token**, because `/click` reads it that way: a third
    --- argument after it is the down/up flag and has nothing to do with which switch is worked.
    local function eachClickButton(str, fn)
        for button in str:gmatch(SWITCH_CLICK_TARGET .. "%s+(%S+)") do
            local answer = fn(button);
            if (answer) then
                return answer;
            end
        end
    end

    --- The switch one such button works, or nil where it works none.
    ---
    --- **`Switches.lua`'s `_onclick` is the grammar and this has to read it the same way.** The
    --- mode is split off at the first `-`, a bare number is shorthand for `$state<n>`, and a token
    --- that does not end up starting with `$` is one that handler quietly does nothing with.
    local function switchForClickButton(button)
        local name = strsplit("-", button, 2);
        local num = tonumber(name);
        if (num) then
            name = "$state" .. num;
        end
        if (strsub(name, 1, 1) ~= "$") then
            return nil;
        end
        return name;
    end

    --- The switch each `/click DebindStates …` line in this body works. `fn` is called with each
    --- name in the order they appear and the first answer it gives is handed back.
    ---
    --- **This is a fifth place a body names a switch, and we are the ones who put it there.**
    --- [Convert to macro text] opens an on/off/toggle action out into one of these lines
    --- (`ConvertToMacroText`), so a reference that used to sit in `action.value` where every walk
    --- could see it moves inside a string where none of them could.
    function DebindPrivate.ForEachClickedSwitch(str, fn)
        if (type(str) ~= "string" or not strfind(str, SWITCH_CLICK_TARGET, 1, true)) then
            return nil;
        end
        return eachClickButton(str, function(button)
            local name = switchForClickButton(button);
            if (name) then
                return fn(name);
            end
        end);
    end

    --- The same body with every `/click DebindStates <from>` pointed at `to`.
    ---
    --- The mode is left exactly as it was: it is not part of the name, and a button written with a
    --- trailing `-` or with no mode at all means the same thing after the rename as before it.
    local function renameClickedSwitch(str, from, to)
        return (str:gsub("(" .. SWITCH_CLICK_TARGET .. "%s+)(%S+)", function(head, button)
            local token, mode = strsplit("-", button, 2);
            if (switchForClickButton(token) ~= from) then
                return nil;
            end
            if (mode) then
                return head .. to .. "-" .. mode;
            end
            return head .. to;
        end));
    end

    --- The same macro text with every `[$from]`, `[no$from]` and `/click DebindStates <from>`
    --- renamed to `to`.
    ---
    --- **Whole tokens, never substrings.** A plain `gsub` on the name would also rewrite `$burstx`
    --- and `[@$burst]`, and what is being edited here is text the user typed by hand. Anything
    --- this touches that was not exactly this switch is a macro they have to find and fix without
    --- being told it changed.
    ---
    --- **Inside `[...]`, and after the frame name, and nowhere else.** The first boundary is the
    --- one `StripSwitchConditions` keeps and for the same reason: `/say [$burst]` outside a
    --- condition position is text. The second is a position too - what follows `DebindStates` is
    --- read as a switch by the handler on the other end, so a name there is as much a reference as
    --- one in a condition.
    ---
    --- Renaming a switch has to rewrite five kinds of reference and this is the one that cannot be
    --- done by moving a key: a condition, an on/off/toggle target and another switch's expression
    --- each hold the name whole, while a macro body holds it inside a sentence
    --- (`redesigning-custom-states.md` §3).
    function DebindPrivate.RenameSwitchInMacroText(str, from, to)
        if (not str) then
            return str;
        end
        if (strfind(str, from, 1, true)) then
            _renameFrom, _renameTo = from, to;
            str = (str:gsub("%[([^%[%]]*)%]", renameGroup));
        end
        -- **Asked separately, because the number shorthand carries no `$` to find.**
        -- `/click DebindStates 1` names `$state1` without those seven characters appearing in the
        -- body at all, so the guard above would answer no for a body that has to be rewritten.
        if (strfind(str, SWITCH_CLICK_TARGET, 1, true)) then
            str = renameClickedSwitch(str, from, to);
        end
        return str;
    end

    function DebindPrivate.StripSwitchConditions(str)
        if (not str or not strfind(str, "$", 1, true)) then
            return str;
        end
        -- 본문에서 `[`도 뺀다. `[^%]]*`만 쓰면 **닫히지 않은 대괄호**가 다음 그룹을 삼킨다 -
        -- `[combat [$state1]`이 본문 `combat [$state1` 하나로 잡히고, 콤마로 가르면 토큰이
        -- `combat [$state1` 한 덩어리라 `$`로 시작하지 않는다. 그대로 통과해서 `$state1`이
        -- 게임까지 가고, 이 함수가 막으려던 바로 그 오류가 채팅에 찍힌다.
        -- `[`를 빼면 안쪽 그룹부터 잡히므로 사용자가 친 대괄호가 어긋나 있어도 토큰은 걸러진다.
        return (str:gsub("%[([^%[%]]*)%]", stripGroup));
    end
end
