local _, DebindPrivate = ...;

local Constants           = DebindPrivate.Constants;
local luatype             = type;
-- One caller: the `dbver` 5 step that opens the old SETSTATE bitpack.
local band                = bit.band;
local ForEachStoredAction = DebindPrivate.ForEachStoredAction;

--- Raises one layer's array of actions from `dbver` to `Constants.DB_VERSION`.
---
--- **Every step opens with `dbver <= N`, never `== N`.** With `==`, a profile two versions behind
--- walks the first step and leaves. And each step has to be safe to run again on data it has
--- already finished.
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
local function MigrateLayer(layerTbl, dbver)
    if (layerTbl == nil) then
        return;
    end

    if (dbver <= 1) then
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.checkUnitExists and (Constants.BASIC_UNITS[action.unit] or Constants.SPECIAL_UNITS[action.unit])) then
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

            if ((Constants.BASIC_UNITS[action.checkedUnit] or Constants.SPECIAL_UNITS[action.checkedUnit]) and action.checkedUnitValue ~= nil) then
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

    if (dbver <= 2) then
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

    if (dbver <= 4) then
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
        for i = 1, #layerTbl do
            local checkedUnits = layerTbl[i].checkedUnits;
            if (checkedUnits) then
                for unit, value in pairs(checkedUnits) do
                    if (value == true) then
                        checkedUnits[unit] = {};
                    elseif (value == false) then
                        checkedUnits[unit] = { exists = false };
                    elseif (value == "help") then
                        checkedUnits[unit] = { reaction = Constants.REACTION_HELP };
                    elseif (value == "harm") then
                        checkedUnits[unit] = { reaction = Constants.REACTION_HARM };
                    end
                end
            end
        end

        -- Then the hover condition moves in beside those units. The folding rule is
        -- `UnitFrameConditionFromLegacy`'s (`Units.lua`): building a binding has to raise a profile
        -- the migration has not reached by the same rule, and written twice that rule would part.
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
                -- 접기는 바인딩 모양 위에서 돈다. 넣기 전에 한 번 통과시키고, 나온 것을 다시
                -- 저장 모양으로 돌린다 - `false`(없을 때)만 표가 되면 되고, 나머지는 그대로다.
                local folded = DebindPrivate.UnitFrameConditionFromLegacy(
                    action.hover, action.reactions,
                    DebindPrivate.UnitConditionForBinding(action.checkedUnits.hover));
                if (folded == false) then
                    folded = { exists = false };
                end
                action.checkedUnits.hover = folded;
                action.hover = nil;
                action.reactions = nil;
            end
        end
    end

    if (dbver <= 5) then
        -- Shipped in 3.3. **An unshipped step takes every storage change until it ships**, rather
        -- than opening the next number: splitting a number nobody has met makes a step for an
        -- intermediate shape that never existed, and that step meets no data forever.
        --
        -- 조건을 액션 최상단에서 `conditions` 안으로 내리고, 옮기는 김에 이름도 간다.
        --
        -- **왜 옮기나.** 저장 필드 서른 개 중 열여덟이 조건이었고, 그 사이에 `unit`이 섞여
        -- 앉아 있었다. `unit`은 겨누는 대상이고 `checkedUnits`는 언제 발동하느냐라, 이름만
        -- 보면 한 식구인데 성격이 정반대다. 높이가 갈리면 구조가 그것을 말한다.
        --
        -- **그래서 `checkedUnits`는 `units`가 된다.** `conditions.` 접두어가 이미 "이건
        -- 조건이다"를 말하므로 `checked`가 같은 말을 한 번 더 한다. 이름은 옮기는 길에
        -- 얹혀서 온다 - 따로 단계를 세우면 아무 데이터도 안 만나는 단계가 하나 는다.
        --
        -- **무엇이 조건인지는 `Constants.IsConditionField` 하나가 답한다.** 여기 목록을 또
        -- 적으면 그 표와 갈라지는 날이 온다. `$state1`~`5`도 그 함수가 같이 받는다.
        --
        -- 다시 돌아도 안전하다. 최상단에 조건 이름이 안 남아 있으면 아무것도 안 한다.
        --
        -- **이름을 먼저 다 모으고, 그다음에 옮긴다.** 한 바퀴로 쓰면 첫 조건을 만났을 때
        -- `action.conditions`라는 **없던 키**가 순회 중에 생기는데, Lua 5.1은 그 경우의
        -- `next` 동작을 정의하지 않는다(있는 필드를 지우는 것은 되고, 없던 필드에 대입하는
        -- 것은 안 된다). 그러면 뒤의 조건이 건너뛰어지고, 최상단에 남은 그것을 바로 뒤의
        -- `CleanUpDB`가 지운다. **사용자가 건 조건이 로그인 한 번에 사라지고 `dbver`는
        -- 이미 찍혀 있어서 다시 돌 기회도 없다.**
        local names = {};
        for i = 1, #layerTbl do
            local action = layerTbl[i];

            local count = 0;
            for k in pairs(action) do
                if (Constants.IsConditionField(k) or k == "checkedUnits") then
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

        -- SETSTATE's `mode | index` bitpack, opened out into three types and a name.
        --
        -- **The step holds the old name and the old numbers itself.** Neither the type `"setstate"`
        -- nor the `SETCUSTOM_MODE_*` flags is a language this build speaks any more, and left in
        -- `Constants.lua` a dead name sits next to the live ones forever. A step is frozen once it
        -- is written, so there is nothing here for it to drift from (`0-DECISION-LOG.md`,
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
            [0x100] = Constants.SETSTATE_ON,
            [0x200] = Constants.SETSTATE_OFF,
            [0x400] = Constants.SETSTATE_TOGGLE,
        };
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.type == "setstate" and luatype(action.value) == "number") then
                local newType = SETSTATE_BY_FLAG[band(action.value, 0x100 + 0x200 + 0x400)];
                local name = Constants.SWITCH_NAMES[band(action.value, 0xf)];
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

    --- **The unreleased step.** Everything raised here landed after the last tag, so it is one
    --- step rather than a rung each, and unrelated jobs share it (`Constants.DB_VERSION`).
    if (dbver <= 6) then
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
                action.type = Constants.USESLOT;
            end
        end

        -- A command that presses an action bar button becomes the action button action under the
        -- same name: Debind holds every key it has an action on, so the game's binding no longer
        -- gets the press (`dropping-the-game-fallback.md` §3). Every other command is left
        -- as saved and binds as a block. Safe to run again, and payloads ride it too.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.type == Constants.COMMAND and Constants.ACTION_BUTTON_COMMANDS[action.value]) then
                action.type = Constants.ACTIONBUTTON;
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
                    and not Constants.SPEC_RESOLVED_TYPES[action.type]) then
                if (action.type ~= Constants.SPELL) then
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
        -- **The axis is read from the top level as well.** Conditions moved inside `conditions` in
        -- the `dbver <= 5` step and that step asks `Constants.IsConditionField`, which no longer
        -- answers for `pet`. A profile riding the ladder from below that step arrives here with the
        -- value still at the top, and `CleanUpDB` deletes what this does not take.
        --
        -- Running twice is safe: the second pass finds no `pet`.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            local value = action.pet;
            local conditions = action.conditions;
            if (value == nil and conditions) then
                value = conditions.pet;
            end

            if (value ~= nil) then
                if (conditions == nil) then
                    conditions = {};
                    action.conditions = conditions;
                end
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
                action.pet = nil;
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
        -- it any more (`MacroText.lua`'s `RenameUnitInMacroText` says why).
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

            if (action.type == Constants.MACROTEXT and luatype(action.value) == "string") then
                action.value = DebindPrivate.RenameUnitInMacroText(action.value, "hover", "unitframe");
                -- **A whole token after the frame name**, the way `/click` reads it and the way
                -- `renameClickedSwitch` reads the switch in the same position.
                --
                -- **Both spellings of the frame, which is why the name is matched loosely.**
                -- `Legacy.lua` rewrites `DebounceCustom` into `DebindCustom` **after** this ladder
                -- has run (`ImportLayer` migrates first and repairs second), so a pre-rename body
                -- still says `DebounceCustom<n>` when it passes here -- and `dbver` is stamped by
                -- then, so the ladder never comes back for it.
                action.value = action.value:gsub("(Deb%a+Custom%d+%s+)(%S+)", function(head, token)
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
        -- **Read from the top level as well.** `frameTypes` is no longer a condition field, so a
        -- profile riding the ladder from below the `dbver <= 5` step arrives with the value still at
        -- the top, exactly as the `pet` step above meets it.
        --
        -- **A mask already on the row wins**, the way that step's row does: one row cannot hold two
        -- answers, and taking the outer one would undo an edit made against the new shape.
        --
        -- Running twice is safe: the second pass finds no `frameTypes` outside the row.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            local conditions = action.conditions;
            local mask = action.frameTypes;
            if (mask == nil and conditions) then
                mask = conditions.frameTypes;
            end

            if (mask ~= nil) then
                if (conditions == nil) then
                    conditions = {};
                    action.conditions = conditions;
                end
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
                        row = { exists = true, reaction = Constants.REACTION_HELP };
                    elseif (row == "harm") then
                        row = { exists = true, reaction = Constants.REACTION_HARM };
                    else
                        row = { exists = false };
                    end
                    units.unitframe = row;
                end
                if (row.frameTypes == nil) then
                    row.frameTypes = mask;
                end
                conditions.frameTypes = nil;
                action.frameTypes = nil;
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
                local lhsImportance = lhsAction.priority or Constants.DEFAULT_IMPORTANCE;
                local rhsImportance = rhsAction.priority or Constants.DEFAULT_IMPORTANCE;
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
                        if (DebindPrivate.UnitConditionForBinding(stored) ~= nil) then
                            return true;
                        end
                    end
                end
                return false;
            end

            for _, group in pairs(groups) do
                for j = 1, #group do
                    local action = group[j].action;
                    local folded = DebindPrivate.UnitConditionForBinding(
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
        -- **The rest get nothing written, because off is the default and off is what they did.** A
        -- key with no unit frame condition never sent a press to the unit under the cursor, and with
        -- no twin its original stands in the last tier exactly as it did. A mouse button keeps the
        -- key's own [no unit frame] as well, which only holds while nothing is stored on that unit
        -- row (`BuildUnitStates`), and a twin is what would have taken it away (§7).
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
                local folded = DebindPrivate.UnitConditionForBinding(units and units.unitframe);
                if (folded ~= nil and folded ~= false) then
                    casting = casting or {};
                    casting.hoverCastMode = "unitframe";
                    casting.hoverCast = "cast";
                    if (action.ignoreHoverUnit) then
                        casting.hoverCast = "usual";
                    end
                    casting.normalCast = false;
                    -- 빈 [올렸을 때]였나. `UnitConditionForBinding`이 낸 표에 축이 하나도 없으면
                    -- 그것이 [올렸을 때]뿐인 조건이다.
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
        -- it answered is the account's now ("House Editor" under Keys Given Back), so a value left
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

end

--- Raises one whole per-spec table (`{[0]=…, [1]=…}`). Class entries and character entries have
--- the same shape, so both go through here.
local function MigrateSpecTable(specTbl, dbver)
    if (specTbl == nil) then
        return;
    end
    for spec = 0, 5 do
        MigrateLayer(specTbl[spec], dbver);
    end
end

--- Everything on the shared side (layers 1-6).
---
--- This used to build class names with `C_CreatureInfo.GetClassInfo` and look each one up, because
--- `dbver` and `options` sat right next to the class names and `pairs` would have walked them too.
--- `shared.classes` holds nothing but classes, so it can just be iterated.
local function MigrateShared(shared, dbver)
    if (shared == nil) then
        return;
    end
    MigrateLayer(shared.GENERAL, dbver);
    if (shared.classes) then
        for _, classTbl in pairs(shared.classes) do
            MigrateSpecTable(classTbl, dbver);
        end
    end
end

--- Every switch name this profile still names, gathered from all five layers of every character
--- and every class.
---
--- **Conditions and `SETSTATE` targets, and nothing else.** Those two are the places a switch is
--- named by picking it out of a menu, so a name cannot get in by being mistyped. A macro body's
--- `[$burst]` is typed by hand and is deliberately left out (`redesigning-custom-states.md`
--- §9-3): read as a use, one typo would keep a definition alive and take away the red mark that is
--- how the user finds out about the typo at all.
---
--- **No `charEntry`, unlike the callers further down.** This runs inside the migration, where the
--- entry for the character logging in has just been made and holds nothing but what the ladder
--- itself writes there.
local function CollectReferencedSwitches(db, found)
    ForEachStoredAction(db, function(action)
        local conditions = action.conditions;
        if (conditions) then
            for name in pairs(conditions) do
                if (Constants.IsSwitchName(name)) then
                    found[name] = true;
                end
            end
        end
        if (Constants.SETSTATE_MODES[action.type] and luatype(action.value) == "string") then
            found[action.value] = true;
        end
    end);
end

--- Has anything been set on this definition, or is it the empty one a load used to plant?
---
--- **`value` is not a setting.** `BindDerivedTables` writes it on every load from `resetValue` and
--- the character's stored value, so it is on every definition including the ones nobody ever
--- touched. Everything else on a definition got there because somebody chose it.
---
--- **Pressing a switch leaves nothing here**, and that is the one thing this cannot answer on its
--- own. The remembered value sits on the character now, so a switch somebody has used and never
--- configured looks exactly like one nobody made. `CollectStoredSwitchValues` is what the caller
--- asks instead.
local function SwitchIsUntouched(definition)
    for key, value in pairs(definition) do
        if (key == "mode") then
            if (value ~= Constants.SWITCH_MODES.MANUAL) then
                return false;
            end
        elseif (key ~= "value") then
            return false;
        end
    end
    return true;
end

--- Every switch name some character remembers a value for.
---
--- **Having a value is evidence the switch was used**, and after the `dbver` 6 move it is the only
--- evidence left for one nobody configured (`SwitchIsUntouched`). Reading it back out of the
--- characters rather than remembering what the move just wrote is what keeps that step safe to run
--- twice: the answer is derived from the shape the step produces, not from the one it consumed.
local function CollectStoredSwitchValues(db, charEntry, out)
    for _, entry in pairs(db.characters) do
        for name in pairs(entry.switches or {}) do
            out[name] = true;
        end
    end
    if (charEntry) then
        for name in pairs(charEntry.switches or {}) do
            out[name] = true;
        end
    end
end

--- The remembered value leaves the account table and lands on the characters.
---
--- **`db.characters` is inside the account file and all of it is in memory on every login**, so
--- the design's "each character migrates on its own first login" does not hold here -- the ladder
--- runs once per account. What that one pass can reach is every entry that already exists plus the
--- character logging in, and between them they cover everyone who could notice: an alt with no
--- entry has no character-specific anything, which is the case the entry is lazily withheld for.
---
--- **Copied to all of them rather than to one.** Handing the value only to the character present
--- would silently flip the switch off on every other one at their next login, and which key does
--- what hangs off that. They diverge from here on, which is the point of the move.
---
--- **A value already on a character wins.** Nothing on the ordinary path has one -- `dbver` 5 data
--- has nowhere to keep it -- but `Legacy.lua` runs this at PLAYER_LOGIN on an account that has been
--- writing values since it was installed, and the account share it carries is older than any of
--- them. Whichever value arrives, the one the user set on that character is the newer answer.
local function MoveSavedValues(db, switches, charEntry)
    local function Give(entry, name, value)
        entry.switches = entry.switches or {};
        if (entry.switches[name] == nil) then
            entry.switches[name] = value;
        end
    end

    for index, definition in pairs(switches) do
        if (luatype(definition) == "table" and definition.savedValue ~= nil) then
            local name = Constants.SWITCH_NAMES[index];
            if (name) then
                for _, entry in pairs(db.characters) do
                    Give(entry, name, definition.savedValue);
                end
                if (charEntry) then
                    Give(charEntry, name, definition.savedValue);
                end
            end
            definition.savedValue = nil;
        end
    end
end

--- The switch definitions, which sit at the top of the global table rather than inside a layer.
---
--- **A second ladder, because `MigrateLayer` cannot reach these.** That one walks a layer's array of
--- actions; a definition is not an action and lives nowhere near one. Both ladders are stepped in
--- the same `MigrateDB` pass, so nothing is ever half raised, and `check:dbver` asks each about its
--- own order because two ladders carrying the same step number is not a fault.
---
--- **`Legacy.lua`'s `ImportAccount` is the other caller**, and it is the one that had to be found:
--- the pre-rename share is laid on top of a table `MigrateDB` has already stamped.
---
--- **It is handed the whole account table, not just the definitions**, because the step below has
--- to know which switches the layers still name. On the `ImportAccount` path this character's own
--- pre-rename layers have not arrived yet (`ImportCharacter` runs after), so a definition used
--- only there is judged on whether anything was ever set on it. That is enough for a switch the
--- user actually used: pressing one leaves a remembered value, and both of the other modes write a
--- field of their own.
---
--- **`charEntry` is this character's entry, and it is handed in because it may not be in
--- `db.characters` yet** -- `InitDB` withholds an entry until there is something in it. Without it
--- the remembered value would reach every alt that has an entry and miss the person logging in.
local function MigrateSwitches(db, dbver, charEntry)
    if (dbver <= 5) then
        -- **아직 안 나간 단계다** - `MigrateLayer`의 같은 단계 주석을 볼 것.
        --
        -- 정의의 저장 모양 셋을 한 번에 옮긴다. 표 이름 `customStates` -> `switches`,
        -- `mode`의 숫자 -> 문자열, `initialValue` -> `resetValue`.
        --
        -- **단계가 옛 숫자를 직접 든다.** `Constants.SWITCH_MODES`는 이 판이 더 이상 모르는
        -- 언어라, 거기에 옛 값을 남겨두면 죽은 이름이 산 것 옆에 영원히 앉는다. 단계는 한 번
        -- 쓰면 얼어붙어서 갈릴 것이 없다 (`Export.lua`의 `NestPayloadConditions`가 같은
        -- 이유로 `checkedUnits`라는 글자를 직접 든다).
        --
        -- 다시 돌아도 안전하다. 옮길 이름이 안 남아 있으면 아무것도 안 한다 - `mode`는 이미
        -- 문자열이면 건드리지 않고, `initialValue`는 옮기면서 지운다.
        if (db.customStates ~= nil) then
            -- **옛 이름이 있으면 그것이 정의다.** 개명 전 SavedVariables는 `MigrateDB`가
            -- 지나간 **뒤에** `customStates`를 통째로 얹으므로(`Legacy.lua`의
            -- `ImportAccount`), 그 길에서는 새 이름이 이미 있는 채로 여기 들어온다. 그때
            -- 지켜야 하는 것은 방금 들어온 쪽이다.
            db.switches = db.customStates;
            db.customStates = nil;
        end

        local switches = db.switches;
        if (switches) then
            for _, definition in pairs(switches) do
                if (luatype(definition) == "table") then
                    if (luatype(definition.mode) == "number") then
                        if (definition.mode == 3) then
                            definition.mode = Constants.SWITCH_MODES.EXPR;
                        else
                            definition.mode = Constants.SWITCH_MODES.MANUAL;
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

            -- **다섯을 미리 만들어두던 것을 여기서 되돌린다.** 매 로드마다 빈 정의 다섯 개를
            -- 심던 자리가 `BindDerivedTables`였고, 그래서 이 기능을 한 번도 안 쓴 프로필에도
            -- 아무도 만든 적 없는 스위치 다섯이 앉아 있다. 만드는 것은 이제 사용자가 이름을
            -- 적는 것뿐이라(`CreateSwitch`), 그때 심긴 것은 여기서 한 번 걷어낸다.
            --
            -- **한 번이지 매 로드 수리가 아니다.** 참조를 훑어 정의를 되살리거나 지우는 것이
            -- 로그인마다 돈다면, 사용자가 지운 스위치가 참조 때문에 돌아오거나 아직 아무 데도
            -- 안 건 새 스위치가 사라진다 (`redesigning-custom-states.md` §9-3).
            --
            -- 지우는 것은 **손댄 적도 없고, 참조도 없고, 어느 캐릭터도 값을 기억하지 않는**
            -- (아래 `dbver <= 6` 단계가 계산식 안의 유닛 이름을 옮긴다)
            -- 것뿐이다. 셋 중 하나라도 있으면 남는다: 설정을 해뒀는데 아직 아무 액션에도 안 건
            -- 스위치가 조용히 사라지면 안 되고, 조건이 거는 이름의 정의가 사라지면 그 조건은
            -- 영영 거짓인 채로 남는다.
            --
            -- **다른 스위치의 계산식은 그 셋에 없고, 없는 것이 맞다.** 계산식은 손으로 치는
            -- 글자라 오타 하나가 정의를 살려두게 되는데, 그건 `CollectReferencedSwitches`가
            -- 매크로 본문을 일부러 뺀 이유 그대로다. 그래서 `[$state3]`만 가리키던 손 안 댄
            -- 정의는 여기서 지워지고, 그것을 부르던 스위치가 `Switches` 탭에서 빨개진다
            -- (`GetUndefinedSwitchInExpr`). 지우고 말해주는 쪽이지 조용히 살려두는 쪽이 아니다.
            --
            -- **값을 옮기는 것이 먼저다.** 옮기고 나면 눌러보기만 한 스위치의 정의에는 모드
            -- 하나만 남아 손 안 댄 것과 모양이 같아진다. 눌러본 증거를 계정이 아니라 캐릭터
            -- 쪽에서 읽는 것이 그것을 받는 자리이고(`CollectStoredSwitchValues`), 옛 판정을
            -- 그대로 뒀으면 실제로 쓰던 스위치가 값을 옮긴 바로 그 단계에 지워졌다.
            MoveSavedValues(db, switches, charEntry);

            local keep = {};
            CollectReferencedSwitches(db, keep);
            CollectStoredSwitchValues(db, charEntry, keep);

            for index, definition in pairs(switches) do
                local name = Constants.SWITCH_NAMES[index];
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
                local name = Constants.SWITCH_NAMES[index];
                if (name and switches[name] == nil) then
                    switches[name] = definition;
                end
            end
        end
    end

    if (dbver <= 6) then
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
                row.expr = DebindPrivate.RenameUnitInMacroText(row.expr, "hover", "unitframe");
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
end

-- Used by `Legacy.lua` to raise imported data to the current version before attaching it.
DebindPrivate.MigrateLayer     = MigrateLayer;
DebindPrivate.MigrateSpecTable = MigrateSpecTable;
DebindPrivate.MigrateShared    = MigrateShared;
DebindPrivate.MigrateSwitches  = MigrateSwitches;

--- The excluded frames, gathered into `options.frameBlacklist`.
---
--- **Named and public because two paths reach it.** The ladder below runs it for a stored profile,
--- and `Legacy.lua` runs it by hand for a pre-rename one: that import copies `options` verbatim at
--- PLAYER_LOGIN, long after the ladder stamped `db.dbver`, so an old shape arriving that way meets
--- no step at all. `MigrateSwitches` is hand-called from the same place for the same reason.
---
--- **`db.packFrames` moves along although no tag has ever carried it.** It was written outside
--- `options` by mistake and only a worktree can hold one, but a worktree is a profile somebody is
--- using and there is nothing gained by dropping it.
---
--- Safe to run again: the second time there is nothing under either old name.
function DebindPrivate.MigrateOptions(db)
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

--- **When the version goes up, everything is raised in one pass.** Every entry in `characters` is
--- in memory on every login, so a single login by any character brings all twenty alts forward on
--- the spot. Nothing can fall behind, which is why there is no per-entry version - `dbver` is the
--- only one.
---
--- The paths that join late (pre-rename SavedVariables, someone else's export file) **arrive
--- carrying their own version and are raised to the current one before being attached**
--- (`Legacy.lua`). Once attached, everything is on the same version.
local function MigrateDB(db, charEntry)
    local dbver = db.dbver;
    if (dbver >= Constants.DB_VERSION) then
        return;
    end

    MigrateShared(db.shared, dbver);
    for _, entry in pairs(db.characters) do
        MigrateSpecTable(entry.layers, dbver);
    end
    MigrateSwitches(db, dbver, charEntry);

    if (dbver <= 5) then
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

    --- The unreleased step; see `MigrateLayer`'s comment on the same one.
    if (dbver <= 6) then
        DebindPrivate.MigrateOptions(db);
    end

    db.dbver = Constants.DB_VERSION;
end
DebindPrivate.MigrateDB = MigrateDB;
