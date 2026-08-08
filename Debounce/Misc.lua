local _, DebouncePrivate      = ...;
local L                       = DebouncePrivate.L;
local Constants               = DebouncePrivate.Constants;

local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;
local CUSTOM_STATE_MODES      = Constants.CUSTOM_STATE_MODES;

local dump                    = DebouncePrivate.dump;
local band                    = bit.band;
local tinsert, wipe           = tinsert, wipe;
local pairs, ipairs           = pairs, ipairs;
local GetMountInfoByID        = C_MountJournal.GetMountInfoByID;
local GetSpellSubtext         = C_Spell.GetSpellSubtext;


local STATE_DRIVER_UPDATE_THROTTLE_DEFAULT = 0.2;

function DebouncePrivate.GetSpellNameAndIconID(spellId)
    local spellInfo = C_Spell.GetSpellInfo(spellId);
    if (spellInfo) then
        return spellInfo.name, spellInfo.iconID;
    end
end

local GetSpellNameAndIconID = DebouncePrivate.GetSpellNameAndIconID;

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
function DebouncePrivate.IsEmptyCallPetSlot(spellID)
    local petIndex, petName = GetCallPetSpellInfo(spellID);
    return petIndex ~= nil and (not petName or petName == "");
end

local IsEmptyCallPetSlot = DebouncePrivate.IsEmptyCallPetSlot;

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
function DebouncePrivate.GetFlyoutNameAndIcon(flyoutID, isOffSpec)
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
function DebouncePrivate.GetFlyoutCastableSlots(flyoutID, out)
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

function DebouncePrivate.GetSpellTabNameAndIcon(index)
    local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(index);
    if skillLineInfo then
        return skillLineInfo.name, skillLineInfo.iconID;
    end
end

local GetSpellTabNameAndIcon = DebouncePrivate.GetSpellTabNameAndIcon;

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
function DebouncePrivate.GetPetActionCommandByActionID(actionID)
    return actionID and PET_ACTION_SLASH_BY_ID[actionID] or nil;
end

function DebouncePrivate.PetActionTakesUnit(command)
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
function DebouncePrivate.GetPetActionMacroText(command, unit)
    local slash = command and _G["SLASH_" .. command .. "1"];
    if (not slash) then
        return nil;
    end
    if (unit and unit ~= "" and DebouncePrivate.PetActionTakesUnit(command)) then
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
function DebouncePrivate.GetMacroSlotLimits()
    local macroConsts = _G.Constants and _G.Constants.MacroConsts;
    local account = (macroConsts and macroConsts.MAX_ACCOUNT_MACROS) or _G.MAX_ACCOUNT_MACROS or 120;
    local character = (macroConsts and macroConsts.MAX_CHARACTER_MACROS) or _G.MAX_CHARACTER_MACROS or 30;
    return account, character;
end

function DebouncePrivate.GetSetCustomStateModeAndIndex(value)
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

do
    local _ActionToBindingCache = setmetatable({}, { __mode = "kv" });

    function DebouncePrivate.GetBindingInfoForAction(action, update)
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
            binding.hover, binding.reactions, binding.frameTypes, binding.ignoreHoverUnit = action.hover, action.reactions, action.frameTypes, action.ignoreHoverUnit;
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
            binding.checkedUnits = action.checkedUnits and CopyTable(action.checkedUnits) or nil;

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

            -- 의미 없는 조건들을 nil로 만듬
            if (binding.hover) then
                if (binding.reactions and band(binding.reactions, Constants.REACTION_ALL) == Constants.REACTION_ALL) then
                    binding.reactions = nil;
                end
                if (binding.frameTypes and band(binding.frameTypes, Constants.FRAMETYPE_ALL) == Constants.FRAMETYPE_ALL) then
                    binding.frameTypes = nil;
                end
            else
                binding.reactions = nil;
                binding.frameTypes = nil;
                binding.ignoreHoverUnit = nil;
            end

            if (binding.known and binding.type ~= Constants.SPELL) then
                binding.known = nil;
            end

            if (binding.checkedUnits) then
                if (binding.checkedUnits["@"] and (binding.unit == nil or binding.unit == "none" or binding.unit == "player")) then
                    binding.checkedUnits["@"] = nil;
                end

                if (binding.checkedUnits["@"] ~= nil and binding.checkedUnits[binding.unit] ~= nil) then
                    if (binding.checkedUnits["@"] == binding.checkedUnits[binding.unit]) then
                        binding.checkedUnits["@"] = nil;
                    elseif (binding.checkedUnits["@"] == true and binding.checkedUnits[binding.unit]) then
                        binding.checkedUnits["@"] = nil;
                    elseif (binding.checkedUnits["@"] and binding.checkedUnits[binding.unit] == true) then
                        binding.checkedUnits[binding.unit] = binding.checkedUnits["@"];
                        binding.checkedUnits["@"] = nil;
                    end
                end
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
                    and not DebouncePrivate.PetActionTakesUnit(binding.value)) then
                -- 펫 명령은 타입만으로 안 갈린다. 대상 메뉴도 같은 것을 보고 안 열린다
                -- (`DropDownMenus.lua`). 여기서도 지워야 옛 프로필에 남은 값이 안 따라온다.
                binding.unit = nil;
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
        end

        return binding;
    end
