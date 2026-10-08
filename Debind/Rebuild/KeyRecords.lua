local _, DebindPrivate = ...;
local Constants               = DebindPrivate.Constants;
local Spells                  = DebindPrivate.Spells;

local DEBUG                   = DebindPrivate.DEBUG;
local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;
local BASIC_UNITS             = Constants.BASIC_UNITS;

local luatype                            = type;
local format, tostring                   = format, tostring;
local wipe, ipairs, pairs, tinsert       = wipe, ipairs, pairs, tinsert;
local band                               = bit.band;
local GetSpellNameAndIconID              = DebindPrivate.GetSpellNameAndIconID;
local GetSpellSubtext                    = C_Spell.GetSpellSubtext;
local FrameAxesOn                        = DebindPrivate.FrameAxesOn;

local Rebuild                 = DebindPrivate.Rebuild;
local _unitsSeen              = Rebuild.unitsSeen;
local sortedKeys              = Rebuild.sortedKeys;
local addSwitch               = Rebuild.addSwitch;
local appendLine              = Rebuild.appendLine;
local appendKeyValue          = Rebuild.appendKeyValue;
local SetBindingAttributes    = Rebuild.SetBindingAttributes;
local ParsedStateAxis         = Rebuild.ParsedStateAxis;
local StateExpression         = Rebuild.StateExpression;
local UnitExpression          = Rebuild.UnitExpression;

--- `EmitRecord`'s scratch for `sortedKeys`. Two, because the walks nest: one unit's cells are
--- sorted inside the walk over the record's units.
local _sortedB           = {};
local _sortedC           = {};

