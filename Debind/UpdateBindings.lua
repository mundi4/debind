local _, DebindPrivate      = ...;
local Constants               = DebindPrivate.Constants;
local BindingDriver           = DebindPrivate.BindingDriver;
local DefaultClickFrame       = DebindPrivate.DefaultClickFrame;

local L                       = DebindPrivate.L;
local DEBUG                   = DebindPrivate.DEBUG;
local SPECIAL_UNITS           = Constants.SPECIAL_UNITS;
local BASIC_UNITS             = Constants.BASIC_UNITS;
local NIL                     = Constants.NIL;
local ALLOW_COMBINE_CLICK     = Constants.ALLOW_COMBINE_CLICK;
local ALLOW_COMBINE_NON_CLICK = Constants.ALLOW_COMBINE_NON_CLICK;
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

local ACTION_BUTTON_USE_KEY_DOWN; -- GetCVarBool("ActionButtonUseKeyDown")

local SetBindingAttributes;
local UpdateBindingsMap;
local UpdateMacroTextsMap;
local UpdateAttrChangedHandler;

local addCustomState;
local addMacrotext;
local addMacrotextBinding;

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

    ACTION_BUTTON_USE_KEY_DOWN = GetCVarBool("ActionButtonUseKeyDown");
    DebindPrivate.RefreshYieldedKeys();
    DebindPrivate.RefreshGameMenuKeys();

    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
wipe(OldStates)
for k, v in pairs(States) do
    OldStates[k] = v
end
self:RunAttribute("ClearClickBindings")
self:RunAttribute("ClearUnitAttributes")
wipe(BindingsMap)
wipe(MacroTextsMap)
wipe(UnitStates)
wipe(CustomStateExpressions)
wipe(States)
]]);

    ClearOverrideBindings(BindingDriver);
    DebindPrivate.BindingDriver:SetAttribute("_onattributechanged", nil);

    for key, _ in pairs(DebindPrivate.CombinedKeys) do
        DefaultClickFrame:SetAttribute("*type-" .. key, nil);
        DefaultClickFrame:SetAttribute("*macrotext-" .. key, nil);
    end
    wipe(DebindPrivate.CombinedKeys);

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
            combinedKeys = DebindPrivate.CombinedKeys,
            customStates = _customStates,
        });
    end

    return true
end

function SetBindingAttributes(type, value, unit, buttonname)
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

    local clickframe, delegate, skipCache;
    if (type == Constants.COMBINED) then
        clickframe = DefaultClickFrame;
        delegate = DebindPrivate.GetDelegateFrame(Constants.COMBINED);
        skipCache = true;
    else
        assert(buttonname == nil);
        buttonname = BindingAttrsCache[type] and BindingAttrsCache[type][value or NIL];
        clickframe = DefaultClickFrame;
        delegate = unit and unit ~= "" and DebindPrivate.GetDelegateFrame(unit) or nil;

        -- **캐시 적중은 "속성을 하나도 안 건드렸다"는 뜻이다.** 아래 블록을 통째로 건너뛴다.
        -- 그게 맞을 때가 대부분이지만, 키에 안 들어간 무언가(unit 등)가 달라졌으면 그게 곧
        -- 옛날 설정으로 도는 버그다. 로그가 없으면 이 분기는 화면에 흔적을 안 남긴다.
        if (DEBUG and buttonname) then
            DebindPrivate.log(format("|cffffcc66[Debind/cache]|r HIT %s/%s -> %s (unit=%s) 속성 갱신 안 함",
                tostring(type), tostring(value), tostring(buttonname), tostring(unit)));
        end
    end

    if (not buttonname or skipCache) then
        buttonname = buttonname or NextButtonName();
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
            local isPressAndHold = IsPressHoldReleaseSpell(value);
            if (isPressAndHold) then
                clickframe:SetAttribute("*typerelease-" .. buttonname, "spell");
                clickframe:SetAttribute("*pressAndHoldAction-" .. buttonname, true);
            end
        elseif (type == Constants.ITEM) then
            value = format("item:%d", value);
            clickframe:SetAttribute("*type-" .. buttonname, "item");
            clickframe:SetAttribute("*item-" .. buttonname, value);
        elseif (type == Constants.MACRO) then
            clickframe:SetAttribute("*type-" .. buttonname, "macro");
            clickframe:SetAttribute("*macro-" .. buttonname, value);
            clickframe:SetAttribute("*macrotext-" .. buttonname, nil);
        elseif (type == Constants.MACROTEXT or type == Constants.COMBINED) then
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

        if (not skipCache) then
            BindingAttrsCache[type] = BindingAttrsCache[type] or {};
            BindingAttrsCache[type][value or NIL] = buttonname;
        end
    end

    if (type == Constants.MACROTEXT or type == Constants.COMBINED) then
        addMacrotextBinding(buttonname, value);
    end

    return delegate or clickframe, buttonname;
