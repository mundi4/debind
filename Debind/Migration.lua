local _, DebindPrivate = ...;

local Constants           = DebindPrivate.Constants;
local luatype             = type;
-- The `dbver` 5 step that opens the old `setstate` bitpack, and version 5's hover fold.
local band                = bit.band;

-- Each step's own version's values (`MigrateLayer`'s header), built once rather than per list.

--- The units a version 1 profile could name.
local UNITS_AT_1          = {
    mouseover = true, player = true, pet = true, target = true, focus = true, none = true,
    tank = true, healer = true, maintank = true, mainassist = true, custom1 = true, custom2 = true,
    hover = true,
};

--- The names version 6 gave the five numbered switches, by number. Both `dbver <= 5` steps read it:
--- the layer step opens the `setstate` bitpack into it, and `MigrateSwitches` re-files the
--- definitions by it.
local SWITCH_NAMES_AT_6   = { "$state1", "$state2", "$state3", "$state4", "$state5" };

local SPEC_RESOLVED_AT_7  = { dispel = true, raidbuff = true, resurrect = true };

--- The command names version 7 ran as an action button: the main bar, the seven fixed bars, the
--- extra button, and the pet and stance bars.
local ACTION_BUTTON_COMMANDS_AT_7 = { EXTRAACTIONBUTTON1 = true };
for i = 1, 12 do
    ACTION_BUTTON_COMMANDS_AT_7["ACTIONBUTTON" .. i] = true;
    for bar = 1, 7 do
        ACTION_BUTTON_COMMANDS_AT_7["MULTIACTIONBAR" .. bar .. "BUTTON" .. i] = true;
    end
end
for i = 1, 10 do
    ACTION_BUTTON_COMMANDS_AT_7["BONUSACTIONBUTTON" .. i] = true;
    ACTION_BUTTON_COMMANDS_AT_7["SHAPESHIFTBUTTON" .. i] = true;
end

--- **A step's rules are its version's too, not only its values.** A step that asked today's reader
--- of a unit condition or of macro text would read an old value by today's rules: one still valid in
--- its version could be read away before the step that retires it, which is the only step that may
--- (owner, 2026-10-09). The readers below are what those versions ran.

--- A stored unit condition read the way version 5 read it: nil for none or turned off, which that
--- version called `off`; `false` for [when there is none]; a table of the axes otherwise.
local function UnitConditionAt5(value)
    if (value == nil) then
        return nil;
    elseif (value == true) then
        return {};
    elseif (value == false) then
        return false;
    elseif (value == "help") then
        return { reaction = 1 };
    elseif (value == "harm") then
        return { reaction = 2 };
    elseif (luatype(value) ~= "table") then
        return false;
    end
    if (value.off) then
        return nil;
    elseif (value.exists == false) then
        return false;
    end
    return { reaction = value.reaction, dead = value.dead, role = value.role, group = value.group,
        frameTypes = value.frameTypes };
end

--- The same as version 7 read it: the turned-off row is `disabled` from there on (the `dbver <= 6`
--- step renames it). A scalar is one of the four that came before tables; anything else reads as
--- [when there is none].
local function UnitConditionAt7(value)
    if (value == nil) then
        return nil;
    elseif (value == true) then
        return {};
    elseif (value == false) then
        return false;
    elseif (value == "help") then
        return { reaction = 1 };
    elseif (value == "harm") then
        return { reaction = 2 };
    elseif (luatype(value) ~= "table") then
        return false;
    end
    if (value.disabled) then
        return nil;
    elseif (value.exists == false) then
        return false;
    end
    return { reaction = value.reaction, dead = value.dead, role = value.role, group = value.group,
        frameTypes = value.frameTypes };
end

--- Version 5's fold of the old `hover`/`reactions` pair into the pointed frame's row. `existing` is
--- that row as `UnitConditionAt5` reads it (the step has just made it a table). **Intersects** rather
--- than overwrites, since dropping either side would widen a binding; where the two do not overlap
--- the answer is `reaction = 0`, a row no unit satisfies.
local function UnitFrameConditionAt5(hover, reactions, existing)
    if (hover == false) then
        if (existing == nil or existing == false) then
            return false;
        end
        return { reaction = 0 };
    end
    if (existing == false) then
        return { reaction = 0 };
    end
    local reaction = reactions;
    if (reaction == 7) then
        reaction = nil;
    end
    local folded = luatype(existing) == "table" and existing or {};
    if (reaction == nil) then
        reaction = folded.reaction;
    elseif (folded.reaction ~= nil) then
        reaction = band(reaction, folded.reaction);
    end
    folded.reaction = reaction;
    return folded;
end

--- The unit suffixes version 7's macro parser took after a unit name.
local UNIT_SUFFIXES_AT_7 = {
    target = true, targettarget = true, targettargettarget = true, targettargettargettarget = true,
    pet = true, pettarget = true, pettargettarget = true, pettargettargettarget = true,
};

--- `from` renamed to `to` wherever a macro body's conditions aim at it, as version 7 did it. Both
--- `dbver <= 6` steps call it, and so does the payload's own (`Export.lua`).
---
--- **It cannot go through `ParseMacroText`.** That parser finds a unit token by asking
--- `Constants.SPECIAL_UNITS`, and the old name has already left that table, so the token to
--- rewrite is exactly the one the parser stopped recognising.
---
--- **Whole tokens inside `[...]`, never substrings.** `@hovering` is not the unit `hover`, and
--- `/say [@hover]` outside a condition position is text -- the boundary `StripSwitchConditions`
--- keeps, for the same reason. A suffix the parser accepted (`@hovertarget`) rides across onto the
--- new name, and the spacing around the token is the user's.
local function RenameUnitInMacroTextAt7(str, from, to)
    if (luatype(str) ~= "string" or not strfind(str, "@" .. from, 1, true)) then
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
                        and UNIT_SUFFIXES_AT_7[strsub(rest, from:len() + 1)]) then
                    suffix = strsub(rest, from:len() + 1);
                end
                if (suffix) then
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
DebindPrivate.RenameUnitInMacroTextAt7 = RenameUnitInMacroTextAt7;

