local ADDON_NAME, DebindPrivate = ...;
local L                       = DebindPrivate.L;
local Constants               = DebindPrivate.Constants;

local dump                    = DebindPrivate.dump;
local tinsert, wipe           = tinsert, wipe;
local pairs                   = pairs;
local GetSpellCastName        = DebindPrivate.GetSpellCastName;


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
    local name, _, numSlots, isKnown = DebindPrivate.Client.FlyoutInfo(flyoutID);
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

    local _, _, numSlots = DebindPrivate.Client.FlyoutInfo(flyoutID);
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

function DebindPrivate.IsInactiveAction(action)
    return not DebindPrivate.ActiveActions[action];
end

--- What to write where a key goes. **Not for a nil key** -- what an action with no key at all reads
--- as differs by where it is shown, so each of those places says its own word.
---
--- **A key is a binding string and nothing else.** This used to take a second argument and to guard
--- against a number, because a set whose key the reader had not decided sat on one and the heading
--- had to be told separately which key it had come in on. An arrival keeps the key it was sent on,
--- so the key names it (`building-export-import.md` 12절) and there is no second thing left
--- to say.
function DebindPrivate.GetKeyDisplayText(key)
    return GetBindingText(key);
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

local _changedStates = {};

--- The line a switch prints when it moves, and **the only place it is written**. A key, a macro
--- and the button on the Switches tab all turn the same switch, and a second copy of these two
--- tests would be a second answer to "does this print" for one of them.
---
--- **Whether it moved is the caller's to know.** The report coming back out of the restricted side
--- carries no such thing -- a rebuild pushes the stored values in and they are reported straight
--- back (`BuildSwitchesSnippet`) -- so the caller that can tell an echo from a change is the one
--- holding the value it moved from.
---
--- **Only a switch this character works by hand announces itself.** A computed one answers a
--- conditional, so its value moves with the world rather than with anything the user did, and
--- there is nobody to read the line. Which kind it is is the winning layer's answer
--- (`ResolveSwitchAnswer`) and not the account-wide definition's: a layer can override manual with
--- an expression and the other way round.
function DebindPrivate.AnnounceSwitchChange(name, value)
    if (not DebindPrivate.SwitchMessagesEnabled()) then
        return;
    end
    if (DebindPrivate.ResolveSwitchAnswer(name) ~= Constants.SWITCH_MODES.MANUAL) then
        return;
    end

    local valueText = value and L["STATE_CHANGED_MESSAGE_ON"] or L["STATE_CHANGED_MESSAGE_OFF"];
    DebindPrivate.DisplayMessage(format(L["STATE_CHANGED_MESSAGE"], name, valueText));
end

--- What the restricted side reported back, folded into the stored definitions.
---
--- **It walks what changed, not the five numbers.** A macro can name any switch
--- (`/click DebindStates $burst-on`, `Switches.lua`), so names outside the five have always been
--- able to arrive here -- the number loop simply never looked at them.
---
--- **A name nothing defines is left alone rather than defined.** There is no row to write the
--- value into and making one here would be the load-time repair §9-3 of
--- `redesigning-custom-states.md` rules out. The switch still works for this session: the
--- value lives in the restricted environment's `States`, and what is missing is only the memory of
--- it across a reload.
---
--- **The remembered value goes on the character, the live one on the definition**, and both are
--- `SetSwitchValue`'s to write (`Profile.lua`). The definition is account-wide, and while the
--- memory sat there too "remember" meant "remember what the character who logged out last left"
--- (§5 of `redesigning-custom-states.md`). **Which of these reports becomes a memory is
--- decided there and not here**: a report carrying the value the definition already holds is a
--- reset this side pushed a moment ago coming back round, and it is the one that must not be
--- remembered (§4-9).
---
--- What is left here is what only this path knows: that the value came from outside, and whether
--- it moved the switch.
---
--- **What the line is worth saying about is a report that moved the switch**, and the definition's
--- value is what it moved from. Every rebuild pushes the stored values in and the restricted side
--- reports them straight back (`BuildSwitchesSnippet`), so without that test a login says one line
--- per switch -- the §4-9 echo again, from the side that prints rather than the side that
--- remembers.
---
--- **Nothing is broadcast any more.** `SWITCH_CHANGED` went on 2026-08-22. A listener on it
--- meant every switch value had to be right the moment it moved, and that reachability is what
--- kept a computed switch from being worked out lazily
--- (`trimming-the-restricted-hot-paths.md`). The Switches tab reads `definition.value`,
--- which `SetSwitchValue` above still fills in, so what it lost was a reason to redraw rather
--- than the value to draw.

local function SwitchesChangedCallback()
    for state, newValue in pairs(_changedStates) do
        local options = DebindPrivate.ResolveSwitchDefinition(state);
        if (options) then
            local moved = options.value ~= newValue;
            DebindPrivate.SetSwitchValue(state, newValue);

            if (moved) then
                DebindPrivate.AnnounceSwitchChange(state, newValue);
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

--- A working copy's TOC still holds the packager's keyword unsubstituted, which is what the `@`
--- test catches.
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
    if (option == nil or option == "unitframeUseMouseDown" or option == "empowerTapControls") then
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
        --- **강화 주문 입력도 같은 문으로 간다.** 설정의 값이 `0`이면 길게 누르기, `1`이면 두 번
        --- 누르기다(`Blizzard_SettingsDefinitions_Frame/Combat.lua`). 두 번 누르기에서는 쥐는
        --- 구간이 없어서 뗌 엣지로 놓을 것이 없고, 그 판단을 클릭 때 해야 한다.
        ---
        --- **빌드 때 읽으면 안 된다.** 버튼 캐시는 한 번도 안 지워지므로 이 값으로 구운 것이
        --- 설정을 바꾼 뒤에도 계속 나간다(`UpdateBindings.lua`의 `BindingAttrsCache`).
        local tapControls = GetCVarBool("empowerTapControls") and true or false;
        --- **A lockdown blocks the only door these have.** `SecureHandlerExecute` cannot cross
        --- one, and no other path pushes them, so an answer given during a fight used to
        --- reach nothing and go on not reaching it for the rest of the session while the menu
        --- showed it as the one chosen. Both doors are open in combat: the CVar moves whenever the
        --- game says so (`Events.CVAR_UPDATE`), and the options menu takes the answer with the
        --- window up. Login is a third, since a reconnect into an encounter arrives locked down.
        ---
        --- The values are not carried, only the fact that one is owed. Whatever is read when the
        --- fight ends is the answer that stands then, which is the right one if the reader moved
        --- it twice while it could not cross.
        if (InCombatLockdown()) then
            DebindPrivate.secureValuesSuspended = true;
        else
            DebindPrivate.secureValuesSuspended = nil;
            SecureHandlerExecute(DebindPrivate.BindingDriver,
                format("ClickCastOnMouseDown=%s EmpowerTapControls=%s",
                    tostring(onMouseDown), tostring(tapControls)));
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

end
