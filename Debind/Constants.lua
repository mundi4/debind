local _, DebindPrivate                  = ...;
DebindPrivate.Constants                 = {};
local Constants                           = DebindPrivate.Constants;

Constants.DEBUG                           = false;
--@debug@
Constants.DEBUG                           = true;
--@end-debug@
Constants.NIL                             = "\0";
Constants.DB_VERSION                      = 4;
Constants.MAX_NUM_ACTIONS_PER_LAYER       = 1000;
Constants.CLICKBINDING_NON_MOD_PREFIX     = ""; -- "" or "*"
Constants.STATE_DRIVER_UPDATETIME_DEFAULT = 0.2;
Constants.PLAYER_CLASS                    = select(2, UnitClass("player"));

-- 키를 누른 순간 보안 스니펫이 조건을 평가해 액션을 고르는 경로. 끄면 라우팅이 전부 멈추고
-- 모든 키가 상태 구동(옛 경로)으로 돌아간다 - 회귀가 보이면 여기부터 뒤집어 볼 것.
-- 어느 키가 이 경로로 가는지는 `IsKeyAlwaysClickBound`가 정한다.
Constants.CLICK_TIME_EVAL                 = true;

-- 클릭 시점 키를 클릭 프레임에 걸 때 쓰는 버튼 이름의 접두사. 래퍼가 이 이름을 보고
-- 자기 키인지 가른 다음 이긴 액션의 이름으로 바꿔 반환한다.
-- `NextButtonName`의 "deb<n>"과 겹치지 않기만 하면 된다.
Constants.CLICKTIME_BUTTON_PREFIX         = "@";


-- Action Types
Constants.SPELL                           = "spell";
Constants.ITEM                            = "item";
Constants.MACRO                           = "macro";
Constants.MACROTEXT                       = "macrotext";
Constants.MOUNT                           = "mount";
Constants.PETACTION                       = "petaction";
Constants.FLYOUT                          = "flyout";
Constants.TARGET                          = "target";
Constants.FOCUS                           = "focus";
Constants.TOGGLEMENU                      = "togglemenu";
Constants.COMMAND                         = "command";
Constants.WORLDMARKER                     = "worldmarker";
Constants.SETCUSTOM                       = "setcustom";
Constants.SETSTATE                        = "setstate";
Constants.UNUSED                          = "unused";

--- 대상(unit)을 가질 수 있는 액션 타입.
---
--- **한 군데에서만 적는다.** 이 목록은 원래 두 곳에 손으로 복사돼 있었다 -
--- `Misc.lua`의 `GetBindingInfoForAction`(목록에 없으면 `binding.unit`을 nil로 지운다)과
--- `DropDownMenus.lua`의 `CreateTargetUnitMenuItem`(목록에 없으면 대상 메뉴를 안 연다).
--- 소환수 명령을 붙이면서 메뉴 쪽에만 넣었더니, **대상은 고를 수 있는데 바인딩으로 가는
--- 길에서 조용히 지워졌다.** 화면에는 "포커스"라고 적혀 있고 나가는 매크로에는 없었다.
--- 한쪽만 고쳐도 티가 안 나는 종류의 중복이라 값을 하나로 만든다.
Constants.TYPES_WITH_UNIT                 = {
    [Constants.SPELL] = true,
    [Constants.ITEM] = true,
    [Constants.PETACTION] = true,
    [Constants.TARGET] = true,
    [Constants.FOCUS] = true,
    [Constants.TOGGLEMENU] = true,
};


Constants.MAX_NUM_CUSTOM_STATES = 5;

Constants.CUSTOM_STATE_INDICES  = {};
for i = 1, Constants.MAX_NUM_CUSTOM_STATES do
    Constants.CUSTOM_STATE_INDICES["$state" .. i] = i;
end

Constants.CUSTOM_STATE_MODES    = {
    MANUAL            = 0,
    ALWAYS_ON         = 1,
    ALWAYS_OFF        = 2,
    MACRO_CONDITIONAL = 3,
};

Constants.SETCUSTOM_MODE_ON     = 0x100;
Constants.SETCUSTOM_MODE_OFF    = 0x200;
Constants.SETCUSTOM_MODE_TOGGLE = 0x400;
Constants.SETCUSTOM_MODE_MASK   = 0x100 + 0x200 + 0x400;


Constants.MACROTEXT_ARG_UNIT         = 1;
Constants.MACROTEXT_ARG_CUSTOM_STATE = 2;


Constants.MAX_BONUS_ACTIONBAR_OFFSET = 5;

-- Priority Values
Constants.DEFAULT_PRIORITY           = 3;
Constants.MIN_PRIORITY               = 1;
Constants.MAX_PRIORITY               = 5;

