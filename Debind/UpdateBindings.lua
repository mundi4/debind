local _, DebindPrivate      = ...;
local Constants               = DebindPrivate.Constants;
local BindingDriver           = DebindPrivate.BindingDriver;
local DefaultClickFrame       = DebindPrivate.DefaultClickFrame;

local L                       = DebindPrivate.L;
local DEBUG                   = DebindPrivate.DEBUG;
local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;
local BASIC_UNITS             = Constants.BASIC_UNITS;
local NIL                     = Constants.NIL;
local CUSTOM_STATE_MODES      = Constants.CUSTOM_STATE_MODES;



local dump                               = DebindPrivate.dump;
local luatype                            = type;
local format, tostring, select           = format, tostring, select;
local wipe, ipairs, pairs, tinsert, sort = wipe, ipairs, pairs, tinsert, sort;
local band, bor, bnot                    = bit.band, bit.bor, bit.bnot;
local InCombatLockdown                   = InCombatLockdown;
local FindBaseSpellByID                  = C_SpellBook.FindBaseSpellByID;
local GetSpellNameAndIconID              = DebindPrivate.GetSpellNameAndIconID;
local GetSpellSubtext                    = C_Spell.GetSpellSubtext;
local IsPressHoldReleaseSpell            = C_Spell.IsPressHoldReleaseSpell;
local GetMountInfoByID                   = C_MountJournal.GetMountInfoByID;

local BindingAttrsCache                  = {};

--- 버튼 이름 -> 그 이름으로 `*typerelease-`를 구웠는가.
---
--- **구운 사실과 같은 출처에서 읽어야 한다.** 래퍼는 맨이름 `pressAndHoldAction`을 이 값으로
--- 쓰는데, 그걸 `IsPressHoldReleaseSpell`로 매번 다시 물으면 캐시 적중으로 속성을 안 건드린
--- 경우와 어긋난다. 그러면 눌러서 시작은 되는데 `*typerelease-`가 없어서 **안 놓인다.**
--- (500행 주석의 그 질문 - 특성으로 값이 바뀌는 경우)
local BindingPressHoldCache              = {};

local STATE_EVAL_STRING_FORMAT           = [[SecureCmdOptionParse(%q) and true or false]];

local STATE_EVAL_EXPRESSIONS             = {
    group = format([[(UnitPlayerOrPetInRaid("player") and %d) or (UnitPlayerOrPetInParty("player") and %d) or %d]],
        Constants.GROUP_RAID,
        Constants.GROUP_PARTY,
        Constants.GROUP_NONE),
    combat = "PlayerInCombat()",
    stealth = "IsStealthed()",
    form = "GetShapeshiftForm()",
    bonusbar = "GetBonusBarOffset()",
    specialbar = "HasVehicleActionBar() or HasOverrideActionBar() or HasTempShapeshiftActionBar() or false",
    extrabar = "HasExtraActionBar()",
    pet = "PlayerPetSummary() and true or false",
    petbattle = format(STATE_EVAL_STRING_FORMAT, "[petbattle]"),
};

-- not used
-- local HOVER_CHECK_SNIPPET = format([[
-- if (hovercheck and value ~= "unitframe") then
--     local unitframe = States.unitframe
--     local clear = not unitframe.frame:IsVisible()

--     if (not clear) then
--         if (unitframe.l) then
--             local x, y = unitframe.frame:GetMousePosition()
--             if (not x or (x < unitframe.l or x > unitframe.r or y < unitframe.b or y > unitframe.t)) then
--                 clear = true
--             end
--         end
--     end

--     if (clear) then
--         States.unitframe = nil
--         hovercheck = false
--         if (self:RunAttribute("SetUnit", "hover", nil)) then
--             DirtyFlags.unitframe = true
--         end
--     else
--         local unit = unitframe.frame:GetEffectiveAttribute("unit");
--         if (UnitExists(unit)) then
--             local reaction
--             if (PlayerCanAssist(unit)) then
--                 reaction = %d
--             elseif (PlayerCanAttack(unit)) then
--                 reaction = %d
--             else
--                 reaction = %d
--             end

--             if (unitframe.unit ~= unit or unitframe.reaction ~= reaction) then
--                 unitframe.unit = unit
--                 unitframe.reaction = reaction
--                 self:RunAttribute("SetUnit", "hover", unit)
--                 DirtyFlags.unitframe = true
--             end
--         end
--     end
-- end
-- ]], Constants.REACTION_HELP, Constants.REACTION_HARM, Constants.REACTION_NONE);


local NextButtonName;
do
    local _nextId = 100;
    function NextButtonName()
        _nextId = _nextId + 1;
        return "deb" .. _nextId;
    end
end

local SetBindingAttributes;
local UpdateBindingsMap;
local UpdateMacroTextsMap;
local UpdateAttrChangedHandler;

local addCustomState;
local addMacrotext;
local addMacrotextBinding;

local GetModifierIndex   = DebindPrivate.GetModifierIndex;

local _strArr            = {};
local _macrotexts        = {};
local _macrotextBindings = {};
local _customStates      = {};
local _states            = {};
local _unitStates        = {};
local _unitsSeen         = {};
local _updateFlags       = {};
local _mergedUnits       = {};

local function ResetContext()
    wipe(DebindPrivate.ClickTimeKeys);
    wipe(_macrotexts);
    wipe(_macrotextBindings);
    wipe(_customStates);
    wipe(_states);
    wipe(_unitStates);
    wipe(_unitsSeen);
end

function addCustomState(stateName)
    local info = _customStates[stateName];
    if (info == nil) then
        if (Constants.CUSTOM_STATE_INDICES[stateName]) then
            local options = DebindPrivate.GetCustomStateOptions(stateName);
            if (options) then
                info = {
                    index = Constants.CUSTOM_STATE_INDICES[stateName],
                    name = stateName,
                    mode = options.mode,
                    value = options.value,
                };
                if (options.mode == CUSTOM_STATE_MODES.MACRO_CONDITIONAL) then
                    info.expr = options.expr or "";
                    addMacrotextBinding(info.name, info.expr);
                end
            end
        end
        info = info or false;
        _customStates[stateName] = info;
    end
    return info;
end

function addMacrotext(macrotext)
    local ret = _macrotexts[macrotext];
    if (ret == nil) then
        local fragments, args, isComplex, normalized = DebindPrivate.ParseMacroText(macrotext);
        if (args) then
            ret = {
                fragments = fragments,
                args = args,
                isComplex = isComplex,
                normalized = normalized,
            };
            _macrotexts[macrotext] = ret;

            for _, arg in ipairs(args) do
                if (arg.type == Constants.MACROTEXT_ARG_CUSTOM_STATE) then
                    addCustomState(arg.name);
                elseif (arg.type == Constants.MACROTEXT_ARG_UNIT) then
                    _unitsSeen[arg.name] = true;
                end
            end
        else
            ret = false;
        end
        _macrotexts[macrotext] = ret;
    end
    return ret;
end

function addMacrotextBinding(buttonOrStateName, macrotext)
    _macrotextBindings[buttonOrStateName] = addMacrotext(macrotext)
end

local function formatValue(value)
    if (value == nil) then
        return "nil";
    elseif (value == true) then
        return "true";
    elseif (value == false) then
        return "false";
    elseif (luatype(value) == "string") then
        return format("%q", value);
    else
        return tostring(value);
    end
end