end

local GetBindingInfoForAction = DebouncePrivate.GetBindingInfoForAction


-- GetMouseButtonAndPrefix는 Solver.lua가 쓰는데 그쪽이 먼저 로드되므로 Constants.lua에 있음

function DebouncePrivate.IsConditionalAction(action)
    local binding = GetBindingInfoForAction(action);
    return DebouncePrivate.IsConditionalBinding(binding);
end

function DebouncePrivate.IsConditionalBinding(binding)
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

function DebouncePrivate.IsInactiveAction(action)
    return not DebouncePrivate.ActiveActions[action];
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
function DebouncePrivate.RefreshGameMenuKeys()
    DebouncePrivate.gmKey1, DebouncePrivate.gmKey2 = GetBindingKey("TOGGLEGAMEMENU");
end

function DebouncePrivate.IsKeyInvalidForAction(action, key)
    if (key == DebouncePrivate.gmKey1 or key == DebouncePrivate.gmKey2) then
        return Constants.BINDING_ISSUE_NOT_SUPPORTED_GAMEMENU_KEY;
    elseif ((key == "BUTTON1" or key == "BUTTON2") and not action.hover) then
        return Constants.BINDING_ISSUE_NOT_SUPPORTED_MOUSE_BUTTON;
    end
    if (action.hover and action.type == Constants.COMMAND and DebouncePrivate.GetMouseButtonAndPrefix(key)) then
        return Constants.BINDING_ISSUE_NOT_SUPPORTED_HOVER_CLICK_COMMAND;
    end
end

local GROUP_ROLE_UNITS = {
    tank = Constants.GROUP_PARTY + Constants.GROUP_RAID,
    healer = Constants.GROUP_PARTY + Constants.GROUP_RAID,
    maintank = Constants.GROUP_RAID,
    mainassist = Constants.GROUP_RAID,
};

