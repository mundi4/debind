local ADDON_NAME, DebindPrivate = ...;
local L                       = DebindPrivate.L;
local Constants               = DebindPrivate.Constants;

local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;

local dump                    = DebindPrivate.dump;
local band                    = bit.band;
local tinsert, wipe           = tinsert, wipe;
local pairs, ipairs           = pairs, ipairs;
local GetMountInfoByID        = C_MountJournal.GetMountInfoByID;
local GetSpellSubtext         = C_Spell.GetSpellSubtext;


local STATE_DRIVER_UPDATE_THROTTLE_DEFAULT = 0.2;

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


--- 플라이아웃 안에서 **실제로 나갈 수 있는** 슬롯들. 시전에 쓸 값까지 같이 낸다.
---
--- 값이 주문 **이름**인 것은 `UpdateBindings.lua`의 `Constants.SPELL` 갈래와 같은 이유다 -
--- id는 다른데 이름이 같은 주문이 있고(특성별 변신 등), id로 걸면 다른 특성에서 안 나간다.
--- 이름을 못 풀 때만 id로 떨어진다.
---
--- **오프스펙은 여기서 안 받는다.** 목록에 그리는 것과 달리 이건 버튼에 올릴 값이고,
--- 안 배운 주문을 올리면 눌러도 아무 일이 없다.
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
            local castName, icon = GetSpellNameAndIconID(spellID);
            if (castName) then
                local subName = GetSpellSubtext(spellID);
                if (subName and subName ~= "") then
                    castName = castName .. "(" .. subName .. ")";
                end
            end

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
--- 태우므로, `@custom1`·`@hover` 같은 우리 유닛은 `ParseMacroText`가 실행 시점에 진짜 토큰으로
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
    ["never"] = 0,
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
--- **옵션을 끄는 것이지 지우는 것이 아니다** - `frameTypes`가 hover를 껐다 켜도 남아 있는 것과
--- 같은 규칙이고, 이 메뉴만 예외일 이유가 없다.
---
---     { }                          있을 때 (표시가 없으면 이것)
---     { reaction = m, dead = b }   있을 때 + 축
---     { exists = false, ... }      없을 때. 축은 기억만 한다
---     { off = true, ... }          이 유닛에 조건 없음. 축은 기억만 한다
---
--- 두 표시가 다 **없는 것이 "있을 때"인 것**이 중요하다. 손으로 쓴 값이나 아직 안 옮겨진
--- 프로필이 그 모양으로 오는데, 그것을 "조건 없음"으로 읽으면 걸어둔 조건이 조용히 사라져
--- 바인딩이 제 것 아닌 키까지 가져간다. 좁아지는 쪽이 안전하다.
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
        -- 조용히 사라지면 그 바인딩이 걸어둔 것보다 넓어져 남의 키를 가져간다. 없음 점으로
        -- 읽는 것이 좁은 쪽이고, 스칼라 시절에도 같은 답이었다.
        return false;
    end

    if (value.off) then
        return nil;
    elseif (value.exists == false) then
        return false;
    end
    return { reaction = value.reaction, dead = value.dead };
end

--- The old `hover` / `reactions` pair -> the unit condition they became.
---
--- The hovered frame's unit is a unit, so it is stored as one: `units["hover"]`
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
local function HoverConditionFromLegacy(hover, reactions, existing)
    if (hover == false) then
        -- "Not hovering" against any condition that needs the unit there. Nothing is both.
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

DebindPrivate.HoverConditionFromLegacy = HoverConditionFromLegacy;
DebindPrivate.UnitConditionForBinding = UnitConditionForBinding;

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