end

local UnitStateFlags = {
    [true] = 1,
    [false] = 1,
    ["help"] = 2,
    ["harm"] = 4,
    ["never"] = 1,
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
--- 그래도 `"never"`를 돌려주는 이유는, 앞단이 새면 **조건이 넓어지는** 쪽으로
--- 틀리기 때문이다. `"never"`는 어떤 `UnitStates` 값과도 안 같아서 항상 불일치다.
local function mergeUnitConditions(a, b)
    if (a == nil or a == b) then
        return b;
    elseif (b == nil) then
        return a;
    elseif (a == true and b ~= false) then
        return b;           -- b는 우호/적대 -- 둘 다 존재를 함의한다
    elseif (b == true and a ~= false) then
        return a;
    end
    return "never";
end

function UpdateBindingsMap()
    appendLine("local bindings,t");
    for key, bindingArray in pairs(DebindPrivate.KeyMap) do
        wipe(_updateFlags);

        local button, buttonPrefix = bindingArray.button, bindingArray.buttonPrefix;
        local hasClick;
        local hasNonClick;
        local combinedClickData;

        for i = 1, #bindingArray do
            local binding = bindingArray[i];
            binding.isClick = button ~= nil and binding.type ~= Constants.COMMAND and (binding.hover or binding.type == Constants.SETCUSTOM or binding.unit == "hover");
            binding.isNonClick = button == nil or not binding.hover;
            binding.clickframe, binding.clickbutton = SetBindingAttributes(binding.type, binding.value, binding.unit);

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

        if (ALLOW_COMBINE_CLICK) then
            local macrotext = DebindPrivate.CombineIfPossible(bindingArray, true);
            if (macrotext) then
                local clickframe, clickbutton = SetBindingAttributes(Constants.COMBINED, macrotext, nil, "^" .. key);
                combinedClickData = { clickframe, clickbutton };
                hasClick = false;
                DebindPrivate.CombinedKeys["^" .. key] = true;
            end
        end

        if (ALLOW_COMBINE_NON_CLICK) then
            local macrotext = DebindPrivate.CombineIfPossible(bindingArray);
            if (macrotext) then
                local clickframe, clickbutton = SetBindingAttributes(Constants.COMBINED, macrotext, nil, key);
                SetOverrideBindingClick(BindingDriver, true, key, clickframe:GetName(), clickbutton);
                hasNonClick = false;
                DebindPrivate.CombinedKeys[key] = true;
            end
        end

        local first = true;
        if (combinedClickData) then
            if (first) then
                first = false;
                if (DEBUG) then
                    appendLine("-- %s", key);
                end
                appendLine("bindings=newtable();BindingsMap[%q]=bindings", key);
            end
            appendLine("t=newtable();tinsert(bindings,t)");
            appendLine("t.isClick,t.clickAttrs=true,newtable()");
            appendLine([[
t.clickAttrs["%1$stype%2$d"]="macro"
t.clickAttrs["%1$smacro%2$d"]=""
t.clickAttrs["%1$smacrotext%2$d"]="/click %3$s %4$s %5$s"
]],
                buttonPrefix or Constants.CLICKBINDING_NON_MOD_PREFIX,
                button,
                combinedClickData[1]:GetName(),
                combinedClickData[2],
                ACTION_BUTTON_USE_KEY_DOWN and "true" or "");
            _updateFlags.unitframe = true;
        end

        if (hasClick or hasNonClick) then
            for i = 1, #bindingArray do
                local binding = bindingArray[i];
                local isClick = hasClick and binding.isClick;
                local isNonClick = hasNonClick and binding.isNonClick;
                local clickframe, clickbutton = binding.clickframe, binding.clickbutton;

                if (isClick or isNonClick) then
                    if (first) then
                        first = false;
                        if (DEBUG) then
                            appendLine("-- %s", key);
                        end
                        appendLine("bindings=newtable();BindingsMap[%q]=bindings", key);
                    end
                    appendLine("t=newtable();tinsert(bindings,t)");

                    if (isClick or isNonClick) then
                        if (binding.type == Constants.UNUSED) then
                            appendKeyValue("type", Constants.UNUSED);
                        elseif (binding.type == Constants.COMMAND) then
                            appendKeyValue("command", binding.value);
                        end

                        if (clickframe and clickbutton) then
                            if (clickframe ~= DefaultClickFrame) then
                                appendKeyValue("clickframe", clickframe:GetName());
                            end
                            if (clickbutton) then
                                appendKeyValue("clickbutton", clickbutton);
                            end
                        end


                        if (binding.hover ~= nil) then
                            appendKeyValue("hover", binding.hover);
                            if (binding.reactions and binding.reactions ~= Constants.REACTION_ALL) then
                                appendKeyValue("reactions", binding.reactions);
                                _updateFlags.reaction = true;
                            end
                            if (binding.frameTypes and binding.frameTypes ~= Constants.FRAMETYPE_ALL) then
                                appendKeyValue("frameTypes", binding.frameTypes);
                                _updateFlags.frameType = true;
                            end
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
                            appendLine("t.checkedUnits=newtable()");
                            -- "@"를 실제 유닛으로 편 다음 **합쳐서** 내보낸다. 바로 쓰면
                            -- "@"와 그 유닛의 명시 조건이 같은 키를 두고 다투다 pairs 순서에
                            -- 따라 한쪽이 사라진다.
                            wipe(_mergedUnits);
                            for k, v in pairs(binding.checkedUnits) do
                                if (k == "@") then
                                    k = binding.unit;
                                end
                                -- unit이 없는데 "@"가 남아 있으면 걸 축이 없다. 정규화가
                                -- 지웠어야 하는 값이므로 조용히 버린다.
                                if (k ~= nil) then
                                    _mergedUnits[k] = mergeUnitConditions(_mergedUnits[k], v);
                                end
                            end
                            for k, v in pairs(_mergedUnits) do
                                appendLine("t.checkedUnits[%q]=%s", k, formatValue(v));
                                _unitsSeen[k] = true;
                                _unitStates[k] = bor(_unitStates[k] or 0, UnitStateFlags[v]);
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

                        if (isClick) then
                            appendLine("t.isClick,t.clickAttrs=true,newtable()");
                            if (clickframe and clickbutton) then
                                appendLine([[
t.clickAttrs["%1$stype%2$d"]="macro"
t.clickAttrs["%1$smacro%2$d"]=""
t.clickAttrs["%1$smacrotext%2$d"]="/click %3$s %4$s %5$s"
]],
                                    buttonPrefix or Constants.CLICKBINDING_NON_MOD_PREFIX,
                                    button,
                                    clickframe:GetName(),
                                    clickbutton,
                                    ACTION_BUTTON_USE_KEY_DOWN and "true" or "");
                            else --if (_type == Constants.UNUSED) then
                                appendLine([[
t.clickAttrs["%1$stype%2$d"]=false
t.clickAttrs["%1$smacro%2$d"]=false
t.clickAttrs["%1$smacrotext%2$d"]=false
]],
                                    buttonPrefix or Constants.CLICKBINDING_NON_MOD_PREFIX,
                                    button);
                            end
                            _updateFlags.unitframe = true;
                        end

                        if (isNonClick) then
                            appendLine("t.isNonClick=true");
                        end
                    end
                end
            end
        end

        for k, _ in pairs(_updateFlags) do
            if (strsub(k, -7) ~= "-exists") then
                _states[k] = true;
            end
        end

        if (next(_updateFlags)) then
            appendLine("bindings.updateFlags=newtable()");
            for flag in pairs(_updateFlags) do
                appendLine("bindings.updateFlags[%q]=true", flag);
            end
        end

        if (hasClick or combinedClickData) then
            appendLine("bindings.hasClick=true");
        end
        if (hasNonClick) then
            appendLine("bindings.hasNonClick=true");
        end
    end

    local snippet = table.concat(_strArr, "\n");
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

---
--- 유닛 하나의 상태를 계산하는 표현식. 값은 false / true / "help" / "harm".
---
--- **한 유닛은 한 값이다.** 블리자드도 같은 자리를 if/elseif로 푼다
--- (`SecureTemplates.lua`의 `helpbutton`/`harmbutton` 치환). 다만 그쪽은 적대를 먼저
--- 본다 -- 여기는 우호가 먼저다. 둘이 동시에 참일 수 있는 상황이 확인되면 그때 갈린다.
---
--- 등록된 비트만 항으로 나간다. 우호를 아무도 안 쓰면 그 항 자체가 없고,
--- 그러면 우호 대상도 `true`로 온다. **소비하는 쪽이 이걸 알아야 한다** --
--- `SecureBindings.lua`의 checkedUnits 루프에서 "존재"가 값 비교가 아닌 이유다.
---
local function unitStateExpression(flags, unitExpr)
    local tmp = {};
    if (band(flags, UnitStateFlags.help) == UnitStateFlags.help) then
        tinsert(tmp, format([[(PlayerCanAssist(%1$s) and "help")]], unitExpr));
    end
    if (band(flags, UnitStateFlags.harm) == UnitStateFlags.harm) then
        tinsert(tmp, format([[(PlayerCanAttack(%1$s) and "harm")]], unitExpr));
    end
    tinsert(tmp, "true");

    return table.concat(tmp, " or ");
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
    end
end
]], Constants.REACTION_HELP, Constants.REACTION_HARM, Constants.REACTION_NONE);

    -- Update States
    appendLine("local stateValue")

    -- Update Basic States
    local stateArray = {};
    for state in pairs(_states) do
        tinsert(stateArray, state);
    end
    sort(stateArray, compareStates);

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
            appendLine("if (States[%1$q] ~= stateValue) then States[%1$q]=stateValue;DirtyFlags[%1$q]=true; end", state);
        elseif (state:sub(1, 6) == "known:") then
            appendLine([[stateValue=SecureCmdOptionParse("[%s]") and true or false]], state);
            appendLine("if (States[%1$q] ~= stateValue) then States[%1$q]=stateValue;DirtyFlags[%1$q]=true; end", state);

        elseif (state == "unitframe" or state == "reaction" or state == "frameType") then
            -- ignore these states
        elseif (_customStates[state]) then
            -- handle later
        elseif (DEBUG) then
            DebindPrivate.log("Unhandled State: " .. state);
        end
    end

    -- Update Unit States
    for unit, flags in pairs(_unitStates) do
        if (unit == "custom1" or unit == "custom2") then
            appendLine("stateValue=UnitMap[%1$q] and UnitExists(UnitMap[%1$q]) and (%2$s) or false",
                unit, unitStateExpression(flags, format("UnitMap[%q]", unit)));
        elseif (SPECIAL_UNITS[unit]) then
            appendLine("stateValue=UnitMap[%1$q] and (%2$s) or false",
                unit, unitStateExpression(flags, format("UnitMap[%q]", unit)));
        else
            appendLine("stateValue=UnitExists(%1$q) and (%2$s) or false",
                unit, unitStateExpression(flags, format("%q", unit)));
        end
        --appendLine([[print(%1$q, stateValue, UnitMap[%1$q])]], unit)
        appendLine([[if (UnitStates[%1$q] ~= stateValue) then UnitStates[%1$q]=stateValue;DirtyFlags["%1$s-exists"]=true; end]], unit);
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
    DebindPrivate.BindingDriver:SetAttribute("_onattributechanged", snippet);

    if (DEBUG) then
        dump("_onattributechanged", { CopyTable(_strArr), snippet:len() });
    end
    wipe(_strArr);
end
