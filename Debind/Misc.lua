local ADDON_NAME, DebindPrivate = ...;
local L                       = DebindPrivate.L;
local Constants               = DebindPrivate.Constants;

local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;

local dump                    = DebindPrivate.dump;
local band                    = bit.band;
local bor                     = bit.bor;
local tinsert, wipe           = tinsert, wipe;
local pairs, ipairs           = pairs, ipairs;
local GetMountInfoByID        = C_MountJournal.GetMountInfoByID;
local GetSpellCastName        = DebindPrivate.GetSpellCastName;


-- One ceiling for two clamps. `BuildBindingPlan` clamps the same option against
-- `Constants.STATE_DRIVER_UPDATETIME_DEFAULT`, and a second copy of the number here is a way for
-- the two to drift apart without anything saying so.
local STATE_DRIVER_UPDATE_THROTTLE_DEFAULT = Constants.STATE_DRIVER_UPDATETIME_DEFAULT;

function DebindPrivate.GetSpellNameAndIconID(spellId)
    local spellInfo = C_Spell.GetSpellInfo(spellId);
    if (spellInfo) then
        return spellInfo.name, spellInfo.iconID;
    end
end

local GetSpellNameAndIconID = DebindPrivate.GetSpellNameAndIconID;

--- 야수 소환 플라이아웃의 **빈 칸**인가.
---
--- 야수 소환은 슬롯 수가 마구간 칸 수로 고정돼 있어서, 그 자리에 야수가 없어도 슬롯은
--- `isKnown`으로 남는다. 그래서 `isKnown` 검사만으로는 안 걸러지고, 아무것도 안 나가는
--- 칸이 목록과 팝업에 그대로 선다. 블리자드 플라이아웃도 같은 검사를 한다
--- (`SpellFlyout.lua`가 `GetCallPetSpellInfo`로 `visible`을 끈다).
---
--- **이 검사가 한 군데인 것이 요점이다.** 처음엔 시전 쪽(`GetFlyoutCastableSlots`)에만
--- 있었고, 선택 창은 안 걸러서 **팝업에는 안 뜨는 칸이 목록에는 뜨는** 상태가 됐다.
--- 지금은 `ActionCatalog.lua`의 `AddFlyoutEntries`도 이것을 부른다.
function DebindPrivate.IsEmptyCallPetSlot(spellID)
    local petIndex, petName = GetCallPetSpellInfo(spellID);
    return petIndex ~= nil and (not petName or petName == "");
end

local IsEmptyCallPetSlot = DebindPrivate.IsEmptyCallPetSlot;

--- 착용 슬롯 하나의 **표시 이름과 빈 칸 그림**. `INVSLOT_HEAD`..`INVSLOT_TABARD`.
---
--- 이름은 게임의 것이다. `GetInventorySlotInfoForInvSlot`이 프레임 이름("HeadSlot")을 주고,
--- 그걸 대문자로 올린 전역이 그 언어의 표시 이름이다(`HEADSLOT` = "머리"). 캐릭터 창이
--- 자기 칸에 이름을 붙이는 방식 그대로다.
---
--- **같은 이름을 쓰는 칸이 있어서 번호를 붙인다.** `TRINKET0SLOT`과 `TRINKET1SLOT`이 둘 다
--- "장신구"고 손가락 둘도 그렇다. 캐릭터 창에서는 자리가 그 둘을 갈라주는데 **목록에서는
--- 갈라줄 것이 없다** - 똑같은 줄이 둘 서면 어느 쪽이 어느 칸인지 알 길이 없다. 게임에
--- 번호가 붙은 문자열이 따로 없어서 우리가 붙인다.
---
--- 번호는 **겹치는 것에만** 붙는다. 목록을 한 번 만들어보고 이름이 두 번 나온 것만 번호를
--- 얻으므로, 게임이 언젠가 둘을 다른 이름으로 갈라 부르면 번호가 저절로 사라진다.
local EquipSlotFacts;
do
    local facts;

    local function build()
        facts = {};
        local nameCount = {};

        for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
            local _, texture, _, frameName = C_PaperDollInfo.GetInventorySlotInfoForInvSlot(slot);
            local name = frameName and _G[strupper(frameName)];
            facts[slot] = { name = name, texture = texture };
            if (name) then
                nameCount[name] = (nameCount[name] or 0) + 1;
            end
        end

        local numbered = {};
        for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
            local entry = facts[slot];
            local name = entry.name;
            if (name and nameCount[name] > 1) then
                numbered[name] = (numbered[name] or 0) + 1;
                entry.name = format(L["USESLOT_NUMBERED"], name, numbered[name]);
            end
        end
    end

    --- **처음 물을 때 짓는다.** 파일이 읽히는 시점에는 `_G["HEADSLOT"]`이 아직 없을 수 있고,
    --- 없는 채로 지어진 표는 이름이 통째로 nil인 채 살아남는다.
    function EquipSlotFacts(slot)
        if (not facts) then
            build();
        end
        local entry = facts[slot];
        if (not entry) then
            return nil, nil;
        end
        return entry.name, entry.texture;
    end
end
DebindPrivate.EquipSlotFacts = EquipSlotFacts;

--- 플라이아웃 **자기 아이콘**. flyoutID -> iconID.
---
--- 게임에는 플라이아웃 자기 아이콘이 있다 - 주문책이 "야수 소환" 칸에 그리는 그 그림이고,
--- 첫 슬롯의 것이 아니다. 문제는 그걸 내주는 API가 `C_SpellBook.GetSpellBookItemTexture`
--- 하나뿐이고 **flyoutID로는 못 묻는다**는 것이다 - 주문서 슬롯 번호가 있어야 한다
--- (`GetFlyoutInfo`가 내는 것은 이름·설명·슬롯 수·습득 여부뿐이다). 그래서 주문서를 한 번
--- 훑어 표를 만들어 둔다.
---
--- **찾은 값은 안 지운다.** 아이콘은 플라이아웃 정의에 박힌 것이라 특성이나 야수에 따라
--- 안 바뀐다. 다시 훑는 것은 **못 찾은 것** 때문이다 - 특성을 바꾸면 없던 플라이아웃이
--- 주문서에 생기고, 그 전까지는 물어볼 슬롯 자체가 없었다.
---
--- `shouldHide` 스킬라인도 훑는다. 카탈로그와 달리 여기서 찾는 것은 목록에 세울 줄이 아니라
--- 그림 한 장이고, 창에 안 보이는 줄에 있는 플라이아웃도 걸어둘 수는 있다.
local FlyoutIcons = {};
local flyoutIconsSwept = false;

local function SweepFlyoutIconsInBank(first, last, bank)
    for slotIndex = first, last do
        local info = C_SpellBook.GetSpellBookItemInfo(slotIndex, bank);
        if (info and info.itemType == Enum.SpellBookItemType.Flyout) then
            local icon = C_SpellBook.GetSpellBookItemTexture(slotIndex, bank);
            if (icon) then
                FlyoutIcons[info.actionID] = icon;
            end
        end
    end
end

local function SweepFlyoutIcons()
    local playerBank = Enum.SpellBookSpellBank.Player;
    local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines() or 0;
    for skillLineIndex = 1, numSkillLines do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex);
        if (skillLineInfo) then
            SweepFlyoutIconsInBank(skillLineInfo.itemIndexOffset + 1,
                skillLineInfo.itemIndexOffset + skillLineInfo.numSpellBookItems, playerBank);
        end
    end

    local numPetSpells = C_SpellBook.HasPetSpells();
    if (numPetSpells) then
        SweepFlyoutIconsInBank(1, numPetSpells, Enum.SpellBookSpellBank.Pet);
    end
end

local function GetFlyoutIcon(flyoutID)
    local icon = FlyoutIcons[flyoutID];
    if (icon) then
        return icon;
    end

    -- 한 번 훑었으면 다시 안 훑는다. 없는 flyoutID를 그릴 때마다 주문서를 통째로 도는 일을
    -- 막는 것이고, 표를 다시 열어주는 것은 아래 `SPELLS_CHANGED`뿐이다.
    if (flyoutIconsSwept) then
        return nil;
    end

    SweepFlyoutIcons();
    flyoutIconsSwept = true;
    return FlyoutIcons[flyoutID];
end

local FlyoutIconEventFrame = CreateFrame("Frame");
FlyoutIconEventFrame:RegisterEvent("SPELLS_CHANGED");
FlyoutIconEventFrame:SetScript("OnEvent", function()
    flyoutIconsSwept = false;
end);

--- 플라이아웃의 이름과 아이콘.
---
--- 아이콘은 위의 표에서 온다 - 주문책이 그리는 **그 플라이아웃의 그림**이다. 표에 없을 때만
--- 첫 번째 쓸 수 있는 슬롯의 주문에서 빌려온다. 그 자리는 주문서에 아직 안 뜬 플라이아웃
--- (특성 변경 직후 등)을 위한 것이지 기본값이 아니다.
---
--- **아이콘은 저장하지 않는다.** 이 애드온의 규약대로(`ActionCatalog.lua` 머리주석) 저장은
--- flyoutID 하나뿐이고 그림은 그릴 때마다 여기서 다시 푼다.
---
--- `isOffSpec`은 **오프스펙 플라이아웃을 통째로 안 배운 상태**를 위한 예외다. 그때는 슬롯의
--- `isKnown`이 전부 거짓이라 그 검사만으로는 쓸 수 있는 슬롯을 하나도 못 고른다.
---
--- 네 번째 값 `hasUsableSlot`은 **열면 뭐라도 나오는가**이다. 야수가 하나도 없는 사냥꾼의
--- 야수 소환이 거짓이고, 부르는 쪽(`AddFlyoutEntry`)이 그 줄을 아예 안 올린다 - 열어도 빈
--- 상자만 뜨는 것을 목록에 세우지 않는 것이 요점이다. 한때 이 신호가 "아이콘이 안 나온다"였다.
--- 아이콘을 첫 슬롯에서 빌려오던 시절에는 같은 말이었지만, 지금은 플라이아웃 자기 아이콘이
--- 빈 칸에도 나오므로 갈라놔야 한다.
function DebindPrivate.GetFlyoutNameAndIcon(flyoutID, isOffSpec)
    local name, _, numSlots, isKnown = GetFlyoutInfo(flyoutID);
    if (not name or not numSlots or numSlots == 0) then
        return nil, nil, nil, false;
    end

    local hasUsableSlot = false;
    local fallbackIcon;
    for slot = 1, numSlots do
        local spellID, overrideSpellID, isKnownSlot = GetFlyoutSlotInfo(flyoutID, slot);
        if (spellID and (isKnownSlot or isOffSpec) and not IsEmptyCallPetSlot(spellID)) then
            hasUsableSlot = true;
            local _, slotIcon = GetSpellNameAndIconID(overrideSpellID or spellID);
            if (slotIcon) then
                fallbackIcon = slotIcon;
                break;
            end
        end
    end

    return name, GetFlyoutIcon(flyoutID) or fallbackIcon, isKnown, hasUsableSlot;
end


--- The slots of a flyout that can actually fire, with the value to cast each by.
---
--- **Off-spec slots are refused here**, unlike the list that draws them. These go on a button, and
--- a spell the reader has not learned does nothing when pressed.
---
--- **Two icons and they are not the same question.** `icon` comes from the slot's own spell so a
--- slot always has one, `displayIcon` from whatever is overriding it right now, which is the picture
--- the spellbook draws. Casting still goes by the base spell's name.
function DebindPrivate.GetFlyoutCastableSlots(flyoutID, out)
    out = out or {};
    wipe(out);

    local _, _, numSlots = GetFlyoutInfo(flyoutID);
    if (not numSlots) then
        return out;
    end

    for slot = 1, numSlots do
        local spellID, overrideSpellID, isKnown, spellName = GetFlyoutSlotInfo(flyoutID, slot);
        if (spellID and isKnown and not IsEmptyCallPetSlot(spellID)) then
            local castName = GetSpellCastName(spellID);
            local _, icon = GetSpellNameAndIconID(spellID);

            local _, displayIcon = GetSpellNameAndIconID(overrideSpellID or spellID);
            tinsert(out, {
                spellID = spellID,
                cast = castName or spellID,
                name = spellName or castName,
                icon = displayIcon or icon,
            });
        end
    end

    return out;
end

function DebindPrivate.GetSpellTabNameAndIcon(index)
    local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(index);
    if skillLineInfo then
        return skillLineInfo.name, skillLineInfo.iconID;
    end
end


--- 펫 명령(공격·따라가기·대기·태세…)을 보안 슬래시 명령으로 옮기는 표.
---
--- **키는 주문서의 `actionID`다.** 펫 바의 텍스처 이름으로 잡았다가 바꿨다 - 펫 바는 10칸뿐이라
--- 거기 못 올라간 명령(흑마 서큐버스에서 Stay·Defensive가 그랬다)이 목록에서 통째로 사라졌다.
--- 주문서에는 전부 있고, 주문서가 주는 손잡이는 이 값 하나다.
---
--- **값은 위치와 무관하고 클래스·펫이 달라도 같다.** 실측으로 확인했다 - 흑마와 사냥꾼에서
--- 같은 값이 나왔고, 슬롯 1의 attack이 `…02`, 슬롯 8의 assist가 `…03`이라 슬롯 번호도 아니다.
---
--- `(계열 << 24) | 번호` 꼴이다. `0x07`이 명령, `0x06`이 태세인데 **번호가 띄엄띄엄하다**
--- (명령에 3이 비고, 태세에 1·2가 빈다). 그래서 규칙으로 채우지 않고 확인한 것만 적는다.
---
--- **여기 없는 이유가 두 가지다. 섞으면 안 된다:**
---
---   값을 못 봤다      `PET_AGGRESSIVE`, `PET_DISMISS`. 없다는 뜻이 아니라 실측을 못 했다는 뜻이다
---   명령이 죽었다     `PET_DEFENSIVE`(`0x06000004`). **값은 안다** - 아래 주석 참고
---
--- 값은 `SlashCommands.lua`가 `CheckAddSecureSlashCommand`로 올린 것들이다.
---
--- **자동시전 셋(`PET_AUTOCASTON/OFF/TOGGLE`)은 보안이 아니라서가 아니라 - 그것들도 보안이다
--- (`Mainline/SlashCommandsOverrides.lua:7-26`) - 주문 이름을 인자로 받기 때문에 여기 없다.**
--- 펫 명령 하나에 대응하는 물건이 아니다.
---
--- 표에 없는 actionID는 목록에 안 올린다. 모르는 것을 대충 걸어두면 눌러도 아무 일이 없는
--- 바인딩이 되는데, 그게 제일 알아채기 어려운 고장이다.
local PET_ACTION_SLASH_BY_ID = {
    [117440512] = "PET_STAY",     -- 0x07000000
    [117440513] = "PET_FOLLOW",   -- 0x07000001
    [117440514] = "PET_ATTACK",   -- 0x07000002
    [117440516] = "PET_MOVE_TO",  -- 0x07000004
    [100663296] = "PET_PASSIVE",  -- 0x06000000
    -- 지원 태세는 **`PET_ASSIST`다.** `PET_DEFENSIVEASSIST`가 아니다.
    --
    -- 리테일 펫 바의 지원 버튼이 하는 일은 `C_PetInfo.PetAssistMode()`이고, 그걸 부르는 보안
    -- 슬래시 명령이 `PET_ASSIST`다(`Blizzard_ChatFrameBase/Mainline/SlashCommandsOverrides.lua:1-5`).
    -- **`PetAssistMode`만 `C_PetInfo`로 옮겨졌고**(`PetInfoDocumentation.lua`) 폐기 shim이 옛
    -- 전역을 그쪽으로 다시 이어준다(`Deprecated_PetInfo.lua`). `PetDefensiveAssistMode`에는
    -- 그게 둘 다 없다.
    --
    -- ※ 한때 이 자리에 *"`PetDefensiveAssistMode`는 트리에 정의가 없으니 죽었다"*고 적었는데
    --   **그 논증은 아무것도 못 가른다** - `PetPassiveMode`·`PetAttack`·`PetFollow` 따위가
    --   전부 똑같이 트리에 정의가 없다(엔진 쪽 전역이다). 위의 "옮겨졌는가"가 진짜 근거다.
    [100663299] = "PET_ASSIST",   -- 0x06000003

    -- **방어 태세(`0x06000004` = 100663300)는 값을 아는데도 뺐다.**
    --
    -- **우리 버그가 아니라 게임 버그다.** `/petdefensive`는 지금도 등록돼 있고
    -- (`SlashCommands.lua`가 `PET_DEFENSIVE`를 올린다) 슬래시 문자열도 살아 있는데,
    -- 그게 부르는 `PetDefensiveMode()`가 **최소 5년째 아무 일도 안 한다**(실측).
    -- 채팅창에 손으로 쳐도 마찬가지다.
    --
    -- 그래서 `GetPetActionMacroText`의 가드를 그냥 통과한다 - 그 가드가 보는 것은 슬래시
    -- **문자열의 존재**뿐이고 그게 부르는 함수가 실제로 무언가를 하는지는 알 수 없다.
    -- 넣어두면 **목록에 뜨는데 눌러도 아무 일이 없는 항목**이 되고, 그게 이 파일이 막으려는
    -- 바로 그 고장이다(아래 "표에 없는 actionID는 …").
    --
    -- 대신 이 애드온에는 **방어 태세를 거는 길이 없다.** 펫 바 버튼은 `CastPetAction(슬롯)`
    -- 이라 되지만, 슬롯은 펫마다 다르고 전투 중에 못 고친다 - 이 타입을 슬래시로 만든 이유가
    -- 그것이라 그쪽으로 돌아갈 수는 없다. 열린 항목으로 `.zzz/TODO.md`에 적어뒀다.
    --
    -- **블리자드가 고치면 이 한 줄을 되살리는 것으로 끝난다:**
    --     `[100663300] = "PET_DEFENSIVE", -- 0x06000004`
    --
    -- 자동으로 살아나게 두지 않은 이유: 살았는지 물어볼 방법이 없다. 전역이 사라진 것이라면
    -- `PetDefensiveMode == nil`로 가를 수 있지만, 그 이름이 남은 채 속이 빈 것이면 어떤 검사도
    -- 통과한다. 게임에서 한 번 쳐보는 것이 유일한 판정이라 사람이 판단할 자리로 남겨둔다.
};

