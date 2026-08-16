local ADDON_NAME, DebindPrivate = ...;
local L                       = DebindPrivate.L;
local Constants               = DebindPrivate.Constants;

local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;
local CUSTOM_STATE_MODES      = Constants.CUSTOM_STATE_MODES;

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

local GetSpellTabNameAndIcon = DebindPrivate.GetSpellTabNameAndIcon;

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

function DebindPrivate.GetSetCustomStateModeAndIndex(value)
    local modeFlag = band(value, Constants.SETCUSTOM_MODE_MASK);
    local mode;
    if (modeFlag == Constants.SETCUSTOM_MODE_ON) then
        mode = "on";
    elseif (modeFlag == Constants.SETCUSTOM_MODE_OFF) then
        mode = "off";
    elseif (modeFlag == Constants.SETCUSTOM_MODE_TOGGLE) then
        mode = "toggle";
    else
        return;
    end
    local stateIndex = band(value, 0xf);
    return mode, stateIndex;
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
--- The hovered frame's unit is a unit, so it is stored as one: `checkedUnits["hover"]`
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

--- One stored unit condition -> the vocabulary the click-time snippet speaks.
---
--- The snippet compares against `true` / `false` / `"help"` / `"harm"` and has **no `bit`
--- library** (`RestrictedEnvironment.lua`), so it cannot be handed a mask and asked to intersect.
--- Until it learns to resolve a unit onto the axis itself, storage that says more than those four
--- values has nowhere to land.
---
--- Unrepresentable conditions come back as `"never"`. There is no safe rounding, but the two
--- directions are not equally bad **here**: a binding that stops firing is visible to whoever set
--- it, while one that fires wider than asked silently takes a key from another binding. The solver
--- is unaffected either way -- it reads `unitStates`, which stays exact.
---
--- Nothing produces such a condition yet: the menus write the same four values they always did,
--- just in the new shape.
local function UnitConditionToRuntimeScalar(value)
    -- 저장 모양이 들어올 수도 있어서 먼저 접는다. 이 함수를 부르는 것은 스펙뿐이고, 스펙은
    -- 마이그레이션이 방금 쓴 값을 그대로 넘긴다.
    value = UnitConditionForBinding(value);
    if (value == false or type(value) ~= "table") then
        return value;
    end

    local reactions = value.reaction;
    if (reactions == nil or reactions == Constants.REACTION_ALL) then
        return true;
    elseif (reactions == Constants.REACTION_HELP) then
        return "help";
    elseif (reactions == Constants.REACTION_HARM) then
        return "harm";
    end
    return "never";
end

DebindPrivate.UnitConditionToRuntimeScalar = UnitConditionToRuntimeScalar;