--- **The names are the role headers' aliases**, which is what `UnitRoles` stores, so nothing
--- translates between the two sides. `unknown` has no header, and cannot: it is the answer for a
--- unit no header claimed.
--- The four cells, as the names both sides speak. **Not the three boxes a user ticks**: those
--- overlap and so cannot name the one thing a unit is (`Constants.lua`'s `UNITGROUPCELL_*`).
local UNITGROUPCELL_NAMES = {
    [Constants.UNITGROUPCELL_NEITHER] = "neither",
    [Constants.UNITGROUPCELL_PARTY]   = "party",
    [Constants.UNITGROUPCELL_RAID]    = "raid",
    [Constants.UNITGROUPCELL_BOTH]    = "both",
};

local ROLE_NAMES = {
    [Constants.ROLE_TANK]    = "tank",
    [Constants.ROLE_HEALER]  = "healer",
    [Constants.ROLE_DAMAGER] = "damager",
    [Constants.ROLE_NONE] = "norole",
};

--- The condition axes that go out as a plain field, **in the order they are emitted in**, with the
--- value that means "no restriction" for the three that have one.
---
--- `known` carries `derived`: what goes out is not the condition's value but the macro conditional
--- built from the action's own value.
local CONDITION_AXES     = {
    { field = "groups",     allValue = Constants.GROUP_ALL },
    { field = "combat" },
    { field = "stealth" },
    { field = "mounted" },
    { field = "indoors" },
    { field = "flyable" },
    { field = "advflyable" },
    { field = "flying" },
    { field = "skyriding" },
    { field = "known",      derived = true },
    { field = "forms",      allValue = Constants.FORM_ALL },
    { field = "bonusbars",  allValue = Constants.BONUSBAR_ALL },
    { field = "specialbar" },
    { field = "extrabar" },
    { field = "petbattle" },
};

local function field(record, name, value)
    local count = record.fieldCount + 1;
    record.fieldCount = count;
    record.fieldNames[count] = name;
    record.fieldValues[count] = value;
end

--- Stamps every binding on one key and **drops the ones with no way to fire**.
---
--- `DescribeBinding` refuses a value that is wrong in itself (a pet command this client has no slash
--- command for, a binding command that presses no action button), and those reach here only if
--- the issue that marks them did not (`BINDING_ISSUE_UNKNOWN_*`, outcome OMIT): the action is
--- skipped and the next one takes the press. **A value the game merely has nothing to do for is
--- not refused** (a flyout with every slot empty, a stance this character lacks): it goes out as a
--- button that does nothing, the way a spell this character does not know is still cast (`Inert`,
--- owner, 2026-10-07).
---
--- **What it returns is whether a record goes out**, of each kind, and that is what decides whether
--- the key is held (`UpdateBindingsMap`).
local function PrepareKeyBindings(key, bindingArray)
    local button, buttonPrefix = bindingArray.button, bindingArray.buttonPrefix;
    local hasClickCast, hasKeyRecord = false, false;

    for i = 1, #bindingArray do
        local binding = bindingArray[i];
        -- **Every record on a mouse button stands on the frame path unless it rules the frame out**,
        -- by the reader's [no unit frame] or by Hover Cast's `"skip"` on that unit
        -- (`which-action-a-key-runs.md` S4). The solver has no column for the path a record takes,
        -- so a box is right only where the record really is: a key-path-only record whose box spans
        -- the frame half would cover, and delete, a frame record it never meets.
        --
        -- **Never with META held.** The secure button builds a click's prefix from Shift, Ctrl and Alt
        -- alone, so a META click arrives on a frame as the bare one, and a record here would be filed
        -- under that button (`GetModifierIndex`) and take its clicks.
        --
        -- **One that needs a frame does not hold the key**: a click over a frame goes to the frame,
        -- so the key path never sees one, and holding the key for it would take the world click.
        --
        -- **Never the self or focus twin** (2026-10-04, owner). A modifier held on a frame click is
        -- that click as it stands: what the frame does with it is Blizzard's click bindings, the
        -- frame's own attributes or another addon's wrapper, differs per frame and cannot be read
        -- reliably, so taking it would hide the game's side of every modified frame click by
        -- default (`which-action-a-key-runs.md` §7).
        local unitFrameCondition = DebindPrivate.UnitFrameConditionOf(binding);
        local wantsFrame = type(unitFrameCondition) == "table";
        local refusesFrame = unitFrameCondition == false or binding.skipsPointedUnit == "unitframe"
            or (buttonPrefix ~= nil and buttonPrefix:find("META-", 1, true) ~= nil);
        binding.isClickCast = button ~= nil and not refusesFrame and
            (binding.castModifier == nil or binding.castModifier == Constants.CASTMOD_NONE) and
            true or false;
        binding.holdsKey = (button == nil or not wantsFrame) and true or false;
        -- A spec-resolved type's spell is on the binding, not in `value` (`FillBinding`), and nil
        -- there is a specialization with nothing to cast: the button is still handed out, with no
        -- action on it, so the key is taken and the press does nothing (§4 of the design).
        --
        -- **`if`, not `and`/`or`.** The ternary shape falls through to `value` when the spell is
        -- nil, which is the one answer this branch exists to produce.
        --
        -- **`spellToCast` first where it is there.** A spec-resolved binding casts its entry's spell
        -- (`SpecSpells.lua`), which is not always `spell`: the warlock's dispel is named and drawn
        -- after the spell in the book and cast under another one, and on camelot the row can show
        -- one of two spells while this binding casts the other. `KnownSpellAsked` reads it too, so
        -- the `known` this binding goes out under names the spell it casts.
        --
        -- **`holdsOnly` goes out as the specialization with nothing to cast does**: the key taken
        -- and the press doing nothing (`FillBinding`).
        local bindingValue = binding.value;
        if (Constants.SPEC_RESOLVED_TYPES[binding.type]) then
            if (binding.holdsOnly) then
                bindingValue = nil;
            else
                bindingValue = binding.spellToCast or binding.spell;
            end
        end
        binding.clickframe, binding.clickbutton, binding.castSpell =
            SetBindingAttributes(binding.type, bindingValue, DebindPrivate.CastUnitOf(binding),
                binding.automatics, binding.pinnedSpell, binding.resolvedSpellID);

        -- **DEBUG only.** Which key ended up on which spell id, which nothing else records: the
        -- action keeps the id the reader picked, `_facts` is wiped per binding, and the button name
        -- says nothing about either. `base` is resolved the same way the bake resolves it, so the
        -- row says what `*spell-`'s name was taken from.
        --
        -- **`ResolveBaseSpell` and not a bare client call, so this row says what the bake used.**
        -- The client places 390414 at 194223 only while the three talents that make it
        -- (`Celestial Alignment`, `Orbital Strike`, `Incarnation: Chosen of Elune`) are all taken
        -- and answers the id back otherwise; the name index is what carries it the rest of the way
        -- (`Spells.lua`). A row showing the client's answer alone would disagree with the button
        -- exactly where this dump is worth reading.
        if (DEBUG and binding.type == Constants.SPELL) then
            -- Nil for a stored name this specialization cannot obtain.
            local base = DebindPrivate.ResolveBaseSpell(bindingValue, binding.resolvedSpellID);
            tinsert(DebindPrivate.SpellFacts, {
                key = binding.key,
                stored = bindingValue,
                base = base,
                baseName = base and GetSpellNameAndIconID(base),
                subtext = base and GetSpellSubtext(base),
                override = base and C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(base, 0, true, 0),
                button = binding.clickbutton,
            });
        end

        if (binding.type ~= Constants.BLOCK
                and not (binding.clickframe and binding.clickbutton)) then
            if (DEBUG) then
                DebindPrivate.log(format("|cffff6666[Debind/attr]|r DROP %s/%s (%s) 걸 수단이 없다",
                    tostring(binding.type), tostring(binding.value), key));
            end
            binding.isClickCast, binding.holdsKey = false, false;
        end

        hasClickCast = hasClickCast or binding.isClickCast;
        hasKeyRecord = hasKeyRecord or binding.holdsKey;
    end

    return hasClickCast, hasKeyRecord;
end

--- One BLOCK per tier, shared by every key. **Nothing hands them to the solver**, so no key and no
--- unit state is read off them.
---
--- **`unitConditions` is set here** because an end never goes through `BuildUnitStates`.
local BLOCKS = {
    [Constants.CASTMOD_SELF] = { type = Constants.BLOCK, conditions = {}, unitConditions = {},
        castModifier = Constants.CASTMOD_SELF, holdsKey = true, isClickCast = false },
    [Constants.CASTMOD_FOCUS] = { type = Constants.BLOCK, conditions = {}, unitConditions = {},
        castModifier = Constants.CASTMOD_FOCUS, holdsKey = true, isClickCast = false },
    [Constants.CASTMOD_NONE] = { type = Constants.BLOCK, conditions = {}, unitConditions = {},
        castModifier = Constants.CASTMOD_NONE, holdsKey = true, isClickCast = false },
};

--- What closes the [none held] tier instead while `GiveBackWhenNoActionRuns` is on: a giveback,
--- bound as a block the way a saved one is (`FillBinding`). A press that still reaches it, before
--- the next beat lets the key go, does nothing.
local GIVEBACK_END = { type = Constants.BLOCK, tail = Constants.GIVEBACK, conditions = {}, unitConditions = {},
    castModifier = Constants.CASTMOD_NONE, holdsKey = true, isClickCast = false };

local _withBlocks = {};

--- The key's bindings with a BLOCK closing the self tier and the focus tier, and the whole list
--- closed by `GIVEBACK_END` or a BLOCK (`giving-keys-back-when-no-action-runs.md`,
--- `dropping-the-game-fallback.md` §3). **The self and focus tiers end in a block either way**: a
--- giveback stands in no cast key tier (`handing-the-rest-of-a-key-to-the-game.md` 2-1), and their
--- closing block answers as the base key does on a chord (`JudgmentEntryFor`). **Only for a key
--- that holds a key record**: on a
--- click-cast-only key a block would take the key, and the world click and camera with it.
---
--- **No block between the hover twins and the originals.** They share the [none held] tier, each
--- twin beside its own original, and the last block closes it for the pointed half and the rest
--- alike.
---
--- **No block for a key turned off in the settings either.** The press never picks that tier
--- (`EVAL_SNIPPET`), so the block would be a record nothing reads.
---
--- `giveBack` is the `GiveBackWhenNoActionRuns` the caller decided the key's hold by.
local function WithBlocks(bindingArray, giveBack)
    wipe(_withBlocks);
    local count = #bindingArray;
    local selfEnd, focusEnd = 0, 0;
    for i = 1, count do
        local castModifier = bindingArray[i].castModifier;
        if (castModifier == Constants.CASTMOD_SELF) then
            selfEnd = i;
        elseif (castModifier == Constants.CASTMOD_FOCUS) then
            focusEnd = i;
        end
    end
    if (focusEnd < selfEnd) then
        focusEnd = selfEnd;
    end

    local n = 0;
    for i = 1, selfEnd do
        n = n + 1;
        _withBlocks[n] = bindingArray[i];
    end
    if (DebindPrivate.SelfCastEnabled()) then
        n = n + 1;
        _withBlocks[n] = BLOCKS[Constants.CASTMOD_SELF];
    end
    for i = selfEnd + 1, focusEnd do
        n = n + 1;
        _withBlocks[n] = bindingArray[i];
    end
    if (DebindPrivate.FocusCastEnabled()) then
        n = n + 1;
        _withBlocks[n] = BLOCKS[Constants.CASTMOD_FOCUS];
    end
    for i = focusEnd + 1, count do
        n = n + 1;
        _withBlocks[n] = bindingArray[i];
    end
    n = n + 1;
    if (giveBack) then
        _withBlocks[n] = GIVEBACK_END;
    else
        _withBlocks[n] = BLOCKS[Constants.CASTMOD_NONE];
    end
    return _withBlocks;
end

--- One binding, as the record the restricted side will hold. Its units are
--- `binding.unitConditions`, **the same table the solver's columns were read off**
--- (`BuildUnitStates`), so the record checks what the solver judged.
---
--- **`out.units` is good only until the binding is filled again**, which the window does whenever
--- it asks about the action: the table is rewritten in place. Every reader of a record has to be
--- done before the key walk moves on (`UpdateBindingsMap`); `JudgmentEntryFor` copies the masks out.
---
--- Nothing here reaches a frame or the client. The one frame question -- which click frame the
--- record hands `SetBindingClick` -- was answered in `PrepareKeyBindings` and arrives as a name.
local function BuildKeyRecord(binding, isClickCast, holdsKey, out)
    out.units = binding.unitConditions;

    local conditions = binding.conditions;

    out.fieldCount = 0;
    wipe(out.switches);
    wipe(out.undefinedSwitches);
    out.isClickCast = isClickCast;
    out.holdsKey = holdsKey;
    -- **Where the cast goes, not where the press aims.** `none` aims like an action with no target
    -- and still goes out asking; the unit it aims at reaches the snippet through its conditions.
    local castUnit = DebindPrivate.CastUnitOf(binding);
    out.targetUnit = castUnit;
    out.setsSwitch = nil;

    if (binding.clickframe and binding.clickbutton) then
        field(out, "clickbutton", binding.clickbutton);
    end

    -- **이 누름이 시전할 주문**, `*spell-`에 구운 그 값 그대로. 클릭 때 클라이언트에 다시 묻는
    -- 쪽이 있고, **이름으로 물으면 덮인 주문이 답한다** - `GetSpellInfo("Celestial Alignment")`가
    -- `Incarnation: Chosen of Elune`를 낸다(2026-09-21, 소유자가 게임에서). 빌드 때 구운 답은
    -- 원래 주문의 것이라 그 자리를 못 따라간다.
    --
    -- **없으면 안 묻는다는 뜻이다.** 아이템·매크로·탈것에는 시전할 주문이 없다.
    if (binding.castSpell) then
        field(out, "spell", binding.castSpell);
    end

    -- **The target rides on the record**, because the wrapper is what puts it on the button, at
    -- the click, for a key and a unit-frame click alike.
    local carriesTarget = isClickCast or holdsKey;

    if (binding.castModifier) then
        field(out, "castModifier", binding.castModifier);
    end

    if (carriesTarget and castUnit and castUnit ~= "") then
        if (SPECIAL_UNITS[castUnit]) then
            field(out, "unitAlias", castUnit);
        elseif (BASIC_UNITS[castUnit]) then
            field(out, "unit", castUnit);
        end
    end

    -- **A record field of its own, though it is stored as an axis of `units["unitframe"]`.** It
    -- describes the **frame** and only the frame record can answer it, where every other axis of
    -- that unit is answered by measuring the unit. It carries its own "is there a frame" guard in
    -- the snippet for that reason.
    local pointedFrame = out.units.unitframe;
    if (type(pointedFrame) == "table" and pointedFrame.frameTypes
            and pointedFrame.frameTypes ~= Constants.FRAMETYPE_ALL) then
        field(out, "frameTypes", pointedFrame.frameTypes);
    end

    for i = 1, #CONDITION_AXES do
        local axis = CONDITION_AXES[i];
        local value = conditions[axis.field];
        if (value ~= nil and value ~= axis.allValue) then
            local omit = false;
            if (axis.derived) then
                -- **Baked as one string, brackets and all.** The click path hands this value to
                -- `SecureCmdOptionParse` as it is, and kept in pieces it would be joined on every
                -- click.
                --
                -- **The condition's own value is the question** -- a spell name, or the id where
                -- the client could not name one (`making-known-a-spell-name.md`).
                --
                -- `true` is the one shape still derived from the action, and it is left to the
                -- three types whose spell the specialization picks: they carry no value of their
                -- own, so a name would nail the condition to one specialization. One that resolved
                -- to nothing asks a conditional that is always false (`known:0` is the fixed
                -- false in `UnitAlternatives` and `EmitMacroTextArg` too).
                local spell = DebindPrivate.KnownSpellAsked(binding);
                -- A true that stands until the next rebuild is settled here instead of going out
                -- as an axis (`baking-the-known-condition.md`), so the press stops parsing it.
                omit = spell ~= nil and Spells.SettleKnown(spell) == true;
                -- **An id goes out twice: as the conditional and as itself.** `[known:<id>]`
                -- answers false for a spell the book holds under an override, so the press asks
                -- the book as well and takes either answer (`SpecSpells.lua`). The conditional
                -- cannot carry that question and the id cannot be read back out of the baked
                -- string.
                if (not omit and type(spell) == "number") then
                    field(out, "knownID", spell);
                end
                value = spell and ("[known:" .. spell .. "]") or "[known:0]";
            end
            if (not omit) then
                field(out, axis.field, value);
            end
        end
    end

    -- **A switch is used by acting on it too, not only by being a condition.** An on/off/toggle
    -- action names its switch in `value`, so the condition loop below never sees it, and
    -- registration is what puts the switch's stored value back into `States` at every rebuild.
    -- Without it the restricted side holds nil while the window shows the stored value, and the
    -- first press only brings the two back together -- it reads as a press that did nothing, and
    -- the rebuild after it puts the pair back out of step.
    --
    -- No flag: this key's own wiring does not depend on the switch, so there is nothing to
    -- re-decide when it changes.
    if (Constants.SETSWITCH_MODES[binding.type] and luatype(binding.value) == "string") then
        out.setsSwitch = binding.value;
    end

    -- **A `SETCUSTOM` action reads the pointed frame's unit, and it is the one reader that names no
    -- unit.** Its value is which custom slot to fill; where the unit comes from is baked as the
    -- literal `"unitframe"` on the `UnitWatch` frame (`DescribeBinding`), and the restricted side
    -- resolves it through `GetUnitFrameUnit` at the press. So nothing about this binding's units or
    -- its target says "unitframe" and `_unitsSeen` would not hear about it -- which is what turns
    -- the slot off underneath it.
    out.readsUnitFrameUnit = binding.type == Constants.SETCUSTOM;

    out.tail = binding.tail;
    out.command = binding.tail == Constants.COMMAND and binding.value or nil;

    -- **조건 표에 있는 스위치 이름을 그대로 훑는다.** 다섯 번호를 도는 루프였고, 그래서
    -- `$state1`~`$state5` 밖의 이름은 조건으로 걸려 있어도 여기서 안 보였다. 솔버는 그 이름에도
    -- 컬럼을 만드니 (`Solver.lua`) 둘이 갈리면 한쪽은 조건이 있다고 보고 다른 쪽은 없다고 본다.
    --
    -- **정의가 없어도 굽는다.** 정의를 못 찾으면 조건을 통째로 빼던 자리다 - 빼면 그 바인딩이
    -- 조건 없이 상시 발동한다. ⚑2가 매크로 본문에서 막은 것과 같은 실패 방향인데 이쪽이 더
    -- 나쁘다: 본문 쪽은 액션에 마커라도 붙는다. 구워두면 런타임 비교가 `States[name] ~= v`라
    -- 아무도 안 쓴 이름은 `nil`이고, 참을 걸었든 거짓을 걸었든 안 맞는다 - 어느 쪽으로 걸어도
    -- 안 나가는 쪽으로 떨어진다.
    --
    -- **이제 그 액션은 여기까지 오지도 않는다.** 정의 없는 이름을 조건으로 건 액션에도 마커가
    -- 붙어서(`GetUndefinedSwitch`) `KeyMap`에서 빠지고, 그래서 위 갈래는 액션 쪽으로는 도달
    -- 불가가 됐다. **그렇다고 지우지 말 것** - 스위치의 계산식은 액션이 아니라 이 길로 그대로
    -- 내려오고, 무엇보다 이건 위험한 방향을 막는 마지막 겹이다. 마커 하나가 빠지거나 좁아지는
    -- 날 여기가 없으면 ⚑2가 그대로 돌아온다.
    for name, value in pairs(conditions) do
        if (Constants.IsSwitchName(name)) then
            out.switches[name] = value and true or false;
            -- Nil wherever it is read, where every defined switch is a boolean (`RecordConstraints`).
            if (not DebindPrivate.ResolveSwitchDefinition(name)) then
                out.undefinedSwitches[name] = true;
            end
        end
    end

    return out;
end

--- What the rest of the rebuild has to set up because of this record: the switches it reads or
--- sets, the aliases it resolves, and the role headers.
local function CollectRecordNeeds(record)
    for unit, condition in pairs(record.units) do
        -- **Role is read off the unitframe slot, not measured on a unit**, filled where the frame is
        -- in hand (`SecureBindings.lua`'s `setup_onenter`), so all this decides is whether the
        -- headers that fill `UnitRoles` run.
        if (FrameAxesOn(unit) and condition ~= false and condition.role) then
            Rebuild.readsRole = true;
        end

        -- 별칭 해석은 어느 갈래든 필요하다. `_unitsSeen`가 `EnableUnitWatch`를 몰고, 그게
        -- `UnitAliasMap[별칭]`을 채운다 - 클릭 경로가 대상을 푸는 자리가 정확히 거기다.
        _unitsSeen[unit] = true;
    end

    if (record.setsSwitch) then
        addSwitch(record.setsSwitch);
    end

    for name in pairs(record.switches) do
        addSwitch(name);
    end

    if (record.targetUnit) then
        _unitsSeen[record.targetUnit] = true;
    end

    if (record.readsUnitFrameUnit) then
        _unitsSeen.unitframe = true;
    end
end

--- Writes one record into the snippet being built.
local function EmitRecord(record)
    appendLine("t=newtable();tinsert(bindings,t)");

    -- The parsed state axes go out as one conditional and not one by one: the press parses it.
    for i = 1, record.fieldCount do
        if (not ParsedStateAxis(record.fieldNames[i])) then
            appendKeyValue(record.fieldNames[i], record.fieldValues[i]);
        end
    end
    local expr = StateExpression(record);
    if (expr) then
        appendKeyValue("expr", expr);
    end

    local unitsTblCreated;
    for _, unit in ipairs(sortedKeys(record.units, _sortedB)) do
        local condition = record.units[unit];
        if (not unitsTblCreated) then
            unitsTblCreated = true;
            appendLine("t.units=newtable()");
        end
        appendLine("u=newtable();t.units[%q]=u", unit);

        local unitExpr, tail, tail2 = UnitExpression(unit, condition);
        if (unitExpr) then
            appendLine("u.expr=%q", unitExpr);
        end
        if (tail) then
            appendLine("u.tail=%q", tail);
        end
        if (tail2) then
            appendLine("u.tail2=%q", tail2);
        end
        if (condition == false) then
            appendLine("u.exists=false");
        else
            appendLine("u.exists=true");
            -- **In cells, not the boxes the reader ticks**: the boxes are not closed under
            -- intersection, so a folded condition may have no box form at all (`CellsToUnitGroup`).
            if (condition.group) then
                appendLine("u.group=newtable()");
                for _, bit in ipairs(sortedKeys(UNITGROUPCELL_NAMES, _sortedC)) do
                    if (band(condition.group, bit) ~= 0) then
                        appendLine("u.group.%s=true", UNITGROUPCELL_NAMES[bit]);
                    end
                end
            end
            -- **Asked again although the fold already drops it elsewhere**: on any other unit the
            -- measuring side never fills the row, so a role that got past the fold would read
            -- `cond.role[nil]` at the press and leave the key quietly dead.
            if (FrameAxesOn(unit) and condition.role) then
                appendLine("u.role=newtable()");
                for _, bit in ipairs(sortedKeys(ROLE_NAMES, _sortedC)) do
                    if (band(condition.role, bit) ~= 0) then
                        appendLine("u.role.%s=true", ROLE_NAMES[bit]);
                    end
                end
            end
        end
    end

    local switchesTblCreated;
    for _, name in ipairs(sortedKeys(record.switches, _sortedB)) do
        if (not switchesTblCreated) then
            appendLine([[t.switches=newtable()]]);
            switchesTblCreated = true;
        end
        appendLine([[t.switches[%q]=%s]], name, record.switches[name] and "true" or "false");
    end

    -- **유닛 프레임은 매크로를 거치지 않는다.**
    --
    -- 옛 경로는 `type="macro"` + `macrotext="/click <프레임> <버튼>"`이었다. 그러면 **바깥이
    -- 매크로**가 되고, 도착한 버튼의 액션이 또 매크로면 실행되지 않는다(게임 제약,
    -- `click-time-poc-results.md` §2-5). 매크로텍스트·매크로·펫 명령·spellID 없는 탈것이 통째로
    -- 안 나갔다.
    --
    -- `type="click"`은 `SECURE_ACTIONS.click` 한 줄이라 매크로를 안 거친다. 대신 **버튼 이름을
    -- 못 싣는다** - `delegate:Click(button)`이 원래 마우스 버튼을 그대로 넘긴다. 그래서 어느
    -- 액션인지는 래퍼가 도착한 뒤에 `ClickCastKeys`에서 되찾는다.
    --
    -- 그 덕에 거기서 거는 `clickbutton`은 **언제나 같은 프레임**이다. 승자가 바뀌어도 안
    -- 바뀌므로 옛 경로처럼 액션마다 다시 쓸 일이 없다. **아무것도 안 굽는다.** 유닛 프레임에
    -- 미리 찍어둘 것이 없어서다 - 프레임이 들고 있는 것은 등록 때 한 번 쓴 고정값
    -- (`*type-debind1` / `*clickbutton-debind1`)뿐이고, 어느 액션인지는 래퍼가 클릭 순간에
    -- 정한다.
    --
    -- 그래서 이 레코드가 클릭 갈래에 속한다는 표시 하나면 된다. 래퍼가 그것으로 볼 레코드를
    -- 고른다(`EVAL_SNIPPET`의 `subset`). **`unitframe` 플래그를 안 세운다.** 옛 경로에서는 상태
    -- 루프가 승자를 유닛 프레임에 미리 찍어뒀으니 호버가 바뀌면 다시 골라야 했다. 지금은 래퍼가
    -- 클릭 순간에 고르므로 다시 걸 것이 없다.
    if (record.isClickCast) then
        appendLine("t.isClickCast=true");
    end

    if (record.holdsKey) then
        appendLine("t.holdsKey=true");
    end

    -- **A giveback that wins a frame click lets it through** to the frame's own handler, which is the
    -- game's side of that click (`which-action-a-key-runs.md` S4). Every other winner with nothing
    -- to click spends it (2026-10-05, owner): a block does nothing, as its own row says, and a
    -- command cannot run on a frame. Let through, either would run whatever the frame has on that
    -- click, which the reader did not pick, and do what the giveback does.
    if (record.isClickCast and record.tail == Constants.GIVEBACK) then
        appendLine("t.letsClickThrough=true");
    end

    -- **DEBUG only, and read by nothing in the addon.** A tail goes out as a BLOCK, so without these a
    -- spec asking which record won cannot tell it from the BLOCK closing the tier
    -- (`judgment_spec.lua`).
    if (DEBUG and record.tail) then
        appendLine("t.tail=%q", record.tail);
        if (record.command) then
            appendLine("t.command=%q", record.command);
        end
    end
end

DebindPrivate.BuildKeyRecord = BuildKeyRecord;

Rebuild.BLOCKS             = BLOCKS;
Rebuild.PrepareKeyBindings = PrepareKeyBindings;
Rebuild.WithBlocks         = WithBlocks;
Rebuild.BuildKeyRecord     = BuildKeyRecord;
Rebuild.CollectRecordNeeds = CollectRecordNeeds;
Rebuild.EmitRecord         = EmitRecord;