--- 대상을 **실제로 쓰는** 명령. 확인된 것은 공격 하나다(`SlashCommands.lua:659`,
--- `PetAttack(target)`). 나머지 핸들러는 조건의 참·거짓만 보고 target을 버린다.
---
--- **여기 없는 명령에는 대상 메뉴가 아예 안 열린다**(`DropDownMenus.lua`) - 안 쓰는 값을
--- 고르게 두면 그 설정이 무언가를 한다고 읽힌다. `GetBindingInfoForAction`도 같은 표를 보고
--- `binding.unit`을 지운다.
---
--- **`PET_MOVE_TO`는 대상을 안 받는다.** 지면을 찍는 명령이라 유닛이 들어갈 자리가 아니다.
--- 핸들러가 `PetMoveTo(target)`으로 넘기는 것은 소스에 그렇게 적혀 있지만
--- (`SlashCommands.lua:676`), 그걸 근거로 넣으면 안 된다 - 고를 수는 있는데 아무 일도 안 하는
--- 항목이 된다.
local PET_ACTION_TAKES_UNIT = {
    PET_ATTACK = true,
};

--- 주문서 `actionID` -> 우리가 저장할 값(슬래시 명령 키). 모르면 nil.
function DebindPrivate.GetPetActionCommandByActionID(actionID)
    return actionID and PET_ACTION_SLASH_BY_ID[actionID] or nil;
end

function DebindPrivate.PetActionTakesUnit(command)
    return command ~= nil and PET_ACTION_TAKES_UNIT[command] == true;
end

--- Whether an action of this type and value can aim at a unit at all. **One test for both readers**:
--- the `Target` menu opens on it and `FillBinding` keeps a unit on it. The menu offering a target
--- the binding drops is a setting that does nothing, which has happened here before.
---
--- **Not what decides `"@"`.** That asks the unit the press aims at, which every action has.
function DebindPrivate.ActionTakesUnit(action)
    if (not Constants.TYPES_WITH_UNIT[action.type]) then
        return false;
    end
    if (action.type == Constants.PETACTION) then
        return DebindPrivate.PetActionTakesUnit(action.value);
    end
    -- A stance is pressed through its bar button, and a click carries no target.
    if (action.type == Constants.ACTIONBUTTON) then
        local info = Constants.ACTION_BUTTON_COMMANDS[action.value];
        return not (info and info.stance);
    end
    return true;
end

--- Whether the reader picked a unit for this action to go to. **Neither a held cast key nor Hover
--- Cast moves one** (2026-09-15, owner): a modifier carried over from the key pressed just before,
--- ALT-1 then 2, reads as held at the press, and the client's own buttons never let it move a unit
--- set on them either.
---
--- **`none` is not one.** It settles nothing before the press, so what the press aims at is worked
--- out the way it is for an action with no target and only the cast goes out asking
--- (`binding.castsAtNone`). A `unit` the type cannot take is not one either, nor the `unitframe` a
--- `unitframe` condition fills in, which is why this reads the action and not `binding.unit`.
function DebindPrivate.ActionHasPickedUnit(action)
    local unit = action.unit;
    return type(unit) == "string" and unit ~= "" and unit ~= "none"
        and DebindPrivate.ActionTakesUnit(action);
end

--- 펫 명령 하나를 매크로 본문으로. 슬래시 명령이 없으면 nil - **부르는 쪽이 그걸로 거른다.**
--- 카탈로그도 이 함수로 걸러서, 목록에 오르는 것은 실행되는 것만 남는다.
---
--- 슬래시 문자열은 전역에서 읽는다. `SLASH_CAST1`을 쓰는 것과 같은 이유 - 로케일마다 다르다.
---
--- 대상은 `[@유닛]` 조건절로 나간다. **이 형태는 게임에서 확인했다** - 손으로 만든
--- `/petattack [@focus]` 매크로가 정상 동작한다. (한때 이 형태를 의심해 본문 형태로 바꾼 적이
--- 있는데, 진짜 원인은 `SetBindingAttributes`의 캐시였다. `refactor-candidates.md` 참고.)
---
--- 조건절의 `@유닛`은 그대로 안 나간다. `SetBindingAttributes`가 이걸 MACROTEXT와 같은 길에
--- 태우므로, `@custom1`·`@unitframe` 같은 우리 유닛은 `ParseMacroText`가 실행 시점에 진짜 토큰으로
--- 바꾼다. 여기서 할 일은 문자열을 만드는 것까지다.
function DebindPrivate.GetPetActionMacroText(command, unit)
    local slash = command and _G["SLASH_" .. command .. "1"];
    if (not slash) then
        return nil;
    end
    if (unit and unit ~= "" and DebindPrivate.PetActionTakesUnit(command)) then
        return format("%s [@%s]", slash, unit);
    end
    return slash;
end

--- 계정 매크로 칸 수와 캐릭터 매크로 칸 수.
---
--- **`MAX_ACCOUNT_MACROS` / `MAX_CHARACTER_MACROS` 전역은 없다.** 블리자드 트리 전체에
--- 그 이름의 정의가 0건이고, `Blizzard_MacroUI`조차 `Constants.MacroConsts`에서 읽는다.
--- 없는 값을 더하거나 비교하면 그 자리에서 터진다 - `GetMacrotextIcon`이 실제로 그러고
--- 있었고, 오류를 삼키는 애드온을 쓰면 조용히 그 함수만 죽는다.
---
--- 세 단계로 떨어진다. 전역이 살아 있던 클라이언트가 있을 수 있으니 그것도 보고,
--- 마지막은 상수의 문서값(120 / 30)이다 - 못 찾았다고 기능을 통째로 접는 것보다 낫다.
---
--- **`_G.Constants`인 것에 주의.** 애드온 파일들의 `Constants`는 우리 것이라 이름이 겹친다.
function DebindPrivate.GetMacroSlotLimits()
    local macroConsts = _G.Constants and _G.Constants.MacroConsts;
    local account = (macroConsts and macroConsts.MAX_ACCOUNT_MACROS) or _G.MAX_ACCOUNT_MACROS or 120;
    local character = (macroConsts and macroConsts.MAX_CHARACTER_MACROS) or _G.MAX_CHARACTER_MACROS or 30;
    return account, character;
end

local UNIT_SCALAR_TO_STATE = {
    [true]    = Constants.UNITSTATE_EXISTS,
    [false]   = Constants.UNITSTATE_NONE,
    ["help"]  = Constants.UNITSTATE_HELP,
    ["harm"]  = Constants.UNITSTATE_HARM,
};

local REACTION_TO_UNIT_STATE = {
    [Constants.REACTION_HELP]  = Constants.UNITSTATE_HELP,
    [Constants.REACTION_HARM]  = Constants.UNITSTATE_HARM,
    [Constants.REACTION_OTHER] = Constants.UNITSTATE_OTHER,
};

--- 저장된 유닛 조건 -> 바인딩이 읽는 모양. 조건이 꺼져 있으면 `nil`.
---
--- **저장과 바인딩은 다른 모양이고, 이 함수가 그 이음매다.**
---
--- 저장은 사용자가 편집하는 것이라 **끈 값을 기억한다.** 라디오를 [사용 안 함]이나
--- [없을 때]로 옮겼다고 골라둔 반응·생사를 지우면, 되돌렸을 때 처음부터 다시 골라야 한다.
--- **옵션을 끄는 것이지 지우는 것이 아니다.**
---
---     { exists = true, ... }       있을 때. 축이 붙으면 그만큼 좁아진다
---     { exists = false, ... }      없을 때. 축은 기억만 한다
---     { disabled = true, ... }     이 유닛에 조건 없음. 축은 기억만 한다
---
--- **표시가 하나도 없는 표는 옛 값이고, "있을 때"로 읽는다.** `dbver <= 6` 단계가 그것을
--- `exists = true`로 올리므로 저장에는 안 남는다. 아직 안 옮겨진 프로필과 페이로드가 그
--- 모양으로 오는데, 그것을 "조건 없음"으로 읽으면 걸어둔 조건이 조용히 사라져 바인딩이 제 것
--- 아닌 키까지 가져간다. 좁아지는 쪽이 안전하다.
---
--- 바인딩은 판정에 쓰는 것이라 기억을 안 들고 간다. 그래야 `IsConditionalBinding`도, 이슈
--- 검사도, 런타임 방출도 "꺼진 축"이라는 경우를 몰라도 된다.
---
--- 옛 스칼라도 여기서 받는다. 가져오기 도중이거나 손으로 고친 프로필, 테스트가 만든 액션이
--- 그 모양으로 온다 - **여기서 끝나야** 하류가 타입 검사를 안 한다.
local function UnitConditionForBinding(value)
    if (value == nil) then
        return nil;
    elseif (value == true) then
        return {};
    elseif (value == false) then
        return false;
    elseif (value == "help") then
        return { reaction = Constants.REACTION_HELP };
    elseif (value == "harm") then
        return { reaction = Constants.REACTION_HARM };
    elseif (type(value) ~= "table") then
        -- 모르는 스칼라. **떨어뜨리지 않는다** - 옛 버전이 쓴 값을 우리가 모를 수 있고, 조건이
        -- 조용히 사라지면 그 바인딩이 걸어둔 것보다 넓어져 남의 키를 가져간다.
        --
        -- **없을 때로 읽지만, 둘째 반환값이 그게 읽어낸 값이 아니라고 말한다.** 없음 점은 크기가
        -- 작을 뿐 "있을 때"의 부분집합이 아니라서, 좁게 틀리는 것이 아니라 **다른 자리로** 틀린다.
        -- 그대로 축에 올리면 이 바인딩이 진짜 [없을 때] 바인딩을 통째로 덮고 solver가 그것을
        -- 지운다. `GetBindingInfoForAction`이 둘째 값을 받아 바인딩을 두 역할에서 뺀다.
        --
        -- 첫째 값은 그대로 두는 것이 이 함수의 나머지 독자들 때문이다 - 툴팁과 조건 메뉴는
        -- 라디오 셋 중 하나를 골라야 하고, 넷째 자리가 없다.
        return false, true;
    end

    -- **옛 이름 `off`는 여기서 안 받는다.** 저장된 표를 읽는 자리가 둘인데
    -- (`IntersectStoredUnitConditions`) 한쪽만 옛 이름을 알면 같은 표를 두 가지로 읽는다.
    -- `dbver <= 6` 단계가 프로필과 페이로드 양쪽에서 이름을 올리고 - 페이로드도 `MigrateLayer`를
    -- 지난다(`Export.lua`의 `BringPayloadDataForward`) - 그 아래로 내려갈 저장은 없다.
    if (value.disabled) then
        return nil;
    elseif (value.exists == false) then
        return false;
    end
    return { reaction = value.reaction, dead = value.dead, role = value.role, group = value.group,
        frameTypes = value.frameTypes };
end