local function appendLine(str, ...)
    if (select("#", ...)) then
        _strArr[#_strArr + 1] = format(str, ...);
    else
        _strArr[#_strArr + 1] = str or "";
    end
end

--- Compiles a generated snippet before it is handed over, in DEBUG builds only.
---
--- The literal snippets are covered by `tools/check-snippets.js`, but these are assembled at
--- runtime and nothing sees them until the restricted environment refuses them -- and what it
--- reports is a stack inside `RestrictedExecution.lua` with a line number into a chunk nobody can
--- look at. `loadstring` is not that environment, so this does not prove a snippet will run; it
--- only says the text is Lua, which is precisely the class of fault that is otherwise so
--- expensive to place.
---
--- Worth having because these strings are assembled from format specifiers: a `%q` too many turns
--- into a missing `end` several hundred lines away from the line that wrote it.
local function AssertSnippetCompiles(snippet, what)
    if (not DEBUG) then
        return;
    end

    local chunk, err = loadstring(snippet, what);
    if (not chunk) then
        DebindPrivate.log(format("|cffff0000[Debind]|r 생성된 스니펫 %s 가 컴파일 안 된다: %s", what, tostring(err)));
    end
end

local function appendKeyValue(key, value)
    if (value == nil) then
        return;
    elseif (value == true) then
        appendLine("t[%q]=true", key);
    elseif (value == false) then
        appendLine("t[%q]=false", key);
    elseif (luatype(value) == "string") then
        appendLine("t[%q]=%q", key, value);
    else
        appendLine("t[%q]=%d", key, value);
    end
end


function DebindPrivate.UpdateBindings()
    if (InCombatLockdown()) then
        DebindPrivate.updateBindingsSuspended = true;
        return;
    end

    -- **특성을 아직 모르면 짓지 않는다.** `EnumerateProfileLayers`는 nil을 0으로 받아 넘기는데
    -- (그쪽 주석: XML을 읽는 길에서 터지지 않게 하려는 보험이다) 그 답은 **특성 레이어 둘이
    -- 빠진 목록**이다. 목록 하나를 그리는 자리에서는 덜 나오는 것으로 끝나지만, 여기서는
    -- 그대로 실제 키 오버라이드가 되어 **우선순위가 낮은 액션이 키를 가져간다.** 조용히.
    --
    -- 짓지 않고 나가는 쪽이 안전한 이유는 이 창이 곧 닫히기 때문이다.
    -- `Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED`가 nil을 보면 0.05초 뒤 자기를 다시 부르고,
    -- 그 길이 다시 여기로 온다. 그동안은 바인딩이 없는 상태고, 그건 틀린 바인딩보다 낫다.
    --
    -- **특성이 없는 캐릭터는 여기 안 걸린다.** 아직 특성을 못 고른 캐릭터에게 이 API가 주는
    -- 것은 nil이 아니라 범위 밖 인덱스라(`EnumerateProfileLayers` 주석), nil은 "아직 모른다"
    -- 하나만 뜻한다.
    if (C_SpecializationInfo.GetSpecialization() == nil) then
        return;
    end

    DebindPrivate.RefreshYieldedKeys();
    DebindPrivate.RefreshGameMenuKeys();

    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
wipe(OldStates)
for k, v in pairs(States) do
    OldStates[k] = v
end
self:RunAttribute("ClearUnitAttributes")
wipe(BindingsMap)
wipe(ClickTimeKeys)
for _, byMod in pairs(ClickCastKeys) do
    wipe(byMod)
end
wipe(HeldButtons)
wipe(HeldUnits)
wipe(MacroTextsMap)
wipe(UnitStates)
wipe(CustomStateExpressions)

-- **`unitframe`은 살려서 넘긴다.** `States`에 든 나머지는 리빌드가 끝나면서 전부 다시
-- 채워지지만, 이건 enter/leave 이벤트로만 서는 값이라 **다시 채워줄 사람이 없다.** 지우면
-- 다음에 커서가 들어올 때까지 빈 채로 남는다.
--
-- 커서는 그대로 프레임 위에 있는데 조건 하나만 바뀌면(전투 진입, 자세 변경, 특성) 리빌드가
-- 돌고, 그 순간 hover 조건 바인딩이 전부 죽는다. 마우스를 뺐다 다시 올려야 살아났다.
--
-- 짝이 되는 `UnitAliasMap["hover"]`는 이 프롤로그가 안 지운다. 그래서 지우면 둘이 갈리기까지
-- 한다 - hover 유닛은 남아 있는데 hover 프레임은 없는 상태가 된다.
local hovered = States.unitframe
wipe(States)
States.unitframe = hovered
]]);

    ClearOverrideBindings(BindingDriver);
    DebindPrivate.BindingDriver:SetAttribute("_onattributechanged", nil);

    ResetContext();

    DebindPrivate.BuildKeyMap();

    UpdateBindingsMap();

    UpdateMacroTextsMap();

    UpdateAttrChangedHandler();

    for state, stateInfo in pairs(_customStates) do
        if (stateInfo) then
            -- previous state value
            if (stateInfo.value ~= nil) then
                -- States 맵에 직접 입력하면 변경 이벤트가 발생하지 않아서 상태 변경 메시지가 출력 안됨.
                --appendLine([[States[%1$q]=%s]], state, tostring(stateInfo.value));
                appendLine([[self:RunAttribute("SetCustomState", %1$q, %s, true)]], state, tostring(stateInfo.value));
            end

            -- fixed macro conditional
            if (stateInfo.mode == CUSTOM_STATE_MODES.MACRO_CONDITIONAL and not addMacrotext(stateInfo.expr)) then
                appendLine([[CustomStateExpressions[%q]=%q]], state, stateInfo.expr);
            end
        end
    end

    if (#_strArr > 0) then
        local snippet = table.concat(_strArr, "\n");
        AssertSnippetCompiles(snippet, "CustomStateExpressions");
        SecureHandlerExecute(DebindPrivate.BindingDriver, snippet);
        if (DEBUG) then
            dump("CustomStateExpressions snippet", { CopyTable(_strArr), snippet:len() });
        end
        wipe(_strArr);
    end

    if (_unitsSeen.hover) then
        _states.unitframe = true;
    end

    for unit in pairs(SPECIAL_UNITS) do
        if (unit ~= "custom1" and unit ~= "custom2") then
            if (_unitsSeen[unit]) then
                DebindPrivate.EnableUnitWatch(unit);
            else
                DebindPrivate.DisableUnitWatch(unit);
                SecureHandlerExecute(DebindPrivate.BindingDriver, format([[self:RunAttribute("SetUnit", %q, nil)]], unit));
            end
        end
    end

    SecureHandlerExecute(DebindPrivate.BindingDriver, format("HoverBindings=%s", tostring(_states.unitframe and true or false)));

    if (_states.unitframe or _states.reaction or _unitStates.mouseover) then
        SecureStateDriverManager:RegisterEvent("UPDATE_MOUSEOVER_UNIT");
        local updatetime = DebindPrivate.Options.updatetime;
        if (not updatetime or updatetime < 0 or updatetime > Constants.STATE_DRIVER_UPDATETIME_DEFAULT) then
            updatetime = Constants.STATE_DRIVER_UPDATETIME_DEFAULT;
        end
        SecureStateDriverManager:SetAttribute("updatetime", updatetime);
    else
        SecureStateDriverManager:UnregisterEvent("UPDATE_MOUSEOVER_UNIT");
        SecureStateDriverManager:SetAttribute("updatetime", Constants.STATE_DRIVER_UPDATETIME_DEFAULT);
    end

    if (_states.reaction) then
        SecureStateDriverManager:RegisterEvent("UNIT_FACTION");
    else
        SecureStateDriverManager:UnregisterEvent("UNIT_FACTION");
    end

    if (_states.specialbar) then
        SecureStateDriverManager:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR");
        SecureStateDriverManager:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR");
    else
        SecureStateDriverManager:UnregisterEvent("UPDATE_OVERRIDE_ACTIONBAR");
        SecureStateDriverManager:UnregisterEvent("UPDATE_VEHICLE_ACTIONBAR");
    end

    if (_states.extrabar) then
        SecureStateDriverManager:RegisterEvent("UPDATE_EXTRA_ACTIONBAR");
    else
        SecureStateDriverManager:UnregisterEvent("UPDATE_EXTRA_ACTIONBAR");
    end

    -- specialbar folds [petbattle] into its own value, so it needs these too
    if (_states.petbattle or _states.specialbar) then
        SecureStateDriverManager:RegisterEvent("PET_BATTLE_OPENING_START");
        SecureStateDriverManager:RegisterEvent("PET_BATTLE_CLOSE");
    else
        SecureStateDriverManager:UnregisterEvent("PET_BATTLE_OPENING_START");
        SecureStateDriverManager:UnregisterEvent("PET_BATTLE_CLOSE");
    end

    local hasKnownState = false;
    for state in pairs(_states) do
        if (strsub(state, 1, 6) == "known:") then
            hasKnownState = true;
            break;
        end
    end

    if (hasKnownState) then
        SecureStateDriverManager:RegisterEvent("SPELLS_CHANGED");
    else
        SecureStateDriverManager:UnregisterEvent("SPELLS_CHANGED");
    end

    -- 클릭캐스팅 라우팅을 프레임들에 반영한다. **아래 상태 루프보다 먼저다** - 그쪽이
    -- `<접두사>type<번호>`를 걸므로, 짝인 `clickbutton`이 아직 없으면 그 사이의 클릭이
    -- 조용히 사라진다(`SECURE_ACTIONS.click`이 delegate가 없으면 아무것도 안 한다).

    -- execute UpdateBindings with forceAll set
    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
        DirtyFlags.forceAll = true
        self:RunAttribute("UpdateAllUnits")
        self:RunAttribute("UpdateMacroTexts", true)
        self:SetAttribute("state-unitexists", 1)
    ]]);

    DebindPrivate.ClearMacroTextCache(_macrotexts);

    DebindPrivate.ApplyOptions("stateDriverUpdateThrottle");

    DebindPrivate.callbacks:Fire("OnBindingsUpdated");

    if (DEBUG) then
        dump("UpdateBindings", {
            states = _states,
            unitStates = _unitStates,
            unitsSeen = _unitsSeen,
            bindingAttrsCache = BindingAttrsCache,
            macrotexts = _macrotexts,
            macrotextBindings = _macrotextBindings,
            customStates = _customStates,
        });
    end

    return true
end

