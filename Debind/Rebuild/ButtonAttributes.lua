local _, DebindPrivate = ...;
local Constants               = DebindPrivate.Constants;
local DefaultClickFrame       = DebindPrivate.DefaultClickFrame;

local DEBUG                   = DebindPrivate.DEBUG;
local NIL                     = Constants.NIL;

local luatype                            = type;
local format, tostring                   = format, tostring;
local strsub, tconcat                    = string.sub, table.concat;
local wipe, ipairs                       = wipe, ipairs;
local GetSpellNameAndIconID              = DebindPrivate.GetSpellNameAndIconID;
local GetSpellSubtext                    = C_Spell.GetSpellSubtext;
--- The pure half of the pair in `Spells.lua`. **The other half asks the client and may not be used
--- here**: `DescribeBinding` is reached with the world already collected, and a spec hands it plain
--- values rather than standing an API up.
local ComposeSpellCastName               = DebindPrivate.ComposeSpellCastName;
local IsPressHoldReleaseSpell            = C_Spell.IsPressHoldReleaseSpell;
local GetMountInfoByID                   = C_MountJournal.GetMountInfoByID;

local Rebuild                 = DebindPrivate.Rebuild;
local addMacrotextBinding     = Rebuild.addMacrotextBinding;
local appendLine              = Rebuild.appendLine;
local sortedKeys              = Rebuild.sortedKeys;

local BindingAttrsCache                  = {};

local NextButtonName;
do
    local _nextId = 100;
    function NextButtonName()
        _nextId = _nextId + 1;
        return "deb" .. _nextId;
    end
end