--- The old `hover` / `reactions` pair -> the unit condition they became.
---
--- The pointed frame's unit is a unit, so it is stored as one: `units["unitframe"]`
--- (`Profile.lua`'s `dbver <= 4` step). Kept in its own pair of fields it was one unit described
--- by two columns, meeting only in `BuildUnitStates` -- which meant two runtime paths measuring
--- the same thing about the same unit.
---
--- `existing` is whatever that key already holds, from the days both menus were live. This
--- **intersects** rather than overwrites: dropping either side would widen a binding past what
--- was set. Where the two do not overlap the answer is `reaction = 0` -- exists, and in none of
--- the three reactions, which no unit satisfies. That is not a new marker: `GetBindingIssue`
--- already reads a zero mask that way, and the pair was already an issue before it was folded.
--- **`existing`도 돌려주는 값도 바인딩 모양이다**(`UnitConditionForBinding`이 내는 것). 저장
--- 모양을 넣지 말 것 - 부르는 쪽이 먼저 통과시킨다. 접기는 "꺼진 축을 기억한다"는 편집 쪽
--- 사정과 아무 상관이 없고, 두 모양을 다 받게 만들면 어느 쪽인지 매번 물어야 한다.
local function UnitFrameConditionFromLegacy(hover, reactions, existing)
    if (hover == false) then
        -- "Not over a frame" against any condition that needs the unit there. Nothing is both.
        -- Spelled out rather than `and false or` -- that idiom cannot return `false`.
        if (existing == nil or existing == false) then
            return false;
        end
        return { reaction = 0 };
    end
    if (existing == false) then
        return { reaction = 0 };
    end

    local reaction = reactions;
    if (reaction == Constants.REACTION_ALL) then
        reaction = nil;
    end

    local folded = type(existing) == "table" and existing or {};
    if (reaction == nil) then
        reaction = folded.reaction;
    elseif (folded.reaction ~= nil) then
        reaction = band(reaction, folded.reaction);
    end
    folded.reaction = reaction;
    return folded;
end

DebindPrivate.UnitFrameConditionFromLegacy = UnitFrameConditionFromLegacy;
DebindPrivate.UnitConditionForBinding = UnitConditionForBinding;

--- 이 액션에 저장된 개체창 유닛 조건. **옛 철자도 읽는다.**
---
--- `dbver <= 6`이 저장된 `units.hover`를 `units.unitframe`으로 옮기지만, **원본 액션을 직접 읽는
--- 자리는 사다리가 아직 안 닿은 것도 만난다** - 손으로 고친 프로필, 그리고 `FillBinding`이 평면
--- `checkedUnits`를 받아주는 것과 같은 경우들이다. 이름 하나만 보게 두면 그 조건이 조용히 사라지고,
--- **조건이 사라진 바인딩은 넓어져서 남의 키를 가져간다.**
---
--- 원본 액션을 읽는 자리가 셋이라(여기 둘과 `ActionTooltip.lua`) 옛 이름은 이 함수 하나만 안다.
--- 표를 새로 만들지 않으므로 행마다 불려도 할당이 없다.
function DebindPrivate.StoredUnitFrameCondition(action)
    local units = action.conditions and action.conditions.units;
    if (units == nil) then
        return nil;
    end
    local value = units.unitframe;
    if (value == nil) then
        value = units.hover;
    end
    return value;
end

--- One stored unit condition -> a mask on the unit axis.
---
--- Storage keeps **one field per axis** (`{ reaction = ... }`), not one packed enum, so that a
--- new axis is a new field and old data stays valid: a field that is absent constrains nothing,
--- which is already the right answer. See `Profile.lua`'s `dbver <= 4` step.
---
--- An axis that is absent contributes its whole range, which is why an empty table means
--- "exists, nothing else asked". `false` is the one non-table value -- the absent point is not
--- on any axis, which is the whole reason this column is a product and not separate columns.
local function UnitConditionToState(value)
    if (value == false) then
        return Constants.UNITSTATE_NONE;
    end
    if (type(value) ~= "table") then
        -- 아직 안 옮겨진 값. `MigrateLayer`가 올려주지만, 가져오기 도중이거나 손으로 고친
        -- 프로필이면 여기로 온다.
        --
        -- **모르는 값이 여기까지 오면 이미 없음 점이다.** `UnitConditionForBinding`이 먼저
        -- 돌면서 `false`로 바꾸고, 못 읽었다는 사실은 그쪽 둘째 반환값이 따로 나른다.
        return UNIT_SCALAR_TO_STATE[value] or Constants.UNITSTATE_NONE;
    end

    local mask;
    local reactions = value.reaction;
    if (reactions == nil) then
        mask = Constants.UNITSTATE_EXISTS;
    else
        mask = 0;
        for reaction, state in pairs(REACTION_TO_UNIT_STATE) do
            if (band(reactions, reaction) ~= 0) then
                mask = mask + state;
            end
        end
    end

    -- Life **takes half of the product away**; it is not a column of its own. `nil` leaves both
    -- halves, which is what "constrains nothing" means -- and is already the right answer for old
    -- data that has no such field.
    if (value.dead ~= nil) then
        mask = band(mask, value.dead and Constants.UNITSTATE_DEAD or Constants.UNITSTATE_ALIVE);
    end

    return mask;
end

--- This binding's condition on `unitframe`, in binding shape: nil, `false`, or a table.
---
--- **Read each time, not kept as a field.** The pointed frame's unit is an ordinary unit
--- (`devdocs/which-action-a-key-runs.md` §0), so a second name for one entry of `units` would be
--- the split that fold removed. The readers left are the ones that ask something about the **key**
--- rather than about the unit: which path a press takes (`UpdateBindings.lua`'s `isClickCast` and
--- `holdsKey`), whether a mouse button can be bound at all (`IsKeyInvalidForAction`), and where the
--- frame's unit fills in for an empty target.
---
--- `false` and `nil` are **different answers** and both are load-bearing -- "only when not over a
--- frame" versus "does not care" -- so this cannot collapse to a boolean.
local function UnitFrameConditionOf(binding)
    local conditions = binding.conditions;
    return conditions and conditions.units and conditions.units.unitframe;
end

DebindPrivate.UnitFrameConditionOf = UnitFrameConditionOf;

--- 저장된 세 상자 -> 그것이 덮는 네 칸.
---
--- **`bor`인 것이 요지다.** `PARTY`와 `RAID`가 둘 다 `BOTH`를 덮으므로 더하면 그 칸을 두 번
--- 센다. 겹치는 것이 이 축의 성질이고, 겹침을 여기서 푸는 것이 컬럼을 분할로 만든다
--- (`Constants.lua`의 `UNITGROUPCELL_*`).
local function UnitGroupToCells(mask)
    if (mask == nil) then
        return Constants.UNITGROUPCELL_ALL;
    end
    local cells = 0;
    for flag, covered in pairs(Constants.UNITGROUP_TO_CELLS) do
        if (band(mask, flag) ~= 0) then
            cells = bor(cells, covered);
        end
    end
    return cells;
end

DebindPrivate.UnitGroupToCells = UnitGroupToCells;

--- The stored box mask naming exactly this cell set, or nil where none does.
---
--- **The three boxes are not closed under intersection.** [In my party] and [In my raid] meet on
--- "in a raid and in my subgroup" alone, and no box or combination of boxes names that one cell.
--- So a fold that has to be written back into a profile has to ask first whether its answer can be
--- written at all; `band` on the boxes themselves returns 0 there, which is not that answer but
--- "no box chosen", and a binding that can fire becomes one that carries an error forever.
local function CellsToUnitGroup(cells)
    for mask = 0, Constants.UNITGROUP_ALL do
        if (UnitGroupToCells(mask) == cells) then
            return mask;
        end
    end
end
DebindPrivate.CellsToUnitGroup = CellsToUnitGroup;

--- The unit a binding's `"@"` is asked of: the unit it aims at, and `target` where it aims at none.
--- nil only for a `unit` that is not a string at all.
---
--- **`target` is where the condition is checked and nothing more.** An original with no target keeps
--- `unit` empty and goes out for the game to place, Auto Self Cast included. Writing `target` into the
--- field would turn Auto Self Cast off the moment a condition was set, which is picking `target` under
--- Target (`devdocs/implementing-focus-and-self-cast.md` §3-6). `""`, the hovered unit turned off, is
--- the game placing the cast too.
---
--- **One rule for every reader**: the unit states below, the record `UpdateBindings.lua` emits, the
--- issue check and the macro conversion. Two of them landing `"@"` on different units is a binding
--- judged on one unit and shown or fired on another.
local function ResolvedUnitOf(binding)
    local unit = binding.unit;
    if (unit == nil or unit == "") then
        return "target";
    end
    if (type(unit) ~= "string") then
        return nil;
    end
    return unit;
end
DebindPrivate.ResolvedUnitOf = ResolvedUnitOf;

--- The unit a binding's cast goes out at: its `unit`, except on `none`, where `unit` is only what the
--- press aims at and the cast itself always asks (`ActionHasPickedUnit`).
function DebindPrivate.CastUnitOf(binding)
    if (binding.castsAtNone) then
        return "none";
    end
    return binding.unit;
end

--- Fold everything that says something about a unit onto one mask per unit.
---
--- `binding.unitStates` is the only thing the solver reads about units.
---
--- The point of doing it here is that **the pointed frame's unit is just a unit, named
--- "unitframe"**. Kept apart, the `unitframe` condition and a unit condition on the same unit are
--- two columns describing one thing, and the solver cannot see that `unitframe=friendly` with
--- `@=hostile` never holds -- it keeps a binding that can never fire and warns about nothing.
---
--- A mouse button reaches the not-pointing point and nothing else: the click fires wherever the
--- cursor already is, and over a unit frame the frame eats it, so only the frame path can act
--- there. The same absent condition on a keyboard key spans the whole axis.
local function BuildUnitStates(binding)
    local states;

    -- **A value this build cannot read makes the binding opaque before any axis is touched.**
    -- `GetBindingInfoForAction` sets the flag while turning the stored table into the binding one;
    -- what it means is the same thing `"@"` with nowhere to go means below, so it lands in the same
    -- field. Reading such a value as the absent point would cover the bindings that really are
    -- [when there is none] and delete them.
    local opaque = binding.unitConditionUnreadable or nil;

    local function narrow(unit, mask)
        states = states or {};
        local prev = states[unit];
        if (prev == nil) then
            states[unit] = mask;
        else
            states[unit] = band(prev, mask);
        end
    end

    --- **Its own column, and only the pointed frame's unit rides it.** The map behind it is keyed
    --- by group unit tokens, and a group frame is the only thing that hands us one
    --- (`Constants.lua`). Two sources can name that unit -- `units.unitframe` and a `"@"` that
    --- resolves to it -- so this narrows the same way `narrow` does.
    local role;
    local function narrowRole(mask)
        if (role == nil) then
            role = mask;
        else
            role = band(role, mask);
        end
    end

    --- 프레임의 종류. 역할과 같은 자리에 산다 - 개체창을 가리켰을 때만 답이 나오는 축이라
    --- 유닛마다 세울 값이 아니다.
    local frameTypes;
    local function narrowFrameTypes(mask)
        if (frameTypes == nil) then
            frameTypes = mask;
        else
            frameTypes = band(frameTypes, mask);
        end
    end

    --- 소속도 자기 컬럼이고, 역할과 달리 **유닛마다** 선다. 어느 유닛에나 물을 수 있는
    --- 축이라 unitframe 슬롯에 얹을 이유가 없다.
    local groups;
    local function narrowGroup(unit, mask)
        groups = groups or {};
        local prev = groups[unit];
        if (prev == nil) then
            groups[unit] = mask;
        else
            groups[unit] = band(prev, mask);
        end
    end

    -- The `unitframe` condition itself is not read here any more -- it lives in
    -- `units["unitframe"]` and the loop below folds it like any other unit. What is left is the
    -- one thing the **key** says: a mouse button reaches the not-pointing point and nothing else,
    -- because the click fires wherever the cursor already is and over a unit frame the frame eats it.
    --
    -- **Only when nothing was said about pointing.** An explicit `unitframe` condition on a mouse
    -- button key is the user overriding that reading, and it has always won here -- narrowing it
    -- to absent as well would leave an empty box and delete the binding for a reason nobody set.
    local conditions = binding.conditions;
    local units = conditions and conditions.units;

    if (binding.key and (units == nil or units.unitframe == nil)
            and DebindPrivate.GetMouseButtonAndPrefix(binding.key)) then
        narrow("unitframe", Constants.UNITSTATE_NONE);
    end
    if (binding.skipsPointedUnit) then
        narrow(binding.skipsPointedUnit, Constants.UNITSTATE_NONE);
    end

    if (units) then
        for key, value in pairs(units) do
            local unit = key;
            if (key == "@") then
                unit = ResolvedUnitOf(binding);
                if (unit == nil) then
                    -- Nowhere to put it. Dropping the condition instead would make the binding
                    -- look wider than it is, and a cover wider than it should be deletes
                    -- bindings that can still fire -- so it leaves both roles, not one.
                    opaque = true;
                    unit = nil;
                end
            end
            if (unit) then
                narrow(unit, UnitConditionToState(value));
                -- `value` is `false` for [when there is none], and role is remembered rather than
                -- applied there -- the menu's rule for every axis under a mode it does not use.
                if (unit == "unitframe" and type(value) == "table") then
                    if (value.role) then
                        narrowRole(value.role);
                    end
                    if (value.frameTypes) then
                        narrowFrameTypes(value.frameTypes);
                    end
                end
                if (type(value) == "table" and value.group) then
                    narrowGroup(unit, UnitGroupToCells(value.group));
                end
            end
        end
    end

    binding.unitStates = states;
    binding.unitStatesOpaque = opaque;
    binding.unitRole = role;
    binding.unitFrameTypes = frameTypes;
    binding.unitGroups = groups;
end

DebindPrivate.BuildUnitStates = BuildUnitStates;

do
    local _ActionToBindingCache = setmetatable({}, { __mode = "kv" });

    --- 액션을 바인딩으로. **두 모양이 무엇을 드는지는 `devdocs/action-and-binding-shapes.md`가
    --- 든다** - 여기서 되풀이하면 둘째 진실이 생긴다.
    ---
    --- 이 함수에만 있는 사실 셋:
    ---
    --- **흐름이 한 방향이다.** 바인딩은 액션에서 다시 만들어지고 액션으로 되쓰이지 않는다.
    --- 그래서 아래 정규화가 사용자가 적은 것을 안 건드린다.
    ---
    --- **표를 재사용한다.** 캐시에서 꺼내 제자리에서 덮어쓰므로, 조건부로만 쓰는 필드는 이전
    --- 리빌드의 값이 남는다. `conditions`를 `wipe`하는 줄이 그것을 막는 자리다.
    ---
    --- **순서 필드는 여기 없다.** 어느 액션이 먼저 발동하느냐는 액션 하나로 답이 안 나오는
    --- 유일한 것이라, 그쪽은 `MakeOrderRecord`가 따로 든다.
    ---
    --- The original is called with the action's `unit` and nothing else. **A twin is called with
    --- `castModifier`, and that is what makes it one**: its `aimedUnit` is already the unit it goes
    --- out at, so nothing below strips or fills it (`GetBindingsForAction` works it out). A hover
    --- twin also brings `twinCondition`, which lands under `pointedUnit`.
    ---
    --- **`unit` has to arrive with the call**: the `unitframe` fill-in and `BuildUnitStates` at the end
    --- both read it, so changing `unit` on a filled binding leaves `"@"` standing on the old unit.
    local function FillBinding(binding, action, aimedUnit, twinCondition, castModifier, pointedUnit)
        local twin = castModifier ~= nil;
        -- **The pre-rename spelling of the target, for the profiles the ladder has not reached.**
        -- `dbver <= 6` renames a stored `unit = "hover"` alongside the condition; the unit table
        -- below carries the same shim for the same reason. Left as it is, `binding.unit` holds a
        -- name nothing answers to any more: the click path does not recognise it
        -- (`UpdateBindings.lua`'s `isClickCast`) and the emitter finds it in neither
        -- `SPECIAL_UNITS` nor `BASIC_UNITS`, so the action goes out with no unit at all.
        if (aimedUnit == "hover") then
            aimedUnit = "unitframe";
        end
        binding.type, binding.value = action.type, action.value;
        -- **Only the binding changes.** The action keeps the type it was saved with, so its row
        -- still says what it was, and an older build reading the same SavedVariables still runs it.
        if (action.type == Constants.UNUSED or action.type == Constants.COMMAND) then
            binding.type = Constants.BLOCK;
        end
        -- **The three spec-resolved types put their spell here and leave `value` alone.** What the
        -- action stores is the kind; which spell that is today is this specialization's answer
        -- (`SpecSpells.lua`), and every reader of the binding that wants a spell id reads this
        -- field ahead of `value`. `spellbook` is the derived-binding probe and is set by the
        -- derivation, never here.
        binding.spellbook = nil;
        if (Constants.SPEC_RESOLVED_TYPES[action.type]) then
            binding.spell = DebindPrivate.SpecSpells.SpellForType(action.type);
        else
            binding.spell = nil;
        end
        -- **Only the original answers a press with nothing held and nothing pointed at**, so this is
        -- the original's field: the twins each stand in a tier of their own and Normal Cast says
        -- nothing about those tiers. `BuildKeyMap` reads it to leave the original out of the last
        -- tier (`devdocs/which-action-a-key-runs.md` §6).
        if (twin or DebindPrivate.NormalCastEnabled(action)) then
            binding.normalCast = nil;
        else
            binding.normalCast = false;
        end

        binding.unit = aimedUnit;
        binding.key = action.key;

        -- **조건은 한 표를 통째로 옮긴다.** 예전에는 열두 줄이 손으로 적혀 있었고, 축이
        -- 하나 늘 때마다 이 줄을 잊으면 그 조건이 바인딩에 도착하지 않았다. 조용히 넓어지는
        -- 쪽이라 아무도 못 잡는다.
        --
        -- 표는 **재사용한다.** 아래 정규화가 제자리에서 nil을 쓰므로 액션 쪽 표를 그대로
        -- 가리키면 사용자가 건 조건을 지우게 된다.
        -- **The refill has to clear this too.** It is set from the conditions below and the table
        -- is reused, so a binding once marked opaque stayed opaque for the life of the action --
        -- the reader fixes the condition the menu could not read and the binding still covers
        -- nothing and is covered by nothing. Reachable only by luck before `_ActionToBindingsCache`
        -- held strong values; now the table never goes away.
        binding.unitConditionUnreadable = nil;

        local conditions = binding.conditions;
        if (conditions == nil) then
            conditions = {};
            binding.conditions = conditions;
        else
            wipe(conditions);
        end
        if (action.conditions) then
            for k, v in pairs(action.conditions) do
                conditions[k] = v;
            end
        end

        -- 저장 모양 -> 바인딩 모양. 꺼진 조건은 여기서 빠지므로 하류는 기억을 안 만난다.
        -- 남는 것이 없으면 표 자체를 안 만든다 - `conditions.units`가 있느냐를 게이트로
        -- 쓰는 자리가 여럿이라(이슈 검사, `IsConditionalBinding`), 빈 표는 조건이 하나도
        -- 없는 액션을 조건부로 만든다.
        conditions.units = nil;
        -- **평면 `action.checkedUnits`도 받는다.** 나간 적 있는 프로필이 그 모양이고
        -- (`dbver <= 5`가 옮기기 전), 바로 아래 옛 `hover`/`reactions` 쌍이 같은 이유로
        -- 여기 있다. 한쪽만 받으면 마이그레이션이 아직 안 닿은 액션의 유닛 조건만 조용히
        -- 사라지는데, **조건이 사라진 바인딩은 넓어져서 남의 키를 가져간다.**
        --
        -- 나머지 축은 안 받는다. 그것들은 값이 스칼라라 중첩 여부가 뜻을 안 바꾸고,
        -- 액션 최상단을 한 번 더 훑는 값이 리빌드마다 붙는다.
        -- **옛 이름을 `rawget`으로 읽는다.** 마이그레이션 전 프로필의 최상단 이름은
        -- `checkedUnits`다(`dbver <= 5`가 옮기면서 `units`로 바꾼다). 최상단에서 조건
        -- 이름을 읽으면 DEBUG 함정이 터지는데(`Profile.lua`의 `ArmAction`), 여기는 그 옛
        -- 자리를 **일부러** 보는 유일한 자리다. 함정을 우회하는 것이 아니라, 함정이 잡으려는
        -- 실수가 아니라는 표시다.
        local storedUnits = (action.conditions and action.conditions.units)
            or rawget(action, "checkedUnits");
        if (storedUnits) then
            for unit, value in pairs(storedUnits) do
                -- **The pre-rename spelling is read here too.** A profile the ladder has not
                -- reached yet calls the pointed frame's unit `hover`, and the legacy lift just
                -- below writes `unitframe` -- so left alone, one unit arrives as two columns,
                -- which is the split the fold exists to remove. `dbver <= 6` renames what is
                -- stored; this is the same rule on the copy, for the profiles it has not met.
                if (unit == "hover") then
                    unit = "unitframe";
                end
                local condition, unreadable = UnitConditionForBinding(value);
                if (unreadable) then
                    -- 이 빌드가 못 읽는 값이 하나라도 있으면 바인딩을 판정에서 뺀다
                    -- (`BuildUnitStates`가 이 표시를 `unitStatesOpaque`로 바꾼다).
                    binding.unitConditionUnreadable = true;
                end
                if (condition ~= nil) then
                    conditions.units = conditions.units or {};
                    conditions.units[unit] = condition;
                end
            end
        end

        -- Same idea for the old hover pair. It is raised **onto the copy**, never onto the
        -- action: `Profile.lua`'s migration owns rewriting what is stored, and an action this
        -- reached first would otherwise be rewritten by whoever read it.
        if (action.hover ~= nil) then
            conditions.units = conditions.units or {};
            conditions.units.unitframe = UnitFrameConditionFromLegacy(
                action.hover, action.reactions, conditions.units.unitframe);
        end

        -- The frame type mask, likewise raised onto the copy. It was a condition of its own until
        -- the pointed frame's unit became an ordinary unit (`dbver <= 6`); a profile the ladder has
        -- not reached carries it at the action's top level or right under `conditions`, and both
        -- have to be cleared off the binding or the name sits there as a condition nothing reads --
        -- which is enough to make an unconditional action rank as a conditional one
        -- (`IsConditionalBinding`).
        --
        -- **Only onto a condition that is a table.** Nothing else can hold an axis: the absent
        -- point is not a frame, and with no `unitframe` condition at all there is no frame to have
        -- a type. The mask is dropped there rather than inventing a condition nobody set.
        local legacyFrameTypes = action.frameTypes or conditions.frameTypes;
        conditions.frameTypes = nil;
        if (legacyFrameTypes ~= nil and legacyFrameTypes ~= Constants.FRAMETYPE_ALL) then
            local row = conditions.units and conditions.units.unitframe;
            if (type(row) == "table" and row.frameTypes == nil) then
                row.frameTypes = legacyFrameTypes;
            end
        end

        -- **Under the unit the twin aims at, not under a fixed name.** That is what narrows the
        -- twin's box to [the unit is there] on that unit's own axis (`BuildUnitStates`), which is
        -- what lets the original take the rest.
        --
        -- **The merge already happened.** `TwinUnitFor` hands over the reader's own condition where
        -- that unit carries one and `UNIT_IS_THERE` where it does not, so what is written here is
        -- the meeting point either way.
        if (twinCondition ~= nil) then
            conditions.units = conditions.units or {};
            conditions.units[pointedUnit] = twinCondition;
        end

        -- 커스텀 상태를 따로 도는 루프가 여기 있었다. 위 벌크 복사가 조건 표를 통째로
        -- 옮기므로 슬롯 다섯을 이름으로 세어줄 필요가 없고, 재설계가 임의 이름을 풀어도
        -- 이 자리가 안 바뀐다.

        -- **A type with no spell carries no `known` at all**, whatever the value is. The question
        -- does stand on its own now that the value names a spell
        -- (`devdocs/making-known-a-spell-name.md`), but no menu offers it on those types, so a
        -- value there is one the reader could not have made and cannot take off. `CleanUpDB` takes
        -- it out of storage for the same reason; this is the same rule on the binding.
        --
        -- **`false` has no state that satisfies it.** It would say "cast it only while it is
        -- unlearned" of the action's own spell, and it is checked against `false` rather than
        -- truthiness because nothing here writes one but a shared profile can carry one, and left
        -- in place it bakes the same conditional a `true` would.
        if (conditions.known == false or (conditions.known ~= nil
                and binding.type ~= Constants.SPELL
                and not Constants.SPEC_RESOLVED_TYPES[binding.type])) then
            conditions.known = nil;
        end

        -- `"@"` and an explicit condition on the same unit used to be folded into one key here, by
        -- hand, for the scalar shape. **Both consumers intersect them themselves now**:
        -- `BuildUnitStates` with `band` for the solver, and `mergeUnitConditions` per axis on the way
        -- to the snippet. Folding again would be a third copy of one rule, and the one that drifts is
        -- the one nothing checks.
        --
        -- **No target drops `"@"`, `none` included** (2026-09-15, owner). `none` is aimed like an
        -- action with no target and only its cast asks, so each binding of it has a unit to ask.

        if (conditions.groups and band(conditions.groups, Constants.GROUP_ALL) == Constants.GROUP_ALL) then
            conditions.groups = Constants.GROUP_ALL;
        end

        -- **`specs` is not folded, unlike the masks around it.** Those fold an all-on mask to the
        -- one value that says "every box ticked", so a condition constraining nothing has one
        -- shape rather than two. A set of specialization ids has no such value: the ids of one
        -- class are not an accident to normalize away, they are the class condition itself.

        if (conditions.forms and band(conditions.forms, Constants.FORM_ALL) == Constants.FORM_ALL) then
            conditions.forms = Constants.FORM_ALL;
        end

        if (conditions.bonusbars and band(conditions.bonusbars, Constants.BONUSBAR_ALL) == Constants.BONUSBAR_ALL) then
            conditions.bonusbars = Constants.BONUSBAR_ALL;
        end

        -- 대상을 못 갖는 타입이면 지운다. 목록은 `Constants.TYPES_WITH_UNIT` 하나뿐이다 -
        -- 대상 메뉴를 여는 쪽(`DropDownMenus.lua`)도 같은 값을 본다. 예전에는 여기와
        -- 저기에 같은 목록이 손으로 하나씩 적혀 있었고, 한쪽에만 타입을 넣는 바람에
        -- **화면에는 대상이 보이는데 나가는 매크로에는 없는** 상태가 나왔다.
        --
        -- **Not on a twin.** A twin of an action that takes no unit still carries `player` or
        -- `focus`, which is what the client's `UnitExists` guard reads: the press stops where there
        -- is no focus, as it does on an action bar.
        --
        -- **`none` keeps no unit here and goes out as `none` all the same** (`CastUnitOf`). Left in
        -- `unit`, it would be where `"@"` is asked and where the `unitframe` condition fills in, and neither
        -- has a unit to stand on there.
        binding.castsAtNone = (action.unit == "none" and DebindPrivate.ActionTakesUnit(binding)) or nil;
        if (twin) then
            binding.unit = aimedUnit;
        elseif (not Constants.TYPES_WITH_UNIT[binding.type]) then
            binding.unit = nil;
        elseif (not DebindPrivate.ActionTakesUnit(binding)) then
            -- The type alone does not settle a pet command or an action button, and the target menu
            -- asks the same question. Cleared here too, or a unit left in an old profile goes out.
            binding.unit = nil;
        elseif (binding.castsAtNone) then
            binding.unit = nil;
        end

        -- **Every original stands on [none held]**, whatever its type or target: every action has
        -- the self and focus twins, so a held modifier is answered among those and never by an
        -- original placed ahead of them (`devdocs/implementing-focus-and-self-cast.md` §3-4).
        binding.castModifier = castModifier or Constants.CASTMOD_NONE;
        binding.hoverTwin = pointedUnit ~= nil or nil;

        -- **An action that takes no unit keeps `"@"`** (2026-09-15, owner). It asks the unit the
        -- press aims at, and whether the action does anything with that unit cannot be known: every
        -- action has the self and focus twins, and a macro body can aim wherever it likes.

        if (conditions.petbattle and conditions.specialbar) then
            conditions.specialbar = nil;
        end

        -- **A unit frame condition fills no target in.** With no unit picked the original lets the
        -- game place the cast, condition or no condition (`devdocs/which-action-a-key-runs.md` §5);
        -- the pointed unit is reached through the hover twin, which is what the condition's own
        -- action is carried over as (§8). The fill-in that used to sit here put `unitframe` in
        -- `unit`, which made an ordinary press over nothing cast at a unit that was not there.

        -- **Hover Cast's Skip stands the original on [the mode's unit is not there]**, and it is not
        -- written into `conditions`: that table is what `IsConditionalBinding` orders by, and a Cast
        -- Options value must not move the action. `BuildUnitStates` and the record read the field,
        -- the way the mouse button's implicit [no unit frame] already stays out of the table.
        --
        -- **A condition on that unit leaves nowhere to stand, and only the original goes.** Left to
        -- the solver it is a zero mask, which is `CONDITIONS_NEVER`, an ERROR, and that takes the
        -- held-key twins off the key with it (`devdocs/which-action-a-key-runs.md` §6).
        binding.skipsPointedUnit = nil;
        if (not twin and DebindPrivate.HoverCastSkipped(action)) then
            local unit = DebindPrivate.HoverCastMode(action);
            local units = conditions.units;
            local own = units and units[unit];
            -- An `if`, not `and`: a `"@"` on another unit has to come out nil, and `and` answers false.
            local resolved;
            if (units and ResolvedUnitOf(binding) == unit) then
                resolved = units["@"];
            end
            if (type(own) == "table" or type(resolved) == "table") then
                binding.normalCast = false;
            elseif (own ~= false and resolved ~= false) then
                binding.skipsPointedUnit = unit;
            end
        end

        BuildUnitStates(binding);

        return binding;
    end

    function DebindPrivate.GetBindingInfoForAction(action)
        local binding = _ActionToBindingCache[action];

        if (not binding) then
            binding = {};
            _ActionToBindingCache[action] = binding;
        end

        return FillBinding(binding, action, action.unit, nil);
    end

    --- The account-wide switch over every switch's own message box. Off silences them all without
    --- touching what any box holds. Absent means on, so a profile written before it reads as on.
    function DebindPrivate.SwitchMessagesEnabled()
        local options = DebindPrivate.Options;
        return not (options and options.switchMessages == false);
    end

    --- One row of `action.casting`, always a table so a reader can index it. **The stored table is
    --- not trusted to hold one**: a payload carries whatever it was written with, and the import
    --- filters `casting` by the name and the type of the outer table alone.
    local EMPTY_CASTING_ROW = {};
    local function CastingRow(action, name)
        local casting = action and action.casting;
        local row = casting and casting[name];
        if (type(row) ~= "table") then
            return EMPTY_CASTING_ROW;
        end
        return row;
    end

    --- Whether that press's twin goes out at the unit the press names, or the way the original does.
    --- "Cast as usual" is the second: the twin keeps its turn in that tier and lets the game place
    --- the cast, Auto Self Cast included (`devdocs/which-action-a-key-runs.md` §6).
    local function CastsAsUsual(action, name)
        return CastingRow(action, name).aim == "usual";
    end

    --- The settings tab's Hover Cast mode, which an action follows unless it names one of its own.
    --- Absent reads as Unit Frames, because that is where the condition it replaces stood
    --- (`devdocs/which-action-a-key-runs.md` §8).
    function DebindPrivate.AccountHoverCastMode()
        local options = DebindPrivate.Options;
        if (options and options.hoverCastMode == "mouseover") then
            return "mouseover";
        end
        return "unitframe";
    end

    --- The unit this action counts as pointed at. **`hover` is a name storage uses and this is where
    --- it stops**: everything below reads `unitframe` or `mouseover`
    --- (`devdocs/which-action-a-key-runs.md` §0).
    ---
    --- **A skipped action has a mode too**: it names the unit whose presence takes the action off the
    --- press (`HoverCastSkipped`).
    ---
    --- **Asked of no action it answers the account's mode**, which is what the settings tab shows.
    function DebindPrivate.HoverCastMode(action)
        local mode = CastingRow(action, "hoverCast").mode;
        if (mode == "unitframe" or mode == "mouseover") then
            return mode;
        end
        return DebindPrivate.AccountHoverCastMode();
    end

    --- Whether Debind answers the Self Cast Key and the Focus Cast Key for this action. **Absent
    --- means on** on both levels, which is how every key behaved before either value existed. Off is
    --- no twin and no question at the press, never the game's own handling
    --- (`devdocs/implementing-focus-and-self-cast.md` §3-12).
    ---
    --- **The account's box and the action's value are one answer.** With the box off the tier is not
    --- built at all, so the action's value has nothing to say there
    --- (`devdocs/which-action-a-key-runs.md` §6); asked of no action, this is the box alone, which
    --- is what the emitter wires the press up from.
    function DebindPrivate.SelfCastEnabled(action)
        local options = DebindPrivate.Options;
        if (options and options.selfCast == false) then
            return false;
        end
        return CastingRow(action, "selfCastKey").aim ~= "skip";
    end

    function DebindPrivate.FocusCastEnabled(action)
        local options = DebindPrivate.Options;
        if (options and options.focusCast == false) then
            return false;
        end
        return CastingRow(action, "focusCastKey").aim ~= "skip";
    end

    --- Whether Skip this action is Hover Cast's answer: no twin, and the original stands only while
    --- the mode's unit is not there, so the action is out of the pointed press the way a skipped
    --- key's action is out of that key's (`devdocs/which-action-a-key-runs.md` §6).
    function DebindPrivate.HoverCastSkipped(action)
        return CastingRow(action, "hoverCast").aim == "skip";
    end

    --- Whether the action stands on a press with nothing held and nothing pointed at. Off is the
    --- original not being made, so the press falls through to the next action on the key -- which is
    --- what the old [when a frame is pointed at] condition did, without swallowing the press
    --- (`devdocs/which-action-a-key-runs.md` §6).
    function DebindPrivate.NormalCastEnabled(action)
        local casting = action and action.casting;
        return not (casting and casting.normalCast == false);
    end

    local _ActionToBindingsCache = setmetatable({}, { __mode = "k" });
    local _ActionToTwinCache = setmetatable({}, { __mode = "kv" });
    local _ActionToProbeCache = setmetatable({}, { __mode = "kv" });
    local _ActionToProbeTwinCache = setmetatable({}, { __mode = "kv" });
    local _ActionToFocusCache = setmetatable({}, { __mode = "kv" });
    local _ActionToProbeFocusCache = setmetatable({}, { __mode = "kv" });
    local _ActionToSelfCache = setmetatable({}, { __mode = "kv" });
    local _ActionToProbeSelfCache = setmetatable({}, { __mode = "kv" });

    -- The stored shape of "that unit, whatever it is" is an empty table (`false` is [when there is
    -- none]); the emitter indexes it, so it cannot be `true`. Read-only downstream, hence one table.
    --
    -- **This is what keeps the twin from deleting the original.** Empty reads as
    -- `UNITSTATE_EXISTS` (`UnitConditionToState`), so the twin's box is the half of the axis where
    -- the unit is there and the original still covers the other half. A twin standing with no
    -- condition at all would cover the original, the solver would drop it, and the key would do
    -- nothing at the moment nothing is pointed at.
    local UNIT_IS_THERE = {};

    --- The hover twin, as three answers: the pointed unit its condition stands under, that
    --- condition, and the unit it goes out at. nil where the action gets none.
    ---
    --- **One rule, and the special cases are gone** (`devdocs/which-action-a-key-runs.md` §4). The
    --- twin inherits every condition the reader wrote, adds [the pointed unit is there] on the unit
    --- the action's mode names, and goes out at that unit. A condition the reader wrote is never
    --- widened, and a unit the reader picked is never moved.
    ---
    --- **Every action gets one unless its Hover Cast says Skip this action**, because the twin is
    --- what gives an action a place in the tier a pointed press is decided in
    --- (§3). An action left without one waits in the last tier, and a Hover Cast action behind it
    --- takes every press made over a unit, however high the reader put the first.
    ---
    --- **A condition the reader put on that unit is narrowed into, never replaced** (2026-09-12,
    --- owner). The twin says [the unit is there] and the reader may have said [it is hostile]; the
    --- two meet at [it is hostile], which is the reader's own table, since `UNIT_IS_THERE` constrains
    --- nothing. Replacing was measured on 2026-09-12: an action aimed at `target` that runs [when the
    --- mouseover unit is hostile] came out with a twin wider than its original on that axis, the
    --- solver deleted the original, and the key fired at whatever the cursor was over.
    ---
    --- **[when there is none] is the one that has no meeting point.** The twin only stands while that
    --- unit is there, so it could never match, and no twin is made.
    ---
    --- **Public because the issue check asks the same question** and must not answer it twice: "no
    --- twin" is half of what makes an action with nothing left to cast, and a second copy of this
    --- rule would drift from the one that builds the bindings.
    local function TwinUnitFor(action, original)
        if (DebindPrivate.HoverCastSkipped(action)) then
            return nil;
        end
        local unit = DebindPrivate.HoverCastMode(action);

        local units = original.conditions and original.conditions.units;

        local existing = units and units[unit];
        if (existing == false) then
            return nil;
        end

        local aim = unit;
        if (DebindPrivate.ActionHasPickedUnit(action) or CastsAsUsual(action, "hoverCast")) then
            aim = original.unit;
        end

        return unit, existing or UNIT_IS_THERE, aim;
    end

    DebindPrivate.TwinUnitFor = TwinUnitFor;

    --- Every binding one action puts on its key, in place: `[1]` is the original
    --- (`GetBindingInfoForAction`'s table) and what follows is derived. `BuildKeyMap` sorts the
    --- originals and lays the key out in tiers after the sort, so only a hover twin has a placement
    --- of its own (`devdocs/implementing-focus-and-self-cast.md` §3-4).
    function DebindPrivate.GetBindingsForAction(action)
        local list = _ActionToBindingsCache[action];
        if (not list) then
            list = {};
            _ActionToBindingsCache[action] = list;
        end

        local original = DebindPrivate.GetBindingInfoForAction(action);
        list[1] = original;
        local n = 1;

        -- **The warlock's dispel is two bindings.** The original casts the player's own Singe Magic
        -- and a derived one casts the pet's through Command Demon, gated at the press by
        -- `FindSpellBookSlotBySpellID` (`SpecSpells.lua`). Every binding here gets its own probe,
        -- which stays right ahead of it in whichever tier it lands.
        --
        -- **The list is filled back to front.** `BuildKeyMap` walks a list from its last entry down,
        -- so each probe is written after the binding it goes ahead of.
        local probe;
        if (original.spell ~= nil) then
            probe = select(2, DebindPrivate.SpecSpells.SpellForType(action.type));
        end

        local function fill(cache, aimedUnit, twinCondition, spell, castModifier, pointedUnit)
            local binding = cache[action];
            if (not binding) then
                binding = {};
                cache[action] = binding;
            end
            FillBinding(binding, action, aimedUnit, twinCondition, castModifier, pointedUnit);
            if (spell) then
                binding.spell = spell;
                binding.spellbook = spell;
            end
            n = n + 1;
            list[n] = binding;
        end

        local pointedUnit, pointedCondition, pointedAim = TwinUnitFor(action, original);
        local focusTwin, selfTwin = DebindPrivate.FocusCastEnabled(action), DebindPrivate.SelfCastEnabled(action);

        -- **Four values off is an action with no bindings at all** (`devdocs/which-action-a-key-runs.md`
        -- §6). It is not blocked: the issue check raises a WARNING and the row wears it, and the key
        -- carries on with whatever else is on it. Answered before anything is filled, so the caches
        -- keep the tables they had. **The original's mark, not the stored box**: Skip can take the
        -- original away as well (`FillBinding`).
        if (original.normalCast == false and not pointedUnit
                and not focusTwin and not selfTwin) then
            for i = 1, #list do
                list[i] = nil;
            end
            return list;
        end

        if (probe) then
            fill(_ActionToProbeCache, action.unit, nil, probe);
        end
        if (pointedUnit) then
            fill(_ActionToTwinCache, pointedAim, pointedCondition, nil, Constants.CASTMOD_NONE, pointedUnit);
            if (probe) then
                fill(_ActionToProbeTwinCache, pointedAim, pointedCondition, probe, Constants.CASTMOD_NONE,
                    pointedUnit);
            end
        end

        -- **Twins on every action, a picked unit and one that takes no unit included**: the original
        -- stands on [none held], so a held modifier has nothing else to land on. A picked unit keeps
        -- its twins aimed at itself (`ActionHasPickedUnit`), which is what keeps its place in the held
        -- tier.
        --
        -- "Cast as usual" keeps the twin and aims it where the original aims, so the action holds its
        -- turn in that tier without using the key's unit. Skip this action is the other value and it
        -- is answered above, where the twin is not made at all.
        -- **개체창 위에서 눌리는 마우스 버튼에는 조합키 쌍둥이가 없다** (2026-09-16, 소유자;
        -- `devdocs/which-action-a-key-runs.md` §7). 개체창 클릭은 조합키 칸이 늘 [없음]이라 1·2층을
        -- 안 돌고, 그 액션은 키를 안 잡으므로 키 경로로도 그 누름이 안 온다. 받을 누름이 없는
        -- 레코드라 만들면 솔버가 상자만 둘 더 세고, 키를 잡아 맨 왼쪽 클릭을 세상에서 가져간다.
        if (DebindPrivate.GetMouseButtonAndPrefix(action.key)
                and DebindPrivate.ActionUnitFrameIsOn(action)) then
            focusTwin, selfTwin = false, false;
        end

        local focusAim, selfAim = "focus", "player";
        if (DebindPrivate.ActionHasPickedUnit(action)) then
            focusAim, selfAim = original.unit, original.unit;
        end
        if (CastsAsUsual(action, "focusCastKey")) then
            focusAim = original.unit;
        end
        if (CastsAsUsual(action, "selfCastKey")) then
            selfAim = original.unit;
        end
        if (focusTwin) then
            fill(_ActionToFocusCache, focusAim, nil, nil, Constants.CASTMOD_FOCUS);
            if (probe) then
                fill(_ActionToProbeFocusCache, focusAim, nil, probe, Constants.CASTMOD_FOCUS);
            end
        end
        if (selfTwin) then
            fill(_ActionToSelfCache, selfAim, nil, nil, Constants.CASTMOD_SELF);
            if (probe) then
                fill(_ActionToProbeSelfCache, selfAim, nil, probe, Constants.CASTMOD_SELF);
            end
        end

        for i = n + 1, #list do
            list[i] = nil;
        end

        return list;
    end

    --- The list as the last `GetBindingsForAction` left it, without refilling. For readers that
    --- only need the tables as keys (`Solver.lua`'s unreachable cache, filled by the last
    --- `BuildKeyMap` from these same tables): refilling would cost a full normalization per call
    --- and change nothing they read. nil for an action never derived, which is one no key map holds.
    function DebindPrivate.PeekBindingsForAction(action)
        return _ActionToBindingsCache[action];
    end
end

local GetBindingInfoForAction = DebindPrivate.GetBindingInfoForAction


-- GetMouseButtonAndPrefix는 Solver.lua가 쓰는데 그쪽이 먼저 로드되므로 Constants.lua에 있음

function DebindPrivate.IsConditionalAction(action)
    local binding = GetBindingInfoForAction(action);
    return DebindPrivate.IsConditionalBinding(binding);
end

--- The record `CompareActionOrder` reads, and **the only place its shape is written.**
---
--- Three callers build one: `Debind.lua`'s `BuildKeyMap`, and `Profile.lua`'s `MakeRow` and
--- `RenumberKeyGroup`. Each used to spell the fields out for itself, and the three lists had
--- drifted apart -- they are never sorted against each other, so nothing was wrong today and
--- nothing would have said so on the day one of them lost a field.
---
--- **Where an action stands is the one thing not derived from the action.** `priority` and
--- `isConditional` are; `layerRank`, `specRank` and `seq` are its place in the profile. Those
--- last three used to be written onto the binding from outside, which left the binding a pure
--- function of its action by convention rather than in fact.
---
--- `dest` lets a caller hand its own table in. `BuildKeyMap` keeps one per binding and rebuilds
--- in place, because it runs over every bound action on every rebuild and used to allocate
--- nothing at all.
---
--- **One record per action, twins included.** Every tier stands in the originals' order, which is
--- the order the window draws (`devdocs/which-action-a-key-runs.md` §2), so a twin is never ordered
--- against anything on its own terms.
function DebindPrivate.MakeOrderRecord(action, layerRank, specRank, dest)
    local binding = GetBindingInfoForAction(action);
    dest = dest or {};
    dest.priority = action.priority or Constants.DEFAULT_IMPORTANCE;
    dest.isConditional = DebindPrivate.IsConditionalBinding(binding);
    dest.layerRank = layerRank;
    dest.specRank = specRank;
    dest.seq = action.seq;
    return dest;
end

--- Every specialization one class has, in the client's order, as `{ id = , name = }`.
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
            out[#out + 1] = { id = id, name = name };
        end
    end
    local initialID = GetSpecializationInfoForClassID(classID, Constants.INITIAL_SPEC_INDEX);
    if (initialID) then
        out[#out + 1] = { id = initialID };
    end
    return out;
end

local specCatalog, specsByClassID;
local EMPTY_SPECS = {};

--- Every class somebody can play, in the client's own order, each carrying its specializations
--- (`EnumerateClassSpecs`). The one enumeration behind both places that draw specializations by
--- name: the condition menu groups it and the tooltip flattens it.
---
--- **Not `Constants.CLASS_IDS`, which holds more than the playable classes.** That table is built
--- from `C_CreatureInfo.GetClassInfo` over a range of ids, and ids nobody can play answer it too:
--- `Adventurer` came out as a class of its own in the condition menu. `GetNumClasses` with
--- `GetClassInfo` is what the client's own class menu walks (`Blizzard_ClassMenu`), and its index
--- is a position in that list rather than a class id, so the id comes back as a return value.
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
    specsByClassID = {};
    for index = 1, GetNumClasses() do
        local _, classFile, classID = GetClassInfo(index);
        if (classFile and classID) then
            local entry = {
                id = classID,
                classFile = classFile,
                specs = DebindPrivate.EnumerateClassSpecs(classID),
            };
            specCatalog[#specCatalog + 1] = entry;
            specsByClassID[classID] = entry.specs;
        end
    end
    return specCatalog;
end

--- One class's specializations off the catalog, so the two below cost a table lookup rather than
--- a walk of the client's specialization calls. **They are on paths that run per draw**: the
--- whole-class checkbox asks the first of these every time the menu redraws, and the tooltip line
--- asks it once per class per draw. Empty for a class nobody plays, which is a class the catalog
--- does not carry.
local function ClassSpecsOf(classID)
    if (specsByClassID == nil) then
        DebindPrivate.ClassSpecCatalog();
    end
    return specsByClassID[classID] or EMPTY_SPECS;
end

local SPEC_LINE_NAME_LIMIT = 3;

--- Does this set hold **every** specialization of one class, which is what a class condition is.
---
--- **One answer for the two places that ask.** The menu's whole-class box is ticked by it and the
--- line above folds a class to its name by it, so the box and the words cannot disagree about
--- what a whole class is.
function DebindPrivate.SpecSetHoldsClass(specs, classID)
    if (specs == nil) then
        return false;
    end
    local classSpecs = ClassSpecsOf(classID);
    if (#classSpecs == 0) then
        return false;
    end
    for i = 1, #classSpecs do
        if (specs[classSpecs[i].id] == nil) then
            return false;
        end
    end
    return true;
end

--- Put one whole class into the set, or take it out. **The initial specialization goes in with
--- the rest**: it is a state a character of that class can be sitting in, so leaving it out would
--- make "while I am a druid" false in one of the worlds it names.
function DebindPrivate.SetClassInSpecSet(specs, classID, turnOn)
    local classSpecs = ClassSpecsOf(classID);
    for i = 1, #classSpecs do
        specs[classSpecs[i].id] = turnOn or nil;
    end
    return specs;
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
            if (specs[classSpecs[j].id] ~= nil) then
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
    -- **An empty set is not another specialization's.** No specialization satisfies it, so a
    -- reader waiting for the right one to come round will wait forever: the action is wrong, and
    -- it already has a word for that (`BINDING_ISSUE_SPECS_NONE_SELECTED`).
    --
    -- Every caller here is asking the same question, "does this belong to a world other than the
    -- one on screen", and for an empty set the answer is no. Answering `false` instead put it in
    -- the same bucket as an off-specialization action three times over: `BuildKeyMap` left it out
    -- of `ActiveActions`, so the key heading -- which asks only active rows whether one is broken
    -- -- drew plain over a dead key while the row under it showed the error; and the tooltip added
    -- "not the one being played" beside a line already saying nothing was chosen.
    --
    -- **The error gate is what keeps it off the key**, the same gate every other ERROR goes
    -- through (`Debind.lua`). Nothing is lost by letting it past this one.
    if (next(specs) == nil) then
        return true;
    end
    if (spec == nil) then
        spec = C_SpecializationInfo.GetSpecialization();
    end
    local specID = DebindPrivate.SpecIDForIndex(spec);
    if (specID == nil) then
        return false;
    end
    return specs[specID] ~= nil;
end

--- Does this binding's `known` condition have a spell to ask about? **The second condition the
--- insecure side settles by itself**, for the same reason as the one above: a spec-resolved type
--- asks about the spell this specialization resolves to (`binding.spell`), a specialization that
--- has none leaves the condition false for every press in this build, and a specialization change
--- rebuilds everything.
---
--- What this binding's `known` condition asks about: the spell it names, or the action's own spell
--- where it says `true` (`devdocs/making-known-a-spell-name.md`). nil where there is no condition,
--- and where `true` has no spell to fall back on.
---
--- **One answer for the three places that ask.** The conditional baked into the record, the
--- solver's column key and the overview's "no spell" mark all have to name the same thing, and
--- they used to spell the derivation out one at a time.
--- A boolean is the shape that asks about the action, and `false` is one of those: it never
--- reaches storage (`GetBindingInfoForAction` strips it) but the solver models both answers on one
--- axis, and both are about the same spell.
---
--- **The action's spell is named too** (2026-09-12, owner). What goes out is then one shape
--- whatever the condition stored, and two actions asking about the same spell share a state key
--- even when one of them is a `Dispel` and the other holds the spell itself. The id is what is
--- left when the client cannot name it, which is where `[known:]` answers false anyway.
function DebindPrivate.KnownSpellAsked(binding)
    local asked = binding.conditions and binding.conditions.known;
    if (asked == nil) then
        return nil;
    end
    if (type(asked) == "boolean") then
        local spell = binding.spell or binding.value;
        return spell and (GetSpellNameAndIconID(spell) or spell);
    end
    return asked;
end

--- **Only `true` can answer no**, because only `true` asks about the action
--- (`devdocs/making-known-a-spell-name.md`). A condition carrying a spell of its own asks the same
--- question whatever this specialization resolves to, and a specialization that cannot answer it
--- is answering false rather than having nothing to answer.
---
--- Only those three types can answer no. Every other type asks about a value the action stores,
--- which is there or the action would not have been built.
function DebindPrivate.KnownConditionCanHold(binding)
    local conditions = binding.conditions;
    if (conditions == nil or conditions.known ~= true) then
        return true;
    end
    if (not Constants.SPEC_RESOLVED_TYPES[binding.type]) then
        return true;
    end
    return binding.spell ~= nil;
end

--- 이 바인딩에 조건이 하나라도 걸려 있나. 발동 순서의 세 번째 단계가 이걸 읽는다
--- (`Ordering.lua`).
---
--- 축마다 `nil` 검사를 쓴 열두 갈래가 여기 있었다. 축이 하나 늘 때마다 갈래를 잊으면 그 조건이
--- 걸린 바인딩이 무조건짜리로 분류돼 **발동 순서가 조용히 바뀌었고**, 그 잘못은 화면에
--- 아무것도 안 남긴다.
---
--- **바인딩 쪽 표는 비어 있을 수 있다.** 리빌드마다 제자리에서 다시 채우느라 늘 존재하기
--- 때문이다(`GetBindingInfoForAction`). 저장 쪽은 반대로 빈 표를 안 남긴다(`CleanUpDB`).
---
--- **표에 든 것은 전부 조건이다.** 이 애드온이 쓰는 이름 밖의 것은 여기까지 오는 길이 없다.
--- 저장 쪽은 `CleanUpDB`가 걷어내고, 가져오기는 그런 이름을 실은 문자열을 통째로 거절한다
--- (`Import.lua`의 `IsUsableAction`). 손으로 고친 SavedVariables는 방어하지 않는다.
function DebindPrivate.IsConditionalBinding(binding)
    local conditions = binding.conditions;
    return conditions ~= nil and next(conditions) ~= nil;
end

function DebindPrivate.IsInactiveAction(action)
    return not DebindPrivate.ActiveActions[action];
end

--- What to write where a key goes. **Not for a nil key** -- what an action with no key at all reads
--- as differs by where it is shown, so each of those places says its own word.
---
--- **A key is a binding string and nothing else.** This used to take a second argument and to guard
--- against a number, because a set whose key the reader had not decided sat on one and the heading
--- had to be told separately which key it had come in on. An arrival keeps the key it was sent on,
--- so the key names it (`devdocs/building-export-import.md` 12절) and there is no second thing left
--- to say.
function DebindPrivate.GetKeyDisplayText(key)
    return GetBindingText(key);
end

--- 게임 메뉴(기본 ESC) 키를 다시 읽는다. `IsKeyInvalidForAction`이 이 두 값으로 막는다.
---
--- **이게 없어서 그 가드가 죽어 있었다.** `gmKey1`/`gmKey2`를 읽는 곳은 있는데 쓰는 곳이
--- 없어서 비교가 늘 `key == nil`이었다. ESCAPE를 걸면 아무 경고 없이 `SetOverrideBinding`이
--- 올라가서 게임 메뉴가 안 열렸고, `BINDING_ERROR_NOT_SUPPORTED_GAMEMENU_KEY`는 도달할 수
--- 없는 문자열이었다.
---
--- 부르는 쪽에서 매번 `GetBindingKey`를 하지 않고 값으로 들고 있는 이유는 아래 함수가
--- **목록을 그릴 때 행마다** 불리기 때문이다. 갱신은 `UpdateBindings`가 돌 때 한 번이고,
--- 바인딩이 바뀌면 `UPDATE_BINDINGS`가 그걸 부른다(`Events.lua:75`). 사용자가 게임 메뉴
--- 키를 안 걸어뒀으면 둘 다 nil이라 가드가 저절로 비켜간다.
function DebindPrivate.RefreshGameMenuKeys()
    DebindPrivate.gmKey1, DebindPrivate.gmKey2 = GetBindingKey("TOGGLEGAMEMENU");
end

--- "이 액션에 개체창 조건이 켜져 있는가"를 **액션에서 바로** 답한다.
---
--- `UnitFrameConditionOf`를 쓰면 될 것 같지만, 아래 함수는 목록을 그릴 때 **행마다** 불린다 -
--- `GetBindingInfoForAction`을 거치면 그때마다 바인딩을 통째로 다시 만든다. 필요한 것은
--- 한 축뿐이라 여기서 읽는다.
---
--- 마이그레이션이 안 닿은 프로필(`action.hover`)도 `UnitFrameConditionFromLegacy`와 같은 답을
--- 내야 한다. 저장된 조건이 있으면 그쪽이 이긴다 - 접기가 교집합하는 것과 같은 순서다.
--- **공개다.** 세 자리가 이 한 물음을 쓴다: 왼/오른쪽 버튼 유효성(`IsKeyInvalidForAction`), 그 키를
--- 우리가 잡느냐(`BuildKeyMap`의 `KeysToHold`), 그리고 조합키 쌍둥이를 만드느냐
--- (`GetBindingsForAction`). 같은 물음에 답하는 자리가 둘이면 갈린다.
function DebindPrivate.ActionUnitFrameIsOn(action)
    -- **개체창 위에서만 도는 액션은 조건 없이도 있다.** Normal Cast를 끄고 Hover Cast를 Unit
    -- Frames로 둔 액션이 그것이고, 옛 개체창 조건 액션이 그 모양으로 옮겨 온다
    -- (`devdocs/which-action-a-key-runs.md` §8). 조건만 보면 그 액션들이 마우스 왼/오른쪽 버튼에서
    -- 통째로 빨개진다 - 조건이 안 적히는 것이 옮기기의 규칙이라 아무도 그것을 되돌릴 수 없다.
    --
    -- **Normal Cast가 켜져 있으면 안 센다.** 그때는 원본이 개체창 밖의 누름을 받아 키를 잡으므로
    -- (`PrepareKeyBindings`의 `holdsKey`), 맨 왼쪽 클릭이 세상에서 사라진다. 그것이 이 문장이
    -- 막는 것이다.
    local casting = action.casting;
    if (casting and casting.normalCast == false
            and not DebindPrivate.HoverCastSkipped(action)
            and DebindPrivate.HoverCastMode(action) == "unitframe") then
        return true;
    end

    local condition = DebindPrivate.StoredUnitFrameCondition(action);
    if (condition == nil) then
        return action.hover == true;
    end
    -- **접어서 본다.** 저장 원문에는 끈 조건도 남아 있어서 `{ exists = false }`도 `{ disabled = true }`도
    -- 표라는 이유만으로 "켜짐"이 된다. 바인딩 쪽과 정반대 답을 내면 왼/우클릭 유효성이 뒤집힌다.
    local folded = UnitConditionForBinding(condition);
    return folded ~= nil and folded ~= false;
end

function DebindPrivate.IsKeyInvalidForAction(action, key)
    local unitFrameIsOn = DebindPrivate.ActionUnitFrameIsOn(action);
    if (key == DebindPrivate.gmKey1 or key == DebindPrivate.gmKey2) then
        return Constants.BINDING_ISSUE_NOT_SUPPORTED_GAMEMENU_KEY;
    elseif ((key == "BUTTON1" or key == "BUTTON2") and not unitFrameIsOn) then
        return Constants.BINDING_ISSUE_NOT_SUPPORTED_MOUSE_BUTTON;
    end
end

--- The first switch this action names that nothing defines, or nil.
---
--- **An action names a switch in four places, and they fail in different directions.**
---
--- One is a condition key, `action.conditions["$burst"]`. That one is already harmless and already
--- dead: codegen bakes the condition whether or not anything defines the name, and the restricted
--- side compares `States[name] ~= v` against a `nil`, so the binding matches on neither `true` nor
--- `false`. **Which is exactly why it needs saying out loud** -- the row draws like any other
--- conditional binding and the key does nothing, for ever, with no reason on screen. It could not
--- happen until §6-B: the five always had definitions, and the `dbver` 6 step keeps every
--- definition a condition still names. Deleting a switch is what makes it reachable, along with an
--- imported string naming one this profile never had.
---
--- Another is hand-written macro text, the one place a name is typed rather than picked:
--- `ParseMacroText` lets any `[a-zA-Z0-9_]+` through, and a name nothing defines used to reach
--- codegen and bake to `""` -- `[$typo]` became `[]`, which is **always true**. In a keybinding
--- addon that is the worst direction to fail in: the binding does not stop firing, it starts
--- firing everywhere.
---
--- The third is the target of an on/off/toggle action, which is `action.value`. That one is picked
--- from a list, so it cannot be mistyped. But the switch it was picked for can be deleted
--- afterwards, and a string from someone else arrives naming switches this profile has never had,
--- because an import plants no definitions (`devdocs/building-export-import.md`). Nothing goes
--- wide there: the press sets a name nothing reads and the row draws clean. **Which is the
--- problem.** The reader's only sign that the key does nothing is that nothing happens, and this
--- mark is the only thing that can say so out loud.
---
--- The last is that same target after [Convert to macro text] has opened it out into
--- `/click DebindStates $burst-on` (`ForEachClickedSwitch`). It fails the way the third one does,
--- and it is here because otherwise converting an action would be a way of taking the mark off it.
---
--- Either way the action is marked, which keeps it out of `KeyMap` entirely (`Debind.lua`'s
--- `not issue` gate). Dropping the switch action loses nothing that was working: it was a key that
--- did nothing on press, the same trade the `MISSING_MACRO` branch below already makes.
---
--- **The question is whether anything defines the name**, which is `ResolveSwitchDefinition` and
--- nothing else (`Profile.lua`). It used to be whether the name was one of the five, from when
--- those five always had a definition whether anybody had made one or not.
---
--- That makes this and codegen ask the same door, which they did not before: this side read the
--- name off the parser and codegen read what the compile had found. They are the same answer now,
--- and it has to stay that way -- a name codegen bakes to `known:0` with no mark on the action is
--- a binding whose macro quietly lost a clause.
---
--- Not memoized on purpose: `ParseMacroText` caches its own result per string, so a repeated
--- call here is a table lookup plus a walk over a handful of args.
--- The switch this action's **conditions** name that nothing defines, or nil.
---
--- Split out from the whole answer below because the condition menu asks exactly this: it colours
--- the box that owns switch conditions, and a macro body's typo must not turn that box red -- the
--- conditions in it would be fine and the reader would go looking in the wrong place
--- (`CreateSwitchConditionMenu`).
---
--- **The lowest name, not the first one `pairs` hands over.** One name gets printed, and a message
--- that names a different one each time it is opened cannot be acted on. Compared rather than
--- sorted, since this runs once per row while a list is drawn.
function DebindPrivate.GetUndefinedSwitchCondition(action)
    local conditions = action.conditions;
    if (not conditions) then
        return nil;
    end

    local undefined;
    for name in pairs(conditions) do
        if (Constants.IsSwitchName(name) and (undefined == nil or name < undefined)
                and not DebindPrivate.ResolveSwitchDefinition(name)) then
            undefined = name;
        end
    end
    return undefined;
end

function DebindPrivate.GetUndefinedSwitch(action)
    -- **Conditions before the value, because they hang off every type.** A spell action carries a
    -- number and a command carries nothing, and both can be conditioned on a switch -- a guard on
    -- `action.value` in front of this would read the conditions of macro-shaped actions only.
    local condition = DebindPrivate.GetUndefinedSwitchCondition(action);
    if (condition) then
        return condition;
    end

    if (type(action.value) ~= "string") then
        return nil;
    end

    if (Constants.SETSTATE_MODES[action.type]) then
        if (DebindPrivate.ResolveSwitchDefinition(action.value)) then
            return nil;
        end
        return action.value;
    end

    if (action.type ~= Constants.MACROTEXT) then
        return nil;
    end

    local _, args = DebindPrivate.ParseMacroText(action.value);

    for i = 1, (args and #args or 0) do
        local arg = args[i];
        -- 부정형(`no$typo`)도 같이 잡는다. 그쪽은 지금도 거짓으로 떨어져 위험하지는 않지만
        -- 오타인 것은 똑같고, 한쪽만 말해주면 고쳐도 왜 아직 안 되는지 알 수 없다.
        if (arg.type == Constants.MACROTEXT_ARG_SWITCH
                and not DebindPrivate.ResolveSwitchDefinition(arg.name)) then
            return arg.name;
        end
    end

    -- **A body can work a switch as well as read one**, and the parser above only sees the reading.
    -- [Convert to macro text] opens an on/off/toggle action out into
    -- `/click DebindStates $burst-on`, so the reference the branch further up catches while it
    -- sits in `action.value` moves inside a string the moment the reader converts. Left out here,
    -- converting an action is a way to take the mark off it.
    return DebindPrivate.ForEachClickedSwitch(action.value, function(name)
        if (not DebindPrivate.ResolveSwitchDefinition(name)) then
            return name;
        end
    end);
end

--- The switch a computed switch's own `expr` names that nothing defines, or nil.
---
--- **A fifth place a name is written down, and the only one that is not in an action.** The four
--- above are asked of an action and answered by `GetUndefinedSwitch`; an `expr` belongs to a
--- definition, so there is no action to hand over and nothing above ever sees it. What that costs
--- is the quietest failure this system has: codegen bakes the dead name to `known:0`
--- (`EmitMacroTextArg` in `UpdateBindings.lua`), so the switch computed from it is false for ever
--- while its expression still reads correctly wherever it is drawn.
---
--- **Deleting is what makes it reachable, and leaving the reference behind is the design.** A
--- reference is kept so the reader can find it (`DeleteSwitch` in `Profile.lua`), which only works
--- while something is red. Renaming already rewrites this one; deleting has no rewrite to do and
--- so needs this instead.
---
--- **`ownerName` is not optional, and nil is not "no owner".** An expression naming its own switch
--- is erased rather than read (`EmitMacroTextArg` again) -- a defined name behaving oddly, not a
--- dead one. Passed nil, `[$a]` inside `$a` would be reported as broken.
---
--- **The first the parser hands over, not the lowest.** These arrive in the order they were typed,
--- unlike the condition keys above, so the first is already the same one on every draw and it is
--- the one nearest the start of the line the reader is looking at.
function DebindPrivate.GetUndefinedSwitchInExpr(expr, ownerName)
    if (type(expr) ~= "string") then
        return nil;
    end

    local _, args = DebindPrivate.ParseMacroText(expr);
    for i = 1, (args and #args or 0) do
        local arg = args[i];
        if (arg.type == Constants.MACROTEXT_ARG_SWITCH and arg.name ~= ownerName
                and not DebindPrivate.ResolveSwitchDefinition(arg.name)) then
            return arg.name;
        end
    end
end

--- The macro name this action points at, when nothing answers to it. nil when the action is fine
--- or is not a `MACRO` at all.
---
--- **This is the only check in the addon that asks whether an action's target exists**, and macros
--- are the only type that needs one. Every other type stores something the game resolves the same
--- way on every install -- a spell ID, an item ID, a mount ID -- so an action that names one either
--- resolves or names a thing that never existed anywhere. A macro name resolves against **this
--- computer's** macro store, which makes it the one reference that can be perfectly valid where it
--- was written and mean nothing here.
---
--- Which is why it could not be left out once strings started travelling between installs
--- (`devdocs/building-export-import.md`). Until now a `MACRO` naming nothing simply bound and
--- did nothing on press: `UpdateBindings` stamps `*macro-<button>` with the name and the secure
--- handler finds no macro, with no error and no mark anywhere on screen. The imported-actions rule
--- is "send broken things too, the reader sees red and deletes them" -- and this was the hole in
--- it, the fallback for a macro that was already dangling when it was sent.
---
--- **Deliberately not extended to the other types**, each for its own reason: item names arrive
--- from an async cache, so a nil there means "not loaded yet" as often as it means "no such item",
--- and a check that reds out a working binding for the first few seconds of a session is worse than
--- no check; spell and mount IDs the reader has not learned still resolve to a name, so there is
--- nothing to detect; `PETACTION` carries its own name and icon. Adding any of those would have to
--- start from evidence that the resolve failing means the target is gone.
function DebindPrivate.GetMissingMacroName(action)
    if (action.type ~= Constants.MACRO) then
        return nil;
    end

    -- **A macro reference is a name. A slot number is not one, at any moment.** `GetMacroInfo`
    -- answers to either, which is the trap: a number is not a reference at all, it is a **position
    -- in a list ordered by name**, and the position moves. Create or delete any macro that sorts
    -- ahead of it and the number now belongs to a different macro. The key then casts something
    -- nobody chose, and nothing goes red, because nothing broke.
    --
    -- **No sharing is involved.** This goes wrong on one account with one character, the day after
    -- the user names a new macro `Aa`. Which is why the rule sits here rather than anywhere near
    -- the export: a stored number is already wrong before it travels.
    --
    -- Nor can one be repaired into a name. Asking what slot 4 holds answers for the store as it is
    -- right now, and that is a guess at what was meant, not a recovery of it.
    --
    -- So a value that is not a string is reported missing rather than resolved, which drops the
    -- action out of `KeyMap` entirely (`GetBindingIssue` -> `BuildKeyMap`). Nothing in the addon
    -- writes one: the picker (`ActionCatalog.lua`) reads a name out of the index it is looping
    -- over, the cursor drop (`GetActionTypeAndValueFromCursorInfo`) does the same and builds no
    -- action when no name comes back, and `BuildAction` (`DebindStorage/Import.lua`) refuses the
    -- field on a pasted one. This is the backstop under all three.
    local value = action.value;
    if (type(value) ~= "string") then
        -- Truthy whatever it holds, so the action is flagged instead of bound. An action with no
        -- value at all has no reference to print, and the empty name is the honest answer: the
        -- tooltip still says no such macro is here, which is the whole of what is known.
        if (value == nil) then
            return "";
        end
        return tostring(value);
    end

    if (GetMacroInfo(value)) then
        return nil;
    end
    return value;
end

--- Does the key fire while something it was told to do is missing?
---
--- Not the complement of the one below it: `IssueKeepsKey`'s negation is the ERROR grade, and a
--- caller that wants exactly this one cannot get it from there.
---
--- Takes the code rather than the action because the callers have already asked for one, often for
--- a single category, and asking again would run the whole of `GetBindingIssue` a second time.
function DebindPrivate.IsIssueWarning(issue)
    return Constants.BINDING_ISSUE_GRADES[issue] == Constants.ISSUE_GRADE_WARNING;
end

--- An issue code's grade, defaulting to ERROR: a code with no row in `BINDING_ISSUE_GRADES` is a
--- code nobody graded, and the safe reading of that is the one that keeps the key off.
local function IssueGrade(code)
    return Constants.BINDING_ISSUE_GRADES[code] or Constants.ISSUE_GRADE_ERROR;
end

--- Does the key still fire with this problem on it? Everything but an ERROR does.
---
--- `BuildKeyMap`'s gate.
function DebindPrivate.IssueKeepsKey(issue)
    -- **없는 등급은 ERROR다**, `IssueGrade`와 `GetIssueColor`가 이미 그렇게 읽는다. 표를
    -- 그대로 비교하던 동안 이 함수만 반대로 답했다: 등급을 안 붙인 코드가 하나 생기면 그
    -- 액션이 `BuildKeyMap`의 게이트를 통과해 솔버와 `UpdateBindings`까지 가는데, 화면에는
    -- 아무 표시도 안 뜬다. **한 표를 읽는 세 함수가 다른 기본값을 쓰면 안 된다.**
    return IssueGrade(issue) ~= Constants.ISSUE_GRADE_ERROR;
end

--- What colour a problem is drawn in. **The grade picks it, never the code** -- that is the whole
--- of `devdocs/legacy/grading-binding-issues.md`, and it is why a new issue needs one row in
--- `BINDING_ISSUE_GRADES` and no edit anywhere that paints.
---
--- Red is what waits on the reader; orange is the key working with one thing it was told to do
--- missing (2026-09-06, owner). **Grey is not one of these**: it says an action is not running,
--- which is the other axis, and the window paints it from there (a keyless row, an
--- off-specialization one, one every neighbour covers).
---
--- **nil for no issue**, so a caller can write `color = GetIssueColor(issue)` and leave the
--- no-problem case to whatever it already had.
function DebindPrivate.GetIssueColor(issue)
    if (issue == nil) then
        return nil;
    end
    if (Constants.BINDING_ISSUE_GRADES[issue] == Constants.ISSUE_GRADE_WARNING) then
        return ORANGE_FONT_COLOR;
    end
    return ERROR_COLOR;
end

--- **Which of the two shapes each check reads is not a free choice, so it is made once here.**
---
--- The branches below used to start on the action and switch to the binding halfway down, with
--- nothing saying which reads had to come from where.
---
---   the binding, necessarily: a disabled unit condition is dropped on the way onto it and its
---     axes with it, `unit` is the one the macro will aim at rather than the one the user picked,
---     and `unitStates`, `unitRole`, `unitFrameTypes` and `unitGroups` exist nowhere else
---   the binding, by choice: `groups`, `specs`, `forms`, `bonusbars`. Normalizing folds only the
---     all-bits case to `_ALL` and leaves `specs` alone entirely, so an empty one reads the same
---     either way. They come off the binding so that this function speaks one shape
---   the action, necessarily: `key`, and the two checks that ask whether a name points at
---     something (`GetUndefinedSwitch`, `GetMissingMacroName`). None of the three is a
---     condition and none survives onto the binding
--- Of the issue already found and one a branch just raised, the one that is reported. **A tie goes
--- to the one already there**, so branches keep the order they are written in among equals.
local function TakeIssue(current, candidate)
    if (candidate ~= nil and (current == nil or IssueGrade(candidate) < IssueGrade(current))) then
        return candidate;
    end
    return current;
end

--- Is there any point asking another branch? **Only while the worst grade there is has not been
--- found**, since nothing below could replace it.
local function LookingForWorse(issue)
    return issue == nil or IssueGrade(issue) > Constants.ISSUE_GRADE_ERROR;
end

local function EvaluateIssues(action, category, notCategory, arg, collected)
    -- **없는 갈래로 물으면 아래 `if`가 전부 비켜가 nil이 나온다**, 그리고 그건 "문제 없음"과
    -- 생김새가 같다. 목록 행이 그렇게 죽은 갈래 넷을 묻고 있었고, 증상이 없어서 읽는 사람만
    -- 그 조건들에 검사가 있다고 읽었다. DEBUG에서만 세운다 - 배포본에서 터뜨릴 잘못이 아니다.
    if (Constants.DEBUG and category ~= nil and not Constants.BINDING_ISSUE_CATEGORIES[category]) then
        error("GetBindingIssue: 없는 갈래 " .. tostring(category), 2);
    end

    --- **A branch may replace only something less severe, and a tie goes to the branch that got
    --- there first.** Every branch used to stop at `not issue`, so the order they are written in
    --- decided the answer: the one WARNING sits above branches that raise ERRORs, and an action
    --- carrying both reported the warning. `IssueKeepsKey` then let it keep its key
    --- (`Debind.lua`), which is how a binding with conditions nothing can satisfy reached the
    --- solver -- the very thing the `unitStates` zero below exists to stop.
    ---
    --- `TakeIssue` holds the tie rule and `LookingForWorse` is what the guards ask, so a branch
    --- stops being asked only once the worst grade there is has been found.
    local issue;

    --- Where a branch hands in the code it raised. `label` names the group that problem is fixed
    --- in, and a branch with no group to open passes none -- an action whose own value is wrong
    --- has no menu behind it. `arg` is the name a sentence with a `%s` in it has to print.
    ---
    --- **Only a collecting call keeps a list.** The same code under the same group is kept once.
    --- Under two different groups it stays two entries: one sentence under two names is a
    --- contradiction that spans both menus, and either one of them undoes it.
    local seen = collected and {};
    local function Report(candidate, label, arg)
        if (candidate == nil) then
            return;
        end
        if (collected) then
            local key = candidate .. "\0" .. (label or "");
            if (not seen[key]) then
                seen[key] = true;
                collected[#collected + 1] = { code = candidate, label = label, arg = arg };
            end
        end
        issue = TakeIssue(issue, candidate);
    end

    --- Is there any point asking another branch? **A collecting call always has one** -- only the
    --- caller that folds to the worst one stops early, which is what `LookingForWorse` decides.
    local function Looking()
        return collected ~= nil or LookingForWorse(issue);

    end
    local binding = DebindPrivate.GetBindingInfoForAction(action);
    local conditions = binding.conditions;

    -- **이 갈래는 키 자체만 본다.** 이웃에 덮였는지는 여기서 안 묻는다 - 그건 이 액션의 잘못이
    -- 아니라 같은 키에 무엇이 더 걸려 있는가이고, 답을 내는 자리가 따로 있다
    -- (`Solver.lua`의 `IsUnreachableAction`). 여기 있던 동안에는 덮인 액션이 자기 경고 대신
    -- 그걸 냈고, 경고가 화면에서 사라졌다.
    if (Looking() and (not category or category == "key") and notCategory ~= "key") then
        if (action.key) then
            Report(DebindPrivate.IsKeyInvalidForAction(action, action.key), "KEY");
        end
    end

    -- **Every press this action could have answered is turned off.** It makes no binding at all
    -- (`GetBindingsForAction`), so the key runs whatever else is on it and this action is not there.
    -- A WARNING rather than an ERROR: the key works, and turning all four off is something the
    -- reader is allowed to mean (`devdocs/which-action-a-key-runs.md` §6).
    --
    -- **The pointed press is asked of `TwinUnitFor` and not of the mode**, because a mode with no
    -- twin under it is the same silence: [when none is pointed at] on that unit leaves the twin
    -- nowhere to stand, and asking the mode alone reported no problem on an action that made no
    -- binding at all. The original is asked of its mark for the same reason: Hover Cast's Skip
    -- takes it away where a condition on that unit leaves it nowhere to stand (`FillBinding`).
    if (Looking() and (not category or category == "casting") and notCategory ~= "casting") then
        if (binding.normalCast == false
                and DebindPrivate.TwinUnitFor(action, binding) == nil
                and not DebindPrivate.SelfCastEnabled(action)
                and not DebindPrivate.FocusCastEnabled(action)) then
            Report(Constants.BINDING_ISSUE_CASTING_NONE_LEFT, "CASTING");
        end
    end

    if (Looking() and (not category or category == "groups") and notCategory ~= "groups") then
        if (conditions.groups == 0) then
            Report(Constants.BINDING_ISSUE_GROUPS_NONE_SELECTED, "CONDITION_GROUP");
        end
    end

    if (Looking() and (not category or category == "specs") and notCategory ~= "specs") then
        if (conditions.specs ~= nil and next(conditions.specs) == nil) then
            Report(Constants.BINDING_ISSUE_SPECS_NONE_SELECTED, "CONDITION_SPEC");
        end
    end

    -- **The name is handed to the conditional parser as it stands.** A comma there ends the
    -- condition and a `]` ends the group, and neither raises: the key goes on working and answers
    -- a question nobody asked. Nothing can quote it, so the binding is refused instead
    -- (`devdocs/making-known-a-spell-name.md`).
    if (Looking() and (not category or category == "known") and notCategory ~= "known") then
        if (type(conditions.known) == "string" and conditions.known:find("[,%]]")) then
            Report(Constants.BINDING_ISSUE_KNOWN_NAME_UNPARSABLE, "CONDITION_KNOWN");
        end
    end

    if (Looking() and (not category or category == "forms") and notCategory ~= "forms") then
        if (conditions.forms == 0) then
            Report(Constants.BINDING_ISSUE_FORMS_NONE_SELECTED, "CONDITION_SHAPESHIFT");
        end
    end

    if (Looking() and (not category or category == "bonusbars") and notCategory ~= "bonusbars") then
        if (conditions.bonusbars == 0) then
            Report(Constants.BINDING_ISSUE_BONUSBARS_NONE_SELECTED, "CONDITION_BONUSBAR");
        end
    end

    -- **Three ways to name a switch, and a box for only one of them.** A macro body and an
    -- on/off/toggle target are the action itself, so nothing asks about them by name: they are
    -- caught by the overall call (`GetBindingIssue(action)`), the row turns red
    -- (`ColoredNameAndIconForAction`) and the tooltip says which name is wrong. A condition does
    -- have a box, and that box colours itself off `GetUndefinedSwitchCondition` rather than off
    -- this branch (`CreateSwitchConditionMenu`) -- it has to name the switch in its message, and
    -- it must not go red for a typo that is in the body instead.
    --
    -- The on/off/toggle target grew a box of its own in 3c (`CreateSetSwitchMenuItem`), and it
    -- colours itself the same way and for the same reason.
    if (Looking() and (not category or category == "states") and notCategory ~= "states") then
        -- **Not chosen yet is asked first, because the other question cannot be asked of it.**
        -- An on/off/toggle action arrives from the picker with no target at all (§6-C), and
        -- "nothing defines nil" is a sentence with no name to print in it. `GetUndefinedSwitch`
        -- says nothing about a value that is not a string, which is the same guard the binding
        -- builder keeps (`UpdateBindings.lua`). The two have to agree, or an action drawn clean
        -- is one that turns back at the door with nothing said.
        if (Constants.SETSTATE_MODES[action.type] and type(action.value) ~= "string") then
            Report(Constants.BINDING_ISSUE_SWITCH_NONE_SELECTED, "CONDITION_CUSTOM_STATES");
        else
            -- **The name goes with the code**: this sentence has a `%s` in it and the reader has
            -- to be told which name is the wrong one.
            local undefined = DebindPrivate.GetUndefinedSwitch(action);
            if (undefined) then
                Report(Constants.BINDING_ISSUE_UNDEFINED_STATE, "CONDITION_CUSTOM_STATES", undefined);
            end
        end
    end

    -- Same shape as the branch above: not a condition, but **a name that points at nothing**. So
    -- there is no caller that asks about it by name: what needs fixing is the action itself rather
    -- than a condition menu, and the name here is one for switching the branch off.
    --
    -- It was `"target"`, which named four other things in this repo already -- an action type, a
    -- unit token, a frame type, and the `Target` menu's own category, which asks about the unit
    -- the action aims at and has nothing to do with this.
    --
    -- An action reported here drops out of `KeyMap` entirely (`Debind.lua`). **Nothing is lost by
    -- that**: it is a binding that already pressed and did nothing, so the only thing that changes
    -- is that it becomes visible.
    if (Looking() and (not category or category == "macro") and notCategory ~= "macro") then
        local missing = DebindPrivate.GetMissingMacroName(action);
        if (missing) then
            Report(Constants.BINDING_ISSUE_MISSING_MACRO, "TYPE_MACRO", missing);
        end
    end

    -- 한 유닛에 걸린 조건들의 **교집합이 비면** 그 유닛이 놓일 수 있는 상태가 없다는 뜻이다.
    -- 개체창 조건과 `"@"`와 명시 유닛 조건이 전부 같은 축에 접혀 있으므로(`BuildUnitStates`),
    -- 조합을 손으로 나열하지 않고 마스크가 0인지만 보면 된다.
    --
    -- 나열하던 시절에는 개체창의 반응 제한과 `"@"` 조건이 어긋나는 경우가 빠져 있었다.
    -- 대상이 `@unitframe`인 액션에 개체창 반응을 `우호`로, `"@"`를 `적대`로 걸면 영원히 안 걸리는데
    -- 두 값이 서로 다른 필드에 있어서 비교 대상이 아니었다. 접힌 지금은 그 경우가 따로가 아니다.
    --
    -- **한 유닛의 0은 여러 메뉴가 같이 만든다. 그래서 그 조건을 고칠 수 있는 묶음은 전부
    -- 빨갛게 칠한다.** 대상이 `unitframe`인 액션에 개체창 조건을 [안 올렸을 때]로 걸면 겨눌 유닛이
    -- 놓일 자리가 없는데, 이건 개체창 메뉴에서 풀 수도 있고 대상 메뉴에서 다른 유닛을 골라
    -- 풀 수도 있다. 한쪽만 칠하면 나머지 한쪽을 연 사람은 멀쩡한 화면을 본다 - 메뉴를 열었을
    -- 때 어디를 봐야 하는지가 이 색으로만 보이므로, 관련된 자리는 다 칠해야 한다.
    --
    -- 대신 **자기가 보여주지 않는 조건으로는 안 칠한다.** `Units` 묶음은 `"unitframe"`을 줄로
    -- 갖고 있지 않으므로 그 키의 0에는 반응하지 않는다.
    --
    -- **This zero is what keeps contradictory conditions out of the secure environment.** An
    -- action reported here never enters `KeyMap` (`Debind.lua`), so it reaches neither the solver
    -- nor `UpdateBindings` -- which is why `mergeUnitConditions` over there treats its own
    -- "impossible" answer as unreachable and skips the binding instead of representing it. That
    -- function's header spells out the reasoning; the two are one rule written twice, so **weaken
    -- this check and the runtime starts carrying conditions nothing can satisfy.**
    --- 이 묶음이 그 0에 **거들었는가.** 안 거든 묶음을 칠하면 아무것도 안 고른 메뉴가
    --- 빨개진다 - 개체창에서 반응을 하나도 안 고른 것만으로 `Target`이 붉어지던 것이 그것이다.
    ---
    --- **두 순회가 같이 쓴다.** 소속은 유닛 곱에 안 들어가고 자기 컬럼으로 서느라 아래쪽
    --- 순회를 따로 도는데, 거든 묶음만 칠한다는 규칙은 축과 무관하다. 유닛 마스크 순회 안에
    --- 있던 동안 소속 쪽은 그 규칙 없이 `binding.unit`만 봤고, 그래서 개체창에서 비운 소속이
    --- `Target`을 칠했다.
    local function contributed(unit)
        if (not conditions.units) then
            return false;
        end
        if (category == "unit") then
            return conditions.units["@"] ~= nil and unit == ResolvedUnitOf(binding);
        end
        return conditions.units[unit] ~= nil;
    end

    -- The unit a submenu asked about. `"@"` resolves the way every other reader resolves it
    -- (`ResolvedUnitOf`). Its nil is a unit this build cannot read, and leaving `target` nil would
    -- turn "asked about one" into "asked about all": **other units' contradictions would show on
    -- that submenu.**
    --
    -- **Both loops below read this.** They open on the same test and remap the same way, and while
    -- each counted for itself the group loop was missing this guard (code review, 2026-09-11).
    local target = arg;
    local askedAboutNothing;
    if (target == "@") then
        target = ResolvedUnitOf(binding);
        askedAboutNothing = target == nil;
    end

    if (Looking() and binding.unitStates and notCategory ~= "units"
            and (not category or category == "units" or category == "unit")) then
        for unit, mask in pairs(binding.unitStates) do
            if (mask == 0 and not askedAboutNothing) then
                local mine;
                if (target ~= nil) then
                    -- 유닛 하나를 짚어 물었다(서브메뉴).
                    mine = target == unit;
                elseif (category == "unit") then
                    -- 대상 메뉴. `"@"`가 가리키는 유닛의 0이 곧 이 메뉴의 문제다.
                    mine = contributed(unit);
                else
                    -- `Units` 묶음이거나 액션 전체. 유닛 조건은 전부 그 묶음에서 고치고,
                    -- 액션 전체는 어느 묶음을 칠할지가 아니라 이 액션이 성립하느냐를 묻는다.
                    mine = true;
                end

                if (mine) then
                    Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, "CONDITION_UNITS");
                    if (not collected) then
                        break;
                    end
                end
            end
        end
    end

    -- 소속을 하나도 안 고른 것. 역할과 같은 이유로 위 순회가 못 본다 - 컬럼이 다르다.
    -- 역할과 달리 **유닛마다** 서므로, 짚어 물었으면 그 유닛만 답한다. 안 그러면 한 유닛의
    -- 빈 묶음으로 서브메뉴가 전부 빨개져서 어느 것을 고쳐야 하는지가 화면에서 사라진다.
    if (Looking() and binding.unitGroups and notCategory ~= "units"
            and (not category or category == "units" or category == "unit")) then
        for unit, mask in pairs(binding.unitGroups) do
            local mine;
            if (askedAboutNothing) then
                mine = false;
            elseif (target ~= nil) then
                mine = target == unit;
            elseif (category == "unit") then
                mine = contributed(unit);
            else
                mine = true;
            end
            if (mask == 0 and mine) then
                Report(Constants.BINDING_ISSUE_UNITGROUPS_NONE_SELECTED, "CONDITION_UNITS");
                if (not collected) then
                    break;
                end
            end
        end
    end

    -- 역할과 프레임 종류를 하나도 안 고른 것. 유닛 축의 0과 같은 뜻인데 컬럼이 달라서 위
    -- 순회가 못 본다. **둘 다 `unitframe` 줄에서만 걸 수 있으므로** 짚어 물었을 때는 그 줄만
    -- 답한다.
    if (Looking() and notCategory ~= "units"
            and (not category or category == "units")
            and (target == nil or target == "unitframe")) then
        if (binding.unitRole == 0) then
            Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, "CONDITION_UNITS");
        end
        if (binding.unitFrameTypes == 0) then
            Report(Constants.BINDING_ISSUE_HOVER_NONE_SELECTED, "CONDITION_UNITS");
        end
    end

    -- **A unit that needs a group, set against being alone.** The four role aliases are empty while
    -- the reader is solo (`UNITS_ABSENT_WHEN_SOLO`, read off the headers that declare it), so a
    -- binding that both requires one to be there and is restricted to `GROUP_NONE` presses and does
    -- nothing. The two halves live in different menus, which is why neither one looks wrong on its
    -- own and why both are told below.
    --
    -- **The mask is what says "has to be there", not the presence of a condition.** [When there is
    -- no tank] while solo is exactly true, and reading it as a contradiction would kill a working
    -- binding. `UNITSTATE_NONE` still being in the mask is that unit being allowed to be absent.
    --
    -- A zero mask is not this: that is a unit with no state left at all and the branch above has
    -- already reported it. `groups == 0` likewise belongs to `GROUPS_NONE_SELECTED`, which runs
    -- first for the same reason -- an axis with nothing ticked is a different sentence.
    if (Looking() and binding.unitStates and conditions.groups
            and (not category or category == "groups" or category == "units")
            and notCategory ~= "groups" and notCategory ~= "units"
            and band(conditions.groups, Constants.GROUP_ALL - Constants.GROUP_NONE) == 0) then
        -- **짚어 물었으면 그 유닛만 답한다.** 유닛 서브메뉴는 유닛마다 자기 색을 따로 묻는데,
        -- 여기가 `arg`를 안 보는 동안 한 유닛의 모순으로 **서브메뉴가 전부 빨개졌다.** 그러면
        -- 어느 것을 고쳐야 하는지가 화면에서 사라진다.
        for unit, mask in pairs(binding.unitStates) do
            if (not askedAboutNothing and (target == nil or target == unit)
                    and DebindPrivate.UNITS_ABSENT_WHEN_SOLO[unit] and mask ~= 0
                    and band(mask, Constants.UNITSTATE_NONE) == 0) then
                Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, "CONDITION_GROUP");
                break;
            end
        end
    end

    -- **A real role asked for, set against being alone.** The three headers that fill the role map
    -- all carry `showSolo = false` (`UnitWatch.lua`), so while the reader is solo nobody is on it
    -- and every unit reads `unknown`. Asking for tank, healer or damage there presses and does
    -- nothing, and the two halves live in different menus.
    --
    -- **`unknown` still being in the mask is what makes it satisfiable**, the same way
    -- `UNITSTATE_NONE` is above: [unknown] while solo is exactly true.
    --
    -- A zero mask is not this; the branch further up already reported it.
    if (Looking() and binding.unitRole and binding.unitRole ~= 0 and conditions.groups
            and (not category or category == "groups" or category == "units")
            and notCategory ~= "groups" and notCategory ~= "units"
            and band(conditions.groups, Constants.GROUP_ALL - Constants.GROUP_NONE) == 0
            and band(binding.unitRole, Constants.ROLE_NONE) == 0) then
        Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, "CONDITION_GROUP");
    end

    if (Looking() and (not category or category == "specialbar") and notCategory ~= "specialbar") then
        if ((conditions.specialbar and conditions.petbattle == false) or (conditions.petbattle and conditions.specialbar == false)) then
            Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, "CONDITION_SPECIALBAR");
        end
    end

    if (Looking() and (not category or category == "petbattle") and notCategory ~= "petbattle") then
        if ((conditions.specialbar and conditions.petbattle == false) or (conditions.petbattle and conditions.specialbar == false)) then
            Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, "CONDITION_PETBATTLE");
        end
    end

    -- **The one pair `skyriding` costs.** It and `bonusbars` read the same `GetBonusBarOffset()`,
    -- so a user who sets both can write a pair no runtime state satisfies -- and the two halves
    -- live in different menus, which is why neither looks wrong on its own. Same shape as the
    -- `specialbar`/`petbattle` pair above, and told under both names for the same reason.
    --
    -- **A zero mask is not this.** `BONUSBARS_NONE_SELECTED` runs further up and says a different
    -- sentence: an axis with nothing ticked, rather than two axes that disagree.
    if (Looking() and conditions.skyriding ~= nil and conditions.bonusbars
            and conditions.bonusbars ~= 0
            and (not category or category == "skyriding" or category == "bonusbars")
            and notCategory ~= "skyriding" and notCategory ~= "bonusbars") then
        local skyridingBit = 2 ^ Constants.BONUSBAR_SKYRIDING;
        local hasSkyridingBar = band(conditions.bonusbars, skyridingBit) ~= 0;
        -- Asked as "is the offset **only** 5", not "is bit 5 in there": with any other offset also
        -- ticked the binding still has somewhere to fire while not skyriding.
        local onlySkyridingBar = conditions.bonusbars == skyridingBit;
        if ((conditions.skyriding and not hasSkyridingBar)
                or (conditions.skyriding == false and onlySkyridingBar)) then
            Report(Constants.BINDING_ISSUE_CONDITIONS_NEVER, "CONDITION_SKYRIDING");
        end
    end

    return issue;
end

--- 이 액션의 문제 하나. **제일 심한 것**이고, 갈래를 짚어 물으면 그 갈래 안에서의 하나다.
--- 색 하나, 마크 하나, 게이트 하나를 정하는 자리는 전부 이것을 쓴다.
function DebindPrivate.GetBindingIssue(action, category, notCategory, arg)
    return EvaluateIssues(action, category, notCategory, arg, nil);
end

--- 이 액션의 문제 **전부**. `{ code, label }`의 목록이고, 순서는 갈래가 쓰인 순서다.
--- `label`은 그 문제를 고칠 수 있는 묶음의 로케일 키이며, 고칠 묶음이 없으면 nil이다.
--- 문제가 없으면 빈 목록이다.
---
--- 하나로 접는 쪽과 나뉜 이유는 답의 모양이 아니라 묻는 사람이 다르기 때문이다: 색을 고르고
--- 게이트를 여는 자리는 제일 심한 것 하나만 있으면 되고 그 하나를 찾는 즉시 멈추는 편이 싸다.
--- 읽는 사람에게 무엇이 잘못됐는지 말하는 자리만 전부가 필요하다.
function DebindPrivate.GetBindingIssues(action)
    local collected = {};
    EvaluateIssues(action, nil, nil, nil, collected);
    return collected;
end




-- 행동단축바 끌어다 놓은 탈것을 클릭하면 필요한 경우 자동으로 변신이 해제되지만 C_MountJournal.SummonByID를 사용하는 경우 자동으로 변신이 해제되지 않음.
-- 'autounshift'가 켜져있어도 마찬가지!
local SUMMON_MOUNT_MACROTEXT = SLASH_SCRIPT1 .. " C_MountJournal.SummonByID(%d)";
if (select(2, UnitClass("player")) == "DRUID") then
    SUMMON_MOUNT_MACROTEXT = SLASH_CANCELFORM1 .. " [form:1/2/5/6,nocombat]\n" .. SUMMON_MOUNT_MACROTEXT;
end

function DebindPrivate.GetMountMacroText(value)
    if (value == 268435455) then
        value = 0;
    end
    return SUMMON_MOUNT_MACROTEXT:format(value);
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
--- not (`devdocs/making-known-a-spell-name.md`). A body sitting in `value` is such a type, so the
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

    -- A probe has no macro-text form: it is a second spell gated on the spell book, and the body can
    -- only hold one. Dropping it would leave the converted key firing the wrong half.
    --
    -- **쌍둥이는 변환을 막지 않는다** (2026-09-16, 소유자). 쌍둥이는 액션이 유닛을 받든 못 받든 서고
    -- 유닛을 받아 간다(`devdocs/which-action-a-key-runs.md` §3). 매크로 본문이 그 유닛을 읽느냐는
    -- 그 액션의 몫이고, 읽게 하고 싶으면 `@@`가 그 자리다
    -- (`devdocs/implementing-focus-and-self-cast.md` §4).
    local list = DebindPrivate.GetBindingsForAction(action);
    for i = 2, #list do
        if (list[i].spellbook ~= nil) then
            return false;
        end
    end

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
--- **`WORLDMARKER` is absent on purpose.** The action places or takes back, because the binding
--- leaves `*action-` unwritten and the client's default is `toggle` (`SECURE_ACTIONS.worldmarker`).
--- `/wm` only places (`SlashCommands.lua`), taking back is `/cwm`, no conditional tells the two
--- apart, and `PlaceRaidMarker` / `ClearRaidMarker` both carry `HasRestrictions` so `/run` cannot
--- reach them either. Every body that can be written here does half of what the key did.
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
        or action.type == Constants.SETCUSTOM;
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

    -- **No unit picked is `@@`, on a type that takes one** (`devdocs/implementing-focus-and-self-cast.md`
    -- §4). The twins pass `player`, `focus` and the pointed unit, and a body that does not read them
    -- takes the cast keys and Hover Cast off the key. The original aims at nothing and `@@` goes out
    -- as a lone `@`, the same as a body with no target in it.
    if (unit == nil and DebindPrivate.ActionTakesUnit(action)) then
        unit = "@";
    end

    if (action.type == Constants.SPELL or action.type == Constants.ITEM) then
        local slashCommand, spellOrItemName;
        if (action.type == Constants.SPELL) then
            slashCommand = SLASH_CAST1;
            local spellID = C_SpellBook.FindBaseSpellByID(action.value) or action.value;
            local _, spellIcon = GetSpellNameAndIconID(spellID);
            icon = spellIcon;
            spellOrItemName = GetSpellCastName(spellID);
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
            macrotext = DebindPrivate.GetMountMacroText(value);
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
    elseif (Constants.SETSTATE_MODES[action.type]) then
        -- **The body needs a name and a mode, and the action already holds both** -- the name in
        -- `value`, the mode decided by the type. The locale key assembles off the type for the
        -- same reason, which is half of why the type names are underscored (`Constants.lua`).
        macrotext = format("/click %s %s-%s", SWITCH_CLICK_TARGET, action.value,
            Constants.SETSTATE_MODES[action.type]);
        name = format(L["TYPE_" .. strupper(action.type)], action.value);
        icon = 254885;
    end

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
    --- hands the old name in, the way every frozen step in `Profile.lua` holds its own literals.
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
    --- (`devdocs/legacy/redesigning-custom-states.md` §3).
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


local FULL_PLAYER_NAME = FULL_PLAYER_NAME;
function DebindPrivate.GetUnitFullName(unit)
    local name, realm = UnitName(unit);
    -- 12.1 can answer with secrets for units outside our access (arena enemies). A
    -- secret name cannot be formatted or concatenated, and every caller already treats
    -- nil as "nothing to show", so that is what a secret becomes.
    if (issecretvalue and (issecretvalue(name) or issecretvalue(realm))) then
        return nil;
    end
    if (realm and realm ~= "") then
        name = FULL_PLAYER_NAME:format(name, realm);
    end
    return name;
end

function DebindPrivate.OnSpecialUnitChanged(alias, value)
    local unit = value or nil;
    local prev = DebindPrivate.Units[alias];
    DebindPrivate.Units[alias] = unit;

    if (prev ~= unit) then
        DebindPrivate.callbacks:Fire("UNIT_CHANGED", alias, unit);
    end
end

local _lastSwitchValues = {};
local _changedStates = {};

--- What the restricted side reported back, folded into the stored definitions.
---
--- **It walks what changed, not the five numbers.** A macro can name any switch
--- (`/click DebindStates $burst-on`, `Switches.lua`), so names outside the five have always been
--- able to arrive here -- the number loop simply never looked at them.
---
--- **A name nothing defines is left alone rather than defined.** There is no row to write the
--- value into and making one here would be the load-time repair §9-3 of
--- `devdocs/legacy/redesigning-custom-states.md` rules out. The switch still works for this session: the
--- value lives in the restricted environment's `States`, and what is missing is only the memory of
--- it across a reload.
---
--- **The remembered value goes on the character, the live one on the definition**, and both are
--- `SetSwitchValue`'s to write (`Profile.lua`). The definition is account-wide, and while the
--- memory sat there too "remember" meant "remember what the character who logged out last left"
--- (§5 of `devdocs/legacy/redesigning-custom-states.md`). **Which of these reports becomes a memory is
--- decided there and not here**: a report carrying the value the definition already holds is a
--- reset this side pushed a moment ago coming back round, and it is the one that must not be
--- remembered (§4-9).
---
--- What is left here is what only this path knows: that the value came from outside, and the
--- user may have asked to be told.
---
--- **Nothing is broadcast any more.** `SWITCH_CHANGED` went on 2026-08-22. A listener on it
--- meant every switch value had to be right the moment it moved, and that reachability is what
--- kept a computed switch from being worked out lazily
--- (`devdocs/legacy/trimming-the-restricted-hot-paths.md`). The Switches tab reads `definition.value`,
--- which `SetSwitchValue` above still fills in, so what it lost was a reason to redraw rather
--- than the value to draw.
local function SwitchesChangedCallback()
    for state, newValue in pairs(_changedStates) do
        local options = DebindPrivate.ResolveSwitchDefinition(state);
        if (options) then
            DebindPrivate.SetSwitchValue(state, newValue);

            if (_lastSwitchValues[state] ~= newValue) then
                _lastSwitchValues[state] = newValue;

                if (options.displayMessage and DebindPrivate.SwitchMessagesEnabled()) then
                    local valueText = newValue and L["STATE_CHANGED_MESSAGE_ON"] or L["STATE_CHANGED_MESSAGE_OFF"];
                    DebindPrivate.DisplayMessage(format(L["STATE_CHANGED_MESSAGE"], state,
                        valueText));
                end
            end
        end
    end
    wipe(_changedStates);
end

function DebindPrivate.OnSwitchChanged(name, value)
    if (not next(_changedStates)) then
        C_Timer.After(0, SwitchesChangedCallback);
    end

    _changedStates[name] = value;
end

--- What this build calls itself, for the two places a user can read it off before writing a bug
--- report: the window title and the login line.
---
--- **A released build needs nothing written down.** The packager stamps `## Version:` from the tag,
--- so the TOC already holds the answer and there is no second copy to fall out of step with it.
---
--- A working copy has no version to read -- `@project-version@` is still sitting there literally,
--- never having been through the packager -- and that unsubstituted token is what identifies a
--- working copy. It names the checkout instead, which `DevStamp.lua` writes; that file is
--- gitignored and its TOC line is inside `#@debug@`, so neither reaches a user. Without the hook
--- that writes it there is simply no stamp, and the fallback covers it.
function DebindPrivate.GetVersionLabel()
    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version");
    if (version and not version:find("@", 1, true)) then
        return version;
    end
    return DebindPrivate.DEV_STAMP or "dev";
end

function DebindPrivate.DisplayMessage(message, r, g, b)
    if (b == nil) then
        local info = ChatTypeInfo["SYSTEM"];
        r, g, b = info.r, info.g, info.b;
    end
    if (Constants.DEBUG) then
        DEFAULT_CHAT_FRAME:AddMessage(GetTime() .. "  " .. L["_MESSAGE_PREFIX"] .. message, r, g, b);
    else
        DEFAULT_CHAT_FRAME:AddMessage(L["_MESSAGE_PREFIX"] .. message, r, g, b);
    end
end

--- Every option whose answer reaches a secure frame is applied from here, and **nothing else
--- applies one**. The settings panel is open during a fight and every control in it is pressable
--- there, so a setter that wrote its own answer through would raise inside the panel's own click
--- handler. A setter writes the stored value and asks for a rebuild instead; `FinishBindingUpdate`
--- calls this with no argument, and a rebuild that could not run during the fight is replayed at
--- `PLAYER_REGEN_ENABLED` (`Events.lua`).
---
--- **The stored value is read here rather than carried in.** Two changes during one fight leave
--- two queued rebuilds and one answer, and it has to be the second one.
function DebindPrivate.ApplyOptions(option)
    if (option == nil or option == "unitframeUseMouseDown") then
        --- **Three answers folded into one boolean before it crosses.** The restricted side
        --- cannot read a CVar, so `nil` - the reader not having chosen - is resolved here, and
        --- re-resolved whenever the CVar moves (`Events.CVAR_UPDATE`).
        ---
        --- **`ActionButtonUseKeyDown` is a setting about keys**, and this is a click on somebody
        --- else's frame. It is what `nil` follows because it is the only place the game asks the
        --- question at all, and because the key side of the addon already falls to it: a reader
        --- who answered it once should not have to answer it twice.
        local onMouseDown = DebindPrivate.Options.unitframeUseMouseDown;
        if (onMouseDown == nil) then
            onMouseDown = GetCVarBool("ActionButtonUseKeyDown") and true or false;
        end
        --- **A lockdown blocks the only door this value has.** `SecureHandlerExecute` cannot cross
        --- one, and no other path pushes the click edge, so an answer given during a fight used to
        --- reach nothing and go on not reaching it for the rest of the session while the menu
        --- showed it as the one chosen. Both doors are open in combat: the CVar moves whenever the
        --- game says so (`Events.CVAR_UPDATE`), and the options menu takes the answer with the
        --- window up. Login is a third, since a reconnect into an encounter arrives locked down.
        ---
        --- The value is not carried, only the fact that one is owed. Whatever is read when the
        --- fight ends is the answer that stands then, which is the right one if the reader moved
        --- it twice while it could not cross.
        if (InCombatLockdown()) then
            DebindPrivate.clickEdgeSuspended = true;
        else
            DebindPrivate.clickEdgeSuspended = nil;
            SecureHandlerExecute(DebindPrivate.BindingDriver,
                format("ClickCastOnMouseDown=%s", tostring(onMouseDown)));
        end
    end

    --- **A unit watch header is a `SecureGroupHeaderTemplate`, so the attribute cannot be written
    --- during a fight.** A header built later reads the same option for itself
    --- (`CreateUnitWatchHeader`), so what is left here is the ones that already exist.
    if (option == nil or option == "excludePlayer") then
        if (not InCombatLockdown()) then
            local excluded = DebindPrivate.Options.excludePlayer;
            local units = DebindPrivate.EXCLUDE_PLAYER_UNITS;
            for i = 1, #units do
                local header = DebindPrivate.GetUnitWatchHeader(units[i]);
                if (header) then
                    header:SetAttribute("showPlayer", not (excluded and excluded[units[i]]));
                end
            end
        end
    end

    --- **The throttle and the flag that reads it move together or not at all.**
    ---
    --- `PollEveryFrame` says the beat already comes every frame, and the restricted side turns a
    --- wake of its own straight round on it (`UpdateAttrChangedHandler`). Writing the flag anywhere
    --- but here would leave a reader who was at zero and raised the slider with every hover
    --- crossing and every switch toggle dropped until the two happened to be written together
    --- again.
    ---
    --- `UnitWatchRegistered` rather than a value carried from the rebuild, for the same reason. It
    --- is what is true now, and a rebuild reaches here through `FinishBindingUpdate`, which runs
    --- after `ApplyBindingPlan` has registered or unregistered the watch.
    ---
    --- **That term is a backstop, and no spec here could make it the difference.** What a
    --- state-driven key registers is also what `WantsStatePoll` asks about, so a profile with an
    --- unregistered beat and a key for the loop to decide is a shape none of them could build. It
    --- stays because the claim the flag makes is "the beat is coming", and reading that off a beat
    --- nobody asked for would be false on its face.
    ---
    --- **A lockdown blocks both doors at once**, which is what makes leaving them is safe: the
    --- manager is a `SecureFrameTemplate` and protected, so the throttle cannot move during a
    --- fight either, and a flag that describes a throttle that cannot move cannot go stale.
    if (option == nil or option == "stateDriverUpdateThrottle") then
        local value = DebindPrivate.Options.stateDriverUpdateThrottle or STATE_DRIVER_UPDATE_THROTTLE_DEFAULT;
        if (type(value) == "number" and not InCombatLockdown()) then
            value = max(0, min(value, STATE_DRIVER_UPDATE_THROTTLE_DEFAULT));
            SecureStateDriverManager:SetAttribute("updatetime", value);
            SecureHandlerExecute(DebindPrivate.BindingDriver, format("PollEveryFrame=%s",
                tostring(value == 0 and UnitWatchRegistered(DebindPrivate.BindingDriver) and true
                    or false)));
        end
    end
end