Constants.GROUP_NONE                 = 2 ^ 0;
Constants.GROUP_PARTY                = 2 ^ 1;
Constants.GROUP_RAID                 = 2 ^ 2;
Constants.GROUP_ALL                  = 2 ^ 3 - 1;

Constants.FORM_ALL                   = 2 ^ 11 - 1;

Constants.MAX_BONUSBAR_OFFSET        = 5;
Constants.BONUSBAR_ALL               = 2 ^ (Constants.MAX_BONUSBAR_OFFSET + 1) - 1;


-- Unit Frame Reactions
Constants.REACTION_HELP  = 2 ^ 0;
Constants.REACTION_HARM  = 2 ^ 1;
Constants.REACTION_OTHER = 2 ^ 2;
Constants.REACTION_ALL   = 2 ^ 3 - 1;
Constants.REACTION_NONE  = 2 ^ 4;


-- Unit Frame Types
Constants.FRAMETYPE_UNKNOWN = 2 ^ 0;
Constants.FRAMETYPE_PLAYER  = 2 ^ 1;
Constants.FRAMETYPE_PET     = 2 ^ 2;
Constants.FRAMETYPE_GROUP   = 2 ^ 3;
Constants.FRAMETYPE_TARGET  = 2 ^ 4;
Constants.FRAMETYPE_BOSS    = 2 ^ 5;
Constants.FRAMETYPE_ARENA   = 2 ^ 6;
Constants.FRAMETYPE_ALL     = 2 ^ 7 - 1;


-- Unit States
--
-- What one unit can be, as a single axis: absent, or present in one of three ways. Exactly
-- one is true of a unit at any moment, which is what lets `Solver.lua` treat a unit condition
-- as a set on this axis and reason about coverage with plain bit ops.
--
-- The hovered frame's unit rides this axis under the name "hover" (`Misc.BuildUnitStates`),
-- so a hover condition and a unit condition aimed at the same unit cannot describe it two
-- different ways.
--
-- Two notes for whoever adds the next per-unit condition -- dead/alive and party/raid are the
-- ones asked for:
--
-- It does not get a column of its own. "Absent, or present and alive" is not a rectangle in
-- (reaction, life), because absent has no life value to constrain; a life column of {alive}
-- would drop half of that condition and the box would come out narrower than the condition it
-- stands for. Narrow boxes get deleted for reasons they never asked for.
--
-- But it should not just widen this enumeration either. A product taken over every axis the
-- addon has runs out of room quickly -- the ceiling is 31 bits, since `bit.bnot` returns a
-- signed 32-bit value and bit 31 turns a mask negative. The product belongs to a key, not to
-- the codebase: `Solver.lua` builds its columns per key already, so it only has to span the
-- axes that key's bindings actually constrain, and storage keeps one mask per axis instead of
-- one packed value. A key that never asks about life then pays nothing for life existing.
Constants.UNITSTATE_NONE   = 2 ^ 0;
Constants.UNITSTATE_HELP   = 2 ^ 1;
Constants.UNITSTATE_HARM   = 2 ^ 2;
Constants.UNITSTATE_OTHER  = 2 ^ 3;

Constants.UNITSTATE_EXISTS = Constants.UNITSTATE_HELP + Constants.UNITSTATE_HARM + Constants.UNITSTATE_OTHER;
Constants.UNITSTATE_ALL    = Constants.UNITSTATE_EXISTS + Constants.UNITSTATE_NONE;


-- Binding Issues
Constants.BINDING_ISSUE_NOT_SUPPORTED_GAMEMENU_KEY        = "NOT_SUPPORTED_GAMEMENU_KEY";
Constants.BINDING_ISSUE_NOT_SUPPORTED_MOUSE_BUTTON        = "NOT_SUPPORTED_MOUSE_BUTTON";
Constants.BINDING_ISSUE_NOT_SUPPORTED_HOVER_CLICK_COMMAND = "NOT_SUPPORTED_HOVER_CLICK_COMMAND";
Constants.BINDING_ISSUE_CONDITIONS_NEVER                  = "CONDITIONS_NEVER";
Constants.BINDING_ISSUE_UNREACHABLE                       = "UNREACHABLE";
Constants.BINDING_ISSUE_CLIQUE_DETECTED                   = "CLIQUE_DETECTED";
Constants.BINDING_ISSUE_CANNOT_USE_HOVER_WITH_CLIQUE      = "CANNOT_USE_HOVER_WITH_CLIQUE";
Constants.BINDING_ISSUE_FORMS_NONE_SELECTED               = "FORMS_NONE_SELECTED";
Constants.BINDING_ISSUE_BONUSBARS_NONE_SELECTED           = "BONUSBARS_NONE_SELECTED";
Constants.BINDING_ISSUE_GROUPS_NONE_SELECTED              = "GROUPS_NONE_SELECTED";
Constants.BINDING_ISSUE_HOVER_NONE_SELECTED               = "HOVER_NONE_SELECTED";