function SetBindingAttributes(type, value, unit)
    if (type == Constants.UNUSED or type == Constants.COMMAND) then
        return;
    end

    -- 펫 명령은 **여기서 MACROTEXT가 된다.** 아래에 자기 갈래를 두면 세 가지를 각각 다시
    -- 만들어야 하는데, 셋 다 이미 매크로텍스트 쪽에 있다:
    --
    --   1. 캐시 키. `BindingAttrsCache`(29줄)는 (type, value)로만 잡고 **한 번도 안 지운다.**
    --      대상을 본문에 굽는 타입이 자기 갈래를 가지면 같은 명령 + 다른 대상 둘이 한 버튼을
    --      나눠 쓰고, 뒤엣것이 앞엣것의 본문을 실행한다. 본문 자체를 value로 만들면 대상이
    --      키에 들어가므로 그 일이 없다. (캐시 자체는 여전히 이 구조다 - refactor-candidates 18)
    --   2. `@custom1`·`@hover`·`@tank`는 진짜 유닛 토큰이 아니다. 바꿔주는 것이
    --      `addMacrotextBinding` -> `ParseMacroText`이고, 그건 MACROTEXT에만 걸려 있다.
    --   3. unit을 여기서 떨군다. 본문이 대상을 들고 있으므로 delegate 프레임이 할 일이
    --      없다(`SECURE_ACTIONS.macro`는 버튼의 unit을 안 본다).
    --
    -- `*type-="pet"`을 안 쓰는 이유는 따로다. 그쪽은 `CastPetAction(슬롯, unit)`이라 unit이
    -- 공짜로 오지만 **슬롯이 펫마다 다르고 전투 중에는 못 고친다** - 전투 중에 펫이 바뀌면
    -- 그 바인딩이 남은 전투 내내 엉뚱한 명령을 실행한다. 안 되는 것보다 나쁘다.
    if (type == Constants.PETACTION) then
        local macrotext = DebindPrivate.GetPetActionMacroText(value, unit);
        if (not macrotext) then
            if (DEBUG) then
                DebindPrivate.log("Unknown pet action:", value);
            end
            return;
        end
        type, value, unit = Constants.MACROTEXT, macrotext, nil;
    end

    -- **플라이아웃이 살아있는지는 캐시보다 먼저 본다.** 캐시 적중은 "속성을 다시 안 써도
    -- 된다"는 뜻이지 "아직 쓸 수 있다"는 뜻이 아닌데, 플라이아웃은 그 둘이 갈라진다.
    --
    -- 갈라지는 자리: 마지막 야수를 놓아주면 `RebuildFlyout`이 `numSlots = 0`으로 만들고
    -- `GetFlyoutOpener`가 nil을 준다. 그런데 `BindingAttrsCache`는 (type, value)로만 잡고
    -- **한 번도 안 지운다**(29줄, refactor-candidates 18). 그래서 아래 갈래 안에 있던
    -- opener 검사가 캐시 적중에 통째로 건너뛰어졌고, 바인딩이 그대로 남았다. 눌러도 아무
    -- 일이 없는 데다 `keyBound`가 서므로 **그 키의 하위 Debind 바인딩까지 전부 막힌다** -
    -- 캐시를 안 지우니 `/reload` 전에는 안 풀렸다. 아래 604-617 주석이 고치겠다고 적은 바로
    -- 그 실패인데, "처음부터 슬롯이 없던" 방향으로만 막히고 있었다.
    local flyoutOpener;
    if (type == Constants.FLYOUT) then
        -- **`*type- = "flyout"`을 안 쓴다.** 블리자드의 그 갈래는 `SpellFlyout:Toggle(self, ...)`
        -- 한 줄이고 그 `self`는 `FlyoutButtonMixin`이어야 한다(`GetPopupDirection`을 부른다).
        -- 여기 `clickframe`은 맨몸 `SecureActionButtonTemplate`이라 nil 메서드 호출로 죽는다.
        -- 자세한 사정은 `Flyout.lua` 머리주석에 있다.
        --
        -- 대신 우리 손잡이를 클릭한다. 손잡이의 보안 스니펫이 커서 위치에 우리 플라이아웃을
        -- 열고, 그건 전투 중에도 돈다.
        flyoutOpener = DebindPrivate.GetFlyoutOpener(value);
        if (not flyoutOpener) then
            -- 안 배웠거나 슬롯이 전부 비었다(길들인 야수가 없는 야수 소환 등).
            -- 키를 걸지 않는다 - 걸어두면 눌러도 아무 일이 없다.
            if (DEBUG) then
                DebindPrivate.log("No flyout opener:", value);
            end
            return;
        end
    end

    local buttonname = BindingAttrsCache[type] and BindingAttrsCache[type][value or NIL];
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
        if (type == Constants.SPELL) then
            -- id는 다르지만 이름은 같은 주문들이 있다.
            -- 예: 조화 전문화의 달빛야수 변신과 회복 전문화의 달빛야수 변신
            -- id로 바인딩하는 경우 다른 전문화의 주문은 실행되지 않음.


            clickframe:SetAttribute("*type-" .. buttonname, "spell");
            local spellID = FindBaseSpellByID(value) or value;
            local spellName = GetSpellNameAndIconID(spellID);
            if (spellName) then
                local subSpellName = GetSpellSubtext(spellID);
                if (subSpellName and subSpellName ~= "") then
                    spellName = spellName .. "(" .. subSpellName .. ")";
                end
                clickframe:SetAttribute("*spell-" .. buttonname, spellName);
            else
                clickframe:SetAttribute("*spell-" .. buttonname, spellID);
            end

            -- what if 'IsPressHoldReleaseSpell' value is changed by a talent or something? is there a such situation?
            --
            -- 그렇다면 이 블록이 캐시 적중으로 통째로 건너뛰어지는 것이 문제가 된다. 답이
            -- 바뀌어도 `*typerelease-`는 옛날 그대로다. 그래서 **구웠다는 사실 자체를 남긴다** -
            -- 래퍼가 맨이름 `pressAndHoldAction`을 쓸 때 이 값을 보므로, 다시 물어서 답이
            -- 달라지면 "시작은 되는데 안 놓이는" 상태가 된다.
            local isPressAndHold = IsPressHoldReleaseSpell(value);
            if (isPressAndHold) then
                clickframe:SetAttribute("*typerelease-" .. buttonname, "spell");
                clickframe:SetAttribute("*pressAndHoldAction-" .. buttonname, true);
                BindingPressHoldCache[buttonname] = true;
            end
        elseif (type == Constants.ITEM) then
            value = format("item:%d", value);
            clickframe:SetAttribute("*type-" .. buttonname, "item");
            clickframe:SetAttribute("*item-" .. buttonname, value);
        elseif (type == Constants.MACRO) then
            clickframe:SetAttribute("*type-" .. buttonname, "macro");
            clickframe:SetAttribute("*macro-" .. buttonname, value);
            clickframe:SetAttribute("*macrotext-" .. buttonname, nil);
        elseif (type == Constants.MACROTEXT) then
            clickframe:SetAttribute("*type-" .. buttonname, "macro");
            clickframe:SetAttribute("*macro-" .. buttonname, nil);
            clickframe:SetAttribute("*macrotext-" .. buttonname, value);
        elseif (type == Constants.MOUNT) then
            local _, spellID = GetMountInfoByID(value);
            if (spellID) then
                local spellName = GetSpellNameAndIconID(spellID);
                clickframe:SetAttribute("*type-" .. buttonname, "spell");
                clickframe:SetAttribute("*spell-" .. buttonname, spellName);
            else
                local macrotext = DebindPrivate.GetMountMacroText(value);
                clickframe:SetAttribute("*type-" .. buttonname, "macro");
                clickframe:SetAttribute("*macro-" .. buttonname, nil);
                clickframe:SetAttribute("*macrotext-" .. buttonname, macrotext);
            end
        elseif (type == Constants.TARGET) then
            clickframe:SetAttribute("*type-" .. buttonname, "target");
        elseif (type == Constants.FOCUS) then
            clickframe:SetAttribute("*type-" .. buttonname, "focus");
        elseif (type == Constants.TOGGLEMENU) then
            clickframe:SetAttribute("*type-" .. buttonname, "togglemenu");
        elseif (type == Constants.SETCUSTOM) then
            clickframe:SetAttribute("*type-" .. buttonname, "attribute");
            clickframe:SetAttribute("*attribute-frame-" .. buttonname, DebindPrivate.UnitWatch);
            clickframe:SetAttribute("*attribute-name-" .. buttonname, "custom" .. value);
            clickframe:SetAttribute("*attribute-value-" .. buttonname, "hover");
        elseif (type == Constants.SETSTATE) then
            local mode, stateIndex = DebindPrivate.GetSetCustomStateModeAndIndex(value);
            if (not mode) then
                if (DEBUG) then
                    DebindPrivate.log("Invalid value:", type, value);
                end
                return;
            end
            clickframe:SetAttribute("*type-" .. buttonname, "attribute");
            clickframe:SetAttribute("*attribute-frame-" .. buttonname, DebindPrivate.CustomStatesUpdaterFrame);
            clickframe:SetAttribute("*attribute-name-" .. buttonname, "$state" .. stateIndex);
            clickframe:SetAttribute("*attribute-value-" .. buttonname, mode);
        elseif (type == Constants.FLYOUT) then
            -- 손잡이는 위에서 이미 받아왔다(캐시 앞에서 봐야 하는 이유가 거기 있다).
            clickframe:SetAttribute("*type-" .. buttonname, "click");
            clickframe:SetAttribute("*clickbutton-" .. buttonname, flyoutOpener);
        elseif (type == Constants.WORLDMARKER) then
            clickframe:SetAttribute("*type-" .. buttonname, "worldmarker");
            clickframe:SetAttribute("*marker-" .. buttonname, value);
        else
            if (DEBUG) then
                DebindPrivate.log("Unhandled type:", type);
            end
            return;
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
        BindingAttrsCache[type][value or NIL] = buttonname;
    end

    if (type == Constants.MACROTEXT) then
        addMacrotextBinding(buttonname, value);
    end

    return delegate or clickframe, buttonname, BindingPressHoldCache[buttonname];