function DebouncePrivate.GetBindingIssue(action, category, notCategory, arg)
    local issue;

    -- `notCategory = "unreachable"`은 이 갈래 **안의 도달불가 검사만** 끈다.
    --
    -- 다른 특성의 세계를 물어본 쪽(`Profile.lua`의 `CollectActionsForKey`)이 필요로 하는 것이
    -- 딱 그거다. 도달불가는 지금 이 특성으로 만든 키 맵에서 나오므로 그 세계에서는 참이 아닌데,
    -- **키 유효성은 특성과 무관하다.** 예전처럼 `notCategory = "key"`로 갈래째 끄면 그것까지
    -- 같이 꺼져서, 같은 저장 데이터가 보는 특성에 따라 ⚠를 달았다 뗐다 했다.
    if (not issue and (not category or category == "key") and notCategory ~= "key") then
        if (action.key) then
            issue = DebouncePrivate.IsKeyInvalidForAction(action, action.key);
            if (not issue and notCategory ~= "unreachable") then
                if (DebouncePrivate.IsUnreachableAction(action)) then
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

    local binding = DebouncePrivate.GetBindingInfoForAction(action);
    if (not issue and (not category or category == "hover") and notCategory ~= "hover") then
        if (binding.hover ~= nil) then
            if (DebouncePrivate.CliqueDetected) then
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
        if (binding.unit == "hover" and DebouncePrivate.CliqueDetected) then
            issue = Constants.BINDING_ISSUE_CANNOT_USE_HOVER_WITH_CLIQUE;
        end
    end

    if (not issue and binding.checkedUnits and (not category or category == "checkedUnits") and notCategory ~= "checkedUnits") then
        if (binding.hover == false and binding.checkedUnits["hover"]) then
            issue = Constants.BINDING_ISSUE_CONDITIONS_NEVER;
        elseif (binding.hover and binding.checkedUnits["hover"] == false) then
            issue = Constants.BINDING_ISSUE_CONDITIONS_NEVER;
        -- 둘 다 있을 때만 비교한다. 개별 유닛 조건이 없으면 nil이 "다른 값"으로 읽혀서
        -- "@"만 걸어둔 액션("대상이 존재할 때만")이 곧바로 모순으로 잡혔다.
        -- 둘 다 있는 경우 남는 조합은 위 GetBindingInfoForAction의 정규화가 포섭 관계를
        -- (true vs "help" 같은) 이미 걷어낸 뒤라 전부 진짜 모순이다.
        elseif (binding.checkedUnits["@"] ~= nil and binding.checkedUnits[binding.unit] ~= nil) then
            if (arg == nil or arg == "@" or arg == binding.unit) then
                if (binding.checkedUnits["@"] ~= binding.checkedUnits[binding.unit]) then
                    issue = Constants.BINDING_ISSUE_CONDITIONS_NEVER;
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



-- 행동단축바 끌어다 놓은 탈것을 클릭하면 필요한 경우 자동으로 변신이 해제되지만 C_MountJournal.SummonByID를 사용하는 경우 자동으로 변신이 해제되지 않음.
-- 'autounshift'가 켜져있어도 마찬가지!
local SUMMON_MOUNT_MACROTEXT = SLASH_SCRIPT1 .. " C_MountJournal.SummonByID(%d)";
if (select(2, UnitClass("player")) == "DRUID") then
    SUMMON_MOUNT_MACROTEXT = SLASH_CANCELFORM1 .. " [form:1/2/5/6,nocombat]\n" .. SUMMON_MOUNT_MACROTEXT;
end

function DebouncePrivate.GetMountMacroText(value)
    if (value == 268435455) then
        value = 0;
    end
    return SUMMON_MOUNT_MACROTEXT:format(value);
end

function DebouncePrivate.CanConvertToMacroText(action)
    return action.type == Constants.SPELL
        or action.type == Constants.ITEM
        or action.type == Constants.MACRO
        or action.type == Constants.MOUNT
        or action.type == Constants.PETACTION
        or action.type == Constants.SETCUSTOM
        or action.type == Constants.SETSTATE
        or action.type == Constants.WORLDMARKER;
end

function DebouncePrivate.ConvertToMacroText(action)
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
            macrotext = DebouncePrivate.GetMountMacroText(value);
        end
    elseif (action.type == Constants.PETACTION) then
        -- 이건 이미 매크로텍스트다 - 바인딩이 나갈 때와 **같은 함수로** 본문을 만든다.
        -- 이름과 아이콘은 액션이 들고 있는 것을 그대로 옮긴다(펫이 없으면 다시 못 푼다).
        macrotext = DebouncePrivate.GetPetActionMacroText(action.value, action.unit);
        name = action.name;
        icon = action.icon;
    elseif (action.type == Constants.SETCUSTOM) then
        macrotext = format("/click DebounceCustom%d hover", action.value);
        name = L["TYPE_SETCUSTOM" .. action.value];
        icon = 1505950;
    elseif (action.type == Constants.SETSTATE) then
        local mode, stateIndex = DebouncePrivate.GetSetCustomStateModeAndIndex(action.value);
        if (not mode or (mode ~= "on" and mode ~= "off" and mode ~= "toggle")) then
            return;
        end

        local state = "$state" .. stateIndex;
        macrotext = format("/click DebounceStates %s-%s", state, mode);
        name = format(L["TYPE_SETSTATE_" .. strupper(mode) .. "_NUM"], stateIndex);
        icon = 254885;



        -- clickframe:SetAttribute("*type-" .. buttonname, "attribute");
        --     clickframe:SetAttribute("*attribute-frame-" .. buttonname, DebouncePrivate.CustomStatesUpdaterFrame);
        --     clickframe:SetAttribute("*attribute-name-" .. buttonname, "$state" .. stateIndex);
        --     clickframe:SetAttribute("*attribute-value-" .. buttonname, mode);

        -- macrotext = format("/click DebounceStates%d hover", action.value);
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

    function DebouncePrivate.ParseMacroText(str, unitsOnly)
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

    function DebouncePrivate.ClearMacroTextCache(excludes)
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
    --- 아이콘을 뽑을 때 쓴다. `GetMacrotextIcon`(DebounceUI.lua)은 매크로텍스트를 **진짜 매크로
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

    function DebouncePrivate.StripCustomStateConditions(str)
        if (not str or not strfind(str, "$", 1, true)) then
            return str;
        end
        return (str:gsub("%[([^%]]*)%]", stripGroup));
    end
