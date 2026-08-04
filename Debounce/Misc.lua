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

function DebouncePrivate.GetSpellTabNameAndIcon(index)
    local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(index);
    if skillLineInfo then
        return skillLineInfo.name, skillLineInfo.iconID;
    end
end

local GetSpellTabNameAndIcon = DebouncePrivate.GetSpellTabNameAndIcon;

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

            if (binding.type ~= Constants.SPELL and
                    binding.type ~= Constants.ITEM and
                    binding.type ~= Constants.TARGET and
                    binding.type ~= Constants.FOCUS and
                    binding.type ~= Constants.TOGGLEMENU) then
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

    if (not issue and (not category or category == "key") and notCategory ~= "key") then
        if (action.key) then
            issue = DebouncePrivate.IsKeyInvalidForAction(action, action.key);
            if (not issue) then
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

                local slashcmd, idx = strmatch(line, "^(/[%S]+%s+)()");
                if (slashcmd) then
                    appendStr(slashcmd);
                else
                    idx = 1;
                end

                while (idx) do
                    local s1, s2, nextIndex = strmatch(line, "^%s*%[([^%]]*)%]([^%;]*)()", idx);
                    if (s1) then
                        appendStr("[")
                        if (parseOptions(unitsOnly, strsplit("[,]", s1))) then
                            isComplex = true;
                        end
                        appendStr("]");
                        appendStr(strtrim(s2));

                        if (strsub(line, nextIndex, nextIndex) == ";") then
                            appendStr(";");
                            idx = nextIndex + 1;
                        else
                            break;
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
            local trigger = DebouncePrivate.Options.unitframeUseMouseDown and "AnyDown" or "AnyUp";
            for frame in pairs(DebouncePrivate.ccframes) do
                frame:RegisterForClicks(trigger);
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