--- The body a wrapped button carries: put each chosen CVar's current value aside and write the
--- action's, fire the real button, put them back. **The values are read in the body and not baked
--- in**, so a setting changed mid-fight is the one the next press restores
--- (`matching-the-clients-cast-targeting.md` §2-2).
---
--- **Lines, not nesting.** A macro inside a macro does not run, so the saves go in front of the one
--- `/click` and the restores behind it. The globals are how the two `/run` lines reach each other:
--- a macro body has no other scope, and the cast frame is protected from where this runs.
---
--- `key` is `CastAutomaticsKeyOf`'s, one character per row.
local function AutomaticsLines(key)
    local rows = DebindPrivate.CAST_AUTOMATIC_ROWS;
    local save, restore = {}, {};
    for i = 1, #rows do
        local mark = strsub(key, i, i);
        if (mark ~= "-") then
            local row = rows[i];
            local global = "DebindAuto_" .. row;
            save[#save + 1] = format('%s=GetCVar("%s");SetCVar("%s","%s")', global, row, row, mark);
            restore[#restore + 1] = format('SetCVar("%s",%s)', row, global);
        end
    end
    return "/run " .. tconcat(save, ";"), "/run " .. tconcat(restore, ";");
end

--- Around a `/click` at the real button, for the actions that reach the cast through one.
---
--- **`edge` is the third token `/click` takes**, and it is what a spell you hold needs: the inner
--- click has to arrive as a press on the way down and as a release on the way up
--- (`SlashCommands.lua` hands it to `Click(button, down)`). One body sent on both edges charges
--- the spell and never lets go, which is the 1.8 seconds §7 of the writeup measured. Left out
--- everywhere else, so those bodies stay exactly as they were.
local function AutomaticsBody(key, buttonname, edge)
    local save, restore = AutomaticsLines(key);
    return save .. "\n"
        .. format("/click %s %s%s\n", DebindPrivate.CastFrameName, buttonname,
            edge and (" " .. edge) or "")
        .. restore;
end

--- Around a body we wrote ourselves. **A macro inside a macro does not run**, so these actions
--- cannot be reached through a `/click` the way a spell is; their bodies are our strings, so the
--- lines go straight in front and behind
--- (`setting-the-clients-cast-automatics-per-action.md` §5).
local function AutomaticsWrap(body, key)
    local save, restore = AutomaticsLines(key);
    return save .. "\n" .. body .. "\n" .. restore;
end

--- `type -> cacheKey -> automatics key -> button name`, beside `BindingAttrsCache` and kept the
--- same way. **The plain button stays shared**: what the automatics split is the wrapper around it,
--- and the one inside is the same button for every combination
--- (`setting-the-clients-cast-automatics-per-action.md` §4).
local WrappedAttrsCache = {};

--- Every wrapped button stamped this session, as `wrapped -> the button its body clicks`. **The
--- click path reads it to know whether the press's unit has to go on the cast frame**, which is the
--- one thing about a wrapped button that cannot be baked: `@hover` and the custom aliases are
--- worked out at the press. What it maps to is for the readers who have to get back to the real
--- action from a button name.
---
--- Not wiped between rebuilds, because a button outlives the rebuild that stamped it
--- (`BindingAttrsCache`).
local _wrappedButtons = {};

--- 감싼 버튼 -> 그 버튼의 올림 엣지가 갈 버튼. 쥐는 주문에만 선다.
local _wrappedRelease = {};
--- `button name -> its ACTION_BUTTON_COMMANDS row` for every action button action stamped this
--- session, emitted as `ActionSlots` on every rebuild.
local _actionSlots = {};
--- Frame -> the button name that clicks it (`ClickButtonFor`).
local _clickButtons = {};
--- `flyoutID -> opener`, refilled by each rebuild that emits `FlyoutOpeners`.
local _flyoutOpeners = {};
--- Whether an action button action stamped by this rebuild reaches a slot. Cleared once
--- `EmitStampedButtons` has read it: `_actionSlots` keeps every one the session ever stamped.
local _reachesSlot = false;

local _sortedA = {};

--- One binding's attributes, worked out but not yet written anywhere.
---
--- **Two parallel arrays rather than a list of pairs**, because an attribute value is allowed to
--- be nil -- `*macrotext-` is cleared for a macro and `*macro-` for macro text -- and a nil in a
--- list of pairs is a hole `#` cannot see past. `count` is what says how long they are.
---
--- **One table, refilled.** A rebuild allocates nothing it can reuse, so the descriptor a caller
--- gets back is only good until the next `DescribeBinding` call. Everything that reads one
--- consumes it on the spot.
local _descriptor = { attrNames = {}, attrValues = {}, count = 0 };

--- What the client answered for the binding being described. One table, refilled, same as above.
local _facts = {};

--- **DEBUG only.** One row per spell binding of this rebuild, filled at the stamp where the key is
--- still in hand. `_facts` cannot show this: it is wiped per binding, so after a rebuild it holds
--- the last one and nothing else.
---
--- **Do not reassign.** DevTool holds this reference; a rebuild wipes and refills it.
DebindPrivate.SpellFacts = {};
DebindPrivate.dump("SpellFacts", DebindPrivate.SpellFacts);

--- Appends one attribute to a descriptor. **A nil value is meaningful** -- it clears the attribute
--- -- and assigning nil into the reused array is what stops the previous descriptor's value from
--- standing in for it.
local function attr(out, name, value)
    local count = out.count + 1;
    out.count = count;
    out.attrNames[count] = name;
    out.attrValues[count] = value;
end

--- What the game has to be asked before a binding can be described. **Every call to the client in
--- this whole path is here**, which is what leaves `DescribeBinding` with nothing to ask.
---
--- A spec hands these in as plain values instead: it is standing a world up, not imitating an API
--- (`going-headless-outside-the-ui.md` §4).
local function CollectBindingFacts(type, value, unit, facts, automatics, pinnedSpell, resolvedSpellID)
    wipe(facts);
    facts.pinnedSpell = pinnedSpell;

    -- A resolved spec type is a spell from here on; one that resolved to nothing asks nothing.
    if (Constants.SPEC_RESOLVED_TYPES[type] and value ~= nil) then
        type = Constants.SPELL;
    end

    if (type == Constants.PETACTION) then
        facts.petMacrotext = DebindPrivate.GetPetActionMacroText(value, unit);
    elseif (type == Constants.FLYOUT) then
        facts.flyoutOpener = DebindPrivate.GetFlyoutOpener(value);
    elseif (type == Constants.ACTIONBUTTON) then
        local info = Constants.ACTION_BUTTON_COMMANDS[value];
        if (info and info.stance) then
            facts.barButton = _G[info.button];
        end
    elseif (type == Constants.SPELL) then
        -- **The name comes off the base and not off the stored id.** A talent version's name only
        -- exists while that talent is taken, so a button carrying it goes dead the moment the
        -- reader drops the talent; the base's name casts the talent version when it is taken and
        -- the plain one when it is not.
        --
        -- `ResolveBaseSpell` and not `FindBaseSpellByID`: the client places a stored id only while
        -- the talent combination that created it still stands, and the name index is what reaches
        -- the base after that (`Spells.lua`).
        local spellID = DebindPrivate.ResolveBaseSpell(value, resolvedSpellID);
        -- **A stored name is asked again at every rebuild** and from here on is the id it resolved
        -- to, so a specialization change resolves it through the new one's index. One that
        -- resolves to nothing, not even through the id stored beside it, goes on the button as it
        -- is.
        if (luatype(value) == "string") then
            facts.namedSpellID = spellID;
            if (spellID == nil) then
                facts.spellName = value;
                facts.pressAndHold = false;
                return facts;
            end
            value = spellID;
        end
        facts.spellID = spellID;
        facts.spellName = GetSpellNameAndIconID(spellID);
        if (facts.spellName) then
            -- **A pinned rank's subtext is the pinned id's**, since the rank is what the reader
            -- picked. A pin held as text needs none (`DescribeBinding` casts the text).
            facts.spellSubtext = GetSpellSubtext(luatype(pinnedSpell) == "number" and pinnedSpell or spellID);
        end
        facts.pressAndHold = IsPressHoldReleaseSpell(value) and true or false;
    elseif (type == Constants.MOUNT) then
        -- **Whether the journal names a spell is the fork, not whether that spell has a name.**
        -- A mount with a spell id goes out as a spell even where the name does not resolve; the
        -- macro text is only for the ones the journal answers no spell for.
        local _, spellID = GetMountInfoByID(value);
        facts.mountSpellID = spellID;
        if (spellID) then
            facts.mountSpellName = GetSpellNameAndIconID(spellID);
        else
            facts.mountMacrotext = DebindPrivate.GetMountMacroText(value,
                DebindPrivate.UnshiftsWith(
                    DebindPrivate.CastAutomaticInKey(automatics, "autoUnshift")));
        end
    end

    return facts;
end

--- A button with no attribute on it: the action wins its press and nothing goes out. **What an
--- action the game has nothing to do for goes out as**, the way a spell this character does not
--- know is still cast and the game answers it (owner, 2026-10-07): the action runs, and the ones
--- under it on the key do not. **One button per type**, filed under a nil value, so a live button of
--- the same type and value is never handed this one's empty attributes from the cache.
local function Inert(out, type)
    out.type = type;
    out.value = nil;
    out.unit = nil;
    out.cacheKey = NIL;
    out.castsAtUnit = false;
    out.pressAndHold = false;
    out.castSpell = nil;
    out.actionSlot = nil;
    return out;
end

--- What has to be stamped on the click frame for one binding to be able to fire, or **nil and a
--- reason**.
---
--- **A refusal is for a value wrong in itself**: a pet command or binding command this client does
--- not have, a switch action with no switch. The caller leaves such an action off the key, and the
--- next action takes the press; the issue that marks it should have kept it from reaching here
--- (`BINDING_ISSUE_UNKNOWN_*`). **A value the game has nothing to do for right now is not refused**
--- -- a flyout with every slot empty, a stance this character lacks -- and goes out `Inert`.
---
--- Nothing here asks the client anything. Everything it needs is in `facts`.
local function DescribeBinding(type, value, unit, facts, out, automatics)
    out = out or { attrNames = {}, attrValues = {} };
    out.count = 0;

    -- **A block writes no attribute and is not a refusal.** It wins the press to do nothing with it.
    if (type == Constants.BLOCK) then
        return nil, "block";
    end

    -- 펫 명령은 **여기서 MACROTEXT가 된다.** 아래에 자기 갈래를 두면 세 가지를 각각 다시
    -- 만들어야 하는데, 셋 다 이미 매크로텍스트 쪽에 있다:
    --
    --   1. 캐시 키. `BindingAttrsCache`는 (type, value)로만 잡고 **한 번도 안 지운다.**
    --      대상을 본문에 굽는 타입이 자기 갈래를 가지면 같은 명령 + 다른 대상 둘이 한 버튼을
    --      나눠 쓰고, 뒤엣것이 앞엣것의 본문을 실행한다. 본문 자체를 value로 만들면 대상이
    --      키에 들어가므로 그 일이 없다. (캐시 자체는 여전히 이 구조다 - refactor-candidates 18)
    --   2. `@custom1`·`@hover`·`@tank`는 진짜 유닛 토큰이 아니다. 바꿔주는 것이
    --      `addMacrotextBinding` -> `ParseMacroText`이고, 그건 MACROTEXT에만 걸려 있다.
    --      (`@custom1`·`@unitframe`·`@tank` 이야기다.)
    --   3. unit을 여기서 떨군다. 본문이 대상을 들고 있으므로 delegate 프레임이 할 일이
    --      없다(`SECURE_ACTIONS.macro`는 버튼의 unit을 안 본다).
    --
    -- `*type-="pet"`을 안 쓰는 이유는 따로다. 그쪽은 `CastPetAction(슬롯, unit)`이라 unit이
    -- 공짜로 오지만 **슬롯이 펫마다 다르고 전투 중에는 못 고친다** - 전투 중에 펫이 바뀌면
    -- 그 바인딩이 남은 전투 내내 엉뚱한 명령을 실행한다. 안 되는 것보다 나쁘다.
    if (type == Constants.PETACTION) then
        if (not facts.petMacrotext) then
            return nil, "unknown-pet-action";
        end
        type, value, unit = Constants.MACROTEXT, facts.petMacrotext, nil;
    end

    -- **A spec-resolved type with no spell writes no attribute at all, and is not a refusal.** A
    -- refusal leaves the action off the key; what the design asks for is a key that stays ours and a
    -- press that does nothing, and a button with no `*type-` on it is exactly that.
    if (Constants.SPEC_RESOLVED_TYPES[type]) then
        if (value == nil) then
            return Inert(out, type);
        end
        type = Constants.SPELL;
    end

    out.type = type;
    out.value = value;
    out.unit = unit;
    out.actionSlot = nil;
    out.castSpell = nil;

    -- **The key the stamp files this button under**, taken before any branch below rewrites the
    -- value for its own attribute. It used to be read after, and only the item branch rewrites --
    -- so an item binding was looked up under `6948` and filed under `"item:6948"`, which is a
    -- cache that never hits and a button allocated afresh on every rebuild, for the whole session.
    --
    -- **`unit` is not in the key, and a new action type has to be checked against that.** A cache
    -- hit means the attributes below were not written at all (`StampBinding`), so two bindings that
    -- share a type and a value share a button -- which is only sound while the unit lives on the
    -- delegate frame rather than in an attribute. Bake the target into an attribute and the second
    -- binding silently gets the first one's target, and the symptom is "it aims at the wrong unit
    -- sometimes", a long way from here.
    --
    -- Pet commands are the one type that breaks the premise, and they dodge it above rather than
    -- here: the target goes into the macro body and the body becomes the value, so it is in the key
    -- after all. A type that cannot do that needs the key widened instead.
    -- **우리가 쓴 본문은 CVar 줄을 스스로 나른다.** 매크로 안에서 매크로가 안 돌아서 주문처럼
    -- `/click`으로 감쌀 수가 없고, 감쌀 필요도 없다. 본문이 우리 문자열이다.
    if (automatics) then
        if (type == Constants.MACROTEXT) then
            value = AutomaticsWrap(value, automatics);
            -- **위에서 잡아 둔 `out.value`를 고쳐 쓴다.** 등록되는 본문이 그 값이고
            -- (`addMacrotextBinding`), 안 고치면 인자가 든 본문은 첫 누름에 조각에서 다시
            -- 지어지면서 CVar 줄이 영영 벗겨진다.
            out.value = value;
        elseif (type == Constants.MOUNT and facts.mountMacrotext) then
            facts.mountMacrotext = AutomaticsWrap(facts.mountMacrotext, automatics);
        end
    end

    out.cacheKey = value or NIL;
    -- **A stored name is filed under the id it resolved to.** What it resolves to moves with the
    -- specialization, and a hit writes nothing, so filed under the name the button would go on
    -- casting whatever the first rebuild resolved.
    if (type == Constants.SPELL and facts.namedSpellID) then
        out.cacheKey = facts.namedSpellID;
    end
    -- **A pinned rank is another button than the highest rank of the same spell**, which shares the
    -- id and would otherwise be handed the other's, and two pins of one spell are two buttons.
    if (facts.pinnedSpell ~= nil and type == Constants.SPELL and value ~= nil) then
        out.cacheKey = tostring(out.cacheKey) .. ":rank:" .. tostring(facts.pinnedSpell);
    end

    -- **탈것의 본문은 탈것 하나로 안 정해진다.** `/cancelform` 줄이 `autoUnshift`를 따르고 CVar
    -- 줄도 액션마다 달라서, 같은 탈것이 여러 꼴로 구워진다. 열쇠가 탈것 번호뿐이면 먼저 구운
    -- 것이 나중 것에게 간다. 이 캐시는 한 번도 안 지워지므로 CVar가 움직인 뒤에도 같은 일이
    -- 난다. 본문을 value로 만들 수 없는 타입이라 열쇠를 넓힌다(위 펫 명령 주석의 마지막 문장).
    if (type == Constants.MOUNT and facts.mountMacrotext) then
        out.cacheKey = facts.mountMacrotext;
    end

    -- **Which actions the engine's automatic self-cast can reach**, and equally which ones may be
    -- fired from inside a macro body -- a `macro` type nested in one does not run. The three
    -- spec-resolved types are already rewritten to `SPELL` above, so they are in.
    --
    -- **A mount goes out as one of two things and only one of them belongs here.** Where the
    -- journal names a spell it is stamped `*type-="spell"` and a `/click` fires it; where it does
    -- not, the body is a macro of ours and carries what it needs itself. Reading the type alone
    -- would leave the same mount answering the action's values or ignoring them depending on what
    -- the journal happens to hold.
    out.castsAtUnit = type == Constants.SPELL or type == Constants.ITEM
        or type == Constants.USESLOT
        or (type == Constants.MOUNT and facts.mountSpellID ~= nil);

    if (type == Constants.SPELL) then
        attr(out, "*type-", "spell");
        -- **A name and not an id**, and the id was tried (2026-09-12, owner, in the game). The
        -- client files the same spell under a different id per specialization and the two are not
        -- related: Starfire is 194153 on Balance and 197628 on Restoration, Starsurge 78674 and
        -- 197626, Remove Corruption 2782 and 440015. Neither `FindBaseSpellByID` nor
        -- `GetBaseSpell` walks from one to the other, so an id baked here dies the moment the
        -- reader changes specialization. The subtext comes along because that is what tells two
        -- same-named spells apart (`Spells.lua`'s `ComposeSpellCastName`).
        -- **레코드가 싣는 것도 이 값 그대로다.** 클릭 때 이 주문을 다시 묻는 쪽이 있고
        -- (`BuildKeyRecord`), 둘을 따로 만들면 언젠가 갈린다.
        -- A pin held as text is what a Clique binding cast, and goes out as it is.
        if (luatype(facts.pinnedSpell) == "string") then
            out.castSpell = facts.pinnedSpell;
        else
            out.castSpell = ComposeSpellCastName(facts.spellName, facts.spellSubtext, facts.pinnedSpell ~= nil)
                or facts.spellID;
        end
        attr(out, "*spell-", out.castSpell);

        -- **유지·시전 주문의 `*typerelease-`는 여기서 안 굽는다.** 클릭 때 쓴다
        -- (`SecureBindings.lua`). 여기 구우면 이 블록이 캐시 적중으로 통째로 건너뛰어지는 것도
        -- 문제고, 무엇보다 위의 `*spell-`이 **이름**이라 그 이름이 가리키는 주문이 덮이면 구운
        -- 답이 틀린 답이 된다.
    elseif (type == Constants.ITEM) then
        attr(out, "*type-", "item");
        -- **A stored name goes on as it is**, since `*item-` takes what `/use` takes
        -- (`importing-clique-profiles.md` §4). So does a string of digits, which `*item-` reads as
        -- an inventory slot -- the meaning it had in the Clique profile it came from.
        if (luatype(value) == "string") then
            attr(out, "*item-", value);
        else
            attr(out, "*item-", format("item:%d", value));
        end
    elseif (type == Constants.USESLOT) then
        -- **A bare number, and that is what makes it a slot.** `SecureCmdItemParse` reads two
        -- numbers as a bag pair and one as an inventory slot, so `"13"` reaches
        -- `UseInventoryItem(13)` -- the same call `/use 13` makes. `item:%d` here would name an
        -- item id instead.
        attr(out, "*type-", "item");
        attr(out, "*item-", tostring(value));
    elseif (type == Constants.MACRO) then
        attr(out, "*type-", "macro");
        attr(out, "*macro-", value);
        attr(out, "*macrotext-", nil);
    elseif (type == Constants.MACROTEXT) then
        attr(out, "*type-", "macro");
        attr(out, "*macro-", nil);
        attr(out, "*macrotext-", value);
    elseif (type == Constants.MOUNT) then
        if (facts.mountSpellID) then
            attr(out, "*type-", "spell");
            attr(out, "*spell-", facts.mountSpellName);
        else
            attr(out, "*type-", "macro");
            attr(out, "*macro-", nil);
            attr(out, "*macrotext-", facts.mountMacrotext);
        end
    elseif (type == Constants.TARGET) then
        attr(out, "*type-", "target");
    elseif (type == Constants.FOCUS) then
        attr(out, "*type-", "focus");
    elseif (type == Constants.TOGGLEMENU) then
        attr(out, "*type-", "togglemenu");
    elseif (type == Constants.SETCUSTOM) then
        attr(out, "*type-", "attribute");
        attr(out, "*attribute-frame-", DebindPrivate.UnitWatch);
        attr(out, "*attribute-name-", "custom" .. value);
        attr(out, "*attribute-value-", "unitframe");
    elseif (Constants.SETSWITCH_MODES[type]) then
        -- **The type decides the mode, so the name is all that is left to be wrong.** What
        -- this guard turned away while the value was a bitpack was an undecodable mode; the
        -- name inherits the place. Handing `SetAttribute` a nil name raises nothing -- it
        -- clears the attribute -- and the key then dies quietly on the restricted side.
        if (luatype(value) ~= "string") then
            return nil, "switch-not-chosen";
        end
        attr(out, "*type-", "attribute");
        attr(out, "*attribute-frame-", DebindPrivate.SwitchesUpdaterFrame);
        attr(out, "*attribute-name-", value);
        attr(out, "*attribute-value-", Constants.SETSWITCH_MODES[type]);
    elseif (type == Constants.FLYOUT) then
        -- **`*type- = "flyout"`을 안 쓴다.** 블리자드의 그 갈래는 `SpellFlyout:Toggle(self, ...)`
        -- 한 줄이고 그 `self`는 `FlyoutButtonMixin`이어야 한다(`GetPopupDirection`을 부른다).
        -- 여기 `clickframe`은 맨몸 `SecureActionButtonTemplate`이라 nil 메서드 호출로 죽는다.
        -- 자세한 사정은 `Flyout.lua` 머리주석에 있다.
        --
        -- 대신 우리 손잡이를 클릭한다. 손잡이의 보안 스니펫이 커서 위치에 우리 플라이아웃을
        -- 열고, 그건 전투 중에도 돈다.
        --
        -- **Whether it still opens anything is asked before the cache.** A cache hit means "no
        -- attribute needs writing again", not "it still works", and a flyout is where the two part:
        -- letting the last beast go makes `RebuildFlyout` set `numSlots = 0` and `GetFlyoutOpener`
        -- answer nil. While the check sat inside the cache, a hit skipped it and the button kept
        -- clicking an opener for a flyout that had emptied, until a `/reload`. An emptied flyout
        -- goes out `Inert` instead, under its own cache key.
        if (not facts.flyoutOpener) then
            -- Not learned, or every slot empty (Call Pet with no tamed beast). The action still
            -- runs and opens nothing (`Inert`).
            return Inert(out, type);
        end
        attr(out, "*type-", "click");
        attr(out, "*clickbutton-", facts.flyoutOpener);
    elseif (type == Constants.WORLDMARKER) then
        attr(out, "*type-", "worldmarker");
        attr(out, "*marker-", value);
    elseif (type == Constants.ACTIONBUTTON) then
        -- `*action-` is the press's to write: the main bar's page moves with vehicles and forms, and
        -- a flyout slot opens our flyout instead (`SecureBindings.lua`'s `ACTION_SLOT_SNIPPET`).
        local info = Constants.ACTION_BUTTON_COMMANDS[value];
        if (not info) then
            return nil, "unknown-action-button";
        end
        if (info.pet) then
            attr(out, "*type-", "pet");
            attr(out, "*action-", info.index);
            -- No slot to work out, but the press still asks whether there is a pet.
            out.actionSlot = info;
        elseif (info.stance) then
            -- No such stance on this character: the press does nothing, as the game's own binding
            -- for it would (`Inert`).
            if (not facts.barButton) then
                return Inert(out, type);
            end
            attr(out, "*type-", "click");
            attr(out, "*clickbutton-", facts.barButton);
        else
            attr(out, "*type-", "action");
            out.actionSlot = info;
        end
    else
        return nil, "unhandled-type";
    end

    out.pressAndHold = facts.pressAndHold and true or false;
    return out;
end

--- A button on the click frame that clicks `frame`, made once per frame: a flyout's opener in
--- `EmitStampedButtons`, a pet battle button in `StampPetBattleButtons`. Cached for the session the
--- way `BindingAttrsCache` is: neither kind of frame ever goes away.
local function ClickButtonFor(frame)
    if (not frame) then
        return nil;
    end
    local buttonname = _clickButtons[frame];
    if (not buttonname) then
        buttonname = NextButtonName();
        DefaultClickFrame:SetAttribute("*type-" .. buttonname, "click");
        DefaultClickFrame:SetAttribute("*clickbutton-" .. buttonname, frame);
        _clickButtons[frame] = buttonname;
    end
    return buttonname;
end

--- Writes a descriptor onto the click frame and answers what a record has to carry to reach it.
---
--- **The cache is this side's business, and `DescribeBinding` knows nothing about it.** A hit
--- means the attributes are already there under a button name we handed out earlier, so nothing
--- is written at all.
local function StampBinding(descriptor, automatics)
    local type, value, unit = descriptor.type, descriptor.value, descriptor.unit;

    local buttonname = BindingAttrsCache[type] and BindingAttrsCache[type][descriptor.cacheKey];
    local clickframe = DefaultClickFrame;
    local delegate = unit and unit ~= "" and DebindPrivate.GetDelegateFrame(unit) or nil;

    -- **캐시 적중은 "속성을 하나도 안 건드렸다"는 뜻이다.** 아래 블록을 통째로 건너뛴다.
    -- 그게 맞을 때가 대부분이지만, 키에 안 들어간 무언가(unit 등)가 달라졌으면 그게 곧
    -- 옛날 설정으로 도는 버그다. 로그가 없으면 이 분기는 화면에 흔적을 안 남긴다.
    if (DEBUG and buttonname) then
        DebindPrivate.log(format("|cffffcc66[Debind/cache]|r HIT %s/%s -> %s (unit=%s) 속성 갱신 안 함",
            tostring(type), tostring(value), tostring(buttonname), tostring(unit)));
    end

    if (not buttonname) then
        buttonname = NextButtonName();

        local names, values = descriptor.attrNames, descriptor.attrValues;
        for i = 1, descriptor.count do
            clickframe:SetAttribute(names[i] .. buttonname, values[i]);
        end

        if (descriptor.actionSlot) then
            _actionSlots[buttonname] = descriptor.actionSlot;
        end

        if (unit and unit ~= "" and not delegate) then
            if (DEBUG) then
                DebindPrivate.log("No delegate frame for:", unit);
            end
        end

        -- 버튼에 방금 쓴 것. 속성은 열거가 안 되므로 **여기서 안 찍으면 다시 볼 수 없다.**
        -- 보안 쪽 짝은 `SecureBindings.lua`의 `printMacroText`이고, 둘을 같이 봐야
        -- "본문이 틀렸나"와 "본문이 아예 안 올라갔나"가 갈린다.
        if (DEBUG) then
            DebindPrivate.log(format("|cff88ff88[Debind/attr]|r SET %s/%s -> %s : %s",
                tostring(type), tostring(value), tostring(buttonname),
                tostring(clickframe:GetAttribute("*macrotext-" .. buttonname)
                    or clickframe:GetAttribute("*spell-" .. buttonname)
                    or clickframe:GetAttribute("*macro-" .. buttonname)
                    or clickframe:GetAttribute("*item-" .. buttonname)
                    or clickframe:GetAttribute("*type-" .. buttonname))));
        end

        BindingAttrsCache[type] = BindingAttrsCache[type] or {};
        BindingAttrsCache[type][descriptor.cacheKey] = buttonname;
    end

    -- **감싼 버튼은 자기 이름을 따로 받는다.** 값이 다른 액션 둘이 안쪽 버튼은 같이 쓰고 감싼
    -- 것만 갈린다. `nil`은 넷 다 기본이라는 뜻이고, 그때는 감쌀 것이 없어 이 아래가 통째로
    -- 없는 일이 된다.
    --
    if (automatics and descriptor.castsAtUnit) then
        local byKey = WrappedAttrsCache[type];
        if (not byKey) then
            byKey = {};
            WrappedAttrsCache[type] = byKey;
        end
        local byAutomatics = byKey[descriptor.cacheKey];
        if (not byAutomatics) then
            byAutomatics = {};
            byKey[descriptor.cacheKey] = byAutomatics;
        end

        local wrapped = byAutomatics[automatics];
        if (not wrapped) then
            -- **엣지 토큰은 언제나 굽고, 짝도 언제나 만든다.** 유지·시전인지는 누를 때 정해지고
            -- (`SecureBindings.lua`, 덮인 주문까지 따라가려고 그렇게 한다), 이 버튼은 세션 내내
            -- 캐시에 남는다. 굽는 쪽이 그 답을 미리 정하면 둘이 갈리는 날 조용히 죽는다.
            --
            -- 한 버튼은 본문을 하나만 들 수 있어서 내림과 올림이 버튼 둘로 갈린다. 게이트가
            -- 올림에서 읽는 것은 `*typerelease-`라 짝은 그 속성으로 선다.
            wrapped = NextButtonName();
            DefaultClickFrame:SetAttribute("*type-" .. wrapped, "macro");
            DefaultClickFrame:SetAttribute("*macrotext-" .. wrapped,
                AutomaticsBody(automatics, buttonname, "true"));
            byAutomatics[automatics] = wrapped;
            _wrappedButtons[wrapped] = buttonname;

            -- 주문만 유지·시전이 될 수 있다. 아이템과 장비칸은 그 답이 영영 거짓이라 짝을
            -- 만들어 둬도 아무도 안 누른다.
            if (type == Constants.SPELL) then
                local release = NextButtonName();
                -- `*type-`은 안 단다. 이 이름은 올림에서만 돌아가고, 달아 두면 내림으로 새어
                -- 들어올 길이 하나 생긴다.
                DefaultClickFrame:SetAttribute("*typerelease-" .. release, "macro");
                DefaultClickFrame:SetAttribute("*macrotext-" .. release,
                    AutomaticsBody(automatics, buttonname, "false"));
                _wrappedRelease[wrapped] = release;
                _wrappedButtons[release] = buttonname;
            end

            -- **캐스트 프레임은 액션의 사본을 따로 받고, 물려받는 것은 안 된다.** 예전에는
            -- `useparent*`로 닿았는데 그건 읽을 때만 맞고 시전이 안 된다(그 프레임을 세우는
            -- `Debind.lua`가 무엇을 쟀는지 적고 있다). 감싼 본문이 그 프레임을 누르는 유일한
            -- 것이라 감싼 버튼이 생길 때만 복사한다.
            local castframe = DebindPrivate.CastFrame;
            local names, values = descriptor.attrNames, descriptor.attrValues;
            for i = 1, descriptor.count do
                castframe:SetAttribute(names[i] .. buttonname, values[i]);
            end
        end

        -- **대리 프레임으로 안 간다.** 나가는 것이 매크로라 버튼의 `unit`을 아무도 안 읽는다.
        -- 누름의 대상은 클릭 때 캐스트 프레임에 얹힌다(`SecureBindings.lua`).
        return DefaultClickFrame, wrapped;
    end

    return delegate or clickframe, buttonname;
end

DebindPrivate.DescribeBinding = DescribeBinding;
DebindPrivate.StampBinding = StampBinding;

--- Asks, describes, stamps. **The reason a binding was refused is dropped here and nowhere else**,
--- because the caller's shape still cannot carry one; stage 3 of
--- `going-headless-outside-the-ui.md` is where the record loop learns to.
local function SetBindingAttributes(type, value, unit, automatics, pinnedSpell, resolvedSpellID)
    local facts = CollectBindingFacts(type, value, unit, _facts, automatics, pinnedSpell, resolvedSpellID);

    local descriptor, reason = DescribeBinding(type, value, unit, facts, _descriptor, automatics);
    if (not descriptor) then
        if (DEBUG and reason ~= "block") then
            DebindPrivate.log("No attributes for:", type, value, reason);
        end
        return;
    end

    local clickframe, buttonname = StampBinding(descriptor, automatics);

    if (descriptor.actionSlot and not descriptor.actionSlot.pet) then
        _reachesSlot = true;
    end

    if (descriptor.type == Constants.MACROTEXT) then
        addMacrotextBinding(buttonname, descriptor.value);
    end

    return clickframe, buttonname, descriptor.castSpell;
end

--- The stamped buttons the restricted side looks up by name, emitted whole rather than per key: a
--- button outlives the rebuild that stamped it (`BindingAttrsCache`), so this belongs to the click
--- frame and not to any one key's records.
local function EmitStampedButtons()
    for _, buttonname in ipairs(sortedKeys(_wrappedButtons, _sortedA)) do
        appendLine("WrappedButtons[%q]=%q", buttonname, _wrappedButtons[buttonname]);
    end

    for _, buttonname in ipairs(sortedKeys(_wrappedRelease, _sortedA)) do
        appendLine("WrappedRelease[%q]=%q", buttonname, _wrappedRelease[buttonname]);
    end

    for _, buttonname in ipairs(sortedKeys(_actionSlots, _sortedA)) do
        local info = _actionSlots[buttonname];
        -- `GetExtraBarIndex` is not in the restricted environment, so its page is asked here.
        local page = info.page or (info.extra and C_ActionBar.GetExtraBarIndex());
        appendLine("ActionSlots[%q]=newtable()", buttonname);
        appendLine("ActionSlots[%q].attr=%q", buttonname, "*action-" .. buttonname);
        appendLine("ActionSlots[%q].index=%d", buttonname, info.index);
        if (page) then
            appendLine("ActionSlots[%q].page=%d", buttonname, page);
        end
        if (info.extra) then
            appendLine("ActionSlots[%q].extra=true", buttonname);
        end
        if (info.pet) then
            appendLine("ActionSlots[%q].pet=true", buttonname);
        end
        if (info.petBattle) then
            appendLine("ActionSlots[%q].petBattle=%d", buttonname, info.petBattle);
        end
    end

    -- **Which flyout a slot holds is only known at the press, and an opener cannot be made then**,
    -- so every flyout the spellbook holds gets one here, out of combat. Not where no action button
    -- action of this rebuild reaches a slot: the frames would be made for nothing.
    if (_reachesSlot) then
        DebindPrivate.GetBookFlyoutOpeners(_flyoutOpeners);
        for _, flyoutID in ipairs(sortedKeys(_flyoutOpeners, _sortedA)) do
            appendLine("FlyoutOpeners[%d]=%q", flyoutID, ClickButtonFor(_flyoutOpeners[flyoutID]));
        end
    end
    _reachesSlot = false;
end

Rebuild.BindingAttrsCache    = BindingAttrsCache;
Rebuild.SetBindingAttributes = SetBindingAttributes;
Rebuild.EmitStampedButtons   = EmitStampedButtons;
Rebuild.ClickButtonFor       = ClickButtonFor;