--- Raises one layer's array of actions from `dbver` to `Constants.DB_VERSION`.
---
--- **Every step opens with `dbver <= N and N < to`, never `== N`.** With `==`, a profile two
--- versions behind walks the first step and leaves. A profile never meets a step twice
--- (`TryMigrateDB`), but a drawer entry can: the drawer raises its entries in place (`Vars` in
--- `Import.lua`), and one stopped partway keeps its old `dbver`. So a step a payload reaches is
--- written to be safe to run again on data it has already finished, except where its own comment
--- says why it cannot be (the `"usual"` cleanup in `dbver <= 7`).
---
--- **What comes through here is not only the profile.** A received payload's action array rides
--- the same ladder (`BringPayloadForward` in `Export.lua`). That is what keeps one transformation
--- from being written twice (`unifying-action-migration.md` §3-4), and the price
--- of it is that **the input is no longer trusted**: a pasted string's fields arrive as any type at
--- all, and
--- an error raised in here takes down a commit with half the arrival already in the profile.
---
--- So **the steps a payload can reach** ask about types, and the rest stand as they were written
--- when only the profile came through. A payload's `dbver` cannot go below 5
--- (`OLDEST_PAYLOAD_DBVER` in `Export.lua`), which is what keeps it out of them.
---
--- **`to` stops it short of the end.** `MigrateDB` raises every ladder one version at a time, so a
--- step never meets data another ladder has already carried further (`MigrateDB`).
---
--- **A step leaves its version's stored shape and nothing else** (owner, 2026-10-09). Whatever it
--- moves or retires it removes in the same pass, and it counts on nothing after it to tidy up: the
--- drawer keeps a payload in the shape the ladder leaves it, so a field one step leaves is there for
--- good. A step that needs a clean-up pass of its own has a conversion that is wrong. The last
--- pass of the `dbver <= 7` step is the one exception, clearing out once what came before this.
---
--- **A step holds its own version's values**: the type names it compares and writes, the tables it
--- asks, the bits it writes, as literals or as a local named for the version (`_AT_N`). A step is
--- frozen once written and a profile meets it once; what `Constants` holds is today's, and moves. A
--- value read from there stops matching the old data the day it changes, and a value written from
--- there skips the later step that would have moved it. **Do not tidy these back into
--- `Constants`.** The same holds for the rules a step reads by: a value valid in its version goes
--- on up the ladder as it is, and only the step into the version that retires it may drop or change
--- it (owner, 2026-10-09).
local function MigrateLayer(layerTbl, dbver, to)
    if (layerTbl == nil) then
        return;
    end
    to = to or Constants.DB_VERSION;

    if (dbver <= 1 and 1 < to) then
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.checkUnitExists and UNITS_AT_1[action.unit]) then
                if (action.checkedUnits == nil or action.checkedUnits["@"] == nil) then
                    action.checkedUnits = action.checkedUnits or {};
                    action.checkedUnits["@"] = true;
                    action.checkUnitExists = nil;
                end
            end

            if (action.checkedUnit == true and action.unit ~= nil and action.unit ~= "none" and action.unit ~= "player") then
                if (action.checkedUnits == nil or action.checkedUnits["@"] == nil) then
                    action.checkedUnits = action.checkedUnits or {};
                    action.checkedUnits[action.unit] = action.checkedUnitValue;
                    action.checkedUnit = nil;
                    action.checkedUnitValue = nil;
                end
            end

            if (UNITS_AT_1[action.checkedUnit] and action.checkedUnitValue ~= nil) then
                if (action.checkedUnits == nil or action.checkedUnits[action.checkedUnit] == nil) then
                    action.checkedUnits = action.checkedUnits or {};
                    action.checkedUnits[action.checkedUnit] = action.checkedUnitValue;
                    action.checkedUnit = nil;
                    action.checkedUnitValue = nil;
                end
            end

            if (action.checkedUnits) then
                if (action.checkedUnits["pet"] ~= nil) then
                    if (action.checkedUnits["pet"]) then
                        action.pet = true;
                    else
                        action.pet = false;
                    end
                    action.checkedUnits["pet"] = nil;
                end

                if (next(action.checkedUnits) == nil) then
                    action.checkedUnits = nil;
                end
            end
        end
    end

    if (dbver <= 2 and 2 < to) then
        -- 발동 순서의 마지막 단계를 **배열 자리에서 저장값으로** 옮긴다.
        --
        -- 예전에는 비교자가 레이어 배열의 자리(index)를 읽었다. 그 자리는 목록이 배열
        -- 순서를 그대로 그리고 드래그로 그 자리를 바꾸던 시절에는 사용자가 보고 만지는
        -- 값이었지만, 목록이 키순 정렬로 바뀌면서 **화면에도 안 나오고 만질 방법도 없는**
        -- 값이 됐다. 뜻이 없는 값이 순서를 정하니 키를 새로 걸었을 때 어떤 액션은 위로
        -- 어떤 액션은 아래로 들어갔다 - 규칙이 아니라 그 액션이 우연히 배열 어디에
        -- 있었느냐였다.
        --
        -- 배열 순서 그대로 번호를 매기므로 **기존 사용자의 발동 순서는 한 칸도 안 바뀐다.**
        -- 번호는 레이어 안에서만 뜻이 있어서(비교자가 layerRank로 먼저 가른다) 레이어마다
        -- 1부터 다시 센다.
        --
        -- 받는 것은 키가 걸린 액션뿐이다. 키 없는 액션의 자리는 애초에 아무것도 안 정했고,
        -- 나중에 키를 걸 때 그 시점의 맨 뒤 번호를 받는다.
        local seq = 0;
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.key ~= nil) then
                seq = seq + 1;
                action.seq = seq;
            else
                action.seq = nil;
            end
        end
    end

    if (dbver <= 4 and 4 < to) then
        -- Unit conditions become **one mask per axis**. The four scalars (`true`/`false`/`"help"`/
        -- `"harm"`) can say neither "friendly or other" nor "friendly and alive": presence and
        -- reaction are packed into one value, with no room to put another axis on top.
        --
        -- **A field per axis instead of a packed enum.** Had life and group arrived as an enum, a
        -- number would change meaning and need another migration. As fields, one more is added, and
        -- **old data lacking the field already says "this axis constrains nothing"**, which is
        -- already the right answer.
        --
        --   absent             { exists = false }   a table, so there is somewhere to keep the axes
        --   present            {}                   no axis constrains it
        --   friendly/hostile   { reaction = ... }
        --
        -- `false` becomes a table **so that values switched off are remembered.** Clearing the
        -- reaction and life picked when the radio moves to [when there is none] would make the
        -- reader pick them again on the way back. Turning off is not deleting, the same way
        -- `frameTypes` stays when the unit frame condition is turned off and on. Ignoring them is
        -- `UnitConditionForBinding`'s job.
        --
        -- Safe to run again: a value already a table is left alone.
        --
        -- Version 5's reaction bits (`MigrateLayer`'s header).
        local HELP_AT_5, HARM_AT_5 = 1, 2;
        for i = 1, #layerTbl do
            local checkedUnits = layerTbl[i].checkedUnits;
            if (checkedUnits) then
                for unit, value in pairs(checkedUnits) do
                    if (value == true) then
                        checkedUnits[unit] = {};
                    elseif (value == false) then
                        checkedUnits[unit] = { exists = false };
                    elseif (value == "help") then
                        checkedUnits[unit] = { reaction = HELP_AT_5 };
                    elseif (value == "harm") then
                        checkedUnits[unit] = { reaction = HARM_AT_5 };
                    end
                end
            end
        end

        -- Then the hover condition moves in beside those units, by version 5's fold
        -- (`UnitFrameConditionAt5`). `Units.lua`'s `UnitFrameConditionFromLegacy` is the binding
        -- builder's for a profile the ladder has not reached; the two are meant to part when today's
        -- rule moves, since this one says what version 5 meant.
        --
        -- `frameTypes`/`ignoreHoverUnit` are not moved here; **the `dbver <= 6` step below** takes
        -- both. The mask goes inside the same row (the pointed frame's unit is a unit, so the mask
        -- is said about it), and the checkbox goes to `casting`, because it decides where the twin
        -- goes out rather than being a condition.
        --
        -- Safe to run again: with no `hover` it does nothing.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.hover ~= nil) then
                action.checkedUnits = action.checkedUnits or {};
                -- The fold runs on the row as version 5 read it (`UnitConditionAt5`), and what comes
                -- out goes back in the stored shape: only `false` (when there is none) has to become
                -- a table, and the rest is stored as it is.
                local folded = UnitFrameConditionAt5(
                    action.hover, action.reactions,
                    UnitConditionAt5(action.checkedUnits.hover));
                if (folded == false) then
                    folded = { exists = false };
                end
                action.checkedUnits.hover = folded;
                action.hover = nil;
                action.reactions = nil;
            end
        end
    end

    if (dbver <= 5 and 5 < to) then
        -- Shipped in 3.3. **An unshipped step takes every storage change until it ships**, rather
        -- than opening the next number: splitting a number nobody has met makes a step for an
        -- intermediate shape that never existed, and that step meets no data forever.
        --
        -- The conditions move down from the top of the action into `conditions`, and a name changes
        -- on the way.
        --
        -- **Why they move.** Eighteen of the thirty stored fields were conditions, with `unit` sitting
        -- among them. `unit` is what the action aims at and `checkedUnits` is when it fires: by name
        -- they look like one family and they are opposites. Put at different levels, the structure
        -- says so.
        --
        -- **So `checkedUnits` becomes `units`.** The `conditions.` prefix already says it is a
        -- condition, and `checked` says it a second time. The rename rides along with the move; a
        -- step of its own would be one more step that meets no data.
        --
        -- **What was a condition is version 5's list, held by this step**, for the reason the
        -- `setstate` step below holds its own names. A live table moves on: a field it stops naming
        -- stays at the top of a profile from below this step, where nothing reads it, and the
        -- condition is lost.
        --
        -- Running twice is safe: with no condition name left at the top it does nothing.
        --
        -- **Every name is gathered first and moved after.** Written as one pass, the first condition
        -- met puts `action.conditions`, a key that was not there, into the table being walked, and
        -- Lua 5.1 leaves `next` undefined once that happens (clearing a field is allowed, adding one
        -- is not). The conditions after it are then skipped and stay at the top, where nothing reads
        -- them: **the conditions the user set stop working on one login, and with `dbver` already
        -- stamped the step never gets another go.**
        local CONDITIONS_AT_5 = {
            checkedUnits = true, frameTypes = true, groups = true, forms = true, bonusbars = true,
            specialbar = true, extrabar = true, combat = true, stealth = true, known = true, pet = true,
            petbattle = true,
            ["$state1"] = true, ["$state2"] = true, ["$state3"] = true, ["$state4"] = true,
            ["$state5"] = true,
        };
        local names = {};
        for i = 1, #layerTbl do
            local action = layerTbl[i];

            local count = 0;
            for k in pairs(action) do
                if (CONDITIONS_AT_5[k]) then
                    count = count + 1;
                    names[count] = k;
                end
            end

            if (count > 0) then
                local conditions = luatype(action.conditions) == "table"
                    and action.conditions or {};
                for j = 1, count do
                    local k = names[j];
                    conditions[k == "checkedUnits" and "units" or k] = action[k];
                    action[k] = nil;
                    names[j] = nil;
                end
                action.conditions = conditions;
            end
        end

        -- `setstate`'s `mode | index` bitpack, opened out into three types and a name.
        --
        -- **The step holds the old name, the old numbers and the names it writes itself.** Neither
        -- the type `"setstate"` nor the `SETCUSTOM_MODE_*` flags is a language this build speaks
        -- any more, and left in `Constants.lua` a dead name sits next to the live ones forever. The
        -- three it writes are version 6's, which the `dbver <= 7` step renames. A step is frozen
        -- once it is written, so there is nothing here for it to drift from (`0-DECISION-LOG.md`,
        -- 2026-08-21; `MigrateSwitches` below holds its own old numbers for the same reason).
        --
        -- **A mode this does not recognise is left alone.** A bitpack that is none of the three
        -- does not say what the action was meant to do, and picking a type for it would turn an
        -- "on" into an "off". Left under the old type it reaches nothing and does nothing, which is
        -- where an unknown type ends up anyway.
        --
        -- Safe to run again: an action already split has a type that is not `"setstate"`.
        -- **The payload side stands on that.** The v1 adapter opens its subtable straight into the
        -- new types, and this block walks past what it produced (`Export.lua`).
        local SETSTATE_BY_FLAG = {
            [0x100] = "setstate_on",
            [0x200] = "setstate_off",
            [0x400] = "setstate_toggle",
        };
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.type == "setstate" and luatype(action.value) == "number") then
                local newType = SETSTATE_BY_FLAG[band(action.value, 0x100 + 0x200 + 0x400)];
                local name = SWITCH_NAMES_AT_6[band(action.value, 0xf)];
                if (newType and name) then
                    action.type = newType;
                    action.value = name;
                end
            end
        end

        -- 합성 키가 없어진다. `key`는 실키 문자열 아니면 nil이고, 어느 arrival이 놓았느냐는
        -- `arrivalID`가 따로 든다(`building-export-import.md` 12절).
        --
        -- **`imported`가 도착 키를 나르던 것을 `key`가 도로 받는다.** 발동을 막는 것은 이제
        -- 배지 하나이고(`BuildKeyMap`), 그 게이트는 원래부터 키 타입이 아니라 배지를 보고
        -- 있었으므로 실키가 들어와도 격리는 그대로다.
        --
        -- **옛 배지 전부가 arrival 하나가 된다.** 옛 합성 번호를 그대로 물려주면 번호가 큰
        -- 값에서 시작하고, 그 번호로 갈라 둘 이유도 없다 - 갈라 두는 값은 같은 키 위에
        -- 두 세트가 앉는 경우인데, 도착 키가 같았던 옛 대기분은 어차피 한 묶음으로 읽어도
        -- 된다. 카운터를 2로 세우는 것은 `MigrateDB`다.
        --
        -- **배지 없이 숫자 키만 든 줄은 키를 잃는다.** 사용자가 직접 언바인드한 세트이고, 그
        -- 번호는 아무도 지목할 수 없는 값이라 남겨두면 그 줄들만 영원히 그룹으로 선다.
        --
        -- 키가 없으면 번호도 없다는 규칙(`PlaceInKeyGroup`)을 여기서도 지킨다.
        --
        -- **페이로드도 이 사다리를 탄다.** 거기엔 `imported`가 없고 숫자 `key`만 있을 수
        -- 있는데(키를 벗겨 보내던 시절의 문자열), 그쪽도 같은 답이 맞다. 정렬은 안 한다 -
        -- 이 단계가 만나는 것은 신뢰할 수 없는 입력이고, `CompareActionOrder`에 넘기면
        -- `priority`가 테이블인 문자열 하나가 커밋 도중에 터진다.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            local badge = action.imported;
            if (badge ~= nil) then
                action.imported = nil;
                if (luatype(badge) == "string") then
                    action.key = badge;
                else
                    action.key = nil;
                end
                action.arrivalID = 1;
            elseif (luatype(action.key) == "number") then
                action.key = nil;
            end
            if (action.key == nil) then
                action.seq = nil;
            end
        end
    end

    --- Shipped in 4.0.
    if (dbver <= 6 and 6 < to) then
        -- Version 7's values (`MigrateLayer`'s header).
        local SPELL_AT_7, MACROTEXT_AT_7, COMMAND_AT_7 = "spell", "macrotext", "command";
        local USESLOT_AT_7, ACTIONBUTTON_AT_7 = "useslot", "actionbutton";
        local HELP_AT_7, HARM_AT_7, DEFAULT_IMPORTANCE_AT_7 = 1, 2, 3;

        -- `equipslot` becomes `useslot`. The action uses what is worn in a slot and equips nothing,
        -- and the game's own `/equipslot 13 <item>` means the opposite (`0-ROADMAP.md`,
        -- 2026-08-28). **The step holds the old string itself**: the constant is gone, and a dead
        -- name left in `Constants.lua` would sit beside the live ones forever.
        --
        -- Safe to run again: nothing carries the old string once this has passed. **Payloads ride
        -- this too** (`Export.lua`'s `BringPayloadDataForward`), which is what lets a string from
        -- 3.5 or earlier arrive under the new name.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.type == "equipslot") then
                action.type = USESLOT_AT_7;
            end
        end

        -- A command that presses an action bar button becomes the action button action under the
        -- same name: Debind holds every key it has an action on, so the game's binding no longer
        -- gets the press (`dropping-the-game-fallback.md` §3). Every other command is left
        -- as saved and binds as a block. Safe to run again, and payloads ride it too.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.type == COMMAND_AT_7 and ACTION_BUTTON_COMMANDS_AT_7[action.value]) then
                action.type = ACTIONBUTTON_AT_7;
            end
        end

        -- `known` stops being "ask about it" and starts saying **what** is asked about
        -- (`making-known-a-spell-name.md`). `true` used to mean the action's own spell,
        -- which left a reader no way to ask about the talent that replaces it.
        --
        -- The action's own value is what it meant, so that is what goes in, as the **name** the
        -- client draws on it. A name survives a specialization change where an id does not: the
        -- same spell has an id per specialization and the two do not point at each other
        -- (`resolving-a-stored-spell-id.md`).
        --
        -- **A value the client cannot name keeps its id.** That is a spell whose data is not
        -- loaded, or one that no longer exists, and `[known:<id>]` answers false for it either
        -- way, which is what it answered before this step.
        --
        -- **The three spec-resolved types keep `true`.** They carry no value and the spell is
        -- picked at the rebuild, so a name here would nail the condition to one specialization.
        --
        -- **Everything else loses it.** A `known` on a type with no spell was already doing
        -- nothing -- the normalization dropped it before a binding was built -- and raising it
        -- would turn an inert flag into a name that is false for good, which is a key that
        -- stops working with nothing said. A macro action's name would be its body.
        --
        -- Running twice is safe: the second pass finds a string or a number, and only `true` is
        -- taken.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            local conditions = action.conditions;
            if (conditions and conditions.known ~= nil
                    and not SPEC_RESOLVED_AT_7[action.type]) then
                if (action.type ~= SPELL_AT_7) then
                    conditions.known = nil;
                elseif (conditions.known == true) then
                    conditions.known = C_Spell.GetSpellName(action.value) or action.value;
                end
            end
        end

        -- Each of a unit condition's three modes takes a value of its own.
        --
        --   when there is one    `{}`                 -> `{ exists = true }`
        --   when there is not    `{ exists = false }`    unchanged
        --   disabled             `{ off = true }`     -> `{ disabled = true }`
        --
        -- **What this step ends is a meaning carried by an empty table.** When `dbver <= 4` spread
        -- the scalars into tables, `true` had no axis to write and so became an empty one, and
        -- "nothing written down means when there is one" became the rule from there. It was a rule
        -- nothing else in the repo followed: an empty table read as an absent condition everywhere
        -- it was gated on, and an action carrying one signed the same as an action carrying no
        -- condition at all, so the duplicate check paired the two.
        --
        -- `off` only changes name. The repo calls that state `disable` (`AppendDisable`,
        -- `disabledReason`, the label `DISABLE`).
        --
        -- **A disabled condition takes no mode on top.** `disabled` is already the mode, and the
        -- axes beside it are values kept only to hand back when it is turned on again.
        --
        -- A value that is not a table is left alone. No build reaches here carrying a scalar
        -- (`dbver <= 4` spread them), but a hand-edited profile and a payload ride this same ladder.
        --
        -- Running twice is safe. The second pass finds no `off` and an `exists` already standing.
        for i = 1, #layerTbl do
            local units = layerTbl[i].conditions and layerTbl[i].conditions.units;
            if (units) then
                for _, value in pairs(units) do
                    if (luatype(value) == "table") then
                        if (value.off ~= nil) then
                            value.disabled = value.off and true or nil;
                            value.off = nil;
                        end
                        if (not value.disabled and value.exists == nil) then
                            value.exists = true;
                        end
                    end
                end
            end
        end

        -- The pet condition becomes the pet unit's row. Both asked whether a pet is there, and the
        -- row asks it of `UnitExists("pet")` where the axis asked `PlayerPetSummary()`; the two
        -- part only on a pet with no creature family, and every pet has one
        -- (`RestrictedEnvironment.lua` answers the summary with `UnitCreatureFamily("pet")`).
        --
        -- **A row already answering wins and the axis is dropped.** One row cannot hold two
        -- answers, and an action that carried both an axis and a row disagreeing with it could not
        -- fire either way. **A disabled row is not such an answer** -- it is a mode meaning "no
        -- unit condition here", with the axes beside it kept only to hand back -- so the axis takes
        -- that slot and the mode goes with it. Leaving it disabled would drop the condition
        -- entirely, which widens the binding.
        --
        -- Running twice is safe: the second pass finds no `pet`.
        for i = 1, #layerTbl do
            local conditions = layerTbl[i].conditions;
            local value;
            if (luatype(conditions) == "table") then
                value = conditions.pet;
            end

            if (value ~= nil) then
                local units = conditions.units;
                if (units == nil) then
                    units = {};
                    conditions.units = units;
                end
                local row = units.pet;
                if (row == nil) then
                    units.pet = { exists = value and true or false };
                elseif (luatype(row) == "table" and row.disabled) then
                    row.disabled = nil;
                    row.exists = value and true or false;
                end
                conditions.pet = nil;
            end
        end

        -- The pointed frame's unit is called `unitframe` from here on. `hover` stops being a unit
        -- at all and becomes the unit an action's Hover Cast mode picks
        -- (`which-action-a-key-runs.md` §0), so every stored spelling of the old name has
        -- to move before that second meaning arrives.
        --
        -- **Bodies move too, not only fields.** `@hover` is a unit token in hand-written macro text
        -- and `/click DebindCustom<n> hover` is the unit a custom target is filled from. Both are
        -- read by name, so a body left alone stops resolving the moment the name leaves
        -- `Constants.SPECIAL_UNITS` -- and nothing is raised, because a token the parser does not
        -- know is handed to the game as text. Leaving it would be worse than breaking it: the same
        -- spelling comes back meaning something else.
        --
        -- **The step hands the old name in** rather than asking `ParseMacroText`, which cannot see
        -- it any more (`RenameUnitInMacroTextAt7` says why).
        --
        -- Running twice is safe: nothing carries the old spelling once this has passed.
        for i = 1, #layerTbl do
            local action = layerTbl[i];

            local units = action.conditions and action.conditions.units;
            if (luatype(units) == "table" and units.hover ~= nil) then
                -- Both names at once is a hand-edited profile. The one this build reads wins;
                -- taking the old one instead would undo an edit made against the new name.
                if (units.unitframe == nil) then
                    units.unitframe = units.hover;
                end
                units.hover = nil;
            end

            if (action.unit == "hover") then
                action.unit = "unitframe";
            end

            if (action.type == MACROTEXT_AT_7 and luatype(action.value) == "string") then
                action.value = RenameUnitInMacroTextAt7(action.value, "hover", "unitframe");
                -- **A whole token after the frame name**, the way `/click` reads it and the way
                -- `renameClickedSwitch` reads the switch in the same position. A pre-rename body
                -- already says `DebindCustom` here: `Legacy.lua` repairs its copies before the
                -- ladder runs.
                action.value = action.value:gsub("(DebindCustom%d+%s+)(%S+)", function(head, token)
                    if (token ~= "hover") then
                        return nil;
                    end
                    return head .. "unitframe";
                end);
            end
        end

        -- The frame type mask becomes an axis of the condition on the pointed frame's unit.
        -- It was its own condition field while the Unit Frame menu was a group of its own; that
        -- group is gone and the mask is one more thing said about `units["unitframe"]`
        -- (`which-action-a-key-runs.md` §0). The role mask was moved into that row by the
        -- `dbver <= 4` step and stays where it is.
        --
        -- **A mask already on the row wins**, the way that step's row does: one row cannot hold two
        -- answers, and taking the outer one would undo an edit made against the new shape.
        --
        -- Running twice is safe: the second pass finds no `frameTypes` outside the row.
        for i = 1, #layerTbl do
            local conditions = layerTbl[i].conditions;
            local mask;
            if (luatype(conditions) == "table") then
                mask = conditions.frameTypes;
            end

            if (mask ~= nil) then
                local units = conditions.units;
                if (units == nil) then
                    units = {};
                    conditions.units = units;
                end
                local row = units.unitframe;
                if (row == nil) then
                    -- 개체창 조건이 아예 없는 액션이다. 마스크는 물을 자리가 없지만
                    -- **버리지 않는다** - 끈 축을 기억하는 것이 이 표의 규칙이라, 다시 켜면
                    -- 고른 값이 그대로 있어야 한다. 그래서 [사용 안 함]인 줄로 들어간다.
                    row = { disabled = true };
                    units.unitframe = row;
                elseif (luatype(row) ~= "table") then
                    -- 손으로 고친 프로필의 옛 스칼라. `UnitConditionForBinding`이 읽는 대로
                    -- 표로 편다 - `true`/`"help"`/`"harm"`은 [올렸을 때]이고 나머지는
                    -- [안 올렸을 때]다. 여기서 안 펴면 마스크를 실을 자리가 없다.
                    if (row == true) then
                        row = { exists = true };
                    elseif (row == "help") then
                        row = { exists = true, reaction = HELP_AT_7 };
                    elseif (row == "harm") then
                        row = { exists = true, reaction = HARM_AT_7 };
                    else
                        row = { exists = false };
                    end
                    units.unitframe = row;
                end
                if (row.frameTypes == nil) then
                    row.frameTypes = mask;
                end
                conditions.frameTypes = nil;
            end
        end

        -- 발동 순서에서 개체창 단계가 빠졌다. **키 묶음마다 번호를 옛 비교자 순서로 다시
        -- 매겨서** 그 단계가 정하던 순서를 번호가 대신 들게 한다 - 안 하면 개체창 조건이
        -- 붙은 액션이 같은 레이어의 이웃 뒤로 조용히 내려앉는다.
        --
        -- **옛 비교자를 이 단계가 직접 든다.** 단계는 한 번 쓰면 얼어붙는 것이라
        -- (`0-DECISION-LOG.md`, 2026-08-21) `Ordering.lua`에서 사라진 규칙을 여기서 다시 부를
        -- 수 없고, 부를 수 있어도 그쪽이 또 바뀌면 이 단계의 답이 바뀐다.
        --
        -- 묶음은 `(key, arrivalID)`다 - `RenumberKeyGroup`과 같은 묶음이고, 레이어 하나가
        -- 이 함수의 전부라 레이어는 이미 갈려 있다.
        --
        -- 다시 돌아도 안전하다: 두 번째 순회는 이미 그 순서로 선 것을 같은 순서로 다시 센다.
        do
            local groups = {};
            for i = 1, #layerTbl do
                local action = layerTbl[i];
                if (action.key ~= nil) then
                    local name = action.key .. "\0" .. tostring(action.arrivalID);
                    local group = groups[name];
                    if (group == nil) then
                        group = {};
                        groups[name] = group;
                    end
                    group[#group + 1] = { action = action, index = i };
                end
            end

            -- 옛 비교자. 레이어 하나 안에서는 `layerRank`와 `specRank`가 상수라 아무것도 못
            -- 가르므로, 남는 단계는 중요도·개체창·조건 유무·번호 넷이다.
            local function OlderOrder(lhs, rhs)
                local lhsAction, rhsAction = lhs.action, rhs.action;
                local lhsImportance = lhsAction.priority or DEFAULT_IMPORTANCE_AT_7;
                local rhsImportance = rhsAction.priority or DEFAULT_IMPORTANCE_AT_7;
                if (lhsImportance ~= rhsImportance) then
                    return lhsImportance < rhsImportance;
                end

                -- **접기 전의 원문을 세 값으로 읽는다**: 조건이 없으면 nil, [안 올렸을 때]면
                -- false, 그 밖이면 조건이 있는 것. 옛 비교자는 nil이 아닌 쪽을 앞세웠다.
                if (lhs.unitFrame ~= rhs.unitFrame) then
                    return lhs.unitFrame;
                end

                if (lhs.conditional ~= rhs.conditional) then
                    return lhs.conditional;
                end

                if ((lhsAction.seq or 0) ~= (rhsAction.seq or 0)) then
                    return (lhsAction.seq or 0) < (rhsAction.seq or 0);
                end
                return lhs.index < rhs.index;
            end

            -- 옛 세 번째 단계가 읽던 "조건이 하나라도 있나". **저장에서 바로 읽는다** -
            -- `IsConditionalBinding`은 바인딩을 통째로 만들게 하고, 그 길은 전문화가 고르는
            -- 주문까지 물어서 로그인 전에 부를 것이 못 된다. 꺼진 유닛 조건이 조건이 아닌 것만
            -- 저쪽과 맞추면 된다.
            local function HasAnyCondition(action)
                local conditions = action.conditions;
                if (conditions == nil) then
                    return false;
                end
                for name, value in pairs(conditions) do
                    if (name ~= "units") then
                        return true;
                    end
                    for _, stored in pairs(value) do
                        if (UnitConditionAt7(stored) ~= nil) then
                            return true;
                        end
                    end
                end
                return false;
            end

            for _, group in pairs(groups) do
                for j = 1, #group do
                    local action = group[j].action;
                    local folded = UnitConditionAt7(
                        action.conditions and action.conditions.units
                        and action.conditions.units.unitframe);
                    -- **Or what the step below turned that condition into**, which is the same
                    -- action on a second pass: a bare [when one is pointed at] is not written as a
                    -- condition any more, and read as an action that never had one it would sort
                    -- somewhere else the second time this runs.
                    local casting = action.casting;
                    group[j].unitFrame = folded ~= nil
                        or (casting ~= nil and casting.normalCast == false
                            and casting.hoverCastMode == "unitframe");
                    -- **The same second pass reaches this line too**, and for the same reason. An
                    -- action whose only condition was that bare one is left with an empty table,
                    -- which reads as never having carried a condition at all -- so it drops out of
                    -- the old comparator's conditional band while every neighbour stays, and the
                    -- second run hands back a different order from the first. The unit frame
                    -- answer above is exactly "it had one", so it settles this as well.
                    group[j].conditional = HasAnyCondition(action) or group[j].unitFrame;
                end
                sort(group, OlderOrder);
                for j = 1, #group do
                    group[j].action.seq = j;
                end
            end
        end

        -- The three boxes become the `action.casting` values. Hover Cast holds a mode per action, and
        -- the account has no off (`which-action-a-key-runs.md` §8).
        --
        -- **An old unit frame condition action becomes a twin-only action.** It meant "on a pointed
        -- press only, ahead of the layers", which in the new shape is Hover Cast on Unit Frames with
        -- Normal Cast off. Keeping the condition and following the account's mode instead would stand
        -- the action over world units for anyone whose settings say Mouseover, on the day it moved.
        --
        -- **A bare [when one is pointed at] is not kept as a condition.** The two Casting values carry
        -- all of what it did, and left in place the twin's condition is written twice and the original
        -- is made conditional too. A condition with an axis on it stays: the twin has to inherit the
        -- reaction, the role and the frame type.
        --
        -- **The rest get nothing written, because at version 7 no value was off and off is what they
        -- did.** What off became after that is the `dbver <= 7` step's.
        --
        -- **It runs after the renumbering.** The comparator above reads the very condition removed
        -- here, and run first it would read a twin-only action as unconditional and turn the old
        -- order over.
        --
        -- Safe to run twice: the second pass finds none of the three old names, and a Hover Cast
        -- value already written is what says the action has been through here.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            local casting = action.casting;

            if (action.ignoreSelfCastKey) then
                casting = casting or {};
                casting.selfCastKey = "skip";
                action.ignoreSelfCastKey = nil;
            end
            if (action.ignoreFocusCastKey) then
                casting = casting or {};
                casting.focusCastKey = "skip";
                action.ignoreFocusCastKey = nil;
            end

            if (casting == nil or (casting.hoverCast == nil and casting.hoverCastMode == nil)) then
                local units = action.conditions and action.conditions.units;
                local folded = UnitConditionAt7(units and units.unitframe);
                if (folded ~= nil and folded ~= false) then
                    casting = casting or {};
                    casting.hoverCastMode = "unitframe";
                    casting.hoverCast = "cast";
                    if (action.ignoreHoverUnit) then
                        casting.hoverCast = "usual";
                    end
                    casting.normalCast = false;
                    -- Was it a bare [when one is pointed at]? With no axis in what `UnitConditionAt7`
                    -- handed back, that is all the condition said.
                    if (next(folded) == nil) then
                        units.unitframe = nil;
                        if (next(units) == nil) then
                            action.conditions.units = nil;
                        end
                    end
                end
            end

            action.ignoreHoverUnit = nil;
            action.casting = casting;
        end

        -- `keepInBindingContext` is gone, and nothing takes its place on the action. The question
        -- it answered is the account's now (`giveBackInBindingContext`), so a value left
        -- here would be a second answer nothing reads (`giving-keys-back.md` §7).
        --
        -- **The reader who had it ticked loses it** rather than carrying it to the account row: the
        -- old value was per action and the new one is not, so one of them would have to decide for
        -- the other.
        --
        -- Running twice is safe: the second pass finds nothing.
        for i = 1, #layerTbl do
            layerTbl[i].keepInBindingContext = nil;
        end

    end

    --- **The unreleased step.** Everything raised here landed after the last tag, so it is one
    --- step rather than a rung each, and unrelated jobs share it (`Constants.DB_VERSION`).
    if (dbver <= 7 and 7 < to) then
        -- A switch stops being called a state (`reshaping-stored-layers.md` §4, 1-2): the three
        -- on/off/toggle types, and the frame a converted body clicks. A body left behind clicks a
        -- frame that no longer exists, and nothing says so. **No alias frame answers to the old
        -- name** (owner), so a line copied into the game's own macro window stays broken; the
        -- rename to Debind shipped the same way.
        --
        -- **The step holds the old names and version 8's itself** (`MigrateLayer`'s header).
        --
        -- Running twice is safe: neither old name is left after the first pass.
        local RENAMED_TYPES = {
            setstate_on     = "setswitch_on",
            setstate_off    = "setswitch_off",
            setstate_toggle = "setswitch_toggle",
        };
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            local renamed = luatype(action.type) == "string" and RENAMED_TYPES[action.type];
            if (renamed) then
                action.type = renamed;
            end
            if (action.type == "macrotext" and luatype(action.value) == "string") then
                action.value = (action.value:gsub("DebindStates", "DebindSwitch"));
            end
        end

        -- **A pinned rank moves out of `value` into `pinnedSpell`**
        -- (`keeping-a-pinned-rank-apart-from-the-spell.md`). `value` keeps the id, which is still
        -- that spell; this step reads no client, so putting it on the first rank is the profile's
        -- own step (`MigrateDB`). Only a spell held by id was ever pinned; anything else here came
        -- in on a payload and is dropped.
        --
        -- Running twice is safe: the second pass finds no `pinRank`.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.pinRank ~= nil) then
                if (action.pinRank == true and action.type == "spell"
                        and luatype(action.value) == "number") then
                    action.pinnedSpell = action.value;
                end
                action.pinRank = nil;
            end
        end

        -- **A saved command or unused becomes a block where it stands**
        -- (`handing-the-rest-of-a-key-to-the-game.md` 2-8). Since 4.0 both bound as a block, so each
        -- has been winning its presses in its own place and holding the key for nothing. As either
        -- type it would hand the key to the game from now on, or run its command, with nothing the
        -- reader did.
        --
        -- `value` goes: a block carries none, and a command name left on one is read by nothing.
        -- Running twice is safe: no command or unused is left after the first pass.
        --
        -- **The two names are written out**, for the reason the Hover Cast part below gives: version
        -- 7's unused is `"unused"`, and the live constant for that type has since become `"giveback"`.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.type == "command" or action.type == "unused") then
                action.type = "block";
                action.value = nil;
            end
        end

        -- **Hover Cast loses off, and off with Normal Cast off becomes "don't run while pointing"**
        -- (`taking-off-out-of-hover-cast.md` §2-9, owner). Off was stored as no value, which is the
        -- usual target from here on, so every other off moves by being left alone. With Normal Cast
        -- off it stood on the cast keys alone; no new value keeps that, and this one is the one that
        -- shows it, as an issue, rather than starting to answer pointed presses without a word.
        --
        -- **Not the bare left and right click**, which read no Hover Cast value then or now. The two
        -- keys are written out rather than asked of `IsBareWorldClick`, for the reason the step holds
        -- the old type names itself: a step says what version 7 meant, and a function the live code
        -- keeps would move it the day that function changes.
        --
        -- **Then a stored `"usual"` becomes nothing** (2026-10-05, owner), which is how the usual
        -- target is stored from here on: one spelling for one value, so no reader has to take two.
        -- After the line above, since off is nothing as well: `"usual"` with Normal Cast off stood on
        -- a pointed press at the usual target, and still does. A table left empty goes with it.
        --
        -- **Not safe to run twice, unlike the rest of the ladder** (owner): a second pass takes a
        -- rewritten `"usual"` with Normal Cast off for off and makes it skip. A profile never meets
        -- it twice (`TryMigrateDB`). A drawer entry still can, being raised in place, and that is
        -- the thing to fix (`0-IDEAS.md`).
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            local casting = action.casting;
            if (luatype(casting) == "table") then
                if (casting.normalCast == false and casting.hoverCast == nil
                        and action.key ~= "BUTTON1" and action.key ~= "BUTTON2") then
                    casting.hoverCast = "skip";
                elseif (casting.hoverCast == "usual") then
                    casting.hoverCast = nil;
                    if (next(casting) == nil) then
                        action.casting = nil;
                    end
                end
            end
        end

        -- **`specialbar` and `petbattle` become one mask, `bartakeover`**
        -- (`turning-replaced-action-bar-into-bar-takeover.md`). `specialbar` took a pet battle in
        -- beside the replaced bars, so on it was "replaced or battle", which two conditions joined by
        -- AND cannot say, and one mask can. Every pair lands on exactly what it ran on, but two:
        -- `specialbar` on with `petbattle` off ran nowhere, because an issue check read it as never
        -- holding while a vehicle outside a battle meets it; it runs on the replaced bars from here on
        -- (owner). Off with `petbattle` on never held at all, and lands on the empty mask, an issue
        -- as before.
        --
        -- **Version 8's bits are written out**, for the reason the old type names above are.
        --
        -- Running twice is safe: neither old field is left after the first pass. A value that is not
        -- a boolean is hand-made and goes without becoming anything.
        local NONE, REPLACED, BATTLE = 1, 2, 4;
        for i = 1, #layerTbl do
            local conditions = layerTbl[i].conditions;
            if (luatype(conditions) == "table") then
                local bar, battle = conditions.specialbar, conditions.petbattle;
                conditions.specialbar, conditions.petbattle = nil, nil;
                if (luatype(bar) ~= "boolean") then
                    bar = nil;
                end
                if (luatype(battle) ~= "boolean") then
                    battle = nil;
                end
                local mask;
                if (battle == true) then
                    mask = (bar == false) and 0 or BATTLE;
                elseif (battle == false) then
                    if (bar == true) then
                        mask = REPLACED;
                    elseif (bar == false) then
                        mask = NONE;
                    else
                        mask = NONE + REPLACED;
                    end
                elseif (bar == true) then
                    mask = REPLACED + BATTLE;
                elseif (bar == false) then
                    mask = NONE;
                end
                if (mask ~= nil) then
                    conditions.bartakeover = mask;
                end
            end
        end

        -- **What every earlier step and every shipped writer left behind goes, once** (owner,
        -- 2026-10-09). Each rule answers something a shipped build left in a profile, a string or a
        -- drawer entry, and nothing else: a value only a hand could have made is `SanitizeAction`'s,
        -- which runs after every ladder. It takes most of these off as well; why the step keeps its
        -- own copy is the paragraph below.
        --
        --   - the old unit fields, which the 1 -> 2 step moves only from a version 1 profile and only
        --     when it can read them (1.11 to 1.15 wrote them at version 2), and `reactions`, which the
        --     4 -> 5 step takes only beside `hover`;
        --   - an empty `conditions`, which the 6 -> 7 step leaves when the condition it takes off
        --     was the only one;
        --   - a talent list left empty, which 4.x kept on disk while the other list was not;
        --   - a spec-resolved `known` of `true`, which the 6 -> 7 step keeps and version 8 says
        --     with `skipWhenUnusable`;
        --   - what a 4.x type change (`SetActionEntry`) or a turn into a macro (`ConvertToMacroText`)
        --     left on a type that cannot hold it, which that session's strings carried;
        --   - an action on Escape, taken as a shape a shipped build could store (owner, 2026-10-09).
        --
        -- **Every rule is version 8's, written out**, for the reason the old type names above are:
        -- `SanitizeAction` is this build's shape and moves with it. So the lines below repeat
        -- `DropFieldsTheTypeCannotHold` and `Talents.Prune` on purpose, and the two are meant to part:
        -- when the live rules change, bringing data already raised along is a new step's job, and
        -- this copy stays as version 8 left it.
        --
        -- A received payload rides this before `SanitizeAction` asks its types (`SanitizePayload`),
        -- so nothing here may raise on one that is wrong.
        --
        -- Running twice is safe: what it takes off is not put back.
        local SPEC_RESOLVED_AT_8 = { dispel = true, dispel2 = true, raidbuff = true, resurrect = true };
        local TALENT_LISTS_AT_8 = { "taken", "notTaken" };
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            action.checkUnitExists = nil;
            action.checkedUnit = nil;
            action.checkedUnitValue = nil;
            action.reactions = nil;

            if (action.key == "ESCAPE") then
                action.key = nil;
                action.seq = nil;
            end

            local specResolved = SPEC_RESOLVED_AT_8[action.type];
            local conditions = action.conditions;
            if (luatype(conditions) == "table") then
                local talents = conditions.talents;
                if (luatype(talents) == "table") then
                    for specID, entry in pairs(talents) do
                        local any = false;
                        if (luatype(entry) == "table") then
                            for j = 1, #TALENT_LISTS_AT_8 do
                                local name = TALENT_LISTS_AT_8[j];
                                if (luatype(entry[name]) == "table") then
                                    if (#entry[name] == 0) then
                                        entry[name] = nil;
                                    else
                                        any = true;
                                    end
                                end
                            end
                        end
                        if (not any) then
                            talents[specID] = nil;
                        end
                    end
                    if (next(talents) == nil) then
                        conditions.talents = nil;
                    end
                end

                if (conditions.known == true and specResolved) then
                    conditions.known = nil;
                    action.skipWhenUnusable = true;
                end

                if (next(conditions) == nil) then
                    action.conditions = nil;
                end
            end

            if (not specResolved) then
                action.skipWhenUnusable = nil;
            end
            if (action.type ~= "resurrect") then
                action.noTargetMassRez = nil;
                action.battleRezOutOfCombat = nil;
            end
            if (action.type ~= "spell" or luatype(action.value) ~= "string"
                    or luatype(action.resolvedSpellID) ~= "number") then
                action.resolvedSpellID = nil;
            end
        end
    end

end

--- Every stored list of actions, in whichever containers the data is in at this point of the
--- ladder: up to 7 in `shared` (`GENERAL` a bare list, `classes[class][spec]`) and on the character
--- entries (`layers[spec]`); from the `dbver <= 7` step of `MigrateContainers` on in
--- `layers[owner][class][spec]`, beside `pendingActions[guid]`. `ForEachStoredAction` in
--- `Profile.lua` knows only `layers`.
local function ForEachActionList(db, fn)
    local function EachSpec(specTbl)
        if (luatype(specTbl) == "table") then
            for spec = 0, 5 do
                if (luatype(specTbl[spec]) == "table") then
                    fn(specTbl[spec]);
                end
            end
        end
    end

    local shared = db.shared;
    if (luatype(shared) == "table") then
        if (luatype(shared.GENERAL) == "table") then
            fn(shared.GENERAL);
        end
        for _, specTbl in pairs(luatype(shared.classes) == "table" and shared.classes or {}) do
            EachSpec(specTbl);
        end
    end
    for _, entry in pairs(luatype(db.characters) == "table" and db.characters or {}) do
        if (luatype(entry) == "table") then
            EachSpec(entry.layers);
        end
    end
    for _, classes in pairs(luatype(db.layers) == "table" and db.layers or {}) do
        for _, specTbl in pairs(classes) do
            EachSpec(specTbl);
        end
    end
    -- **Every character's pending actions too.** They are out of `layers` on disk
    -- (`StowPendingActions`), and a step that rewrites actions but misses them leaves another
    -- character's in the old shape for good. No step written before this table existed meets one.
    for _, share in pairs(luatype(db.pendingActions) == "table" and db.pendingActions or {}) do
        if (luatype(share) == "table") then
            for _, specTbl in pairs(luatype(share.account) == "table" and share.account or {}) do
                EachSpec(specTbl);
            end
            EachSpec(share.character);
        end
    end
end

--- Version 6's rule for a condition naming a switch, and its two modes: the `dbver <= 5` switch
--- step and its two helpers below read these (`MigrateLayer`'s header).
local function IsSwitchNameAt6(name)
    return luatype(name) == "string" and name:sub(1, 1) == "$";
end
local MANUAL_AT_6, EXPR_AT_6 = "manual", "expr";

--- Every switch name this profile still names, gathered from all five layers of every character
--- and every class.
---
--- **Conditions and on/off/toggle targets, and nothing else.** Those two are the places a switch is
--- named by picking it out of a menu, so a name cannot get in by being mistyped. A macro body's
--- `[$burst]` is typed by hand and is deliberately left out (`redesigning-custom-states.md`
--- §9-3): read as a use, one typo would keep a definition alive and take away the mark that is
--- how the user finds out about the typo at all.
---
--- **The `dbver <= 5` step's helper, so it reads version 6's names**: the types that version's
--- layer step has just opened the bitpack into.
local SETSTATE_TYPES_AT_6 = { setstate_on = true, setstate_off = true, setstate_toggle = true };

local function CollectReferencedSwitches(db, found)
    ForEachActionList(db, function(list)
        for i = 1, #list do
            local action = list[i];
            local conditions = action.conditions;
            if (luatype(conditions) == "table") then
                for name in pairs(conditions) do
                    if (IsSwitchNameAt6(name)) then
                        found[name] = true;
                    end
                end
            end
            if (SETSTATE_TYPES_AT_6[action.type] and luatype(action.value) == "string") then
                found[action.value] = true;
            end
        end
    end);
end

--- Has anything been set on this definition, or is it the empty one a load used to plant?
---
--- **`value` is not a setting.** `BindDerivedTables` writes it on every load from `resetValue` and
--- the character's stored value, so it is on every definition including the ones nobody ever
--- touched. Everything else on a definition got there because somebody chose it.
---
--- **A remembered value is not asked here.** It is evidence of use rather than a setting, and the
--- caller reads it before dropping it.
local function SwitchIsUntouched(definition)
    for key, value in pairs(definition) do
        if (key == "mode") then
            if (value ~= MANUAL_AT_6) then
                return false;
            end
        elseif (key ~= "value") then
            return false;
        end
    end
    return true;
end

--- The switch definitions, which sit at the top of the global table rather than inside a layer.
---
--- **A second ladder, because `MigrateLayer` cannot reach these.** That one walks a layer's array of
--- actions; a definition is not an action and lives nowhere near one. Both ladders are stepped in
--- the same `MigrateDB` pass, so nothing is ever half raised, and `check:dbver` asks each about its
--- own order because two ladders carrying the same step number is not a fault.
---
--- **It is handed the whole account table, not just the definitions**, because the step below has
--- to know which switches the layers still name. On `Legacy.lua`'s `ImportAccount` path this
--- character's own pre-rename layers have not arrived yet (`ImportCharacter` runs after), so a definition used
--- only there is judged on whether anything was ever set on it. That is enough for a switch the
--- user actually used: pressing one leaves a remembered value, and both of the other modes write a
--- field of their own.
local function MigrateSwitches(db, dbver, to)
    to = to or Constants.DB_VERSION;

    if (dbver <= 5 and 5 < to) then
        -- Three stored shapes of a definition move at once: the table's name `customStates`
        -- becomes `switches`, `mode` goes from a number to a string, and `initialValue` becomes
        -- `resetValue`.
        --
        -- **The step holds the old numbers and version 6's names itself** (`MigrateLayer`'s header).
        -- `Constants.SWITCH_MODES` no longer speaks the old language, and what it speaks now may
        -- move on (`NestPayloadConditions` in `Export.lua` holds `checkedUnits` as a literal for the
        -- same reason).
        --
        -- Safe to run again: with nothing left under an old name it does nothing. A `mode` that is
        -- already a string is left alone, and `initialValue` is cleared as it moves.
        if (db.customStates ~= nil) then
            db.switches = db.customStates;
            db.customStates = nil;
        end

        local switches = db.switches;
        if (switches) then
            for _, definition in pairs(switches) do
                if (luatype(definition) == "table") then
                    if (luatype(definition.mode) == "number") then
                        if (definition.mode == 3) then
                            definition.mode = EXPR_AT_6;
                        else
                            definition.mode = MANUAL_AT_6;
                        end
                    end

                    if (definition.initialValue ~= nil) then
                        if (definition.resetValue == nil) then
                            definition.resetValue = definition.initialValue;
                        end
                        definition.initialValue = nil;
                    end
                end
            end

            -- **The five a load used to plant are taken back out here.** `BindDerivedTables`
            -- planted five empty definitions on every load, so a profile that never used the
            -- feature holds five switches nobody made. Making one is now only the user writing a
            -- name (`CreateSwitch`), so what was planted goes once, here.
            --
            -- **Once, not a repair on every load.** A walk that revived or deleted definitions by
            -- their references at every login would bring back a switch the user deleted, or take
            -- away a new one not yet on anything (`redesigning-custom-states.md` §9-3).
            --
            -- What goes is only a definition **never touched, never referenced, and never
            -- pressed**. Any one of the three keeps it: a switch set up but not yet on an action
            -- must not vanish quietly, and a condition naming a vanished definition stays false
            -- for good.
            --
            -- **Another switch's expression is not among the three, rightly.** An expression is
            -- typed by hand, so one typo would keep a definition alive, which is the reason
            -- `CollectReferencedSwitches` leaves macro bodies out. A definition only `[$state3]`
            -- pointed at goes here, and the switch that read it is marked on the Switches tab
            -- (`GetUndefinedSwitchInExpr`).
            --
            -- **The remembered value is dropped** (owner, 2026-09-27). It was one for the whole
            -- account, and from 6 a character remembers its own; which character this one belonged
            -- to is not in the data. It is read first as the evidence of a press: without it, a
            -- switch only ever pressed has nothing left but `mode`, the shape of an untouched one.
            local keep = {};
            for index, definition in pairs(switches) do
                if (luatype(definition) == "table" and definition.savedValue ~= nil) then
                    local name = SWITCH_NAMES_AT_6[index];
                    if (name) then
                        keep[name] = true;
                    end
                    definition.savedValue = nil;
                end
            end
            CollectReferencedSwitches(db, keep);

            for index, definition in pairs(switches) do
                local name = SWITCH_NAMES_AT_6[index];
                if (luatype(definition) == "table" and name and not keep[name]
                        and SwitchIsUntouched(definition)) then
                    switches[index] = nil;
                end
            end

            -- **The table stops being filed by number and starts being filed by name.** Everything
            -- downstream of storage already named a switch by string: a condition key, a macro
            -- body, an on/off/toggle target, `DebindPrivate.Switches`. The number was the one
            -- place left where a switch had a second identity. Renaming is what could not be built
            -- on top of that: the name would have had to be a field beside the number, and then
            -- two things would say which switch this is (§6-B of
            -- `redesigning-custom-states.md`).
            --
            -- **Only number keys move.** A table that has already been through here is keyed by
            -- name, and the pre-rename share `Legacy.lua` lays on top arrives numbered and comes
            -- back through this step, so running twice has to be a no-op on what it produced.
            --
            -- A number outside the five is dropped rather than carried. Nothing could ever address
            -- it: `BindDerivedTables` read names off `SWITCH_NAMES` and skipped anything it had no
            -- name for, so such a row has never been a switch anybody could see or set.
            --
            -- Collected before anything moves, because **adding a key to a table `pairs` is walking
            -- is undefined.** Clearing one is allowed and putting one back is not, and the two
            -- would have been in the same loop.
            local numbered = {};
            for index, definition in pairs(switches) do
                if (luatype(index) == "number") then
                    numbered[index] = definition;
                end
            end
            for index, definition in pairs(numbered) do
                switches[index] = nil;
                local name = SWITCH_NAMES_AT_6[index];
                if (name and switches[name] == nil) then
                    switches[name] = definition;
                end
            end
        end
    end

    if (dbver <= 6 and 6 < to) then
        -- The unit rename, on this ladder. A computed switch's expression is macro text and can
        -- name the pointed frame's unit, which `MigrateLayer`'s step at the same number renames
        -- everywhere else -- that step's comment carries the reasoning, and an expression left
        -- behind bakes to a token the parser no longer knows.
        --
        -- **Every row, not only the root's.** A layer override carries an expression of its own,
        -- and one left behind is the quietest failure there is here: the switch reads false on
        -- that one tab and right everywhere the reader is likely to look. `RenameSwitch` walks the
        -- overrides for exactly this reason.
        --
        -- Running twice is safe: nothing carries the old spelling once this has passed.
        local function RenameUnitInRow(row)
            if (luatype(row) == "table" and luatype(row.expr) == "string") then
                row.expr = RenameUnitInMacroTextAt7(row.expr, "hover", "unitframe");
            end
        end
        for _, definition in pairs(db.switches or {}) do
            if (luatype(definition) == "table") then
                RenameUnitInRow(definition);
                for _, row in pairs(definition.overrides or {}) do
                    RenameUnitInRow(row);
                end
            end
        end
    end

    if (dbver <= 7 and 7 < to) then
        -- The definitions lay out the way `layers` does (`reshaping-stored-layers.md` §1): the
        -- root rows under `account.GENERAL[0]`, a class's override rows under `account[class][spec]`
        -- and a character's under `[guid][class][spec]`, each a table of `name -> row`. The
        -- overrides used to hang off the definition under a string naming the layer, which put a
        -- character's answer inside the account's definition.
        --
        -- **A character whose class the file does not hold** waits under `"*"` until it logs in
        -- (`HealSwitchCells` in `Profile.lua`). An alt whose only content was an override never had
        -- an entry in `characters`, and its rows are still its own.
        --
        -- **Only the three fields that are settings come across** (`mode`, `resetValue`, `expr`).
        -- `value` is worked out at every load and `displayMessage` nothing reads.
        --
        -- Running twice is safe: the new shape has an `account` key, and no switch can be named
        -- that (a switch name starts with `$`).
        local old = db.switches;
        if (luatype(old) == "table" and old.account == nil) then
            local function Row(row)
                return { mode = row.mode, resetValue = row.resetValue, expr = row.expr };
            end
            local function Cell(switches, owner, class, spec)
                switches[owner] = switches[owner] or {};
                switches[owner][class] = switches[owner][class] or {};
                switches[owner][class][spec] = switches[owner][class][spec] or {};
                return switches[owner][class][spec];
            end

            local switches = {};
            local root = Cell(switches, "account", "GENERAL", 0);
            for name, definition in pairs(old) do
                if (luatype(name) == "string" and luatype(definition) == "table") then
                    root[name] = Row(definition);
                    for key, row in pairs(luatype(definition.overrides) == "table"
                            and definition.overrides or {}) do
                        local owner, spec = strmatch(luatype(key) == "string" and key or "",
                            "^(.+):(%d+)$");
                        spec = tonumber(spec);
                        if (owner and spec and luatype(row) == "table") then
                            if (strfind(owner, "-", 1, true)) then
                                local entry = db.characters and db.characters[owner];
                                local class = luatype(entry) == "table"
                                    and luatype(entry.class) == "string" and entry.class or "*";
                                Cell(switches, owner, class, spec)[name] = Row(row);
                            else
                                Cell(switches, "account", owner, spec)[name] = Row(row);
                            end
                        end
                    end
                end
            end
            db.switches = switches;
        end
    end
end

-- `MigrateLayer` is what a received payload rides (`BringPayloadForward`).
DebindPrivate.MigrateLayer     = MigrateLayer;
DebindPrivate.MigrateSwitches  = MigrateSwitches;

--- The excluded frames, gathered into `options.frameBlacklist`.
---
--- **`db.packFrames` moves along although no tag has ever carried it.** It was written outside
--- `options` by mistake and only a worktree can hold one, but a worktree is a profile somebody is
--- using and there is nothing gained by dropping it.
---
--- Safe to run again: the second time there is nothing under either old name.
local function MigrateOptions(db)
    local options = db.options or {};
    local blacklist = options.frameBlacklist or {};
    if (type(options.blizzframes) == "table") then
        blacklist.blizzard = options.blizzframes;
    end
    options.blizzframes = nil;
    if (type(db.packFrames) == "table") then
        blacklist.addons = db.packFrames;
    end
    db.packFrames = nil;
    options.frameBlacklist = blacklist;
    db.options = options;
end

--- The containers around the layers, which neither ladder above can reach: `MigrateLayer` is handed
--- one array and `MigrateSwitches` one set of definitions.
local function MigrateContainers(db, dbver, to)
    to = to or Constants.DB_VERSION;

    if (dbver <= 7 and 7 < to) then
        -- The layers leave `shared` and the character entries and gather in `layers`, the account's
        -- under `account` and each character's under its GUID, both keyed by class and then spec
        -- (`reshaping-stored-layers.md` §1).
        --
        -- **What does not fit is dropped rather than carried.** Only tables under spec 0..5 come
        -- across, and only the array part of each, so a `customStates = {}` an old build left
        -- beside the actions goes. Empty lists go too; `LoadLayer` makes the ones it needs.
        --
        -- **A character entry with no `class` loses its layers.** `RefreshIdentity` has written the
        -- class on every login since the entry could exist, so only a hand-edited file lacks one,
        -- and what a hand edit meant is not ours to work out.
        --
        -- Running twice is safe: the second time there is no `shared` and no `entry.layers`.
        local function CleanSpecTable(specTbl)
            if (luatype(specTbl) ~= "table") then
                return nil;
            end
            local out;
            for spec = 0, 5 do
                local list = specTbl[spec];
                if (luatype(list) == "table") then
                    local kept = {};
                    for i = 1, #list do
                        if (luatype(list[i]) == "table") then
                            kept[#kept + 1] = list[i];
                        end
                    end
                    if (#kept > 0) then
                        out = out or {};
                        out[spec] = kept;
                    end
                end
            end
            return out;
        end

        db.layers = db.layers or {};
        local shared = db.shared;
        if (luatype(shared) == "table") then
            local account = db.layers.account or {};
            account.GENERAL = CleanSpecTable({ [0] = shared.GENERAL });
            for class, specTbl in pairs(luatype(shared.classes) == "table" and shared.classes or {}) do
                if (luatype(class) == "string") then
                    account[class] = CleanSpecTable(specTbl);
                end
            end
            db.layers.account = account;
        end
        db.shared = nil;

        for guid, entry in pairs(db.characters or {}) do
            if (luatype(entry) == "table") then
                local specTbl = CleanSpecTable(entry.layers);
                if (specTbl and luatype(entry.class) == "string") then
                    db.layers[guid] = { [entry.class] = specTbl };
                end
                entry.layers = nil;
            end
        end
    end
end

--- The rest of the account table: what no other ladder holds. `uiVars` as in `MigrateDB`.
local function MigrateAccount(db, dbver, to, uiVars)
    to = to or Constants.DB_VERSION;

    if (dbver <= 5 and 5 < to) then
        -- `MigrateLayer`'s step above stamps every badge it finds as arrival 1, so the next one
        -- handed out has to be 2. **Here and not there**, because that ladder runs once per layer
        -- and is also what a pasted payload rides -- a payload has no business writing this
        -- profile's counter.
        --
        -- The counter this replaces was `nextSyntheticKey`, and it counted keys rather than
        -- arrivals. Left behind it is a field nothing reads sitting in SavedVariables forever.
        db.nextArrivalID = 2;
        db.nextSyntheticKey = nil;
    end

    if (dbver <= 6 and 6 < to) then
        MigrateOptions(db);
    end

    if (dbver <= 7 and 7 < to) then
        -- **What a character carries leaves its entry for `states`**, so `characters` holds identity
        -- and nothing else (`reshaping-stored-layers.md` §1). An empty table is no state: every
        -- entry used to be handed one on load.
        local function NonEmpty(tbl)
            return luatype(tbl) == "table" and next(tbl) ~= nil and tbl or nil;
        end
        for owner, entry in pairs(db.characters or {}) do
            if (luatype(entry) == "table") then
                local switches, targets = NonEmpty(entry.switches), NonEmpty(entry.CustomTargets);
                if (switches or targets) then
                    db.states = db.states or {};
                    db.states[owner] = { switches = switches, CustomTargets = targets };
                end
                entry.switches = nil;
                entry.CustomTargets = nil;
                -- Only ever `"local"`, and read by nothing. An entry that has not logged in here is
                -- told by having no `lastSeen`.
                entry.origin = nil;
            end
        end

        -- What only the window reads leaves for `DebindUIVars`. **Only the closed tips are carried**
        -- (owner): positions, the sort and the picker's filters start over, which costs a drag and
        -- a click, while a tip somebody closed coming back is noticed.
        if (uiVars and luatype(db.tipsSeen) == "table" and uiVars.tipsSeen == nil) then
            uiVars.tipsSeen = db.tipsSeen;
        end
        db.tipsSeen = nil;
        db.ui = nil;
        db.spellPicker = nil;

        -- Keys nothing reads. The four at the top came in with the pre-rename import, which copied
        -- every key it did not know; the options are ones no build reads any more.
        db.global = nil;
        db.char = nil;
        db.class = nil;
        db.profileKeys = nil;
        db.unitFrameNoticeSeen = nil;
        -- **A value outliving its option is an orphan, not a setting turned off.** Turning a box off
        -- keeps its value because the box can be turned back on; a box that is gone cannot. 4.1.2
        -- wrote what the class trainers were read selling on camelot, which the generated table
        -- carries now (`ClassSpells_Camelot.lua`); 4.0 to 4.1.2 wrote the row taken out with its
        -- option (`giving-keys-back-when-no-action-runs.md` §1).
        db.trainerSpells = nil;
        local options = db.options;
        if (luatype(options) == "table") then
            options.giveBackWhenActionExists = nil;
            options.overviewui = nil;
            options.stateDriverUpdateThrottle = nil;
            options.removeStateDriverUpdateThrottle = nil;
            options.addCustomTargetMenusOnUnitPopup = nil;
            options.addCustomTargetMenusToUnitPopup = nil;
            -- **Dropped, not moved.** On a profile below 7 the step above has just moved it; one
            -- still on a profile at 7 arrived afterwards through the pre-rename import's verbatim
            -- copy, and moving it now would overwrite what the reader has ticked since.
            options.blizzframes = nil;
        end
    end
end

--- **When the version goes up, everything is raised in one pass.** Every entry in `characters` is
--- in memory on every login, so a single login by any character brings all twenty alts forward on
--- the spot. Nothing can fall behind, which is why there is no per-entry version - `dbver` is the
--- only one.
---
--- **One version at a time, every ladder at each.** A step raises its own version to the next and
--- reads that version's shape only (owner, `reshaping-stored-layers.md` §4 1-2). Run ladder by
--- ladder, an early step of one would meet data another had already carried to the end: the
--- `dbver <= 5` switch step read actions from containers that only exist at 8. Within a version
--- the containers go first, then the actions, then the definitions that name them, then the rest.
---
--- The paths that join late (pre-rename SavedVariables, someone else's export file) **arrive
--- carrying their own version and are raised to the current one before being attached**
--- (`Legacy.lua`). Once attached, everything is on the same version.
---
--- `uiVars` is `DebindUIVars`, where a step can hand on what only the window reads. Nil for a
--- profile that is not the one being loaded.
local function MigrateDB(db, uiVars)
    local dbver = db.dbver;
    if (dbver >= Constants.DB_VERSION) then
        return;
    end

    for version = dbver, Constants.DB_VERSION - 1 do
        local to = version + 1;
        MigrateContainers(db, version, to);
        ForEachActionList(db, function(list)
            MigrateLayer(list, version, to);
        end);
        -- **The profile's spells go on their first rank, once**
        -- (`keeping-a-pinned-rank-apart-from-the-spell.md` §7). Here and not in `MigrateLayer`,
        -- which received payloads ride too: they do the same where they arrive, every time
        -- (`BringPayloadDataForward`). Read off the generated table, so what this release's table
        -- does not know stays where it was, and **nothing tries again later** (owner): what is left
        -- is a duplicate the cleanup misses, which keeps both.
        if (version <= 7 and 7 < to) then
            ForEachActionList(db, function(list)
                for i = 1, #list do
                    local action = list[i];
                    -- Version 8's type name (`MigrateLayer`'s header).
                    if (action.type == "spell") then
                        action.value = DebindPrivate.CanonicalSpellID(action.value);
                    end
                end
            end);
        end
        MigrateSwitches(db, version, to);
        MigrateAccount(db, version, to, uiVars);
    end

    db.dbver = Constants.DB_VERSION;
end
DebindPrivate.MigrateDB = MigrateDB;

--- `MigrateDB` that does not raise. Returns true when the ladder reached the end, or false and the
--- error, which has already gone to `geterrorhandler()`.
---
--- **A caller hands in a table it can throw away**, and takes it only on true. `dbver` is stamped
--- after every step has run, so a profile abandoned partway carries the old number over data some
--- steps have already raised, and the next login walks those steps a second time. That is what
--- this takes away: a profile is either raised whole or left as it was.
---
--- **The error handler and not `pcall`**, so the report carries the stack of the step that failed.
function DebindPrivate.TryMigrateDB(db, uiVars)
    return xpcall(function()
        MigrateDB(db, uiVars);
    end, function(err)
        geterrorhandler()(err);
        return err;
    end);
end