end

--- Which axes have to be **measured** for a unit. Accumulated per unit across every binding that
--- names it, so an axis nobody asks about is never measured and simply has no field in
--- `UnitStates[unit]`. Nothing can ask about an unmeasured axis -- asking is what turns the bit on
--- -- so its absence never reaches a comparison.
---
--- This is what retires the old encoding's defect. Registration used to change the **meaning** of
--- the value (with nobody asking about reaction, a friendly unit came back as `true`), so every
--- consumer had to know who else had registered what. Now registration changes only precision.
local UNITAXIS_EXISTS   = 1;
--- Reaction is measured as **one axis, all the way**. Emitting a term per registered value saved a
--- call when only `help` was asked for, and paid for it by putting `true` in the place of the
--- values nobody asked about. Resolving to exactly one of help/harm/other costs one more C call in
--- the worst case and buys back a value that means the same thing to everyone.
local UNITAXIS_REACTION = 2;
--- Life is two C calls, not one: `UnitIsDeadOrGhost` is not in the restricted environment
--- (`RestrictedEnvironment.lua`'s `DIRECT_MACRO_CONDITIONAL_NAMES` lists only `UnitIsDead` and
--- `UnitIsGhost`). Both have to be asked, because a ghost is not dead by `UnitIsDead` and the
--- macro `[dead]` this mirrors counts it as dead. Reading a ghost as alive sends heals at a corpse.
local UNITAXIS_DEAD     = 4;

local REACTION_NAMES = {
    [Constants.REACTION_HELP]  = "help",
    [Constants.REACTION_HARM]  = "harm",
    [Constants.REACTION_OTHER] = "other",
};