--- Fold everything that says something about a unit onto one mask per unit.
---
--- `binding.unitStates` is the only thing the solver reads about units. `units` and
--- `hover`/`reactions` are left untouched because the runtime still speaks that shape; when the
--- menus move to masks, storage becomes these values and this collapses into a copy.
---
--- The point of doing it here is that **the hovered frame's unit is just a unit, named "hover"**.
--- Kept apart, the hover condition and a unit condition on the same unit are two columns
--- describing one thing, and the solver cannot see that `hover=friendly` with `@=hostile` never
--- holds -- it keeps a binding that can never fire and warns about nothing.
---
--- A mouse button reaches the not-hovering point and nothing else: the click fires wherever the
--- cursor already is, and over a unit frame the frame eats it, so only the frame path can act
--- there. The same absent condition on a keyboard key spans the whole axis.
--- `binding.hover` from the stored condition.
---
--- **Derived, not stored** (`Profile.lua`'s `dbver <= 4` step). Storage keeps one column for the
--- hovered frame's unit; this is the view of it the rest of the addon already speaks --
--- ordering ranks a hover binding by `hover ~= nil` (`Ordering.lua`), the runtime routes a key to
--- the click path by it (`UpdateBindings.lua`'s `isClickCast`), the frame-type column gates on it
--- (`Solver.lua`), and key validity asks about it (`IsKeyInvalidForAction`).
---
--- `false` and `nil` are **different answers** and both are load-bearing -- "only when not
--- hovering" versus "does not care" -- so this cannot collapse to a boolean.
---
--- Idempotent, and called from both seams: `GetBindingInfoForAction` needs it before the checks
--- below it read `hover`, and `BuildUnitStates` needs it for bindings that never went through
--- there (the solver specs hand-write theirs).
local function DeriveHoverFields(binding)
    local conditions = binding.conditions;
    local condition = conditions and conditions.units and conditions.units.hover;
    if (condition == nil) then
        binding.hover = nil;
    elseif (condition == false) then
        binding.hover = false;
    else
        binding.hover = true;
    end
end

DebindPrivate.DeriveHoverFields = DeriveHoverFields;

--- 호버 조건이 허용하는 반응 마스크. 아무 축도 제약 안 하면 nil.
---
--- **`binding.reactions`라는 필드였다.** 호버 조건 하나를 세 겹으로 설명하던 마지막 겹이고
--- (`units["hover"]` -> `hover` -> `reactions`), `dbver <= 4`가 저장 쪽에서 없앤 것이
--- 정확히 그 모양이다. 읽는 데가 아래 이슈 검사 둘뿐이라 필드로 들고 있을 값이 아니었다.
---
--- `hover`는 남는다. 저쪽은 발동 순서·클릭 경로·솔버 컬럼·키 유효성이 다 읽는다.
local function HoverReactionMask(binding)
    local conditions = binding.conditions;
    local condition = conditions and conditions.units and conditions.units.hover;
    if (type(condition) ~= "table" or condition.reaction == Constants.REACTION_ALL) then
        return nil;
    end
    return condition.reaction;
end

local function BuildUnitStates(binding)
    DeriveHoverFields(binding);

    local states, opaque;

    local function narrow(unit, mask)
        states = states or {};
        local prev = states[unit];
        if (prev == nil) then
            states[unit] = mask;
        else
            states[unit] = band(prev, mask);
        end
    end

    -- The hover condition itself is not read here any more -- it lives in `units["hover"]`
    -- and the loop below folds it like any other unit. What is left is the one thing the **key**
    -- says: a mouse button reaches the not-hovering point and nothing else, because the click
    -- fires wherever the cursor already is and over a unit frame the frame eats it.
    --
    -- **Only when nothing was said about hovering.** An explicit hover condition on a mouse
    -- button key is the user overriding that reading, and it has always won here -- narrowing it
    -- to absent as well would leave an empty box and delete the binding for a reason nobody set.
    local conditions = binding.conditions;
    local units = conditions and conditions.units;

    if (binding.key and (units == nil or units.hover == nil)
            and DebindPrivate.GetMouseButtonAndPrefix(binding.key)) then
        narrow("hover", Constants.UNITSTATE_NONE);
    end

    if (units) then
        for key, value in pairs(units) do
            local unit = key;
            if (key == "@") then
                unit = binding.unit;
                if (type(unit) ~= "string" or unit == "") then
                    -- Nowhere to put it. Dropping the condition instead would make the binding
                    -- look wider than it is, and a cover wider than it should be deletes
                    -- bindings that can still fire -- so it leaves both roles, not one.
                    opaque = true;
                    unit = nil;
                end
            end
            if (unit) then
                narrow(unit, UnitConditionToState(value));
            end
        end
    end

    binding.unitStates = states;
    binding.unitStatesOpaque = opaque;
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
    function DebindPrivate.GetBindingInfoForAction(action)
        local binding = _ActionToBindingCache[action];

        if (not binding) then
            binding = {};
            _ActionToBindingCache[action] = binding;
        end

        binding.type, binding.value = action.type, action.value;
        binding.ignoreHoverUnit = action.ignoreHoverUnit;
        binding.unit = action.unit;
        binding.key = action.key;

        -- **조건은 한 표를 통째로 옮긴다.** 예전에는 열두 줄이 손으로 적혀 있었고, 축이
        -- 하나 늘 때마다 이 줄을 잊으면 그 조건이 바인딩에 도착하지 않았다. 조용히 넓어지는
        -- 쪽이라 아무도 못 잡는다.
        --
        -- 표는 **재사용한다.** 아래 정규화가 제자리에서 nil을 쓰므로 액션 쪽 표를 그대로
        -- 가리키면 사용자가 건 조건을 지우게 된다.
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
                local condition = UnitConditionForBinding(value);
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
            conditions.units.hover = HoverConditionFromLegacy(
                action.hover, action.reactions, conditions.units.hover);
        end

        -- Everything below this line reads `binding.hover`, so it has to be derived here and
        -- not only in `BuildUnitStates` at the end.
        DeriveHoverFields(binding);

        -- 커스텀 상태를 따로 도는 루프가 여기 있었다. 위 벌크 복사가 조건 표를 통째로
        -- 옮기므로 슬롯 다섯을 이름으로 세어줄 필요가 없고, 재설계가 임의 이름을 풀어도
        -- 이 자리가 안 바뀐다.

        -- 의미 없는 조건들을 nil로 만듬.
        if (binding.hover) then
            if (conditions.frameTypes and band(conditions.frameTypes, Constants.FRAMETYPE_ALL) == Constants.FRAMETYPE_ALL) then
                conditions.frameTypes = nil;
            end
        else
            conditions.frameTypes = nil;
            binding.ignoreHoverUnit = nil;
        end

        -- **`true` or nothing. There is no third answer here**, unlike every other condition
        -- in this block. The question is always about this action's own spell -- both the
        -- conditional (`UpdateBindings` bakes `binding.value` into it) and the solver's column
        -- (keyed by that same value) -- so `false` would say "cast it only while it is
        -- unlearned", and no state satisfies that.
        --
        -- A nil check rather than a truthy one, for the same reason as the `"@"` cleanup
        -- below: nothing here writes `false`, but a shared profile can carry one, and left in
        -- place it reaches `UpdateBindings`, which bakes the same `[known:<value>]` a `true`
        -- would. It then fires on exactly the state it was asked to stay off.
        if (conditions.known == false or (conditions.known ~= nil and binding.type ~= Constants.SPELL)) then
            conditions.known = nil;
        end

        if (conditions.units) then
            -- truthy가 아니라 nil 검사다. "@"에 "없을 때"가 들어와 있으면(UI로는 못 만들지만
            -- 공유 프로필로는 들어온다) truthy 검사는 그걸 못 지우고, 걸 축이 없는 조건이
            -- 그대로 UpdateBindings까지 간다.
            if (conditions.units["@"] ~= nil and (binding.unit == nil or binding.unit == "none" or binding.unit == "player")) then
                conditions.units["@"] = nil;
            end

            -- `"@"` and an explicit condition on the same unit used to be folded into one key
            -- here, by hand, for the scalar shape. **Both consumers intersect them
            -- themselves now**: `BuildUnitStates` with `band` for the solver, and
            -- `mergeUnitConditions` per axis on the way to the snippet. Folding again would
            -- be a third copy of one rule, and the one that drifts is the one nothing checks.
        end

        if (conditions.groups and band(conditions.groups, Constants.GROUP_ALL) == Constants.GROUP_ALL) then
            conditions.groups = Constants.GROUP_ALL;
        end

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
        if (not Constants.TYPES_WITH_UNIT[binding.type]) then
            binding.unit = nil;
        elseif (binding.type == Constants.PETACTION
                and not DebindPrivate.PetActionTakesUnit(binding.value)) then
            -- 펫 명령은 타입만으로 안 갈린다. 대상 메뉴도 같은 것을 보고 안 열린다
            -- (`DropDownMenus.lua`). 여기서도 지워야 옛 프로필에 남은 값이 안 따라온다.
            binding.unit = nil;
        end

        -- **대상을 뺏었으면 `"@"`도 뺏는다.** `"@"`는 대상 유닛을 가리키는 포인터라
        -- 가리킬 것이 없으면 뜻이 없는데, 그걸 지우는 위쪽 검사는 대상 메뉴가 쓴 값을
        -- 보고 이미 지나갔다. 바로 위 두 갈래가 그 뒤에서 대상을 지운다.
        --
        -- **아래 hover 채워넣기보다 앞이어야 한다.** 저기서 `"hover"`가 들어가고 나면
        -- 남은 `"@"`가 그걸 가리켜서, focus를 겨누고 켠 조건이 **호버한 유닛** 조건으로
        -- 조용히 바뀐다. 갈 축이 없어 판정에서 빠지는 것보다 나쁘다 - 이쪽은 멀쩡히
        -- 동작하는 얼굴로 다른 일을 한다.
        --
        -- `""`도 같이 본다. 대상 메뉴는 그런 값을 못 쓰지만 공유 프로필로는 들어오고,
        -- 위쪽 검사의 목록에는 없다.
        if (conditions.units and (binding.unit == nil or binding.unit == "")) then
            conditions.units["@"] = nil;
        end

        -- **빈 표는 남기지 않는다.** `"@"`가 유일한 키였으면 위 두 자리가 그것을 지우고
        -- `{}`가 남는데, `conditions.units`가 있느냐를 게이트로 쓰는 자리가 여럿이라
        -- (`IsConditionalBinding`, 이슈 검사) 조건이 하나도 없는 액션이 조건부가 된다.
        if (conditions.units and not next(conditions.units)) then
            conditions.units = nil;
        end

        if (conditions.petbattle and conditions.specialbar) then
            conditions.specialbar = nil;
        end

        if (binding.hover and binding.unit == nil) then
            if (binding.ignoreHoverUnit) then
                binding.unit = "";
            else
                binding.unit = "hover";
            end
        end

        BuildUnitStates(binding);

        return binding;
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
--- **Where an action stands is the one thing not derived from the action.** `priority`, `hover`
--- and `isConditional` are; `layerRank`, `specRank` and `seq` are its place in the profile. Those
--- last three used to be written onto the binding from outside, which left the binding a pure
--- function of its action by convention rather than in fact.
---
--- `hover` is read **off the binding**, and that is not interchangeable with reading the action:
--- an action has no such field any more (`Profile.lua`'s `dbver <= 4` folded it into
--- `units["hover"]`), so taking it from there would hand the comparator `nil` every time
--- and kill its HOVER tier outright -- **the list would then draw in an order the key does not
--- fire in.** It is also **the raw value**: `false` and `nil` are different answers and the
--- comparator reads them apart, so it must not be folded to a boolean (`Ordering.lua`).
---
--- `dest` lets a caller hand its own table in. `BuildKeyMap` keeps one per binding and rebuilds
--- in place, because it runs over every bound action on every rebuild and used to allocate
--- nothing at all.
function DebindPrivate.MakeOrderRecord(action, layerRank, specRank, dest)
    local binding = GetBindingInfoForAction(action);
    dest = dest or {};
    dest.priority = action.priority or Constants.DEFAULT_PRIORITY;
    dest.hover = binding.hover;
    dest.isConditional = DebindPrivate.IsConditionalBinding(binding);
    dest.layerRank = layerRank;
    dest.specRank = specRank;
    dest.seq = action.seq;
    return dest;
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

--- "이 액션에 호버 조건이 켜져 있는가"를 **액션에서 바로** 답한다.
---
--- `binding.hover`를 쓰면 될 것 같지만, 아래 함수는 목록을 그릴 때 **행마다** 불린다 -
--- `GetBindingInfoForAction`을 거치면 그때마다 바인딩을 통째로 다시 만든다. 필요한 것은
--- 한 축뿐이라 여기서 읽는다.
---
--- 마이그레이션이 안 닿은 프로필(`action.hover`)도 `HoverConditionFromLegacy`와 같은 답을
--- 내야 한다. 저장된 조건이 있으면 그쪽이 이긴다 - 접기가 교집합하는 것과 같은 순서다.
local function ActionHoverIsOn(action)
    local conditions = action.conditions;
    local condition = conditions and conditions.units and conditions.units.hover;
    if (condition == nil) then
        return action.hover == true;
    end
    -- **접어서 본다.** 저장 원문에는 끈 조건도 남아 있어서 `{ exists = false }`도 `{ off = true }`도
    -- 표라는 이유만으로 "켜짐"이 된다. `DeriveHoverFields`와 정반대 답을 내면 왼/우클릭
    -- 유효성이 뒤집힌다.
    local folded = UnitConditionForBinding(condition);
    return folded ~= nil and folded ~= false;
end

function DebindPrivate.IsKeyInvalidForAction(action, key)
    local hoverIsOn = ActionHoverIsOn(action);
    if (key == DebindPrivate.gmKey1 or key == DebindPrivate.gmKey2) then
        return Constants.BINDING_ISSUE_NOT_SUPPORTED_GAMEMENU_KEY;
    elseif ((key == "BUTTON1" or key == "BUTTON2") and not hoverIsOn) then
        return Constants.BINDING_ISSUE_NOT_SUPPORTED_MOUSE_BUTTON;
    end
    if (hoverIsOn and action.type == Constants.COMMAND and DebindPrivate.GetMouseButtonAndPrefix(key)) then
        return Constants.BINDING_ISSUE_NOT_SUPPORTED_HOVER_CLICK_COMMAND;
    end
end

--- The first switch this action names that nothing defines, or nil.
---
--- **An action names a switch in three places, and they fail in different directions.**
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
--- The other is the target of an on/off/toggle action, which is `action.value`. That one is picked
--- from a list, so it cannot be mistyped. But the switch it was picked for can be deleted
--- afterwards, and a string from someone else arrives naming switches this profile has never had,
--- because an import plants no definitions (`devdocs/building-export-import.md`). Nothing goes
--- wide there: the press sets a name nothing reads and the row draws clean. **Which is the
--- problem.** The reader's only sign that the key does nothing is that nothing happens, and this
--- mark is the only thing that can say so out loud.
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
    if (not args) then
        return nil;
    end

    for i = 1, #args do
        local arg = args[i];
        -- 부정형(`no$typo`)도 같이 잡는다. 그쪽은 지금도 거짓으로 떨어져 위험하지는 않지만
        -- 오타인 것은 똑같고, 한쪽만 말해주면 고쳐도 왜 아직 안 되는지 알 수 없다.
        if (arg.type == Constants.MACROTEXT_ARG_SWITCH
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

--- Is this problem one that the row it sits on is **not** at fault for?
---
--- The one place that reads `BINDING_ISSUE_GRADES`, so that "what does a code with no grade mean"
--- is answered once. It answers false, which puts an ungraded code in with the loud ones -- see the
--- table's header for why that is the safe direction.
---
--- Takes the code rather than the action because the callers have already asked for one, often for
--- a single category, and asking again would run the whole of `GetBindingIssue` a second time.
function DebindPrivate.IsIssueMinor(issue)
    return Constants.BINDING_ISSUE_GRADES[issue] == Constants.ISSUE_GRADE_MINOR;
end

--- **Which of the two shapes each check reads is not a free choice, so it is made once here.**
---
--- The branches below used to start on the action and switch to the binding halfway down, with
--- nothing saying which reads had to come from where.
---
---   the binding, necessarily: `frameTypes` is nil'd for a non-hover binding there and only
---     there, `hover` has no action field at all any more, `unit` is the one the macro will aim
---     at rather than the one the user picked, and `unitStates` exists nowhere else
---   the binding, by choice: `groups`, `forms`, `bonusbars`. Normalizing only folds the
---     all-bits case to `_ALL`, so a zero reads the same either way. They come off the binding
---     so that this function speaks one shape
---   the action, necessarily: `key`, and the two checks that ask whether a name points at
---     something (`GetUndefinedSwitch`, `GetMissingMacroName`). None of the three is a
---     condition and none survives onto the binding
function DebindPrivate.GetBindingIssue(action, category, notCategory, arg)
    -- **없는 갈래로 물으면 아래 `if`가 전부 비켜가 nil이 나온다**, 그리고 그건 "문제 없음"과
    -- 생김새가 같다. 목록 행이 그렇게 죽은 갈래 넷을 묻고 있었고, 증상이 없어서 읽는 사람만
    -- 그 조건들에 검사가 있다고 읽었다. DEBUG에서만 세운다 - 배포본에서 터뜨릴 잘못이 아니다.
    if (Constants.DEBUG and category ~= nil and not Constants.BINDING_ISSUE_CATEGORIES[category]) then
        error("GetBindingIssue: 없는 갈래 " .. tostring(category), 2);
    end

    local issue;
    local binding = DebindPrivate.GetBindingInfoForAction(action);
    local conditions = binding.conditions;

    -- `notCategory = "unreachable"`은 이 갈래 **안의 도달불가 검사만** 끈다.
    --
    -- 다른 특성의 세계를 물어본 쪽(`Profile.lua`의 `CollectActionsForKey`)이 필요로 하는 것이
    -- 딱 그거다. 도달불가는 지금 이 특성으로 만든 키 맵에서 나오므로 그 세계에서는 참이 아닌데,
    -- **키 유효성은 특성과 무관하다.** 예전처럼 `notCategory = "key"`로 갈래째 끄면 그것까지
    -- 같이 꺼져서, 같은 저장 데이터가 보는 특성에 따라 ⚠를 달았다 뗐다 했다.
    if (not issue and (not category or category == "key") and notCategory ~= "key") then
        if (action.key) then
            issue = DebindPrivate.IsKeyInvalidForAction(action, action.key);
            if (not issue and notCategory ~= "unreachable") then
                if (DebindPrivate.IsUnreachableAction(action)) then
                    issue = Constants.BINDING_ISSUE_UNREACHABLE;
                end
            end
        end
    end

    if (not issue and (not category or category == "groups") and notCategory ~= "groups") then
        if (conditions.groups == 0) then
            issue = Constants.BINDING_ISSUE_GROUPS_NONE_SELECTED;
        end
    end

    if (not issue and (not category or category == "forms") and notCategory ~= "forms") then
        if (conditions.forms == 0) then
            issue = Constants.BINDING_ISSUE_FORMS_NONE_SELECTED;
        end
    end

    if (not issue and (not category or category == "bonusbars") and notCategory ~= "bonusbars") then
        if (conditions.bonusbars == 0) then
            issue = Constants.BINDING_ISSUE_BONUSBARS_NONE_SELECTED;
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
    if (not issue and (not category or category == "states") and notCategory ~= "states") then
        -- **Not chosen yet is asked first, because the other question cannot be asked of it.**
        -- An on/off/toggle action arrives from the picker with no target at all (§6-C), and
        -- "nothing defines nil" is a sentence with no name to print in it. `GetUndefinedSwitch`
        -- says nothing about a value that is not a string, which is the same guard the binding
        -- builder keeps (`UpdateBindings.lua`). The two have to agree, or an action drawn clean
        -- is one that turns back at the door with nothing said.
        if (Constants.SETSTATE_MODES[action.type] and type(action.value) ~= "string") then
            issue = Constants.BINDING_ISSUE_SWITCH_NONE_SELECTED;
        elseif (DebindPrivate.GetUndefinedSwitch(action)) then
            issue = Constants.BINDING_ISSUE_UNDEFINED_STATE;
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
    if (not issue and (not category or category == "macro") and notCategory ~= "macro") then
        if (DebindPrivate.GetMissingMacroName(action)) then
            issue = Constants.BINDING_ISSUE_MISSING_MACRO;
        end
    end

    if (not issue and (not category or category == "hover") and notCategory ~= "hover") then
        if (binding.hover ~= nil) then
            if (DebindPrivate.CliqueDetected) then
                issue = Constants.BINDING_ISSUE_CANNOT_USE_HOVER_WITH_CLIQUE;
            elseif (binding.hover and (HoverReactionMask(binding) == 0 or conditions.frameTypes == 0)) then
                issue = Constants.BINDING_ISSUE_HOVER_NONE_SELECTED;
            end
        end
    end

    if (not issue and (not category or category == "reactions") and notCategory ~= "reactions") then
        if (binding.hover) then
            if (HoverReactionMask(binding) == 0) then
                issue = Constants.BINDING_ISSUE_HOVER_NONE_SELECTED;
            end
        end
    end

    if (not issue and (not category or category == "frameTypes") and notCategory ~= "frameTypes") then
        if (binding.hover) then
            if (conditions.frameTypes == 0) then
                issue = Constants.BINDING_ISSUE_HOVER_NONE_SELECTED;
            end
        end
    end

    if (not issue and (not category or category == "unit") and notCategory ~= "unit") then
        if (binding.unit == "hover" and DebindPrivate.CliqueDetected) then
            issue = Constants.BINDING_ISSUE_CANNOT_USE_HOVER_WITH_CLIQUE;
        end
    end

    -- 한 유닛에 걸린 조건들의 **교집합이 비면** 그 유닛이 놓일 수 있는 상태가 없다는 뜻이다.
    -- hover 조건과 `"@"`와 명시 유닛 조건이 전부 같은 축에 접혀 있으므로(`BuildUnitStates`),
    -- 조합을 손으로 나열하지 않고 마스크가 0인지만 보면 된다.
    --
    -- 나열하던 시절에는 hover의 반응 제한과 `"@"` 조건이 어긋나는 경우가 빠져 있었다.
    -- 대상이 `@hover`인 액션에 hover 반응을 `우호`로, `"@"`를 `적대`로 걸면 영원히 안 걸리는데
    -- 두 값이 서로 다른 필드에 있어서 비교 대상이 아니었다. 접힌 지금은 그 경우가 따로가 아니다.
    --
    -- **한 유닛의 0은 여러 메뉴가 같이 만든다. 그래서 그 조건을 고칠 수 있는 묶음은 전부
    -- 빨갛게 칠한다.** 대상이 `hover`인 액션에 hover 조건을 [안 올렸을 때]로 걸면 겨눌 유닛이
    -- 놓일 자리가 없는데, 이건 hover 메뉴에서 풀 수도 있고 대상 메뉴에서 다른 유닛을 골라
    -- 풀 수도 있다. 한쪽만 칠하면 나머지 한쪽을 연 사람은 멀쩡한 화면을 본다 - 메뉴를 열었을
    -- 때 어디를 봐야 하는지가 이 색으로만 보이므로, 관련된 자리는 다 칠해야 한다.
    --
    -- 대신 **자기가 보여주지 않는 조건으로는 안 칠한다.** `Units` 묶음은 `"hover"`를 줄로
    -- 갖고 있지 않으므로 그 키의 0에는 반응하지 않는다.
    --
    -- **This zero is what keeps contradictory conditions out of the secure environment.** An
    -- action reported here never enters `KeyMap` (`Debind.lua`), so it reaches neither the solver
    -- nor `UpdateBindings` -- which is why `mergeUnitConditions` over there treats its own
    -- "impossible" answer as unreachable and skips the binding instead of representing it. That
    -- function's header spells out the reasoning; the two are one rule written twice, so **weaken
    -- this check and the runtime starts carrying conditions nothing can satisfy.**
    if (not issue and binding.unitStates and notCategory ~= "units"
            and (not category or category == "units" or category == "hover"
                or category == "unit")) then
        local target = arg;
        local askedAboutNothing;
        if (target == "@") then
            -- 겨눌 대상이 없으면 `"@"`가 가리킬 유닛도 없다. 여기서 `target`을 nil로 두면
            -- "짚어 물었다"가 "전부 물었다"로 바뀌어 **남의 유닛 모순이 이 서브메뉴에 뜬다.**
            target = binding.unit;
            askedAboutNothing = target == nil;
        end

        --- 이 묶음이 그 0에 **거들었는가.** 안 거든 묶음을 칠하면 아무것도 안 고른 메뉴가
        --- 빨개진다 - hover에서 반응을 하나도 안 고른 것만으로 `Target`이 붉어지던 것이 그것이다.
        local function contributed(unit)
            if (not conditions.units) then
                return false;
            end
            if (category == "unit") then
                return conditions.units["@"] ~= nil and unit == binding.unit;
            end
            return conditions.units[unit] ~= nil;
        end

        for unit, mask in pairs(binding.unitStates) do
            if (mask == 0 and not askedAboutNothing) then
                local mine;
                if (target ~= nil) then
                    -- 유닛 하나를 짚어 물었다(서브메뉴).
                    mine = target == unit;
                elseif (category == "hover") then
                    mine = unit == "hover" and contributed(unit);
                elseif (category == "unit") then
                    -- 대상 메뉴. `"@"`가 가리키는 유닛의 0이 곧 이 메뉴의 문제다.
                    mine = contributed(unit);
                elseif (category == "units") then
                    mine = unit ~= "hover";
                else
                    -- 액션 전체. 어느 묶음을 칠할지가 아니라 이 액션이 성립하느냐를 묻는다.
                    mine = true;
                end

                if (mine) then
                    issue = Constants.BINDING_ISSUE_CONDITIONS_NEVER;
                    break;
                end
            end
        end
    end

    if (not issue and (not category or category == "specialbar") and notCategory ~= "specialbar") then
        if ((conditions.specialbar and conditions.petbattle == false) or (conditions.petbattle and conditions.specialbar == false)) then
            issue = Constants.BINDING_ISSUE_CONDITIONS_NEVER;
        end
    end

    if (not issue and (not category or category == "petbattle") and notCategory ~= "petbattle") then
        if ((conditions.specialbar and conditions.petbattle == false) or (conditions.petbattle and conditions.specialbar == false)) then
            issue = Constants.BINDING_ISSUE_CONDITIONS_NEVER;
        end
    end

    return issue;
end



--- Is anything in the profile stopped by Clique being installed?
---
--- **What the login warning is gated on.** Saying it whenever Clique is loaded means saying it to
--- people who never bound anything to a unit frame, and a line that is noise on most logins is not
--- read on the one where it matters.
---
--- No count comes back. What the reader needs is whether to go and look, and this is a chat line
--- that scrolls past -- the window is where the affected rows are already red.
---
--- Asked once, from `PLAYER_LOGIN`. It is safe to ask there even though the key map has not been
--- built yet: `CliqueDetected` is read when the file loads and the addon list cannot change without
--- a reload, and the two branches below need nothing but the action itself.
---
--- Every layer, not just the live ones. The conflict is a property of the setup rather than of the
--- specialization being played, and switching spec does not come back here.
function DebindPrivate.HasBindingBlockedByClique()
    -- A shortcut, not the guard: `GetBindingIssue` raises this code only when the flag is set, so
    -- the answer is the same either way. What it buys is that everyone without Clique -- nearly
    -- everyone -- skips a walk over every action on the profile at login.
    if (not DebindPrivate.CliqueDetected) then
        return false;
    end

    local blocked = Constants.BINDING_ISSUE_CANNOT_USE_HOVER_WITH_CLIQUE;
    for _, layer in DebindPrivate.EnumerateAllProfileLayers() do
        for _, action in layer:Enumerate() do
            -- The same gate `BuildKeyMap` uses. A number stands in for a key not chosen yet and a
            -- badged action is quarantined -- neither was going to fire, so neither lost anything
            -- to Clique.
            if (type(action.key) == "string" and not action.arrivalID) then
                -- Two branches raise this code and the second is not reachable through the first:
                -- an action aimed at `hover` can carry the conflict with no hover condition set.
                if (DebindPrivate.GetBindingIssue(action, "hover") == blocked
                        or DebindPrivate.GetBindingIssue(action, "unit") == blocked) then
                    return true;
                end
            end
        end
    end
    return false;
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

--- Whether the menu stands [Convert to macro text] on this action.
---
--- **What enables it and what carries it out must not part company.** `ConvertToMacroText` does
--- nothing at all when it cannot build a body, and a menu item that does nothing when pressed says
--- why nowhere. A `MACRO` not holding a name is that case.
function DebindPrivate.CanConvertToMacroText(action)
    if (action.type == Constants.MACRO) then
        return type(action.value) == "string";
    end

    -- An on/off/toggle action that has not been told which switch yet is the same case: the body
    -- is `/click DebindStates <name>-<mode>`, and there is no name to put in it (§6-C).
    if (Constants.SETSTATE_MODES[action.type]) then
        return type(action.value) == "string";
    end

    return action.type == Constants.SPELL
        or action.type == Constants.ITEM
        or action.type == Constants.MOUNT
        or action.type == Constants.PETACTION
        or action.type == Constants.SETCUSTOM
        or action.type == Constants.WORLDMARKER;
end

function DebindPrivate.ConvertToMacroText(action)
    local macrotext, name, icon;

    if (action.type == Constants.SPELL or action.type == Constants.ITEM) then
        local slashCommand, spellOrItemName;
        if (action.type == Constants.SPELL) then
            slashCommand = SLASH_CAST1;
            local spellID = C_SpellBook.FindBaseSpellByID(action.value) or action.value;
            spellOrItemName, icon = GetSpellNameAndIconID(spellID);
            if (spellOrItemName) then
                local subSpellName = GetSpellSubtext(spellID);
                if (subSpellName and subSpellName ~= "") then
                    spellOrItemName = spellOrItemName .. "(" .. subSpellName .. ")";
                end
            end
            name = spellOrItemName;
        else
            slashCommand = SLASH_USE1;
            spellOrItemName = format("item:%d", action.value);
            name = C_Item.GetItemNameByID(action.value);
            icon = C_Item.GetItemIconByID(action.value);
        end

        if (spellOrItemName) then
            if (action.unit) then
                macrotext = format("%s [@%s] %s", slashCommand, action.unit, spellOrItemName);
            else
                macrotext = format("%1$s %3$s", slashCommand, action.unit, spellOrItemName);
            end
        end
    elseif (action.type == Constants.MACRO) then
        -- Asked only when the value is a name. Anything else is the shape `GetMissingMacroName`
        -- reports, and `GetMacroInfo(nil)` raises. Leaving it unanswered is the whole handling
        -- needed: the tail below already treats a nil body as "nothing to convert".
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
        macrotext = DebindPrivate.GetPetActionMacroText(action.value, action.unit);
        name = action.name;
        icon = action.icon;
    elseif (action.type == Constants.SETCUSTOM) then
        macrotext = format("/click DebindCustom%d hover", action.value);
        name = L["TYPE_SETCUSTOM" .. action.value];
        icon = 1505950;
    elseif (Constants.SETSTATE_MODES[action.type]) then
        -- **The body needs a name and a mode, and the action already holds both** -- the name in
        -- `value`, the mode decided by the type. The locale key assembles off the type for the
        -- same reason, which is half of why the type names are underscored (`Constants.lua`).
        macrotext = format("/click DebindStates %s-%s", action.value,
            Constants.SETSTATE_MODES[action.type]);
        name = format(L["TYPE_" .. strupper(action.type)], action.value);
        icon = 254885;
    elseif (action.type == Constants.WORLDMARKER) then
        macrotext = format("/wm %d", action.value);
        name = _G["WORLD_MARKER" .. action.value];
        icon = 4238933;
    end

    if (macrotext) then
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
                if (SPECIAL_UNITS[token]) then
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

    --- The same macro text with every `[$from]` and `[no$from]` renamed to `to`.
    ---
    --- **Whole tokens, never substrings.** A plain `gsub` on the name would also rewrite `$burstx`
    --- and `[@$burst]`, and what is being edited here is text the user typed by hand. Anything
    --- this touches that was not exactly this switch is a macro they have to find and fix without
    --- being told it changed.
    ---
    --- **Only inside `[...]`**, which is the same boundary `StripSwitchConditions` keeps and for
    --- the same reason: `/say [$burst]` outside a condition position is text, and a name that
    --- happens to appear in a chat line is not a reference to anything.
    ---
    --- Renaming a switch has to rewrite four kinds of reference and this is the one that cannot be
    --- done by moving a key: a condition, an on/off/toggle target and another switch's expression
    --- each hold the name whole, while a macro body holds it inside a sentence
    --- (`devdocs/redesigning-custom-states.md` §3).
    function DebindPrivate.RenameSwitchInMacroText(str, from, to)
        if (not str or not strfind(str, from, 1, true)) then
            return str;
        end
        _renameFrom, _renameTo = from, to;
        return (str:gsub("%[([^%[%]]*)%]", renameGroup));
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
--- `devdocs/redesigning-custom-states.md` rules out. The switch still works for this session: the
--- value lives in the restricted environment's `States`, and what is missing is only the memory of
--- it across a reload.
---
--- **The remembered value goes on the character, the live one on the definition**, and both are
--- `SetSwitchValue`'s to write (`Profile.lua`). The definition is account-wide, and while the
--- memory sat there too "remember" meant "remember what the character who logged out last left"
--- (§5 of `devdocs/redesigning-custom-states.md`). **Which of these reports becomes a memory is
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
--- (`devdocs/trimming-the-restricted-hot-paths.md`). The Switches tab reads `definition.value`,
--- which `SetSwitchValue` above still fills in, so what it lost was a reason to redraw rather
--- than the value to draw.
local function SwitchesChangedCallback()
    for state, newValue in pairs(_changedStates) do
        local options = DebindPrivate.ResolveSwitchDefinition(state);
        if (options) then
            DebindPrivate.SetSwitchValue(state, newValue);

            if (_lastSwitchValues[state] ~= newValue) then
                _lastSwitchValues[state] = newValue;

                if (options.displayMessage) then
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

function DebindPrivate.ApplyOptions(option)
    if (option == nil or option == "stateDriverUpdateThrottle") then
        local value = DebindPrivate.Options.stateDriverUpdateThrottle or STATE_DRIVER_UPDATE_THROTTLE_DEFAULT;
        if (type(value) == "number") then
            value = max(0, min(value, STATE_DRIVER_UPDATE_THROTTLE_DEFAULT));
            SecureStateDriverManager:SetAttribute("updatetime", value);
        end
    end
end