local BASIC_UNITS                                   = {
    mouseover = 1,
    player = 2,
    pet = 3,
    target = 4,
    focus = 5,
    none = 6,
    --[""] = 8,
};

local SPECIAL_UNITS                                 = {
    tank = 1,
    healer = 2,
    maintank = 3,
    mainassist = 4,
    custom1 = 5,
    custom2 = 6,
    hover = 7,
};

Constants.BASIC_UNITS                               = BASIC_UNITS;
Constants.SPECIAL_UNITS                             = SPECIAL_UNITS;


-- 키 문자열 파싱. 순수 Lua라 와우 없이도 돌고, Solver.lua가 hover 컬럼에서 쓴다.
-- Solver.lua는 Misc.lua보다 먼저 로드되므로 여기에 둔다.
local MOUSE_BUTTONS = {};
for i = 1, 5 do
    MOUSE_BUTTONS["BUTTON" .. i] = i;
end

--- 수식어 접두사를 **와우의 정규 순서**(`ALT-CTRL-SHIFT-`)로 다시 쓴다.
---
--- 저장된 키에서 떼어낸 접두사는 순서가 뒤집혀 있을 수 있다(손으로 고친 프로필, 가져온
--- 프로필). 그러면 두 가지가 어긋난다:
---
---   속성 이름   게임은 정규 순서로만 조회하므로 `SHIFT-ALT-type2`는 **아무도 안 본다.**
---               그 바인딩은 원래부터 안 나갔다
---   색인        `GetModifierIndex`는 순서를 안 보므로 `ALT-SHIFT-`와 같은 칸을 쓴다.
---               그래서 **안 나가던 키가 멀쩡한 키의 칸을 덮어쓴다**
---
--- 둘을 같은 접두사에서 뽑으면 둘 다 닫힌다. 덤으로 비정규 접두사로 저장된 키도 살아난다.
local function CanonicalModifierPrefix(prefix)
    if (not prefix or prefix == "") then
        return nil;
    end
    local canonical = "";
    if (prefix:find("ALT-", 1, true)) then
        canonical = canonical .. "ALT-";
    end
    if (prefix:find("CTRL-", 1, true)) then
        canonical = canonical .. "CTRL-";
    end
    if (prefix:find("SHIFT-", 1, true)) then
        canonical = canonical .. "SHIFT-";
    end
    -- 아는 수식어가 하나도 없으면 우리가 모르는 접두사다. 건드리지 않고 그대로 돌려준다 -
    -- 지어내면 엉뚱한 자리에 걸린다.
    return canonical ~= "" and canonical or prefix;
end

local _mousebuttonCache = {};
function DebindPrivate.GetMouseButtonAndPrefix(key)
    local cached = _mousebuttonCache[key];
    if (cached == nil) then
        if (MOUSE_BUTTONS[key]) then
            cached = { MOUSE_BUTTONS[key], nil };
            _mousebuttonCache[key] = cached;
        else
            local idx = key:match(".*%-()");
            if (idx) then
                local button = MOUSE_BUTTONS[key:sub(idx)];
                if (button) then
                    local prefix = CanonicalModifierPrefix(key:sub(1, idx - 1));
                    cached = { button, prefix };
                    _mousebuttonCache[key] = cached;
                else
                    _mousebuttonCache[key] = false;
                end
            end
        end
    end
    if (cached) then
        return cached[1], cached[2];
    else
        return nil, nil;
    end
end

--- `GetMouseButtonAndPrefix`가 떼어낸 접두사("SHIFT-", "ALT-CTRL-", nil)를 수식어 번호
--- 0~7로 접는다.
---
--- 클릭캐스팅은 `type="click"`으로 넘어오는데 그 길은 **버튼 이름을 못 싣는다**
--- (`SECURE_ACTIONS.click`이 `delegate:Click(button)`이라 원래 마우스 버튼만 온다).
--- 그래서 도착한 버튼과 지금 눌린 수식어로 어느 키였는지를 되찾는데, 이 함수가 그 색인의
--- 굽는 쪽이다.
---
--- **푸는 쪽이 `SecureBindings.lua`의 OnClick 래퍼에 따로 있다.** 그쪽은 제한 환경이라 이
--- 함수를 못 부르므로 손계산이 한 벌 더 있는데, 자릿값만은 아래 상수를 양쪽이 같이 쓴다 -
--- 래퍼는 `CONSTANTS.MOD_ALT` 꼴로 적고 `BakeSnippet`이 빌드 시점에 치환한다. 이름이
--- 틀리면 거기 `assert`에서 터지므로, 어긋난 채로 나가는 길이 없다.
---
--- 자릿값이 갈리면 **수식어가 걸린 클릭캐스팅만** 조용히 다른 목록을 찾는다. 오류도 로그도
--- 안 나므로 값을 한 군데 두는 것이 유일한 방어다.
---
--- 순서를 안 보고 부분 문자열로 찾는 이유는 와우의 정규 순서(`ALT-CTRL-SHIFT-`)에 기대지
--- 않기 위해서다. 접두사는 우리가 만든 것이 아니라 저장된 키 문자열에서 떼어낸 것이다.
Constants.MOD_ALT   = 1;
Constants.MOD_CTRL  = 2;
Constants.MOD_SHIFT = 4;