---
--- 같은 유닛에 조건이 두 번 걸렸을 때 하나로 합친다.
---
--- `"@"`는 이 액션 자신의 대상 유닛을 가리키므로, 그 유닛에 명시 조건도 걸려 있으면
--- **`t.checkedUnits`의 같은 키에 두 번 쓰게 된다.** 합치지 않으면 `pairs` 순서에 따라
--- 한쪽이 조용히 사라진다 - 걸어둔 조건이 무작위로 없어지는 것이다.
---
--- 포섭 관계(`true` vs `"help"`)는 `GetBindingInfoForAction`의 정규화가 앞에서
--- 걷어내지만 여기서도 받아준다. 나머지 조합은 전부 모순이고, 그건 `GetBindingIssue`가
--- 걸러서 `KeyMap`에 안 들어온다.
---
--- Values carry one field per axis (`Profile.lua`'s `dbver <= 4` step), so merging is an
--- intersection **per axis**. One empty axis leaves no state at all, which is `NEVER` for the
--- whole condition.
---
--- ============================================================================================
--- `NEVER` IS UNREACHABLE. DO NOT BUILD A RUNTIME REPRESENTATION FOR IT.
--- ============================================================================================
---
--- Every way this function can return `NEVER` is a zero mask in `binding.unitStates`, and a zero
--- mask is an issue, and an action with an issue never enters `KeyMap`:
---
---   absent vs a constrained axis   `band(UNITSTATE_NONE, ...)`  == 0
---   reactions do not overlap       `band(reaction, reaction)`   == 0
---   life asked both ways           `band(ALIVE, DEAD)`          == 0
---
--- `Misc.BuildUnitStates` folds the same conditions with the same intersection, `GetBindingIssue`
--- reports the zero, and `Debind.lua` leaves that binding out of `KeyMap`. So a contradictory
--- binding reaches **neither the solver nor this file**.
---
--- That makes `NEVER` a backstop for one thing only: **the two intersections disagreeing.** Two
--- implementations of one rule -- this one and `BuildUnitStates` -- which is why the redesign
--- notes want this function gone once the runtime speaks masks.
---
--- The caller answers a `NEVER` by **not emitting the binding at all**. Do not reach for a marker
--- value or a `never` field instead. Anything carried into the secure environment is paid for
--- three times: the match loop walks and rejects the record on every re-selection, its units get
--- registered so the update loop measures them every tick forever, and a marker field costs every
--- *ordinary* condition a lookup on a path that runs thousands of times in a fight. All of that
--- to carry a case that cannot happen.
local NEVER = {};

local function mergeUnitConditions(a, b)
    if (a == nil) then return b; end
    if (b == nil) then return a; end
    if (a == NEVER or b == NEVER) then return NEVER; end

    -- `false` is "absent". The absent point sits on no axis, so it cannot overlap with a condition
    -- that constrains one -- but two conditions that both say "absent" agree, and that has to come
    -- back as `false`. Spelled out rather than `and false or`: that idiom cannot return `false`,
    -- so it answered `NEVER` for the one case it was written to let through and the binding was
    -- dropped without any issue being reported.
    if (a == false or b == false) then
        if (a == b) then
            return false;
        end
        return NEVER;
    end

    local reaction = a.reaction;
    if (reaction == nil) then
        reaction = b.reaction;
    elseif (b.reaction ~= nil) then
        reaction = band(reaction, b.reaction);
        if (reaction == 0) then
            return NEVER;
        end
    end

    local dead = a.dead;
    if (dead == nil) then
        dead = b.dead;
    elseif (b.dead ~= nil and b.dead ~= dead) then
        return NEVER;
    end

    return { reaction = reaction, dead = dead };
end

--- Emits the line that creates a key's record list, and puts it in `BindingsMap` unless the key's
--- wiring is fixed.
---
--- **`BindingsMap` is read by the update loop and by nothing else.** A key whose wiring is fixed
--- has nothing for that loop to decide -- it is bound once, below, and which action goes out is
--- the wrapper's call at the click -- so being in the table only buys a walk over its records on
--- every dirty flag, ending in "nothing to do". Out of the table, that walk does not happen.
---
--- The list still has an owner: the `ClickTimeKeys` registration below holds it, and that is the
--- table the wrapper reaches it through. Both lines are driven by the same `first` flag, so a key
--- that emitted no records gets neither.
local function AppendBindingsList(key, alwaysOurs)
    if (alwaysOurs) then
        appendLine("bindings=newtable()");
    else
        appendLine("bindings=newtable();BindingsMap[%q]=bindings", key);
    end
end

function UpdateBindingsMap()
    appendLine("local bindings,t,u");
    for key, bindingArray in pairs(DebindPrivate.KeyMap) do
        wipe(_updateFlags);

        local button, buttonPrefix = bindingArray.button, bindingArray.buttonPrefix;
        local hasClick;
        local hasNonClick;

        for i = 1, #bindingArray do
            local binding = bindingArray[i];
            binding.isClick = button ~= nil and binding.type ~= Constants.COMMAND and (binding.hover or binding.type == Constants.SETCUSTOM or binding.unit == "hover");
            binding.isNonClick = button == nil or not binding.hover;
            binding.clickframe, binding.clickbutton, binding.pressAndHold =
                    SetBindingAttributes(binding.type, binding.value, binding.unit);

            -- **나갈 수단이 없는 바인딩은 여기서 떨군다.**
            --
            -- `SetBindingAttributes`는 값이 못 쓰는 것이면 아무것도 안 걸고 되돌아간다
            -- (알 수 없는 펫 명령, 칸이 전부 빈 플라이아웃 등). 그런데 그때도 레코드는
            -- `BindingsMap`에 실려 나갔고, 보안 쪽(`SecureBindings.lua`)은 그것을 **성사된
            -- 바인딩으로 센다** - `keyBound`가 서면서 `SetBindingClick`도 `ClearBinding`도
            -- 안 부르고, 아래쪽 `not keyBound` 청소까지 건너뛴다.
            --
            -- 결과는 **키가 통째로 먹히는 것**이다. 그 액션이 안 나가는 데서 끝나지 않고
            -- 같은 키의 낮은 우선순위 액션들이 전부 막힌다. 야수를 안 데리고 다니는
            -- 사냥꾼의 "야수 소환"이 그 경우다.
            --
            -- 사용 안 함과 명령은 예외다. 둘은 clickbutton 없이 자기 방식으로 나간다
            -- (`ClearBinding` / `SetBinding`).
            if (binding.type ~= Constants.UNUSED and binding.type ~= Constants.COMMAND
                    and not (binding.clickframe and binding.clickbutton)) then
                if (DEBUG) then
                    DebindPrivate.log(format("|cffff6666[Debind/attr]|r DROP %s/%s (%s) 걸 수단이 없다",
                        tostring(binding.type), tostring(binding.value), key));
                end
                binding.isClick, binding.isNonClick = false, false;
            end

            hasClick = hasClick or binding.isClick;
            hasNonClick = hasNonClick or binding.isNonClick;
        end

        -- **두 결정은 원래 분리된다.** 한 플래그로 묶여 있던 것을 여기서 가른다.
        --
        --   이 키를 어떻게 걸 것인가   상태에 의존한다. 클릭이 도착하기 전에 정해져 있어야 한다
        --   어느 액션이 나갈 것인가     클릭 순간에 정하면 된다
        --
        -- `IsKeyAlwaysOurs`는 **첫 번째**에만 답한다(`click-time-eval.md` §6). 그 답이
        -- 거짓이면 두 번째까지 옛 방식에 남길 이유가 없는데 2단계가 그렇게 두었다. 같은 문서가
        -- 이미 적어둔 결론이다 - "그 판정만 지금 방식으로 추적한다. 어느 액션인지는 여전히
        -- 클릭 시점에 정한다."
        --
        -- 판정은 반드시 위 전처리 루프가 끝난 뒤다. `isNonClick`이 거기서 정해지고, 걸 수단이
        -- 없어 떨궈진 항목도 거기서 걸러진다. 먼저 부르면 전부 nil이라 아무 키도 라우팅되지
        -- 않는데 회귀는 안 나므로 알아채기 어렵다.
        --
        -- 나중에 이 앞에 tier 1이 들어온다 - 조건을 매크로 본문에 직접 구워 게임이 시전 순간에
        -- 판정하게 하는 것. 되는 키는 클릭당 우리 비용이 0이라 래퍼를 태우는 것보다 싸다.

        -- 어느 액션인가를 클릭 시점에 정한다. 키를 잡는 레코드가 하나라도 있으면 된다.
        local clickTime = Constants.CLICK_TIME_EVAL and hasNonClick and true or false;

        -- 키 배선까지 고정이다. 한 번 `SetBindingClick` 걸고 상태 루프는 이 키의 키 역할을
        -- 아예 안 본다.
        local alwaysOurs = clickTime and DebindPrivate.IsKeyAlwaysOurs(bindingArray);

        local first = true;

        if (hasClick or hasNonClick) then
            for i = 1, #bindingArray do
                local binding = bindingArray[i];
                local isClick = hasClick and binding.isClick;
                local isNonClick = hasNonClick and binding.isNonClick;
                local clickframe, clickbutton = binding.clickframe, binding.clickbutton;

                -- Unit conditions are merged **before the record exists**, so a binding that can
                -- never fire is skipped instead of emitted with a marker that says so.
                --
                -- Emitting it would cost three times over: the match loop walks and rejects it on
                -- every re-selection, its units get registered for measurement so the update loop
                -- prices them every tick, and every ordinary condition pays whatever lookup the
                -- marker needs.
                --
                -- **Nothing should reach here anyway.** All three ways `mergeUnitConditions` can
                -- come back `NEVER` leave a zero mask in `binding.unitStates`, which
                -- `GetBindingIssue` reports and `Debind.lua` acts on by keeping the binding out
                -- of `KeyMap` -- so it reaches neither the solver nor this file. This is the
                -- backstop for the two intersections disagreeing, and now it costs nothing.
                local unreachable;
                if (binding.checkedUnits) then
                    wipe(_mergedUnits);
                    for k, v in pairs(binding.checkedUnits) do
                        if (k == "@") then
                            k = binding.unit;
                        end
                        -- A "@" with no unit to point at has no axis to land on. Normalization
                        -- should have dropped it, so drop it quietly.
                        if (k ~= nil) then
                            v = mergeUnitConditions(_mergedUnits[k], v);
                            if (v == NEVER) then
                                unreachable = true;
                                break;
                            end
                            _mergedUnits[k] = v;
                        end
                    end
                end

                if ((isClick or isNonClick) and not unreachable) then
                    if (first) then
                        first = false;
                        if (DEBUG) then
                            appendLine("-- %s", key);
                        end
                        AppendBindingsList(key, alwaysOurs);
                    end
                    appendLine("t=newtable();tinsert(bindings,t)");

                    if (isClick or isNonClick) then
                        if (binding.type == Constants.UNUSED) then
                            appendKeyValue("type", Constants.UNUSED);
                        elseif (binding.type == Constants.COMMAND) then
                            appendKeyValue("command", binding.value);
                        end

                        if (clickframe and clickbutton) then
                            -- `clickframe`은 상태 루프가 `SetBindingClick`에 넘길 때만 읽는다.
                            -- 배선이 고정된 키는 그 루프를 안 도니 실어 보낼 이유가 없다.
                            -- `clickbutton`은 클릭 경로가 읽으므로 어느 갈래든 나간다.
                            if (not alwaysOurs and clickframe ~= DefaultClickFrame) then
                                appendKeyValue("clickframe", clickframe:GetName());
                            end
                            appendKeyValue("clickbutton", clickbutton);
                        end

                        -- **대상은 여기서만 BindingsMap에 실린다.**
                        --
                        -- 옛 경로는 대상을 delegate 프레임의 맨이름 `unit`으로 나르므로
                        -- 실어 보낼 필요가 없었다. 클릭 시점 경로는 `DefaultClickFrame`
                        -- 하나에 걸고 래퍼가 클릭 순간에 맨이름으로 넣기 때문에 어느 대상인지를
                        -- 스니펫이 알아야 한다.
                        --
                        -- 범위를 `GetDelegateFrame`(Debind.lua:61)과 정확히 맞춘다. 그 밖의
                        -- 값은 옛 경로에서도 delegate가 없어 대상이 조용히 사라지므로, 여기서
                        -- 안 내보내는 것이 곧 현행 유지다. `""`(hover인데 재타겟 금지)도 같다.
                        -- up 엣지에서 `typerelease`가 나갈 수 있는 액션인가. 래퍼가 down의
                        -- 선택을 붙들어야 하는지를 이걸로 가른다 - 그 밖의 액션은 up에서
                        -- `typerelease` 조회가 nil이라 아무 일도 안 나므로 붙들 이유가 없고,
                        -- 괜히 붙들면 낡은 판단을 재사용하게 된다.
                        --
                        -- **클릭캐스팅 레코드도 같은 것을 실어야 한다.** 그쪽도 이제 래퍼가
                        -- 대상을 맨이름으로 넣는다 - 유닛 프레임에서 delegate 프레임으로 가던
                        -- `/click` 한 단계가 없어졌으므로 delegate가 들고 있던 `unit`이
                        -- 안 실리면 대상이 조용히 사라진다.
                        --
                        -- `isClick` 쪽은 `CLICK_TIME_EVAL`을 안 본다. 그 플래그는 **키 역할을
                        -- 클릭 시점으로 내릴지**를 가르는 것이고, 클릭캐스팅은 그 선택지가 없다 -
                        -- 매크로를 안 거치려면 래퍼를 지날 수밖에 없어서 언제나 클릭 시점이다.
                        local carriesTarget = isClick
                                or (Constants.CLICK_TIME_EVAL and clickTime and isNonClick);

                        -- **press-and-hold는 키 갈래에만 싣는다.**
                        --
                        -- 클릭캐스팅은 `delegate:Click(button)`으로 오는데 그 호출이 엣지를
                        -- 안 싣는다. 그래서 언제나 `down=false`로 도착하고, 래퍼의
                        -- `if (down)` 갈래가 영영 안 돌아 이 값을 읽을 자리가 없다.
                        --
                        -- **읽을 자리를 만들어서도 안 된다.** 여기서 `pressAndHoldAction`을
                        -- 켜면 게이트가 `useOnKeyDown`을 강제로 참으로 만드는데
                        -- (SecureTemplates.lua:813), 도착이 `down=false`라
                        -- `clickAction = (down and useOnKeyDown)`이 거짓이 되고
                        -- `releasePressAndHoldAction`으로 넘어가 **누른 적 없는 주문의
                        -- `typerelease`만 나간다.** 지금처럼 안 싣는 쪽이 평범한 시전으로
                        -- 떨어져서 낫다.
                        --
                        -- 그래서 클릭캐스팅으로 건 유지·시전 주문은 눌러서 시작하고 떼서
                        -- 놓는 동작이 안 된다. 고치려면 엣지를 실어 올 길이 필요한데
                        -- `SECURE_ACTIONS.click`에는 없다.
                        if (Constants.CLICK_TIME_EVAL and clickTime and isNonClick
                                and binding.pressAndHold) then
                            appendKeyValue("pressAndHold", true);
                        end

                        if (carriesTarget and binding.unit and binding.unit ~= "") then
                            if (SPECIAL_UNITS[binding.unit]) then
                                appendKeyValue("unitAlias", binding.unit);
                            elseif (BASIC_UNITS[binding.unit]) then
                                appendKeyValue("unit", binding.unit);
                            end
                        end


                        -- **`hover` and `reactions` are not emitted.** They are the derived view
                        -- of `checkedUnits["hover"]`, which goes out below with every other unit
                        -- as `t.units["hover"]` -- emitting both would have the match loop ask the
                        -- same question about the same unit twice, once against the frame record
                        -- and once against `UnitStates`.
                        --
                        -- `frameTypes` stays, because it describes the **frame** and only the
                        -- frame record can answer it. It carries its own "is there a frame" guard
                        -- in the snippet for that reason -- there is no `t.hover` in front of it
                        -- any more.
                        if (binding.hover and binding.frameTypes
                                and binding.frameTypes ~= Constants.FRAMETYPE_ALL) then
                            appendKeyValue("frameTypes", binding.frameTypes);
                            _updateFlags.frameType = true;
                            _updateFlags.unitframe = true;
                        end

                        if (binding.groups ~= nil and binding.groups ~= Constants.GROUP_ALL) then
                            appendKeyValue("groups", binding.groups);
                            _updateFlags.group = true;
                        end

                        if (binding.combat ~= nil) then
                            appendKeyValue("combat", binding.combat);
                            _updateFlags.combat = true;
                        end

                        if (binding.stealth ~= nil) then
                            appendKeyValue("stealth", binding.stealth);
                            _updateFlags.stealth = true;
                        end

                        if (binding.known ~= nil) then
                            local stateValue = "known:"..binding.value;
                            appendKeyValue("known", stateValue);
                            _updateFlags[stateValue] = true;
                        end

                        if (binding.forms ~= nil and binding.forms ~= Constants.FORM_ALL) then
                            appendKeyValue("forms", binding.forms);
                            _updateFlags.form = true;
                        end

                        if (binding.bonusbars ~= nil and binding.bonusbars ~= Constants.BONUSBAR_ALL) then
                            appendKeyValue("bonusbars", binding.bonusbars);
                            _updateFlags.bonusbar = true;
                        end

                        if (binding.specialbar ~= nil) then
                            appendKeyValue("specialbar", binding.specialbar);
                            _updateFlags.specialbar = true;
                        end

                        if (binding.extrabar ~= nil) then
                            appendKeyValue("extrabar", binding.extrabar);
                            _updateFlags.extrabar = true;
                        end

                        if (binding.pet ~= nil) then
                            appendKeyValue("pet", binding.pet);
                            _updateFlags.pet = true;
                        end

                        if (binding.petbattle ~= nil) then
                            appendKeyValue("petbattle", binding.petbattle);
                            _updateFlags.petbattle = true;
                        end

                        -- if (binding.checkUnitExists) then
                        --     appendKeyValue("checkUnitExists", binding.checkUnitExists);
                        --     local existsKey = binding.checkUnitExists .. "-exists";
                        --     _updateFlags[existsKey] = true;
                        --     _unitStates[binding.checkUnitExists] = true;
                        -- end

                        if (binding.checkedUnits) then
                            -- `_mergedUnits` was filled above, before the record was created --
                            -- "@" already resolved onto the unit it names and merged with any
                            -- explicit condition on that same unit, so that the two cannot write
                            -- the same key twice and let `pairs` order decide which survives.
                            local unitsTblCreated;
                            for k, v in pairs(_mergedUnits) do
                                if (not unitsTblCreated) then
                                    unitsTblCreated = true;
                                    appendLine("t.units=newtable()");
                                end
                                appendLine("u=newtable();t.units[%q]=u", k);

                                local axes = UNITAXIS_EXISTS;
                                if (v == false) then
                                    appendLine("u.exists=false");
                                else
                                    appendLine("u.exists=true");
                                    if (v.reaction) then
                                        axes = bor(axes, UNITAXIS_REACTION);
                                        -- `UNIT_FACTION`을 등록시키는 자리다. 예전에는 hover
                                        -- 방출이 켰는데 그 갈래가 없어졌다 - 안 켜면 반응
                                        -- 변화가 0.2초 폴링으로만 들어온다.
                                        _updateFlags.reaction = true;
                                        -- A set, not a mask: membership is one lookup, while the
                                        -- `%` idiom the restricted environment forces on masks
                                        -- needs the same two lookups **plus** arithmetic.
                                        appendLine("u.reaction=newtable()");
                                        for bit, name in pairs(REACTION_NAMES) do
                                            if (band(v.reaction, bit) ~= 0) then
                                                appendLine("u.reaction.%s=true", name);
                                            end
                                        end
                                    end
                                    if (v.dead ~= nil) then
                                        axes = bor(axes, UNITAXIS_DEAD);
                                        appendLine("u.dead=%s", tostring(v.dead));
                                    end
                                end

                                _unitsSeen[k] = true;
                                _unitStates[k] = bor(_unitStates[k] or 0, axes);
                                _updateFlags[k .. "-exists"] = true;
                            end
                        end

                        local customStatesTblCreated;
                        for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
                            local state = "$state" .. stateIndex;
                            local v = binding[state];
                            if (v ~= nil) then
                                if (addCustomState(state)) then
                                    if (not customStatesTblCreated) then
                                        appendLine([[t.customStates=newtable()]])
                                        customStatesTblCreated = true;
                                    end
                                    appendLine([[t.customStates[%q]=%s]], state, v and "true" or "false");
                                    _updateFlags[state] = true;
                                end
                            end
                        end

                        if (binding.customStates) then
                            local tblCreated;
                            for state, v in pairs(binding.customStates) do
                                local stateInfo = addCustomState(state);
                                if (stateInfo) then
                                    if (not tblCreated) then
                                        appendLine([[t.customStates=newtable()]])
                                        tblCreated = true;
                                    end
                                    appendLine([[t.customStates[%q]=%s]], state, v and "true" or "false");
                                    _updateFlags[state] = true;
                                end
                            end
                        end

                        if (binding.unit) then
                            _unitsSeen[binding.unit] = true;
                        end

                        -- **유닛 프레임은 매크로를 거치지 않는다.**
                        --
                        -- 옛 경로는 `type="macro"` + `macrotext="/click <프레임> <버튼>"`이었다.
                        -- 그러면 **바깥이 매크로**가 되고, 도착한 버튼의 액션이 또 매크로면
                        -- 실행되지 않는다(게임 제약, `click-time-poc-results.md` §2-5).
                        -- 매크로텍스트·매크로·펫 명령·spellID 없는 탈것이 통째로 안 나갔다.
                        --
                        -- `type="click"`은 `SECURE_ACTIONS.click` 한 줄이라 매크로를 안 거친다.
                        -- 대신 **버튼 이름을 못 싣는다** - `delegate:Click(button)`이 원래 마우스
                        -- 버튼을 그대로 넘긴다. 그래서 어느 액션인지는 래퍼가 도착한 뒤에
                        -- `ClickCastKeys`에서 되찾는다(아래 등록).
                        --
                        -- 그 덕에 여기서 거는 `clickbutton`은 **언제나 같은 프레임**이다.
                        -- 승자가 바뀌어도 안 바뀌므로 옛 경로처럼 액션마다 다시 쓸 일이 없다.
                        -- **아무것도 안 굽는다.** 유닛 프레임에 미리 찍어둘 것이 없어서다 -
                        -- 프레임이 들고 있는 것은 등록 때 한 번 쓴 고정값
                        -- (`*type-debind1` / `*clickbutton-debind1`)뿐이고, 어느 액션인지는
                        -- 래퍼가 클릭 순간에 정한다.
                        --
                        -- 그래서 이 레코드가 클릭 갈래에 속한다는 표시 하나면 된다. 래퍼가
                        -- 그것으로 볼 레코드를 고른다(`EVAL_SNIPPET`의 `subset`).
                        if (isClick) then
                            appendLine("t.isClick=true");
                            _updateFlags.unitframe = true;
                        end

                        if (isNonClick) then
                            appendLine("t.isNonClick=true");
                        end
                    end
                end
            end
        end

        -- **아무 레코드도 안 나갔으면 빈 목록이라도 세운다.** 아래로 이어지는 것들은
        -- (`bindings.updateFlags`, `ClickCastKeys`, `bindings.hasNonClick`, `alwaysOurs`)
        -- `hasClick`/`hasNonClick`을 보고 도는데, 그 둘은 위 루프가 레코드를 하나도 안
        -- 내보낼 수 있다는 것을 모른 채 앞에서 정해졌다. 그러면 `bindings`는 **직전 키의
        -- 목록**을 가리킨 채로 남고, 이 키의 표시가 남의 목록에 붙는다.
        --
        -- 빈 목록은 뜻이 맞다: 쓸 수 있는 레코드가 없는 키이므로 매치 루프가 아무것도 못
        -- 고르고 키는 안 걸린다.
        if (first and (hasClick or hasNonClick)) then
            first = false;
            AppendBindingsList(key, alwaysOurs);
        end

        for k, _ in pairs(_updateFlags) do
            if (strsub(k, -7) ~= "-exists") then
                _states[k] = true;
            end
        end

        -- **상태 루프 전용이라 상태 구동 키에만 굽는다.** `alwaysOurs` 키는 그 루프가 안 보므로
        -- (그 표에 없다) 여기 실린 플래그를 읽는 코드가 없다. `_states` 등록은 위에서 이미
        -- 끝났고 그건 별개다 - 클릭 경로가 아직 `States`를 읽는다.
        if (not alwaysOurs and next(_updateFlags)) then
            appendLine("bindings.updateFlags=newtable()");
            for flag in pairs(_updateFlags) do
                appendLine("bindings.updateFlags[%q]=true", flag);
            end
        end

        if (hasClick) then
            -- 클릭캐스팅으로 도착할 자리를 등록한다. 유닛 프레임이 `type="click"`으로 넘기면
            -- 래퍼는 마우스 버튼 이름밖에 못 받으므로(`/click`과 달리 이름을 못 싣는다),
            -- **버튼 번호와 수식어로 이 키를 되찾는다.**
            --
            -- `ClickTimeKeys`와 나란한 등록이지 그것의 일부가 아니다. 저쪽은 키 역할을
            -- 클릭 시점에 정하는 키들이고 이쪽은 클릭캐스팅이라, 한 키가 양쪽에 다 있을 수도
            -- 어느 한쪽에만 있을 수도 있다.
            appendLine("ClickCastKeys[%d]=ClickCastKeys[%d] or newtable()", button, button);
            appendLine("ClickCastKeys[%d][%d]=bindings", button, GetModifierIndex(buttonPrefix));
        end
        if (hasNonClick) then
            appendLine("bindings.hasNonClick=true");
        end

        -- 클릭 시점 키를 배선한다.
        --
        -- **이름 등록은 언제나 여기서 한 번이다.** 래퍼는 `self`와 `button`만 받으므로 버튼
        -- 이름에 키를 실어 보내고, 그 이름으로 `ClickTimeKeys`를 찾아 바인딩 목록을 얻는다.
        -- 목록은 리빌드마다 새로 만들어지니 등록도 리빌드마다 한 번이면 된다.
        --
        -- **거는 것은 갈린다:**
        --
        --   alwaysOurs   여기서 한 번 걸고 끝. 상태가 뭐가 되든 우리 클릭 프레임이라 다시 걸
        --                일이 없다. 상태 루프에 둘 이유가 없다
        --   그 밖         상태 루프가 건다. "잡느냐 놓느냐"가 상태에 달렸으므로 여기서 한 번
        --                걸어버리면 놓아줘야 할 때 못 놓는다
        --
        -- 순서는 맞다: 이 스니펫은 `ClearOverrideBindings` 뒤에 실행된다.
        if (clickTime and not first) then
            local clickTimeButton = Constants.CLICKTIME_BUTTON_PREFIX .. key;
            DebindPrivate.ClickTimeKeys[key] = clickTimeButton;
            appendLine("ClickTimeKeys[%q]=bindings", clickTimeButton);
            if (alwaysOurs) then
                -- **진단으로 남긴다.** 아무도 안 읽는다 - 어느 표에 들어 있느냐가 이미 답이고,
                -- 진짜는 그 멤버십이며 이 필드는 사본이다. 어긋나면 필드가 틀린 것이고, 이걸로
                -- 판정하는 코드를 새로 쓰면 안 된다. 그래도 두는 이유는 `bindings` 하나만 보고
                -- 이 키가 어느 갈래인지 알 수 있어야 인게임에서 확인이 되기 때문이다.
                appendLine("bindings.alwaysOurs=true");
                appendLine("self:SetBindingClick(true,%q,DefaultClickFrameName,%q)", key, clickTimeButton);
            else
                -- 상태 루프가 걸 때 쓸 이름. 문자열 결합을 클릭 경로 밖으로 빼둔다.
                -- **이 값이 곧 "clickTime 키인가" 표시다** - 따로 불리언을 두면 둘이 갈라진다.
                -- 배선이 고정된 키에는 굽지 않는다: 거는 것은 위에서 이미 끝났고, 그 루프가
                -- 이 키를 보지 않는다.
                appendLine("bindings.clickTimeButton=%q", clickTimeButton);
            end
        end
    end

    local snippet = table.concat(_strArr, "\n");
    AssertSnippetCompiles(snippet, "UpdateBindingsMap");
    SecureHandlerExecute(DebindPrivate.BindingDriver, snippet);
    if (DEBUG) then
        dump("UpdateBindingsMap", {
            CopyTable(_strArr),
            snippet:len(),
        });
    end
    wipe(_strArr);
end

function UpdateMacroTextsMap()
    appendLine("local tempArray, t = newtable()");

    local index = 0;

    for buttonOrStateName, data in pairs(_macrotextBindings) do
        if (data) then
            index = index + 1;
            data.index = index;
            appendLine("t=newtable()");
            appendLine("t.id=%d", index);
            local isState = false;
            if (strsub(buttonOrStateName, 1, 1) == "$") then
                appendLine("t.state=%q", buttonOrStateName);
                isState = true;
            else
                appendLine("t.attr=%q", "*macrotext-" .. buttonOrStateName);
            end

            if (data.isComplex) then
                appendLine("t.fragments,t.args=newtable(),newtable()");
                for i = 1, #data.fragments do
                    appendLine([[t.fragments[%d]=%q]], i, data.fragments[i]);
                end
                for i = 1, #data.args do
                    local arg = data.args[i];
                    appendLine([[t.args[%d]=newtable()]], i);
                    if (arg.type == Constants.MACROTEXT_ARG_UNIT) then
                        appendLine([[t.args[%d].unit=%q]], i, arg.name);
                    elseif (arg.type == Constants.MACROTEXT_ARG_CUSTOM_STATE) then
                        if ((isState and arg.name == buttonOrStateName) or not addCustomState(arg.name)) then
                            if (arg.reverse) then
                                appendLine([[t.args[%d].fixed=%q]], i, "known:0");
                            else
                                appendLine([[t.args[%d].fixed=%q]], i, "");
                            end
                        else
                            appendLine([[t.args[%d].state=%q]], i, arg.name);
                            if (arg.reverse) then
                                appendLine([[t.args[%d].reverse=true]], i);
                            end
                        end
                    end
                end
            else
                appendLine("t.formatString=%q", data.fragments);
            end
            appendLine("tempArray[%d]=t", index);
        end
    end

    -- dependents
    local keysSeen = {};
    for _, data in pairs(_macrotexts) do
        if (data) then
            assert(data.index);
            for _, arg in ipairs(data.args) do
                local key = arg.name;
                if (not keysSeen[key]) then
                    keysSeen[key] = true;
                    appendLine("MacroTextsMap[%q]=newtable()", key);
                end
                appendLine("tinsert(MacroTextsMap[%q], tempArray[%d])", key, data.index);
            end
        end
    end
    appendLine("tempArray = nil")

    local snippet = table.concat(_strArr, "\n");
    AssertSnippetCompiles(snippet, "UpdateMacroTextsMap");
    SecureHandlerExecute(DebindPrivate.BindingDriver, snippet);
    if (DEBUG) then
        dump("UpdateMacroTextsMap", {
            CopyTable(_strArr),
            snippet:len(),
        });
    end
    wipe(_strArr);
end

local function compareStates(lhs, rhs)
    if (lhs == "petbattle") then
        return true;
    end
    if (rhs == "petbattle") then
        return false;
    end

    return lhs < rhs;
end

--- Emits the code that refreshes one unit's row in `UnitStates`. One field per axis, not one
--- value.
---
--- The row table is created once per unit and **reused**. Building a fresh one each tick would
--- destroy change detection: a new table never equals the old one, so every tick would look like
--- a change and rebind.
---
--- Axes that were not registered emit nothing and leave no field behind. Nothing can ask about
--- them, so the absence is never compared against.
---
--- A unit that does not exist is not asked anything else. Absence is not a point on the other
--- axes -- it is the case where those axes have no value at all -- and the condition side splits
--- at the same place.
---
--- `stateOverride` is the same optional line the basic states get, and it lands in the same place
--- -- after the value is computed, before it is compared. Life is the axis that needs it: a test
--- can stand up a friendly unit or an absent one on demand, but not a dead one.
local function appendUnitStateUpdate(unit, axes, unitExpr, existsExpr, stateOverride)
    local dirty = format([[DirtyFlags["%s-exists"]=true]], unit);

    appendLine("u=UnitStates[%1$q];if (not u) then u=newtable();UnitStates[%1$q]=u end", unit);
    appendLine("stateValue=%s and true or false", existsExpr);
    -- **계산 뒤, 비교 앞.** 이 줄이 계산보다 위에 있던 동안 `stateValue`가 바로 덮어써져서
    -- 존재 축 주입이 조용히 아무것도 안 했다.
    if (stateOverride) then
        appendLine(stateOverride, unit .. "-exists");
    end
    appendLine("if (u.exists ~= stateValue) then u.exists=stateValue;%s end", dirty);

    local wantsReaction = band(axes, UNITAXIS_REACTION) ~= 0;
    local wantsDead = band(axes, UNITAXIS_DEAD) ~= 0;

    -- Both axes share one existence test. They are asked the same question -- "does this unit have
    -- a value on the axis at all" -- and the answer was just computed above.
    if (wantsReaction or wantsDead) then
        appendLine("if (u.exists) then");

        if (wantsReaction) then
            -- Blizzard resolves the same fork with if/elseif (`SecureTemplates.lua`, the
            -- `helpbutton`/`harmbutton` substitution). It asks about hostile first; this asks about
            -- friendly first. If a state where both are true ever turns up, that is where they part.
            appendLine([[stateValue=(PlayerCanAssist(%1$s) and "help") or (PlayerCanAttack(%1$s) and "harm") or "other"]],
                unitExpr);
            appendLine("if (u.reaction ~= stateValue) then u.reaction=stateValue;%s end", dirty);
        end

        if (wantsDead) then
            -- `UnitIsDead` alone is not `[dead]`: a ghost answers false to it. The pair is what the
            -- macro conditional means, and the restricted environment has no `UnitIsDeadOrGhost`.
            appendLine("stateValue=(UnitIsDead(%1$s) or UnitIsGhost(%1$s)) and true or false", unitExpr);
            if (stateOverride) then
                appendLine(stateOverride, unit .. "-dead");
            end
            appendLine("if (u.dead ~= stateValue) then u.dead=stateValue;%s end", dirty);
        end

        appendLine("end");
    end
end

-- 'state-unitexists' attribute 값이 변경될 때 상태 업데이트 후 UpdateBindings 실행함.
-- 블리자드 StateDriverManager는 기존 값과 새로운 값(true or false)이 다른 경우에만 _onattributechanged를 호출하므로
-- 'state-unitexists'은 true/false가 아닌 값을 넣어둔다.
function UpdateAttrChangedHandler()
    appendLine([[
if (name == "state-unitexists") then
    if (value == 0) then return end
    self:SetAttribute("state-unitexists", 0)
]]);

    -- The `elseif` below is the half that was missing. A unit can go away under a cursor that
    -- never moves -- neither enter nor leave fires -- and without it the reaction the frame had
    -- when the cursor arrived stayed true forever. The frame itself is kept so this same poll
    -- can pick the unit back up; only the reaction is cleared, and `reaction == nil` is what
    -- every reader now treats as "not hovering".
    appendLine([[
if (States.unitframe) then
    local unitframe = States.unitframe
    local unit = unitframe.frame:GetEffectiveAttribute("unit");
    if (UnitExists(unit)) then
        local reaction
        if (PlayerCanAssist(unit)) then
            reaction = %d
        elseif (PlayerCanAttack(unit)) then
            reaction = %d
        else
            reaction = %d
        end

        if (unitframe.unit ~= unit or unitframe.reaction ~= reaction) then
            unitframe.unit = unit
            unitframe.reaction = reaction
            self:RunAttribute("SetUnit", "hover", unit)
            DirtyFlags.unitframe = true
        end
    elseif (unitframe.reaction) then
        unitframe.unit = nil
        unitframe.reaction = nil
        self:RunAttribute("SetUnit", "hover", nil)
        DirtyFlags.unitframe = true
    end
end
-- 마지막 인자가 REACTION_OTHER인 것이 중요하다. 여기는 **hover 중이고 UnitExists도 참인**
-- 갈래이므로 REACTION_NONE(= hover 안 함, Solver.lua:67의 그 값)이 올 자리가 아니다.
-- NONE은 REACTION_ALL 밖의 비트라 어떤 사용자 마스크에도 안 걸린다 - 그 값이 들어가면
-- 반응 제한이 걸린 hover 바인딩이 "공격도 도움도 안 되는 대상"에서 전부 죽는다
-- (상인·경비병 등 우호 NPC, 시체, 토템). setup_onenter는 처음부터 OTHER를 쓰고 있어서,
-- 마우스를 올린 직후에는 맞다가 첫 폴링 틱에 꺼지는 형태로 나타났다.
]], Constants.REACTION_HELP, Constants.REACTION_HARM, Constants.REACTION_OTHER);

    -- Update States
    -- `u` holds the `UnitStates` row being refreshed. Declared here rather than assigned as a
    -- global: every snippet shares one environment, so a stray global would collide across them.
    appendLine("local stateValue,u")

    -- Update Basic States
    local stateArray = {};
    for state in pairs(_states) do
        tinsert(stateArray, state);
    end
    sort(stateArray, compareStates);

    -- An optional line, supplied from outside, that gets a say in `stateValue` between the
    -- expression that computed it and the comparison that stores it.
    --
    -- **Overriding has to happen here and nowhere else.** Writing into `States` from outside does
    -- not hold: the poll comes round every 0.2s, or any of the events fires, and the real value
    -- goes back. Stopping the loop to keep it would be switching off the code the override exists
    -- to exercise. So the loop runs exactly as it always does, and only the value it lands on is
    -- allowed to differ.
    --
    -- Debind does not know what the line says. It is a format string handed over by whoever wants
    -- it -- in practice the test addon, which is absent for every real user, so nothing is
    -- generated and the emitted snippet is unchanged.
    local stateOverride = DebindPrivate.SnippetProbes and DebindPrivate.SnippetProbes.stateValue;

    local function appendStateStore(state)
        if (stateOverride) then
            appendLine(stateOverride, state);
        end
        appendLine("if (States[%1$q] ~= stateValue) then States[%1$q]=stateValue;DirtyFlags[%1$q]=true; end", state);
    end

    for _, state in ipairs(stateArray) do
        if (STATE_EVAL_EXPRESSIONS[state]) then
            if (state == "specialbar") then
                if (_states.petbattle) then
                    appendLine("stateValue=(%s) or States.petbattle", STATE_EVAL_EXPRESSIONS.specialbar);
                else
                    appendLine([[stateValue=(%s) or (SecureCmdOptionParse("[petbattle]") and true or false)]], STATE_EVAL_EXPRESSIONS.specialbar);
                end
            else
                appendLine("stateValue=%s", STATE_EVAL_EXPRESSIONS[state]);
            end
            appendStateStore(state);
        elseif (state:sub(1, 6) == "known:") then
            appendLine([[stateValue=SecureCmdOptionParse("[%s]") and true or false]], state);
            appendStateStore(state);

        elseif (state == "unitframe" or state == "reaction" or state == "frameType") then
            -- ignore these states
        elseif (_customStates[state]) then
            -- handle later
        elseif (DEBUG) then
            DebindPrivate.log("Unhandled State: " .. state);
        end
    end

    -- Update Unit States
    for unit, axes in pairs(_unitStates) do
        local unitExpr, existsExpr;
        if (unit == "custom1" or unit == "custom2") then
            unitExpr = format("UnitAliasMap[%q]", unit);
            existsExpr = format("UnitAliasMap[%1$q] and UnitExists(UnitAliasMap[%1$q])", unit);
        elseif (SPECIAL_UNITS[unit]) then
            -- For the other aliases, being in `UnitAliasMap` **is** the proof of existence -- `SetUnit`
            -- does not put one there otherwise. Asking `UnitExists` again would tighten the
            -- condition without anyone saying so.
            unitExpr = format("UnitAliasMap[%q]", unit);
            existsExpr = format("UnitAliasMap[%q]", unit);
        else
            unitExpr = format("%q", unit);
            existsExpr = format("UnitExists(%q)", unit);
        end

        appendUnitStateUpdate(unit, axes, unitExpr, existsExpr, stateOverride);
    end

    -- Update Custom States
    for state, stateInfo in pairs(_customStates) do
        if (stateInfo) then
            if (stateInfo.mode == CUSTOM_STATE_MODES.MACRO_CONDITIONAL) then
                appendLine([[stateValue=SecureCmdOptionParse(CustomStateExpressions[%q] or "") and true or false]], stateInfo.name);
                appendLine([[if (States[%1$q] ~= stateValue) then self:RunAttribute("SetCustomState", %1$q, stateValue, true) end]], stateInfo.name);
            end
        end
    end

    appendLine([[
local shouldUpdate
for flag in pairs(DirtyFlags) do
    shouldUpdate = true
    if (MacroTextsMap[flag]) then
        self:RunAttribute("UpdateMacroTexts")
        break
    end
end

if (shouldUpdate) then
    --self:CallMethod("print", "Call UpdateBindings()")
    self:RunAttribute("UpdateBindings")
end
]]);

    appendLine([[end]]);

    local snippet = table.concat(_strArr, "\n");
    AssertSnippetCompiles(snippet, "_onattributechanged");
    DebindPrivate.BindingDriver:SetAttribute("_onattributechanged", snippet);

    if (DEBUG) then
        dump("_onattributechanged", { CopyTable(_strArr), snippet:len() });
    end
    wipe(_strArr);
end
