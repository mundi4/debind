-- **[사용자 지정 매크로로 바꾸기]가 무엇을 내주고 무엇을 거절하나** (`Misc.lua`의
-- `CanConvertToMacroText` / `ConvertToMacroText`).
--
-- 이 변환은 액션을 **제자리에서 갈아치운다.** 되돌리는 길은 메뉴가 들고 있는 [취소] 하나뿐이고
-- (`DropDownMenus.lua`), 그 창을 닫고 나면 원래 타입은 어디에도 안 남는다. 그래서 **바뀐 키가
-- 바뀌기 전과 다른 일을 하면 아무도 못 잡는다** - 화면에는 사용자가 적은 매크로 한 줄이 서 있고,
-- 그 줄은 제 본문대로 정확히 동작한다.
--
-- 여기 있는 것은 그 한 가지 규칙이다. **매크로 본문으로 못 옮기는 것을 들고 있으면 변환을
-- 안 내준다.** 내주면서 조용히 떨어뜨리지 않는다.
--
-- 몇 가지는 다른 스펙이 든다. 주문 본문이 시전 이름과 같은 문자열인지는 `castname_spec`이,
-- 스위치를 안 고른 액션이 거절되는지는 `switch_spec`이 든다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");

    local T = { passed = 0, failures = {} };

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "check failed", 2);
        end
    end

    local Can = DebindPrivate.CanConvertToMacroText;
    local Convert = DebindPrivate.ConvertToMacroText;

    local function installWorld()
        shim.world.spells[774] = { name = "Rejuvenation", iconID = 136081 };
        shim.world.macros["Heal"] = { name = "Heal", icon = 4, body = "/cast Rejuvenation" };
    end

    ---------------------------------------------------------------------------
    -- 못 옮기는 것은 안 내준다
    ---------------------------------------------------------------------------

    --- 표식 액션은 **놓고 거두기**다. 보안 버튼은 `*action-`을 안 적어서 블리자드 기본값인
    --- `toggle`로 가고(`SecureTemplates.lua`의 `SECURE_ACTIONS.worldmarker`), 그것이 툴팁이
    --- 약속하는 동작이기도 하다(`TYPE_WORLDMARKER_DESC`).
    ---
    --- **매크로에는 그 절반이 없다.** `/wm N`의 핸들러는 `PlaceRaidMarker`만 부르고
    --- (`SlashCommands.lua`), 거두는 것은 `/cwm`이라 명령이 따로다. 둘을 갈라주는 조건절도
    --- 없고, `PlaceRaidMarker`와 `ClearRaidMarker`는 `HasRestrictions`라 `/run`으로도 못
    --- 부른다. 그래서 변환 자체를 안 내준다.
    test("월드 표식은 매크로로 못 바꾼다", function()
        installWorld();
        check(not Can({ type = Constants.WORLDMARKER, value = 5 }),
            "놓기만 되는 본문으로 바꿔주겠다고 나선다");
    end);

    --- 이름은 문자열인데 그 이름의 매크로가 없는 경우. `ConvertToMacroText`는 본문을 못 지어서
    --- 아무 일도 안 하고 끝나므로, 메뉴에 서면 **눌러도 아무 일이 없는 항목**이 된다.
    test("지워진 매크로는 매크로로 못 바꾼다", function()
        installWorld();
        check(Can({ type = Constants.MACRO, value = "Heal" }),
            "있는 매크로인데 변환이 안 선다");
        check(not Can({ type = Constants.MACRO, value = "Gone" }),
            "없는 매크로에 변환이 선다");
    end);

    ---------------------------------------------------------------------------
    -- 착용 칸
    ---------------------------------------------------------------------------

    --- `/use <칸 번호>`가 그대로 되는 타입이다. 나가는 속성도 이미 같은 것이다 - `*item-`에
    --- 맨 숫자를 적고, `SecureCmdItemParse`가 그것을 가방 쌍이 아니라 인벤토리 칸으로 읽는다
    --- (`UpdateBindings.lua`).
    ---
    --- **이름과 아이콘은 그리는 쪽과 같은 자리에서 가져온다**(`ActionDisplay.lua`의 같은
    --- 갈래). 매크로텍스트는 저장된 이름을 그리므로, 여기서 안 적으면 그 줄이 영영 이름 없는
    --- 줄로 남는다.
    test("착용 칸은 /use <칸>이 된다", function()
        installWorld();
        local action = { type = Constants.EQUIPSLOT, value = 13 };
        check(Can(action), "착용 칸에 변환이 안 선다");
        check(Convert(action), "변환이 거절됐다");
        check(action.type == Constants.MACROTEXT, "타입이 안 바뀌었다: " .. tostring(action.type));
        check(action.value == "/use 13", "본문이 " .. tostring(action.value) .. "다");
        check(action.name == DebindPrivate.EquipSlotFacts(13),
            "이름이 " .. tostring(action.name) .. "다");
        check(action.icon ~= nil, "아이콘이 안 붙었다");
    end);

    --- 대상은 본문에 굽는다. 착용 칸은 대상을 갖는 타입이고(`TYPES_WITH_UNIT`), 매크로텍스트는
    --- 안 갖는 타입이라 필드로는 못 따라간다.
    test("착용 칸의 대상은 본문에 들어간다", function()
        installWorld();
        local action = { type = Constants.EQUIPSLOT, value = 13, unit = "focus" };
        check(Convert(action), "변환이 거절됐다");
        check(action.value == "/use [@focus] 13", "본문이 " .. tostring(action.value) .. "다");
        check(action.unit == nil, "대상 필드가 남았다");
    end);

    ---------------------------------------------------------------------------
    -- 겨누는 대상
    ---------------------------------------------------------------------------

    --- **겨누는 대상은 액션의 필드로만 오는 것이 아니다.** 호버 조건만 걸어둔 액션은 그 필드가
    --- 비어 있고, 겨누기는 `GetBindingInfoForAction`이 끝에서 파생시킨다.
    ---
    --- 매크로텍스트가 되면 그 파생값을 실을 자리가 없다. `SECURE_ACTIONS.macro`는 버튼의 unit을
    --- 안 보고(`SecureTemplates.lua`) `UpdateBindings`도 그래서 이 타입에서 unit을 떨군다. 본문에
    --- 안 적히면 **겨누기가 통째로 사라져서 현재 대상에게 나간다.**
    test("호버로 겨누던 것도 본문에 실린다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774,
            conditions = { units = { hover = {} } } };
        check(DebindPrivate.GetBindingInfoForAction(action).unit == "hover",
            "이 액션은 호버를 겨누고 있지 않다");
        check(Convert(action), "변환이 거절됐다");
        check(action.value == "/cast [@hover] Rejuvenation",
            "본문이 " .. tostring(action.value) .. "다");
    end);

    --- 겨누기를 끈 호버 액션. `binding.unit`이 `""`라 겨누는 곳이 없고, 본문도 그래야 한다.
    test("겨누기를 끈 호버 액션은 대상이 안 실린다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774, ignoreHoverUnit = true,
            conditions = { units = { hover = {} } } };
        check(Convert(action), "변환이 거절됐다");
        check(action.value == "/cast Rejuvenation", "본문이 " .. tostring(action.value) .. "다");
    end);

    --- [호버 안 했을 때]는 겨누는 조건이 아니다. 파생도 안 생기므로 본문에도 안 실린다.
    test("호버 안 했을 때는 겨누지 않는다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774,
            conditions = { units = { hover = false } } };
        check(Convert(action), "변환이 거절됐다");
        check(action.value == "/cast Rejuvenation", "본문이 " .. tostring(action.value) .. "다");
    end);

    --- **겨누기가 파생이면 `"@"`는 변환 전에 이미 죽어 있다.** `GetBindingInfoForAction`은
    --- 겨눌 것이 없는 `"@"`를 지우는데, 그 검사가 **hover 채워넣기보다 앞이다** - 뒤에 두면 다른
    --- 유닛을 겨누며 켠 조건이 호버한 유닛 조건으로 조용히 바뀌기 때문이다.
    ---
    --- 그러니 변환도 그것을 되살리면 안 된다. 되살리면 **변환이 바인딩을 좁혀서**, 전에는 발동하던
    --- 상태에서 안 나가게 된다. 본문에 `[@hover]`를 적는 것과는 다른 물음이다.
    test("죽어 있던 `@`는 변환이 되살리지 않는다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774,
            conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM },
                hover = {} } } };
        local before = DebindPrivate.GetBindingInfoForAction(action).unitStates.hover;
        check(Convert(action), "변환이 거절됐다");
        check(action.value == "/cast [@hover] Rejuvenation",
            "본문이 " .. tostring(action.value) .. "다");

        local after = DebindPrivate.GetBindingInfoForAction(action).unitStates.hover;
        check(after == before, "hover 축이 " .. tostring(before) .. "에서 "
            .. tostring(after) .. "로 움직였다");
    end);

    ---------------------------------------------------------------------------
    -- 조건은 따라오거나, 못 따라오면 변환이 안 선다
    ---------------------------------------------------------------------------

    --- `known`은 **이 액션 제 주문**에 대한 물음이라 `SPELL`에만 뜻이 있다. 매크로텍스트가 되면
    --- 물어볼 id가 사라지고, `GetBindingInfoForAction`이 그 조건을 바인딩에서 지운다
    --- (`Misc.lua`). 저장에는 남은 채로 아무 일도 안 하므로, **화면에는 조건이 걸린 것으로
    --- 보이는데 키는 늘 발동한다.**
    test("배웠을 때만 조건이 걸린 액션은 못 바꾼다", function()
        installWorld();
        check(not Can({ type = Constants.SPELL, value = 774, conditions = { known = true } }),
            "살릴 수 없는 조건을 들고도 변환이 선다");
        check(Can({ type = Constants.SPELL, value = 774 }),
            "조건이 없는데 변환이 안 선다");
    end);

    --- `"@"`는 **이 액션이 겨누는 대상**을 가리키는 키다. 매크로텍스트는 대상 필드를 안 가지므로
    --- (`TYPES_WITH_UNIT`) 변환 뒤에는 가리킬 것이 없어져서 `GetBindingInfoForAction`이 그 조건을
    --- 지운다. 본문의 `[@focus]`는 남으니 **겨누기는 하는데 그 유닛에 걸어둔 조건만 사라진다.**
    ---
    --- 겨누던 유닛의 이름으로 옮기면 뜻이 그대로다. 그 키는 조건 메뉴가 이미 쓰는 키이고
    --- (`DropDownMenus.lua`의 `isListedUnit`), 하류는 유닛 이름으로만 축을 만든다.
    test("겨누는 대상 조건은 그 유닛 이름으로 옮겨간다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774, unit = "focus",
            conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM } } } };
        check(Can(action), "옮길 수 있는데 변환이 안 선다");
        check(Convert(action), "변환이 거절됐다");
        check(action.conditions.units["@"] == nil, "`@`가 그대로 남았다");
        check(action.conditions.units.focus ~= nil, "겨누던 유닛으로 안 옮겨졌다");
        check(action.conditions.units.focus.reaction == Constants.REACTION_HARM,
            "옮기면서 값이 바뀌었다");

        local binding = DebindPrivate.GetBindingInfoForAction(action);
        check(binding.conditions.units and binding.conditions.units.focus ~= nil,
            "옮긴 조건이 바인딩에 안 닿는다");
    end);

    --- 같은 유닛에 조건이 이미 걸려 있는 경우. 변환 전에는 그 유닛에 대한 말이 두 키에 나뉘어
    --- 있고 `BuildUnitStates`가 `band`로 접는다. 변환 뒤에는 담을 키가 하나뿐이므로 **접힌
    --- 값을 저장 모양으로 적어야** 한다.
    ---
    --- **재는 것은 접힌 마스크다.** 저장 표의 필드가 어떻게 생겼느냐가 아니라 유닛 축이
    --- 움직였느냐가 이 변환이 지켜야 할 것이고, 그 답은 `binding.unitStates`에 있다.
    test("겹치면 교집합이 그 유닛 키에 들어간다", function()
        installWorld();

        local HELP, HARM = Constants.REACTION_HELP, Constants.REACTION_HARM;
        local cases = {
            { at = { reaction = HARM },    other = { dead = false } },
            { at = {},                     other = { reaction = HELP } },
            { at = { reaction = HELP },    other = { reaction = HARM } },
            { at = { dead = true },        other = { dead = false } },
            { at = { exists = false },     other = {} },
            { at = { exists = false },     other = { exists = false } },
            { at = { reaction = HELP },    other = { off = true, dead = true } },
        };

        for i = 1, #cases do
            local action = { type = Constants.SPELL, value = 774, unit = "focus",
                conditions = { units = { ["@"] = cases[i].at, focus = cases[i].other } } };
            local before = DebindPrivate.GetBindingInfoForAction(action).unitStates.focus;

            check(Can(action), i .. "번 경우에 변환이 안 선다");
            check(Convert(action), i .. "번 경우에 변환이 거절됐다");
            check(action.conditions.units["@"] == nil, i .. "번 경우에 `@`가 남았다");

            local after = DebindPrivate.GetBindingInfoForAction(action).unitStates.focus;
            check(after == before, i .. "번 경우에 focus 축이 " .. tostring(before)
                .. "에서 " .. tostring(after) .. "로 움직였다");
        end
    end);

    --- 꺼둔 `"@"`는 조건이 아니다. 저장은 끈 축을 기억하지만 그것은 메뉴가 되돌려주려고 드는
    --- 것이고, 바인딩에는 애초에 안 닿는다. **변환이 건드리는 것은 닿는 것뿐이다** - 옮겨서
    --- 접으면 기억이 살아 있는 조건으로 바뀐다.
    test("꺼둔 `@`는 옮기지 않는다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774, unit = "focus",
            conditions = { units = { ["@"] = { off = true, reaction = Constants.REACTION_HELP },
                focus = { reaction = Constants.REACTION_HARM } } } };
        local before = DebindPrivate.GetBindingInfoForAction(action).unitStates.focus;
        check(Convert(action), "변환이 거절됐다");
        check(action.conditions.units.focus.reaction == Constants.REACTION_HARM,
            "꺼진 값이 접혀 들어갔다");
        local after = DebindPrivate.GetBindingInfoForAction(action).unitStates.focus;
        check(after == before, "focus 축이 " .. tostring(before) .. "에서 "
            .. tostring(after) .. "로 움직였다");
    end);

    --- **바인딩이 유닛 조건을 읽는 자리는 둘이다.** `conditions.units`가 없으면 마이그레이션
    --- 전의 평평한 `checkedUnits`를 본다(`GetBindingInfoForAction`). 그래서 바인딩에는 살아 있는
    --- `"@"`가 있는데 `conditions.units`는 그 이름을 모르는 액션이 성립한다.
    ---
    --- 옮겨 적을 자리가 그쪽이면 이 파일이 옛 저장 모양을 두 번째로 배우는 것이 된다. 그 자리를
    --- 일부러 보는 곳은 하나로 두고, 여기서는 변환을 안 내준다. 마이그레이션이 지나가면 돌아온다.
    test("마이그레이션 전 모양은 못 바꾼다", function()
        installWorld();
        local at = { ["@"] = { reaction = Constants.REACTION_HARM } };

        local bare = { type = Constants.SPELL, value = 774, unit = "focus", checkedUnits = at };
        check(DebindPrivate.GetBindingInfoForAction(bare).conditions.units["@"] ~= nil,
            "이 액션은 살아 있는 `@`를 안 들고 있다");
        check(not Can(bare), "옮겨 적을 자리를 모르는데 변환이 선다");

        -- 조건 표는 있는데 유닛만 옛 자리에 있는 모양. 같은 갈래다.
        local mixed = { type = Constants.SPELL, value = 774, unit = "focus",
            conditions = { combat = true }, checkedUnits = at };
        check(not Can(mixed), "옮겨 적을 자리를 모르는데 변환이 선다");
    end);

    --- 이 빌드가 못 읽는 값. `UnitConditionForBinding`이 그것을 없음 점으로 읽으면서 **읽어낸
    --- 값이 아니라는 표시를 따로 낸다**(`binding.unitConditionUnreadable`). 접을 수 없는 값을
    --- 접은 척하면 그 표시가 사라지므로, 그 경우만 변환을 안 내준다.
    test("못 읽는 값이 끼어 있으면 못 바꾼다", function()
        installWorld();
        check(not Can({ type = Constants.SPELL, value = 774, unit = "focus",
                conditions = { units = { ["@"] = {}, focus = "언젠가의값" } } }),
            "못 읽는 값을 접겠다고 나선다");
    end);

    --- 겨누는 대상이 없으면 `"@"`는 가리킬 것이 없어서 바인딩에 닿은 적도 없다
    --- (`GetBindingInfoForAction`이 지운다). 옮길 것이 없으므로 변환은 그대로 내준다.
    test("겨누는 대상이 없으면 `@`는 막지 않는다", function()
        installWorld();
        check(Can({ type = Constants.SPELL, value = 774,
                conditions = { units = { ["@"] = {} } } }),
            "닿은 적도 없는 조건이 변환을 막는다");
    end);

    return T;
end