--- Fold everything that says something about a unit onto one mask per unit.
---
--- `binding.unitStates` is the only thing the solver reads about units. `checkedUnits` and
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
--- `binding.hover` / `binding.reactions` from the stored condition.
---
--- **Derived, not stored** (`Profile.lua`'s `dbver <= 4` step). Storage keeps one column for the
--- hovered frame's unit; these two are the view of it the rest of the addon already speaks --
--- ordering ranks a hover binding by `hover ~= nil` (`Ordering.lua`), the runtime routes a key to
--- the click path by it (`UpdateBindings.lua`'s `isClick`), the frame-type column gates on it
--- (`Solver.lua`), and key validity asks about it (`IsKeyInvalidForAction`).
---
--- `false` and `nil` are **different answers** and both are load-bearing -- "only when not
--- hovering" versus "does not care" -- so this cannot collapse to a boolean.
---
--- Idempotent, and called from both seams: `GetBindingInfoForAction` needs it before the checks
--- below it read `hover`, and `BuildUnitStates` needs it for bindings that never went through
--- there (the solver specs hand-write theirs).
local function DeriveHoverFields(binding)
    local condition = binding.checkedUnits and binding.checkedUnits.hover;
    if (condition == nil) then
        binding.hover = nil;
        binding.reactions = nil;
    elseif (condition == false) then
        binding.hover = false;
        binding.reactions = nil;
    else
        binding.hover = true;
        binding.reactions = condition.reaction ~= Constants.REACTION_ALL and condition.reaction
            or nil;
    end
end

DebindPrivate.DeriveHoverFields = DeriveHoverFields;

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

    -- The hover condition itself is not read here any more -- it lives in `checkedUnits["hover"]`
    -- and the loop below folds it like any other unit. What is left is the one thing the **key**
    -- says: a mouse button reaches the not-hovering point and nothing else, because the click
    -- fires wherever the cursor already is and over a unit frame the frame eats it.
    --
    -- **Only when nothing was said about hovering.** An explicit hover condition on a mouse
    -- button key is the user overriding that reading, and it has always won here -- narrowing it
    -- to absent as well would leave an empty box and delete the binding for a reason nobody set.
    if (binding.key and (binding.checkedUnits == nil or binding.checkedUnits.hover == nil)
            and DebindPrivate.GetMouseButtonAndPrefix(binding.key)) then
        narrow("hover", Constants.UNITSTATE_NONE);
    end

    local checkedUnits = binding.checkedUnits;
    if (checkedUnits) then
        for key, value in pairs(checkedUnits) do
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

    --- The two shapes this function converts between.
    ---
    --- An **action** is what a profile stores and what the menus edit. `Profile.lua`'s
    --- `KEYS_TO_SAVE` is the authoritative field list -- a field missing from there is not
    --- persisted no matter who writes it. A **binding** is derived per action and is what the
    --- solver and `UpdateBindings` read. The flow is one-way: a binding is rebuilt from its
    --- action, never written back, so normalizing a binding never edits what the user typed.
    ---
    --- ### `unit` and `checkedUnits` sound like one family and are opposites
    ---
    --- `unit` is **what the action aims at** -- the `[@unit]` of the macro, so it changes what the
    --- action *does*. Only the `Target` menu's radio list writes it. That menu passes `"unit"` as
    --- its issue category, which is why `GetBindingIssue(action, "unit")` asks about the target
    --- and not about any unit condition.
    ---
    --- `checkedUnits` is a **condition set** -- when the action fires, never what it acts on.
    --- The `Units` menu writes it, and so does the lower half of the `Target` menu (under `"@"`).
    ---
    --- And `binding.unit` is not `action.unit`. It is the unit the macro will actually aim at:
    --- cleared for types that cannot carry one, and **filled in with the hovered unit** when a
    --- hover action has no target of its own. Only `action.unit` answers "did the user point at
    --- something", which is why the `"@"` cleanup below runs before that fill-in.
    ---
    --- ### action fields
    ---
    ---   type, value      required. `Constants.SPELL` and friends; `value` is a spell/item id,
    ---                    macro body, pet command, ... depending on `type`
    ---   key              the key it is bound to. Without one the action is never bound.
    ---   name, icon       display only -- neither the solver nor the runtime reads them
    ---   seq              its place inside its key group, 1..n. Rewritten after every change to
    ---                    that group (`Profile.lua`'s `RenumberKeyGroup`), so it always says where
    ---                    the action stands rather than when it was made.
    ---   priority         number; `Constants.DEFAULT_PRIORITY` when absent
    ---   unit             a `UNIT_INFO` key. See above -- this is the target, not a condition.
    ---   checkedUnits     `{ [unit or "@"] = true | false | "help" | "harm" }`. `"@"` is a
    ---                    pointer to whatever `unit` names, so it dies when `unit` does.
    ---   hover            true | false | nil. `reactions` / `frameTypes` / `ignoreHoverUnit`
    ---                    only mean anything while this is true.
    ---   reactions        `REACTION_*` mask        frameTypes  `FRAMETYPE_*` mask
    ---   groups           `GROUP_*` mask           forms       `FORM_*` mask
    ---   bonusbars        `BONUSBAR_*` mask
    ---   known, combat, stealth, pet, petbattle, specialbar, extrabar, ignoreHoverUnit,
    ---   keepInBindingContext, $state1..$state5
    ---                    true | false | nil. `known` only means something on a spell;
    ---                    `keepInBindingContext` is read straight off the action and is one of
    ---                    the few fields no binding carries.
    ---
    --- ### what a binding has on top of those
    ---
    ---   spellName        resolved name, for display and macro text
    ---   unitStates       `{ [unit] = UNITSTATE_* mask }` from `BuildUnitStates` -- **the only
    ---                    thing the solver reads about units.** The hovered frame's unit rides
    ---                    this under the name `"hover"`.
    ---   unitStatesOpaque a `"@"` that could not be placed on any axis; puts the binding out of
    ---                    both solver roles rather than letting it look wider than it is
    ---   layerRank, isConditional
    ---                    filled in by `Debind.lua` after this returns, not here
    function DebindPrivate.GetBindingInfoForAction(action, update)
        local binding = _ActionToBindingCache[action];

        if (not binding) then
            binding = {};
            _ActionToBindingCache[action] = binding;
            update = true;
        end

        if (true) then
            -- if (update or action._dirty) then
            action._dirty = nil;

            binding.type, binding.value = action.type, action.value;
            binding.frameTypes, binding.ignoreHoverUnit = action.frameTypes, action.ignoreHoverUnit;
            binding.groups = action.groups;
            binding.combat = action.combat;
            binding.stealth = action.stealth;
            binding.known = action.known;
            binding.forms = action.forms;
            binding.bonusbars = action.bonusbars;
            binding.specialbar = action.specialbar;
            binding.extrabar = action.extrabar;
            binding.pet = action.pet;
            binding.petbattle = action.petbattle;
            binding.unit = action.unit;
            binding.key = action.key;
            binding.priority = action.priority or Constants.DEFAULT_PRIORITY;
            -- 저장 모양 -> 바인딩 모양. 꺼진 조건은 여기서 빠지므로 하류는 기억을 안 만난다.
            -- 남는 것이 없으면 표 자체를 안 만든다 - `binding.checkedUnits`가 있느냐를 게이트로
            -- 쓰는 자리가 여럿이라(이슈 검사, `IsConditionalBinding`), 빈 표는 조건이 하나도
            -- 없는 액션을 조건부로 만든다.
            binding.checkedUnits = nil;
            if (action.checkedUnits) then
                for unit, value in pairs(action.checkedUnits) do
                    local condition = UnitConditionForBinding(value);
                    if (condition ~= nil) then
                        binding.checkedUnits = binding.checkedUnits or {};
                        binding.checkedUnits[unit] = condition;
                    end
                end
            end

            -- Same idea for the old hover pair. It is raised **onto the copy**, never onto the
            -- action: `Profile.lua`'s migration owns rewriting what is stored, and an action this
            -- reached first would otherwise be rewritten by whoever read it.
            if (action.hover ~= nil) then
                binding.checkedUnits = binding.checkedUnits or {};
                binding.checkedUnits.hover = HoverConditionFromLegacy(
                    action.hover, action.reactions, binding.checkedUnits.hover);
            end

            -- Everything below this line reads `binding.hover`, so it has to be derived here and
            -- not only in `BuildUnitStates` at the end.
            DeriveHoverFields(binding);

            if action.type == Constants.SPELL and action.value then
                local spellInfo = C_Spell.GetSpellInfo(action.value)
                if spellInfo and spellInfo.name then
                    binding.spellName = spellInfo.name
                end
            end

            for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
                local state = "$state" .. stateIndex;
                binding[state] = action[state];
            end

            -- 의미 없는 조건들을 nil로 만듬. `reactions`는 위에서 파생될 때 이미 접혔다.
            if (binding.hover) then
                if (binding.frameTypes and band(binding.frameTypes, Constants.FRAMETYPE_ALL) == Constants.FRAMETYPE_ALL) then
                    binding.frameTypes = nil;
                end
            else
                binding.frameTypes = nil;
                binding.ignoreHoverUnit = nil;
            end

            if (binding.known and binding.type ~= Constants.SPELL) then
                binding.known = nil;
            end

            if (binding.checkedUnits) then
                -- truthy가 아니라 nil 검사다. "@"에 "없을 때"가 들어와 있으면(UI로는 못 만들지만
                -- 공유 프로필로는 들어온다) truthy 검사는 그걸 못 지우고, 걸 축이 없는 조건이
                -- 그대로 UpdateBindings까지 간다.
                if (binding.checkedUnits["@"] ~= nil and (binding.unit == nil or binding.unit == "none" or binding.unit == "player")) then
                    binding.checkedUnits["@"] = nil;
                end

                -- `"@"` and an explicit condition on the same unit used to be folded into one key
                -- here, by hand, for the scalar shape. **Both consumers intersect them
                -- themselves now**: `BuildUnitStates` with `band` for the solver, and
                -- `mergeUnitConditions` per axis on the way to the snippet. Folding again would
                -- be a third copy of one rule, and the one that drifts is the one nothing checks.
            end

            if (binding.groups and band(binding.groups, Constants.GROUP_ALL) == Constants.GROUP_ALL) then
                binding.groups = Constants.GROUP_ALL;
            end

            if (binding.forms and band(binding.forms, Constants.FORM_ALL) == Constants.FORM_ALL) then
                binding.forms = Constants.FORM_ALL;
            end

            if (binding.bonusbars and band(binding.bonusbars, Constants.BONUSBAR_ALL) == Constants.BONUSBAR_ALL) then
                binding.bonusbars = Constants.BONUSBAR_ALL;
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
            if (binding.checkedUnits and (binding.unit == nil or binding.unit == "")) then
                binding.checkedUnits["@"] = nil;
            end

            -- **빈 표는 남기지 않는다.** `"@"`가 유일한 키였으면 위 두 자리가 그것을 지우고
            -- `{}`가 남는데, `binding.checkedUnits`가 있느냐를 게이트로 쓰는 자리가 여럿이라
            -- (`IsConditionalBinding`, 이슈 검사) 조건이 하나도 없는 액션이 조건부가 된다.
            if (binding.checkedUnits and not next(binding.checkedUnits)) then
                binding.checkedUnits = nil;
            end

            if (binding.petbattle and binding.specialbar) then
                binding.specialbar = nil;
            end

            if (binding.hover and binding.unit == nil) then
                if (binding.ignoreHoverUnit) then
                    binding.unit = "";
                else
                    binding.unit = "hover";
                end
            end

            BuildUnitStates(binding);
        end

        return binding;
    end
end

local GetBindingInfoForAction = DebindPrivate.GetBindingInfoForAction


-- GetMouseButtonAndPrefix는 Solver.lua가 쓰는데 그쪽이 먼저 로드되므로 Constants.lua에 있음

function DebindPrivate.IsConditionalAction(action)
    local binding = GetBindingInfoForAction(action);
    return DebindPrivate.IsConditionalBinding(binding);
end

function DebindPrivate.IsConditionalBinding(binding)
    if (binding.hover ~= nil) then
        return true;
    end

    if (binding.groups ~= nil) then
        return true;
    end

    if (binding.bonusbars ~= nil) then
        return true;
    end

    if (binding.specialbar ~= nil) then
        return true;
    end

    if (binding.extrabar ~= nil) then
        return true;
    end

    if (binding.forms ~= nil) then
        return true;
    end

    if (binding.combat ~= nil) then
        return true;
    end

    if (binding.stealth ~= nil) then
        return true;
    end

    if (binding.known ~= nil) then
        return true;
    end

    if (binding.petbattle ~= nil) then
        return true;
    end

    if (binding.pet ~= nil) then
        return true;
    end

    if (binding.checkedUnits) then
        return true;
    end

    for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
        if (binding["$state" .. stateIndex] ~= nil) then
            return true;
        end
    end

    return false;
end

function DebindPrivate.IsInactiveAction(action)
    return not DebindPrivate.ActiveActions[action];
end

--- What to write where a key goes. **Not for a nil key** -- what an action with no key at all reads
--- as differs by where it is shown, so each of those places says its own word.
---
--- **A number is a key group with no key yet** (`NextSyntheticKey`) -- a set that came in a string,
--- or one the reader unbound whole. `GetBindingText` is not asked: a number is not a binding string,
--- and this is the guard that keeps it from being handed one.
---
--- **It reads as the client's `NOT_BOUND`, the same as no key at all**, because that is what it is:
--- the number is how the set is filed, not something the reader has. It used to print that number
--- ("Imported Binding #3"), from when the heading had nothing else to call the set by; the heading
--- names it now - the first action and how many follow (`DebindKeyHeaderMixin:UpdateSummary`).
---
--- `from` is the key it arrived on, which is `action.imported` for anything that came in a string.
--- Nothing reads it here at the moment.
function DebindPrivate.GetKeyDisplayText(key, from)
    if (type(key) == "number") then
        return L["OVERVIEW_NO_KEY"];
    end
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
    local condition = action.checkedUnits and action.checkedUnits.hover;
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

--- The first custom state this action's macro text names that nothing defines, or nil.
---
--- Hand-written macro text is the one place a state name is typed rather than picked, and
--- `ParseMacroText` lets any `[a-zA-Z0-9_]+` through. A name nothing defines used to reach
--- codegen and bake to `""` -- `[$typo]` became `[]`, which is **always true**. In a keybinding
--- addon that is the worst direction to fail in: the binding does not stop firing, it starts
--- firing everywhere. So the name is checked here and the action is marked, which keeps it out
--- of `KeyMap` entirely (`Debind.lua`'s `not issue` gate).
---
--- **Ask `CUSTOM_STATE_INDICES`, not `GetCustomStateOptions`** -- that one indexes the table by
--- name and errors on a name it does not know (`CustomStates.lua`).
---
--- Not memoized on purpose: `ParseMacroText` caches its own result per string, so a repeated
--- call here is a table lookup plus a walk over a handful of args.
function DebindPrivate.GetUndefinedCustomState(action)
    if (action.type ~= Constants.MACROTEXT or type(action.value) ~= "string") then
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
        if (arg.type == Constants.MACROTEXT_ARG_CUSTOM_STATE
                and not Constants.CUSTOM_STATE_INDICES[arg.name]) then
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
--- (`devdocs/building-export-import.md`, open question 7). Until now a `MACRO` naming nothing simply bound and
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

    -- Stored as the name (`ActionCatalog.lua`), but `GetMacroInfo` also takes a slot index and old
    -- data may hold one. Anything else is not a reference we can ask about.
    local value = action.value;
    local valueType = type(value);
    if (valueType ~= "string" and valueType ~= "number") then
        return nil;
    end

    if (GetMacroInfo(value)) then
        return nil;
    end
    return tostring(value);
end

local GROUP_ROLE_UNITS = {
    tank = Constants.GROUP_PARTY + Constants.GROUP_RAID,
    healer = Constants.GROUP_PARTY + Constants.GROUP_RAID,
    maintank = Constants.GROUP_RAID,
    mainassist = Constants.GROUP_RAID,
};

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

function DebindPrivate.GetBindingIssue(action, category, notCategory, arg)
    local issue;

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
        if (action.groups == 0) then
            issue = Constants.BINDING_ISSUE_GROUPS_NONE_SELECTED;
        end
    end

    if (not issue and (not category or category == "forms") and notCategory ~= "forms") then
        if (action.forms == 0) then
            issue = Constants.BINDING_ISSUE_FORMS_NONE_SELECTED;
        end
    end

    if (not issue and (not category or category == "bonusbars") and notCategory ~= "bonusbars") then
        if (action.bonusbars == 0) then
            issue = Constants.BINDING_ISSUE_BONUSBARS_NONE_SELECTED;
        end
    end

    -- 이 갈래에는 **조건 메뉴가 없다.** 이름은 매크로 본문에 손으로 적히고, 그래서 짚어 묻는
    -- 호출자도 없다 - `"states"`는 갈래를 끄기 위한 이름이지 어느 칸을 칠할지 고르는 이름이
    -- 아니다. 총괄 호출(`GetBindingIssue(action)`)로 걸리고, 행에서는 이름이 빨개진다
    -- (`ColoredNameAndIconForAction`), 툴팁이 어느 이름이 틀렸는지 말한다.
    if (not issue and (not category or category == "states") and notCategory ~= "states") then
        if (DebindPrivate.GetUndefinedCustomState(action)) then
            issue = Constants.BINDING_ISSUE_UNDEFINED_STATE;
        end
    end

    -- Same shape as the branch above: not a condition, but **a name that points at nothing**. So
    -- there is no caller that asks about it by name -- what needs fixing is the action itself, not
    -- a condition menu -- and `"target"` here is a name for switching the branch off, not for
    -- choosing which control to paint.
    --
    -- An action reported here drops out of `KeyMap` entirely (`Debind.lua`). **Nothing is lost by
    -- that**: it is a binding that already pressed and did nothing, so the only thing that changes
    -- is that it becomes visible.
    if (not issue and (not category or category == "target") and notCategory ~= "target") then
        if (DebindPrivate.GetMissingMacroName(action)) then
            issue = Constants.BINDING_ISSUE_MISSING_MACRO;
        end
    end

    local binding = DebindPrivate.GetBindingInfoForAction(action);
    if (not issue and (not category or category == "hover") and notCategory ~= "hover") then
        if (binding.hover ~= nil) then
            if (DebindPrivate.CliqueDetected) then
                issue = Constants.BINDING_ISSUE_CANNOT_USE_HOVER_WITH_CLIQUE;
            elseif (binding.hover and (binding.reactions == 0 or binding.frameTypes == 0)) then
                issue = Constants.BINDING_ISSUE_HOVER_NONE_SELECTED;
            end
        end
    end

    if (not issue and (not category or category == "reactions") and notCategory ~= "reactions") then
        if (binding.hover) then
            if (binding.reactions == 0) then
                issue = Constants.BINDING_ISSUE_HOVER_NONE_SELECTED;
            end
        end
    end

    if (not issue and (not category or category == "frameTypes") and notCategory ~= "frameTypes") then
        if (binding.hover) then
            if (binding.frameTypes == 0) then
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
    if (not issue and binding.unitStates and notCategory ~= "checkedUnits"
            and (not category or category == "checkedUnits" or category == "hover"
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
            if (not binding.checkedUnits) then
                return false;
            end
            if (category == "unit") then
                return binding.checkedUnits["@"] ~= nil and unit == binding.unit;
            end
            return binding.checkedUnits[unit] ~= nil;
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
                elseif (category == "checkedUnits") then
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

    -- FIXME
    -- if (not issue and (not category or (category == "groups" or category == "unit") and (notCategory ~= "groups" and notCategory ~= "unit"))) then
    --     if (binding.groups) then
    --         local groupFlags = GROUP_ROLE_UNITS[binding.checkUnitExists];
    --         if (groupFlags) then
    --             if (band(groupFlags, binding.groups) == 0) then
    --                 issue = Constants.BINDING_ISSUE_CONDITIONS_NEVER;
    --             end
    --         end
    --     end
    -- end

    if (not issue and (not category or category == "specialbar") and notCategory ~= "specialbar") then
        if ((binding.specialbar and binding.petbattle == false) or (binding.petbattle and binding.specialbar == false)) then
            issue = Constants.BINDING_ISSUE_CONDITIONS_NEVER;
        end
    end

    if (not issue and (not category or category == "petbattle") and notCategory ~= "petbattle") then
        if ((binding.specialbar and binding.petbattle == false) or (binding.petbattle and binding.specialbar == false)) then
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
            if (type(action.key) == "string" and not action.imported) then
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

function DebindPrivate.CanConvertToMacroText(action)
    return action.type == Constants.SPELL
        or action.type == Constants.ITEM
        or action.type == Constants.MACRO
        or action.type == Constants.MOUNT
        or action.type == Constants.PETACTION
        or action.type == Constants.SETCUSTOM
        or action.type == Constants.SETSTATE
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
        name, icon, macrotext = GetMacroInfo(action.value);
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
    elseif (action.type == Constants.SETSTATE) then
        local mode, stateIndex = DebindPrivate.GetSetCustomStateModeAndIndex(action.value);
        if (not mode or (mode ~= "on" and mode ~= "off" and mode ~= "toggle")) then
            return;
        end

        local state = "$state" .. stateIndex;
        macrotext = format("/click DebindStates %s-%s", state, mode);
        name = format(L["TYPE_SETSTATE_" .. strupper(mode) .. "_NUM"], stateIndex);
        icon = 254885;



        -- clickframe:SetAttribute("*type-" .. buttonname, "attribute");
        --     clickframe:SetAttribute("*attribute-frame-" .. buttonname, DebindPrivate.CustomStatesUpdaterFrame);
        --     clickframe:SetAttribute("*attribute-name-" .. buttonname, "$state" .. stateIndex);
        --     clickframe:SetAttribute("*attribute-value-" .. buttonname, mode);

        -- macrotext = format("/click DebindStates%d hover", action.value);
        -- name = L["TYPE_SETCUSTOM" .. action.value];
        -- icon = 1505950;
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
        local isComplex = false;
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
                                token = unit;
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
                        arg = appendArg(token, Constants.MACROTEXT_ARG_CUSTOM_STATE, str, reverse);
                        isComplex = true;
                    end
                end

                if (not arg) then
                    appendStr(str);
                end

                -- elseif (not unitsOnly and char == "$") then
                --     token = strsub(opt, 2, opt:len() + 1);
                --     if (strmatch(token, "^([a-zA-Z0-9_]+)$")) then
                --         addArg(opt, Constants.MACROTEXT_ARG_CUSTOM_STATE);
                --         isComplex = true;
                --     else
                --         appendStr(opt);
                --     end
            else
                appendStr(str);
            end
        end
        return isComplex;
    end

    function DebindPrivate.ParseMacroText(str, unitsOnly)
        local cached = _parsedMacrotextCache[str];

        if (cached == nil) then
            _fragments = {};
            _args = {};

            local isComplex;
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
                        if (parseOptions(unitsOnly, strsplit("[,]", s1))) then
                            isComplex = true;
                        end
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

            if (#_fragments > 1) then
                local normalized = table.concat(_fragments);
                if (isComplex) then
                    cached = { _fragments, _args, true, normalized };
                else
                    for i = 1, #_args do
                        local arg = _args[i];
                        assert(arg.type == Constants.MACROTEXT_ARG_UNIT);
                        local unitIndex = SPECIAL_UNITS[arg.name];
                        _fragments[i * 2] = format("%%%d$s", unitIndex);
                    end
                    local s = table.concat(_fragments);
                    cached = { s, _args, nil, normalized };
                end
            else
                cached = false;
            end

            _parsedMacrotextCache[str] = cached;
        end

        if (cached) then
            return cached[1], cached[2], cached[3], cached[4];
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
    --- 아이콘을 뽑을 때 쓴다. `GetMacrotextIcon`(DebindUI.lua)은 매크로텍스트를 **진짜 매크로
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
    local function isCustomStateToken(token)
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
            if (not isCustomStateToken(tokens[i])) then
                kept[#kept + 1] = tokens[i];
            end
        end
        return "[" .. table.concat(kept, ",") .. "]";
    end

    function DebindPrivate.StripCustomStateConditions(str)
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


-- do
--     local _parsedMacrotextCache = {};
--     local _unitSuffixes = {
--         target = true,
--         targettarget = true,
--         targettargettarget = true,
--         targettargettargettarget = true,
--         pet = true,
--         pettarget = true,
--         pettargettarget = true,
--         pettargettargettarget = true,
--     };

--     function DebindPrivate.ParseMacroText(str)
--         local cached = _parsedMacrotextCache[str];
--         if (cached == nil) then
--             local args;
--             local unitSeen;
--             local newstr = str:gsub("(%[[^%[%]]*@)(%w+)([^%[%]]*%])", function(pre, token, post)
--                 if (Constants.SPECIAL_UNITS[token]) then
--                     if (not args) then
--                         args = {};
--                         unitSeen = {};
--                     end
--                     if (not unitSeen[token]) then
--                         unitSeen[token] = true;
--                         tinsert(args, token);
--                     end
--                     return format("%s%%%d$s%s", pre, Constants.SPECIAL_UNITS[token], post);
--                 else
--                     for k, v in pairs(Constants.SPECIAL_UNITS) do
--                         if (strsub(token, 1, k:len()) == k) then
--                             local suffix = strsub(token, k:len() + 1);
--                             if (_unitSuffixes[suffix]) then
--                                 --if (suffix == "pet" or suffix == "target") then
--                                 if (not args) then
--                                     args = {};
--                                     unitSeen = {};
--                                 end
--                                 if (not unitSeen[k]) then
--                                     unitSeen[k] = true;
--                                     tinsert(args, k);
--                                 end
--                                 return format("%s%%%d$s%s%s", pre, v, suffix, post);
--                             end
--                         end
--                     end
--                 end
--             end);
--             if (args) then
--                 cached = { newstr, args };
--             else
--                 cached = false;
--             end
--             _parsedMacrotextCache[str] = cached;
--         end
--         if (cached) then
--             return cached[1], cached[2];
--         else
--             return str;
--         end
--     end

--     function DebindPrivate.ClearMacroTextCache(excludes)
--         for k in pairs(_parsedMacrotextCache) do
--             if (excludes[k] == nil) then
--                 _parsedMacrotextCache[k] = nil;
--             end
--         end
--     end
-- end


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

local _lastCustomStateValues = {};
local _changedStates = {};
local function CustomStatesChangedCallback()
    for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
        local state = "$state" .. stateIndex;
        if (_changedStates[state] ~= nil) then
            local options = DebindPrivate.GetCustomStateOptions(stateIndex);

            local newValue, savedValue = _changedStates[state], nil;
            if (options.mode == CUSTOM_STATE_MODES.MANUAL) then
                if (options.initialValue == nil) then
                    savedValue = newValue;
                else
                    savedValue = nil;
                end
            end

            options.value = newValue;
            options.savedValue = savedValue;

            if (_lastCustomStateValues[state] ~= newValue) then
                _lastCustomStateValues[state] = newValue;

                DebindPrivate.callbacks:Fire("STATE_CHANGED", state, newValue);

                if (options and options.displayMessage) then
                    local stateText = format(L["CUSTOM_STATE_NUM"], stateIndex);
                    local valueText = newValue and L["STATE_CHANGED_MESSAGE_ON"] or L["STATE_CHANGED_MESSAGE_OFF"];
                    DebindPrivate.DisplayMessage(format(L["STATE_CHANGED_MESSAGE"], stateText, valueText));
                end
            end
        end
    end
    wipe(_changedStates);
end

function DebindPrivate.OnCustomStateChanged(name, value)
    if (not next(_changedStates)) then
        C_Timer.After(0, CustomStatesChangedCallback);
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
    if (option == nil or option == "unitframeUseMouseDown") then
        if (not DebindPrivate.CliqueDetected) then
            -- `RegisterForClicks`를 여기서 직접 부르지 않는다. 대상은 **블리자드 유닛프레임
            -- 버튼**이라(`RegisterFrame`이 `IsProtected()` 참인 것만 넣는다) 전투 중에는
            -- 막힌다. 같은 일을 하는 `UpdateRegisteredClicks`에 전투 큐가 이미 있으므로
            -- 그쪽으로 보낸다 - 전투 중이면 밀렸다가 `PLAYER_REGEN_ENABLED`에 다시 돈다.
            -- (지금은 창이 전투 시작과 함께 숨어서 이 옵션에 손이 닿지 않을 뿐이다.)
            --
            -- `false`인 칸은 **등록을 거절당한 프레임**이다 - protected가 아니거나,
            -- forbidden이거나, 앵커가 묶여 있거나, `RegisterForClicks` 자체가 없거나.
            -- 걸러내지 않으면 마지막 경우에 nil을 부른다.
            for frame, info in pairs(DebindPrivate.ccframes) do
                if (info) then
                    DebindPrivate.UpdateRegisteredClicks(frame);
                end
            end
        end
    end
    -- if (option == nil or option == "removeStateDriverUpdateThrottle") then
    --     if (DebindPrivate.Options.removeStateDriverUpdateThrottle) then
    --         print("ApplyOptions", 0)
    --         SecureStateDriverManager:SetAttribute("updatetime", 0);
    --     else
    --         SecureStateDriverManager:SetAttribute("updatetime", STATE_DRIVER_UPDATE_THROTTLE_DEFAULT);
    --     end
    -- end
    if (option == nil or option == "stateDriverUpdateThrottle") then
        local value = DebindPrivate.Options.stateDriverUpdateThrottle or STATE_DRIVER_UPDATE_THROTTLE_DEFAULT;
        if (type(value) == "number") then
            value = max(0, min(value, STATE_DRIVER_UPDATE_THROTTLE_DEFAULT));
            SecureStateDriverManager:SetAttribute("updatetime", value);
        end
    end
end