function DebindPrivate.GetModifierIndex(buttonPrefix)
    if (not buttonPrefix or buttonPrefix == "") then
        return 0;
    end
    local mod = 0;
    if (buttonPrefix:find("ALT-", 1, true)) then
        mod = mod + Constants.MOD_ALT;
    end
    if (buttonPrefix:find("CTRL-", 1, true)) then
        mod = mod + Constants.MOD_CTRL;
    end
    if (buttonPrefix:find("SHIFT-", 1, true)) then
        mod = mod + Constants.MOD_SHIFT;
    end
    return mod;
end

Constants.MAX_BOSSES                                = 8;

Constants.CUSTOM_TARGET_VALID_UNIT_TOKENS           = {};
Constants.CUSTOM_TARGET_VALID_UNIT_TOKENS["player"] = "player";
Constants.CUSTOM_TARGET_VALID_UNIT_TOKENS["pet"]    = "pet";
for i = 1, MAX_PARTY_MEMBERS do
    Constants.CUSTOM_TARGET_VALID_UNIT_TOKENS["party" .. i] = "group"
end
for i = 1, MAX_RAID_MEMBERS do
    Constants.CUSTOM_TARGET_VALID_UNIT_TOKENS["raid" .. i] = "group"
end
for i = 1, Constants.MAX_BOSSES do
    Constants.CUSTOM_TARGET_VALID_UNIT_TOKENS["boss" .. i] = "boss"
end
for i = 1, MAX_ARENA_ENEMIES do
    Constants.CUSTOM_TARGET_VALID_UNIT_TOKENS["arena" .. i] = "arena"
end


if (Constants.DEBUG) then
    if (_G.DevTool and _G.DevTool.AddData) then
        local DevTool = _G.DevTool;
        function DebindPrivate.dump(strName, tData)
            DevTool:AddData(tData, "[" .. GetTime() .. "] " .. (strName or ""));
        end
    elseif (_G.ViragDevTool_AddData) then
        local ViragDevTool_AddData = _G.ViragDevTool_AddData;
        function DebindPrivate.dump(strName, tData)
            ViragDevTool_AddData(tData, "[" .. GetTime() .. "] " .. (strName or ""));
        end
    end
end

DebindPrivate.dump = DebindPrivate.dump or function() end
DebindPrivate.dump("DebindPrivate", DebindPrivate);

--- DEBUG 진단 한 줄.
---
--- **채팅으로 안 보낸다.** 이 줄들은 바인딩 하나마다 하나씩 나오므로 재바인딩 한 번에 수십 줄이
--- 되고, 그러면 정작 읽어야 할 것(로그인 메시지, 경고, 게임이 하는 말)이 밀려 올라간다.
---
--- DevTool에도 줄마다 항목을 만들면 같은 일이 거기서 벌어진다. 그래서 **표 하나를 한 번만
--- 등록하고 거기에 쌓는다** - DevTool은 참조를 들고 있으므로 펼칠 때마다 지금까지 쌓인 것이
--- 보인다. 항목 하나가 곧 로그 전체다.
---
--- DevTool이 없으면 채팅으로 떨어진다. 그때는 도배가 곧 "DevTool을 깔아라"는 신호다.
do
    local MAX_LINES = 500;
    local lines = {};
    local registered = false;

    DebindPrivate.logLines = lines;

    local hasDevTool = (_G.DevTool and _G.DevTool.AddData) or _G.ViragDevTool_AddData;

    if (not Constants.DEBUG) then
        DebindPrivate.log = function() end;
    else
        function DebindPrivate.log(...)
            local parts = {};
            for i = 1, select("#", ...) do
                parts[i] = tostring((select(i, ...)));
            end
            local line = format("[%.3f] %s", GetTime(), table.concat(parts, " "));

            if (not hasDevTool) then
                print(line);
            else
                -- 오래된 줄부터 버린다. 개발 세션이 길어지면 이 표가 유일하게 상한 없이 자란다.
                lines[#lines + 1] = line;
                if (#lines > MAX_LINES) then
                    tremove(lines, 1);
                end

                if (not registered) then
                    registered = true;
                    DebindPrivate.dump("Debind log", lines);
                end
            end
        end
    end
end