end


do
    local _arr = {};
    local _tmp = {};

    local function cross(opts)
        local ret = {};

        for i = 1, #_arr do
            local s = _arr[i];
            for j = 1, #opts do
                if (s == "") then
                    tinsert(ret, opts[j]);
                else
                    tinsert(ret, s .. "," .. opts[j]);
                end
            end
        end

        return ret;
    end

    local function BuildMacroConditional(binding, isClick)
        wipe(_arr);
        wipe(_tmp);
        dump("BuildMacroConditional", { binding, isClick })

        local helpOrHarm;
        if (isClick) then
            -- click binding의 경우 @hover를 @mouseover로 대체해도 안전하다.
            if (binding.hover and binding.reactions ~= nil and band(binding.reactions, Constants.REACTION_ALL) ~= Constants.REACTION_ALL) then
                if (binding.reactions == Constants.REACTION_HELP) then
                    _tmp[#_tmp + 1] = "@mouseover,help";
                elseif (binding.reactions == Constants.REACTION_HARM) then
                    _tmp[#_tmp + 1] = "@mouseover,harm";
                elseif (binding.reactions == (Constants.REACTION_HELP + Constants.REACTION_OTHER)) then
                    _tmp[#_tmp + 1] = "@mouseover,noharm";
                elseif (binding.reactions == (Constants.REACTION_HARM + Constants.REACTION_OTHER)) then
                    _tmp[#_tmp + 1] = "@mouseover,nohelp";
                elseif (binding.reactions == Constants.REACTION_HELP + Constants.REACTION_HARM) then
                    _tmp[#_tmp + 1] = "@mouseover";
                    helpOrHarm = true;
                end
            end
        else
            if (binding.hover) then
                if (binding.reactions == Constants.REACTION_HELP) then
                    _tmp[#_tmp + 1] = "@hover,help"
                elseif (binding.reactions == Constants.REACTION_HARM) then
                    _tmp[#_tmp + 1] = "@hover,harm"
                elseif (binding.reactions == (Constants.REACTION_HELP + Constants.REACTION_OTHER)) then
                    _tmp[#_tmp + 1] = "@hover,noharm"
                elseif (binding.reactions == (Constants.REACTION_HARM + Constants.REACTION_OTHER)) then
                    _tmp[#_tmp + 1] = "@hover,nohelp"
                elseif (binding.reactions == Constants.REACTION_HELP + Constants.REACTION_HARM) then
                    _tmp[#_tmp + 1] = "@hover"
                    helpOrHarm = true;
                else
                    _tmp[#_tmp + 1] = "@hover,exists"
                end
            end
        end


        if (binding.groups ~= nil) then
            if (binding.groups == Constants.GROUP_NONE) then
                _tmp[#_tmp + 1] = "nogroup";
            elseif (binding.groups == Constants.GROUP_PARTY) then
                _tmp[#_tmp + 1] = "group:party";
            elseif (binding.groups == Constants.GROUP_RAID) then
                _tmp[#_tmp + 1] = "group:raid";
            else
                _tmp[#_tmp + 1] = "group";
            end
        end

        if (binding.combat ~= nil) then
            if (binding.combat == true) then
                _tmp[#_tmp + 1] = "combat";
            else
                _tmp[#_tmp + 1] = "nocombat";
            end
        end

        if (binding.stealth ~= nil) then
            if (binding.stealth == true) then
                _tmp[#_tmp + 1] = "stealth";
            else
                _tmp[#_tmp + 1] = "nostealth";
            end
        end

        if (binding.known ~= nil) then
            if (binding.known == true) then
                _tmp[#_tmp + 1] = "known:" .. binding.spellName;
            end
        end

        if (binding.forms ~= nil) then
            if (binding.forms == 0) then
                return;
            end
            local s;
            for i = 0, 10 do
                local f = 2 ^ i;
                if (band(binding.forms, f) == f) then
                    if (s) then
                        s = s .. "/";
                    else
                        s = "form:";
                    end
                    s = s .. i;
                end
            end
            _tmp[#_tmp + 1] = s;
        end

        if (binding.bonusbars ~= nil) then
            if (binding.forms == 0) then
                return;
            end
            local s;
            for i = 0, 5 do
                local f = 2 ^ i;
                if (band(binding.bonusbars, f) == f) then
                    if (s) then
                        s = s .. "/";
                    else
                        s = "bonusbar:";
                    end
                    s = s .. i;
                end
            end
            _tmp[#_tmp + 1] = s;
        end

        if (binding.extrabar ~= nil) then
            if (binding.extrabar == true) then
                _tmp[#_tmp + 1] = "extrabar";
            else
                _tmp[#_tmp + 1] = "noextrabar";
            end
        end

        if (binding.pet ~= nil) then
            if (binding.pet == true) then
                _tmp[#_tmp + 1] = "pet";
            else
                _tmp[#_tmp + 1] = "nopet";
            end
        end

        if (binding.specialbar == false) then
            _tmp[#_tmp + 1] = "nopossessbar,novehicleui,noshapeshift,nooverridebar,nopetbattle";
        elseif (binding.petbattle ~= nil) then
            if (binding.petbattle == true) then
                _tmp[#_tmp + 1] = "petbattle";
            else
                _tmp[#_tmp + 1] = "nopetbattle";
            end
        end

        for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
            local state = "$state" .. stateIndex;
            local value = binding[state];
            if (value == true) then
                _tmp[#_tmp + 1] = state;
            elseif (value == false) then
                _tmp[#_tmp + 1] = "no" .. state;
            end
        end

        _arr[1] = table.concat(_tmp, ",");

        if (helpOrHarm) then
            _arr = cross({ "help", "harm" });
        end

        if (binding.specialbar) then
            if (binding.petbattle == nil) then
                _arr = cross({ "possessbar", "vehicleui", "shapeshift", "overridebar", "petbattle" });
            else
                _arr = cross({ "possessbar", "vehicleui", "shapeshift", "overridebar" });
            end
        end

        return table.concat(_arr, "][");
    end

    function DebouncePrivate.CombineIfPossible(bindings, isClick)
        for i = 1, #bindings do
            if (not bindings[i].clickframe) then
                --print("no clickframe")
                return;
            end
        end

        local first = true;
        local combinables = {};
        for i = #bindings, 1, -1 do
            local binding = bindings[i];
            if ((isClick and binding.isClick) or (not isClick and binding.isNonClick)) then
                local opts = BuildMacroConditional(binding, isClick);
                if (not opts or (first and opts ~= "")) then
                    --print("last binding should not be conditional", opts)
                    return;
                end

                if (opts ~= "") then
                    tinsert(combinables, 1, format("[%s] %s %s %s", opts, binding.clickframe:GetName(), binding.clickbutton, ACTION_BUTTON_USE_KEY_DOWN and "true" or ""));
                else
                    tinsert(combinables, 1, format("%s %s %s", binding.clickframe:GetName(), binding.clickbutton, ACTION_BUTTON_USE_KEY_DOWN and "true" or ""));
                end
                first = false;
            end
        end

        return combinables and #combinables > 0 and "/click " .. table.concat(combinables, ";") or nil;
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

--     function DebouncePrivate.ParseMacroText(str)
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

--     function DebouncePrivate.ClearMacroTextCache(excludes)
--         for k in pairs(_parsedMacrotextCache) do
--             if (excludes[k] == nil) then
--                 _parsedMacrotextCache[k] = nil;
--             end
--         end
--     end
-- end


local FULL_PLAYER_NAME = FULL_PLAYER_NAME;
function DebouncePrivate.GetUnitFullName(unit)
    local name, realm = UnitName(unit);
    if (realm and realm ~= "") then
        name = FULL_PLAYER_NAME:format(name, realm);
    end
    return name;
end

function DebouncePrivate.OnSpecialUnitChanged(alias, value)
    local unit = value or nil;
    local prev = DebouncePrivate.Units[alias];
    DebouncePrivate.Units[alias] = unit;

    if (prev ~= unit) then
        DebouncePrivate.callbacks:Fire("UNIT_CHANGED", alias, unit);
    end
end

local _lastCustomStateValues = {};
local _changedStates = {};
local function CustomStatesChangedCallback()
    for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
        local state = "$state" .. stateIndex;
        if (_changedStates[state] ~= nil) then
            local options = DebouncePrivate.GetCustomStateOptions(stateIndex);

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

                DebouncePrivate.callbacks:Fire("STATE_CHANGED", state, newValue);

                if (options and options.displayMessage) then
                    local stateText = format(L["CUSTOM_STATE_NUM"], stateIndex);
                    local valueText = newValue and L["STATE_CHANGED_MESSAGE_ON"] or L["STATE_CHANGED_MESSAGE_OFF"];
                    DebouncePrivate.DisplayMessage(format(L["STATE_CHANGED_MESSAGE"], stateText, valueText));
                end
            end
        end
    end
    wipe(_changedStates);
end

function DebouncePrivate.OnCustomStateChanged(name, value)
    if (not next(_changedStates)) then
        C_Timer.After(0, CustomStatesChangedCallback);
    end

    _changedStates[name] = value;
end

function DebouncePrivate.DisplayMessage(message, r, g, b)
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

function DebouncePrivate.ApplyOptions(option)
    if (option == nil or option == "unitframeUseMouseDown") then
        if (not DebouncePrivate.CliqueDetected) then
            -- `RegisterForClicks`를 여기서 직접 부르지 않는다. 대상은 **블리자드 유닛프레임
            -- 버튼**이라(`RegisterFrame`이 `IsProtected()` 참인 것만 넣는다) 전투 중에는
            -- 막힌다. 같은 일을 하는 `UpdateRegisteredClicks`에 전투 큐가 이미 있으므로
            -- 그쪽으로 보낸다 - 전투 중이면 밀렸다가 `PLAYER_REGEN_ENABLED`에 다시 돈다.
            -- (지금은 창이 전투 시작과 함께 숨어서 이 옵션에 손이 닿지 않을 뿐이다.)
            --
            -- `false`인 칸은 **등록을 거절당한 프레임**이다 - protected가 아니거나,
            -- forbidden이거나, 앵커가 묶여 있거나, `RegisterForClicks` 자체가 없거나.
            -- 걸러내지 않으면 마지막 경우에 nil을 부른다.
            for frame, info in pairs(DebouncePrivate.ccframes) do
                if (info) then
                    DebouncePrivate.UpdateRegisteredClicks(frame);
                end
            end
        end
    end
    -- if (option == nil or option == "removeStateDriverUpdateThrottle") then
    --     if (DebouncePrivate.Options.removeStateDriverUpdateThrottle) then
    --         print("ApplyOptions", 0)
    --         SecureStateDriverManager:SetAttribute("updatetime", 0);
    --     else
    --         SecureStateDriverManager:SetAttribute("updatetime", STATE_DRIVER_UPDATE_THROTTLE_DEFAULT);
    --     end
    -- end
    if (option == nil or option == "stateDriverUpdateThrottle") then
        local value = DebouncePrivate.Options.stateDriverUpdateThrottle or STATE_DRIVER_UPDATE_THROTTLE_DEFAULT;
        if (type(value) == "number") then
            value = max(0, min(value, STATE_DRIVER_UPDATE_THROTTLE_DEFAULT));
            SecureStateDriverManager:SetAttribute("updatetime", value);
        end
    end
end
