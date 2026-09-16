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

    --- 쌍둥이를 세우는 계정 스위치를 읽으려면 프로필이 서 있어야 한다. 이 파일은 액션을 직접
    --- 만들어 넘기므로 레이어는 비어 있어도 된다.
    _G.DebindVars = {
        dbver = Constants.DB_VERSION,
        shared = { GENERAL = {}, classes = { [Constants.PLAYER_CLASS] = {} } },
        characters = {},
        migrated = {},
        switches = {},
    };
    DebindPrivate.InitDB();

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
        local action = { type = Constants.USESLOT, value = 13 };
        check(Can(action), "착용 칸에 변환이 안 선다");
        check(Convert(action), "변환이 거절됐다");
        check(action.type == Constants.MACROTEXT, "타입이 안 바뀌었다: " .. tostring(action.type));
        check(action.value == "/use [@@] 13", "본문이 " .. tostring(action.value) .. "다");
        check(action.name == DebindPrivate.EquipSlotFacts(13),
            "이름이 " .. tostring(action.name) .. "다");
        check(action.icon ~= nil, "아이콘이 안 붙었다");
    end);

    --- 대상은 본문에 굽는다. 착용 칸은 대상을 갖는 타입이고(`TYPES_WITH_UNIT`), 매크로텍스트는
    --- 안 갖는 타입이라 필드로는 못 따라간다.
    test("착용 칸의 대상은 본문에 들어간다", function()
        installWorld();
        local action = { type = Constants.USESLOT, value = 13, unit = "focus" };
        check(Convert(action), "변환이 거절됐다");
        check(action.value == "/use [@focus] 13", "본문이 " .. tostring(action.value) .. "다");
        check(action.unit == nil, "대상 필드가 남았다");
    end);

    ---------------------------------------------------------------------------
    -- 겨누는 대상
    ---------------------------------------------------------------------------

    --- 개체창의 유닛을 **대상으로 고른** 액션. 그 이름은 매크로 본문에서도 살아 있는 토큰이라
    --- (`ParseMacroText`가 누를 때 진짜 유닛으로 바꾼다) 그대로 실린다. 안 실으면 겨누기가 통째로
    --- 사라져서 현재 대상에게 나간다 - `SECURE_ACTIONS.macro`는 버튼의 unit을 안 본다.
    test("개체창 유닛을 고른 액션은 본문에 그 유닛이 실린다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774, unit = "unitframe" };
        check(Convert(action), "변환이 거절됐다");
        check(action.value == "/cast [@unitframe] Rejuvenation",
            "본문이 " .. tostring(action.value) .. "다");
    end);

    --- **쌍둥이는 변환을 막지 않는다** (2026-09-16, 소유자). 쌍둥이는 액션이 유닛을 받든 못 받든
    --- 서고 유닛을 받아 간다. 주문도 유닛을 쓰는 것이 있고 안 쓰는 것이 있는데 넘기는 쪽은 언제나
    --- 넘기고, 매크로 본문이 그 유닛을 읽느냐도 똑같이 그 액션의 몫이다. 읽게 하고 싶으면 `@@`가
    --- 그 자리다 (`implementing-focus-and-self-cast.md` §4).
    test("Hover Cast가 켜져 있어도 변환이 선다", function()
        installWorld();
        check(DebindPrivate.CanConvertToMacroText({ type = Constants.SPELL, value = 774 }),
            "쌍둥이를 들었다고 변환이 안 선다");
        check(DebindPrivate.CanConvertToMacroText({ type = Constants.SPELL, value = 774,
                casting = { hoverCast = { aim = "usual" } },
                conditions = { units = { unitframe = {} } } }),
            "Cast as usual인 액션에서 변환이 안 선다");
    end);

    --- **An action with no unit picked converts to `[@@]`** (`implementing-focus-and-self-cast.md`
    --- §4). Its twins pass `player`, `focus` and the pointed unit, and a body with no `@@` reads none
    --- of them, so the conversion would take the cast keys and Hover Cast off the key. On the
    --- original the press aims at nothing and `@@` goes out as a lone `@`, which the client ignores.
    ---
    --- A type that takes no unit keeps its body as it is: whether a body reads the unit is the
    --- action's business, and those never did.
    test("대상을 안 고른 액션은 [@@]로 겨눈다", function()
        installWorld();
        _G.SLASH_PET_ATTACK1 = "/petattack";
        _G.SLASH_PET_FOLLOW1 = "/petfollow";
        for _, case in ipairs({
            { { type = Constants.SPELL, value = 774 }, "/cast [@@] Rejuvenation" },
            { { type = Constants.USESLOT, value = 13 }, "/use [@@] 13" },
            { { type = Constants.PETACTION, value = "PET_ATTACK" }, "/petattack [@@]" },
            { { type = Constants.PETACTION, value = "PET_FOLLOW" }, "/petfollow" },
        }) do
            local action = case[1];
            local label = tostring(action.value) .. ": ";
            check(Convert(action), label .. "변환이 거절됐다");
            check(action.value == case[2], label .. "본문이 " .. tostring(action.value) .. "다");
        end
    end);

    --- [호버 안 했을 때]는 겨누는 조건이 아니다. 본문이 가리킨 유닛을 따로 적지 않는다.
    test("호버 안 했을 때는 겨누지 않는다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774,
            conditions = { units = { unitframe = false } } };
        check(Convert(action), "변환이 거절됐다");
        check(action.value == "/cast [@@] Rejuvenation", "본문이 " .. tostring(action.value) .. "다");
    end);

    --- **개체창 조건은 대상을 안 정하므로 본문에도 안 실린다** (§5), 그리고 조건 자체는 제 축에
    --- 그대로 남아야 한다. 변환이 그 축을 좁히면 전에 나가던 상태에서 키가 멈춘다.
    test("개체창 조건은 본문에 안 실리고 축도 안 움직인다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774,
            conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM },
                unitframe = {} } } };
        local before = DebindPrivate.GetBindingInfoForAction(action).unitStates.unitframe;
        check(Convert(action), "변환이 거절됐다");
        check(action.value == "/cast [@@] Rejuvenation", "본문이 " .. tostring(action.value) .. "다");

        local after = DebindPrivate.GetBindingInfoForAction(action).unitStates.unitframe;
        check(after == before, "개체창 축이 " .. tostring(before) .. "에서 "
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

    --- **이름을 들었어도 못 바꾼다** (2026-09-12, 소유자). 물음 자체는 본문이 되어도 서지만,
    --- 주문이 아닌 액션에 `known`을 세울 자리가 UI에 없어서 저장 쪽이 그 값을 안 들고 간다
    --- (`Profile.lua`의 청소, `devdocs/making-known-a-spell-name.md`). 변환을 세워 주면 조건이
    --- 조용히 사라지는 것이 된다.
    test("이름을 든 배웠을 때만 조건도 변환을 막는다", function()
        installWorld();
        check(not Can({ type = Constants.SPELL, value = 774, conditions = { known = "Regrowth" } }),
            "살릴 수 없는 조건을 들고도 변환이 선다");
    end);

    --- **`"@"`는 변환을 건너서도 같은 유닛에 묻는다.** 매크로텍스트의 쌍둥이도 제 유닛을 싣고
    --- (`FillBinding`), `"@"`는 그 바인딩이 겨누는 유닛에 묻는 것이라(`ResolvedUnitOf`) 바꾸기
    --- 전후가 같다. 원본은 앞뒤로 `target`이다.
    test("대상 none에 `@`가 걸려 있어도 바꿀 수 있다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774, unit = "none",
            casting = { hoverCast = {} },
            conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM } } } };
        local before = DebindPrivate.GetBindingsForAction(action);
        local twinBefore = before[2] and before[2].unit;
        check(DebindPrivate.CanConvertToMacroText(action), "변환이 안 선다");
        check(DebindPrivate.ConvertToMacroText(action), "변환이 거절됐다");

        local after = DebindPrivate.GetBindingsForAction(action);
        check(after[2] and after[2].unit == twinBefore,
            "쌍둥이가 겨누던 것이 " .. tostring(twinBefore) .. "에서 "
                .. tostring(after[2] and after[2].unit) .. "로 움직였다");
    end);

    --- `"@"` is **the unit the press aims at**. The macro text carries no target field, so after the
    --- conversion its `"@"` would ask `target` while the body's `[@focus]` still goes to the focus.
    --- Moved to that unit's own name, the condition keeps asking the unit the cast goes to.
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
            { at = { reaction = HELP },    other = { disabled = true, dead = true } },
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

    --- **유닛 축 밖의 축들.** 위 테스트가 `unitStates`를 재는데, 소속과 역할은 그 마스크에
    --- 안 접히고 제 컬럼으로 산다(`binding.unitGroups`, `binding.unitRole`). 그래서 접는 쪽이
    --- 그 필드를 빠뜨려도 위 테스트는 초록으로 남고, 사라진 조건은 **바인딩이 넓어지는**
    --- 방향이라 그 키가 걸리면 안 될 때 걸린다.
    test("소속과 역할도 접힌 값에 남는다", function()
        installWorld();

        local PARTY = Constants.UNITGROUP_PARTY;
        local RAID = Constants.UNITGROUP_RAID;

        -- `"@"`만 소속을 들고 있다. 옮길 곳의 필드가 비어 있어도 옮겨야 한다.
        local action = { type = Constants.SPELL, value = 774, unit = "focus",
            conditions = { units = {
                ["@"] = { group = PARTY },
                focus = { dead = false },
            } } };
        check(Convert(action), "변환이 거절됐다");
        check(action.conditions.units.focus.group == PARTY,
            "`@`의 소속이 사라졌다: " .. tostring(action.conditions.units.focus.group));

        -- 양쪽이 다 들고 있으면 교집합이다. 겹치는 축이라 이 둘은 **하나로 안 접힌다** -
        -- 저장은 상자를 그대로 들고 파생이 칸으로 편다(`Misc.UnitGroupToCells`).
        action = { type = Constants.SPELL, value = 774, unit = "focus",
            conditions = { units = {
                ["@"] = { group = PARTY + RAID },
                focus = { group = PARTY },
            } } };
        check(Convert(action), "변환이 거절됐다");
        check(action.conditions.units.focus.group == PARTY,
            "소속 교집합이 틀렸다: " .. tostring(action.conditions.units.focus.group));

        -- 역할은 hover에만 실리므로 `"@"`가 hover를 가리킬 때만 만난다.
        action = { type = Constants.SPELL, value = 774, unit = "unitframe",
            conditions = { units = {
                ["@"] = { role = Constants.ROLE_TANK },
                unitframe = { dead = false },
            } } };
        if (Can(action)) then
            check(Convert(action), "변환이 거절됐다");
            check(action.conditions.units.unitframe.role == Constants.ROLE_TANK,
                "`@`의 역할이 사라졌다: " .. tostring(action.conditions.units.unitframe.role));
        end
    end);

    --- 꺼둔 `"@"`는 조건이 아니다. 저장은 끈 축을 기억하지만 그것은 메뉴가 되돌려주려고 드는
    --- 것이고, 바인딩에는 애초에 안 닿는다. **변환이 건드리는 것은 닿는 것뿐이다** - 옮겨서
    --- 접으면 기억이 살아 있는 조건으로 바뀐다.
    test("꺼둔 `@`는 옮기지 않는다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774, unit = "focus",
            conditions = { units = { ["@"] = { disabled = true, reaction = Constants.REACTION_HELP },
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

    --- **With no unit in the body, `"@"` stays `"@"`.** The macro text aims at nothing either, so
    --- its `"@"` resolves where the action's did: `target` with nothing held, and the twins' units
    --- with a key held. Moving it to `target` would keep the first and break the second.
    test("겨누는 대상이 없으면 `@`는 그대로 남는다", function()
        installWorld();
        local action = { type = Constants.SPELL, value = 774,
            conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM } } } };
        check(Can(action), "변환이 안 선다");
        local before = DebindPrivate.GetBindingInfoForAction(action).unitStates.target;
        check(Convert(action), "변환이 거절됐다");
        check(action.conditions.units["@"] ~= nil, "`@`가 옮겨졌다");
        check(action.conditions.units.target == nil, "`@`가 target 키로 갔다");
        local after = DebindPrivate.GetBindingInfoForAction(action).unitStates.target;
        check(after == before, "target 축이 " .. tostring(before) .. "에서 "
            .. tostring(after) .. "로 움직였다");
    end);

    --- **On `none` the body says `[@none]` and `"@"` stays `"@"`.** `none` is aimed like an action with
    --- no target (2026-09-15, owner), which is how the converted macro text is aimed as well, so the
    --- condition already asks the right unit. A hover condition fills in `hover` on the binding without
    --- the body going there; moving `"@"` onto that unit would stop the twins asking `player` and
    --- `focus`.
    test("대상 none의 `@`는 변환해도 그대로 남고 본문은 none을 겨눈다", function()
        installWorld();
        for _, withHover in ipairs({ false, true }) do
            local units = { ["@"] = { reaction = Constants.REACTION_HARM } };
            if (withHover) then
                units.unitframe = {};
            end
            local label = withHover and "hover 조건 있음: " or "hover 조건 없음: ";
            local action = { type = Constants.SPELL, value = 774, unit = "none",
                conditions = { units = units } };
            check(Convert(action), label .. "변환이 거절됐다");
            check(action.value == "/cast [@none] Rejuvenation", label .. "본문이 " .. tostring(action.value) .. "다");
            check(action.conditions.units["@"] ~= nil, label .. "`@`가 옮겨졌다");
            check(action.conditions.units.none == nil, label .. "`@`가 none 키로 갔다");
        end
    end);

    return T;
end
