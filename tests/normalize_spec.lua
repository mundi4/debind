-- `GetBindingInfoForAction`의 정규화 테스트. 와우 클라이언트 불필요.
--
-- 이 함수는 액션(프로필이 저장하는 것)에서 바인딩(solver와 `UpdateBindings`가 읽는 것)을
-- 만들면서, **뜻이 없어진 조건들을 지운다.** 그 판정이 여기 다 모여 있다.
--
-- 왜 테스트가 필요한가: 지우는 순서가 곧 의미다. 검사 하나가 그것을 무효로 만드는 코드보다
-- 위에 있으면 조용히 통과하고, 잘못 지우면 조건이 사라진 채 바인딩이 나간다. 어느 쪽도
-- 화면에 아무 표시가 없다.
--
-- `"@"` especially: it is not a unit name but **a pointer to the unit the press aims at**, and the
-- places that clear `unit` and the one that fills it in decide where it lands.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local normalize = DebindPrivate.GetBindingInfoForAction;

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
            error(msg or "assertion failed", 2);
        end
    end

    --- 타입을 안 적으면 주문으로 본다. 대상을 가질 수 있는 타입 중 제일 흔한 것이라
    --- 대부분의 갈래에서 "정상적인 액션"의 대역이 된다.
    --- 스펙 리터럴을 **프로덕션과 같은 모양**으로 세운다: 조건은 `conditions` 안에 산다
    --- (`Profile.lua`의 `KEYS_TO_SAVE`, `Misc.GetBindingInfoForAction`).
    ---
    --- 리터럴은 평평하게 쓴다. 자리마다 `conditions = { ... }`를 손으로 적으면 한 줄
    --- 빠뜨렸을 때 그 조건이 조용히 사라지고, **조건이 빠진 액션은 넓어진다** - 스펙이 잡아야
    --- 할 바로 그 종류의 잘못이 스펙 안에서 난다.
    ---
    --- **무엇이 조건인지는 여기서 안 정한다.** `Constants.IsConditionField`를 그대로 부르므로
    --- 축이 하나 늘어도 이 함수는 안 바뀌고, 프로덕션과 갈릴 자리가 없다.
    local function nest(action)
        local conditions = action.conditions;
        for k, v in pairs(action) do
            if (Constants.IsConditionField(k)) then
                conditions = conditions or {};
                conditions[k] = v;
                action[k] = nil;
            end
        end
        action.conditions = conditions;
        return action;
    end
    local function spell(fields)
        local action = { type = Constants.SPELL, value = 100 };
        for k, v in pairs(fields or {}) do
            action[k] = v;
        end
        return normalize(nest(action), true);
    end

    ---------------------------------------------------------------------------
    -- 조건부 판정
    --
    -- 발동 순서의 셋째 단계가 `isConditional`을 읽는다. 조건부가 무조건보다 앞이다.
    -- 물음은 `next` 하나다 - 표에 든 것은 전부 조건이다.
    ---------------------------------------------------------------------------

    test("아는 상태 이름 하나면 조건부다", function()
        check(DebindPrivate.IsConditionalBinding(spell({ ["$state2"] = false })) == true,
            "조건부인데 무조건으로 셌다");
        check(DebindPrivate.IsConditionalBinding(spell({})) == false, "오탐");
    end);

    ---------------------------------------------------------------------------
    -- 바인딩은 액션 하나의 순수 파생이다
    --
    -- 순서를 정하는 값은 액션 하나로 답이 안 나온다 - 프로필 안에서의 자리이기 때문이다.
    -- 그래서 그것은 `Misc.MakeOrderRecord`가 따로 들고, 바인딩에는 안 앉는다.
    --
    -- 여기서 보는 것은 `GetBindingInfoForAction`이 낸 바인딩이다. `layerRank`/`seq`/
    -- `isConditional`을 써넣던 것은 `Debind.lua`의 `BuildKeyMap`이고, **그 파일도 이 하네스가
    -- 싣는다** - `KeyMap`을 거쳐 나온 쪽은 아직 `/debtest`의 `Binding carries no ordering
    -- fields`가 보고 있고, 여기로 내려올 수 있다.
    ---------------------------------------------------------------------------

    test("바인딩은 순서 필드를 안 든다", function()
        local b = spell({ priority = 1, seq = 4 });
        check(b.priority == nil, "priority가 바인딩에 앉아 있다");
        check(b.seq == nil, "seq가 바인딩에 앉아 있다");
        check(b.layerRank == nil, "layerRank가 바인딩에 앉아 있다");
        check(b.isConditional == nil, "isConditional이 바인딩에 앉아 있다");
    end);
    ---------------------------------------------------------------------------
    -- 개체창 조건은 `units["unitframe"]`에 산다
    --
    -- 저장에는 그 키 하나뿐이다. 아래 다른 절들이 옛 이름으로 액션을 만드는 것은 **그쪽이
    -- 들어올림 경로를 지나기 때문**이고, 여기가 그 두 모양이 같은 답을 낸다는 것을 잠근다.
    ---------------------------------------------------------------------------

    test("저장된 호버 조건이 축에 실린다", function()
        local b = spell({ units = { unitframe = { reaction = Constants.REACTION_HELP } } });
        check(b.conditions.units.unitframe ~= nil, "조건이 안 옮겨짐");
        check(b.unitStates["unitframe"] == Constants.UNITSTATE_HELP, "축에 안 실림");
    end);

    test("저장된 호버 조건이 false면 부재로 파생된다", function()
        local b = spell({ units = { unitframe = false } });
        check(b.conditions.units.unitframe == false, "false가 안 남음 - nil과 다른 답이다");
        check(b.unitStates["unitframe"] == Constants.UNITSTATE_NONE, "부재로 안 좁혀짐");
    end);

    test("반응을 전부 고른 저장값은 제약이 없는 것과 같다", function()
        local b = spell({ units = { unitframe = { reaction = Constants.REACTION_ALL } } });
        check(b.unitStates["unitframe"] == Constants.UNITSTATE_EXISTS, "축이 좁아짐");
    end);

    test("호버 유닛에도 생사가 걸린다", function()
        local b = spell({ units = { unitframe = { dead = true } } });
        check(b.unitStates["unitframe"] == Constants.UNITSTATE_DEAD, "생사가 축에 안 실림");
    end);

    ---------------------------------------------------------------------------
    -- 끈 조건은 **기억하되 판정에서 뺀다**
    --
    -- 라디오를 [사용 안 함]이나 [없을 때]로 옮겼다고 골라둔 반응·생사를 지우면, 되돌렸을 때
    -- 처음부터 다시 골라야 한다. 옵션을 끄는 것이지 지우는 것이 아니고, 무시하는 것은
    -- 코드가 한다.
    ---------------------------------------------------------------------------

    test("꺼진 조건은 바인딩에 안 나온다", function()
        local b = spell({ units = {
            target = { disabled = true, reaction = Constants.REACTION_HELP, dead = true },
        } });
        check(b.conditions.units == nil, "꺼진 조건이 바인딩까지 갔다");
        check(b.unitStates == nil or b.unitStates.target == nil, "축을 좁혔다");
    end);

    test("\"없을 때\"는 기억한 축을 안 읽는다", function()
        local b = spell({ units = {
            target = { exists = false, reaction = Constants.REACTION_HELP, dead = true },
        } });
        check(b.unitStates.target == Constants.UNITSTATE_NONE,
            "기억만 해야 할 축이 판정에 실렸다");
    end);

    test("표시가 없는 표는 \"있을 때\"다", function()
        -- 손으로 쓴 값과 아직 안 옮겨진 프로필이 이 모양으로 온다. 조건 없음으로 읽으면
        -- 걸어둔 것보다 넓어져 남의 키를 가져간다.
        check(spell({ units = { target = {} } }).unitStates.target
            == Constants.UNITSTATE_EXISTS, "빈 표가 조건 없음으로 읽힘");
    end);

    test("꺼진 조건만 있으면 조건부 액션이 아니다", function()
        local action = { type = Constants.SPELL, value = 100,
            units = { target = { disabled = true, reaction = Constants.REACTION_HELP } } };
        check(not DebindPrivate.IsConditionalAction(action),
            "기억만 하는 값이 액션을 조건부로 만들었다");
    end);

    ---------------------------------------------------------------------------
    -- 옛 `hover`/`reactions`를 들어올린다
    --
    -- 마이그레이션이 아직 안 닿은 프로필(가져오기 도중, 손으로 고친 것)이 여기로 온다.
    -- 들어올림은 **바인딩 사본에만** 일어나고 액션은 안 건드린다 - 저장을 고치는 것은
    -- `Profile.lua`의 마이그레이션 몫이다.
    ---------------------------------------------------------------------------

    test("옛 hover/reactions가 같은 답을 낸다", function()
        local action = { type = Constants.SPELL, value = 100,
            hover = true, reactions = Constants.REACTION_HELP };
        local b = normalize(action, true);
        check(b.unitStates["unitframe"] == Constants.UNITSTATE_HELP, "새 모양과 답이 다름");
        check(action.hover == true, "액션이 고쳐졌다 - 들어올림은 사본에만 일어나야 한다");
        check(action.units == nil, "액션에 units가 생겼다");
    end);

    -- 두 메뉴가 다 살아 있던 시절의 프로필이면 같은 유닛에 조건이 둘 있을 수 있다. 덮으면
    -- 걸어둔 것보다 넓어지므로 교집합하고, 안 겹치면 어떤 유닛도 못 드는 조건이 된다.
    test("옛 hover가 같은 유닛의 조건과 교집합된다", function()
        local b = normalize(nest({ type = Constants.SPELL, value = 100,
            hover = true, reactions = Constants.REACTION_HELP,
            units = { unitframe = { reaction = Constants.REACTION_HARM } } }), true);
        check(b.unitStates["unitframe"] == 0, "안 겹치는 두 조건이 0이 안 됨");
    end);

    test("옛 hover=false가 존재 조건과 만나면 0이 된다", function()
        local b = normalize(nest({ type = Constants.SPELL, value = 100,
            hover = false, units = { unitframe = {} } }), true);
        check(b.unitStates["unitframe"] == 0, "부재와 존재가 0이 안 됨");
    end);

    ---------------------------------------------------------------------------
    -- hover가 꺼져 있으면 hover에 딸린 것들은 뜻이 없다
    --
    -- 이 셋은 "마우스를 올린 프레임"에 대한 이야기라, 그 조건 자체가 없으면 말할 대상이
    -- 없다. 남겨두면 solver가 없는 축을 좁히고, 사용자는 끄고 나서도 예전 값에 걸린다.
    ---------------------------------------------------------------------------

    test("hover가 없으면 반응과 frameTypes가 사라진다", function()
        local b = spell({
            reactions = Constants.REACTION_HELP,
            frameTypes = Constants.FRAMETYPE_PLAYER,
        });
        -- 옛 `reactions`는 `hover`가 있을 때만 읽힌다. 혼자 오면 호버 조건이 안 선다.
        check(b.conditions.units == nil or b.conditions.units.unitframe == nil, "호버 조건이 남음");
        check(b.conditions.frameTypes == nil, "frameTypes가 남음");
    end);

    -- `false`는 "호버 중이 **아닐** 때"라는 진짜 조건이다. 그래도 반응·프레임종류는
    -- 여전히 말할 대상이 없다 - 올라간 프레임이 없으니까.
    test("hover가 false여도 딸린 것들은 사라진다", function()
        local b = spell({
            hover = false,
            reactions = Constants.REACTION_HELP,
            frameTypes = Constants.FRAMETYPE_PLAYER,
        });
        -- 안 올렸을 때와 반응은 같이 설 수 없다. 접기가 조건을 `false` 하나로 만든다.
        check(b.conditions.units.unitframe == false, "반응이 조건으로 남음");
        check(b.conditions.frameTypes == nil, "frameTypes가 남음");
    end);

    ---------------------------------------------------------------------------
    -- 전부 고른 마스크는 조건이 아니다
    --
    -- 같은 조건이 두 형태(nil과 전체비트)로 저장되면 solver가 서로 다른 상자로 본다.
    ---------------------------------------------------------------------------

    test("hover 반응을 전부 고르면 nil로 접힌다", function()
        local b = spell({ hover = true, reactions = Constants.REACTION_ALL });
        check(b.conditions.units.unitframe.reaction == nil, "전체 비트가 안 접힘");
    end);

    test("hover 프레임종류를 전부 고르면 nil로 접힌다", function()
        local b = spell({ hover = true, frameTypes = Constants.FRAMETYPE_ALL });
        check(b.conditions.units.unitframe.frameTypes == nil, "전체 비트가 안 접힘");
        check(b.unitFrameTypes == nil, "축이 좁아짐");
    end);

    test("일부만 고른 마스크는 그대로 남는다", function()
        local b = spell({
            hover = true,
            reactions = Constants.REACTION_HELP,
            frameTypes = Constants.FRAMETYPE_PLAYER,
        });
        check(b.conditions.units.unitframe.reaction == Constants.REACTION_HELP, "반응이 바뀜");
        check(b.conditions.units.unitframe.frameTypes == Constants.FRAMETYPE_PLAYER,
            "frameTypes가 바뀜");
        check(b.unitFrameTypes == Constants.FRAMETYPE_PLAYER, "축에 안 실림");
    end);

    ---------------------------------------------------------------------------
    -- 주문이 아니면 "배웠는가"를 물을 수 없다
    ---------------------------------------------------------------------------

    test("주문이 아니면 known이 사라진다", function()
        check(normalize(nest({ type = Constants.ITEM, value = 1, known = true }), true)
            .conditions.known == nil, "known이 남음");
    end);

    test("주문이면 known이 남는다", function()
        check(spell({ known = true }).conditions.known == true, "known이 사라짐");
    end);

    --- **이름을 들었어도 마찬가지다** (2026-09-12, 소유자). 값이 주문 이름이 되면서 물음 자체는
    --- 액션과 무관해졌지만, 주문이 아닌 액션에 그 조건을 세울 자리가 UI에 없다. 공유 프로필과
    --- 손으로 고친 것이 들고 올 수 있는 값이고, 살려 두면 화면에 끌 자리가 없는 조건이 된다.
    test("주문이 아니면 이름을 든 known도 사라진다", function()
        local b = normalize(nest({ type = Constants.MACROTEXT, value = "/cast Foo",
            known = "천체의 정렬" }), true);
        check(b.conditions == nil or b.conditions.known == nil,
            "known이 " .. tostring(b.conditions and b.conditions.known));
    end);

    ---------------------------------------------------------------------------
    -- `known`은 참 아니면 없음이다. 이 블록의 다른 조건들과 달리 세 번째 값이 없다
    --
    -- 묻는 대상이 언제나 그 액션 자신의 주문이라, `false`는 "그 주문을 모를 때 그 주문을
    -- 시전"이 된다. 성립하는 상태가 없다. UI도 체크박스 하나라 참/없음만 쓴다.
    --
    -- 그런데 `Export.lua`가 `known = "boolean"`이고 `Import.lua`의 `FieldAllowed`는 이름과
    -- 타입만 보므로 `false`가 통과한다. 여기서 안 지우면 `UpdateBindings`가 참일 때와 **같은**
    -- `[known:<값>]`을 굽고, 그 바인딩은 꺼져 있어야 할 상태에서 발동한다.
    ---------------------------------------------------------------------------

    test("주문이어도 거짓인 known은 사라진다", function()
        check(spell({ known = false }).known == nil, "known=false가 남음");
    end);

    test("주문이 아니면 거짓인 known도 사라진다", function()
        check(normalize(nest({ type = Constants.MACROTEXT, value = "/cast Foo", known = false }), true).known == nil,
            "known=false가 남음");
    end);

    ---------------------------------------------------------------------------
    -- 대상 유닛 자체의 정규화
    --
    -- `binding.unit`은 "사용자가 고른 대상"이 아니라 **매크로가 실제로 겨눌 유닛**이다.
    -- 못 갖는 타입이면 지우고, hover 액션이 제 대상이 없으면 채워 넣는다.
    ---------------------------------------------------------------------------

    test("대상을 못 갖는 타입이면 대상이 사라진다", function()
        local b = normalize(nest({ type = Constants.MACROTEXT, value = "/say hi", unit = "focus" }), true);
        check(b.unit == nil, "대상이 남음");
    end);

    test("대상을 안 받는 펫 명령이면 대상이 사라진다", function()
        local b = normalize(nest({ type = Constants.PETACTION, value = "PET_FOLLOW", unit = "focus" }), true);
        check(b.unit == nil, "대상이 남음");
    end);

    test("대상을 받는 펫 명령은 대상을 지킨다", function()
        local b = normalize(nest({ type = Constants.PETACTION, value = "PET_ATTACK", unit = "focus" }), true);
        check(b.unit == "focus", "대상이 사라짐");
    end);

    --- **개체창 조건은 대상을 안 채워 넣는다** (`devdocs/which-action-a-key-runs.md` §5). 대상을
    --- 안 고른 원본은 게임이 놓는 대상으로 나가고, 가리킨 유닛은 쌍둥이가 든다. 채워 넣던 동안에는
    --- 아무것도 안 가리킨 누름이 없는 유닛에게 나갔다.
    test("개체창 조건은 원본의 대상을 안 채운다", function()
        check(spell({ hover = true }).unit == nil,
            "채워넣기가 남았다: " .. tostring(spell({ hover = true }).unit));
    end);

    test("제 대상이 있으면 그 대상 그대로다", function()
        check(spell({ hover = true, unit = "focus" }).unit == "focus", "대상이 덮어써짐");
    end);

    -- **개명 전 이름으로 고른 대상도 옮겨서 읽는다.** `dbver <= 6`이 저장된 `unit = "hover"`를
    -- 옮기지만, 사다리가 아직 안 닿은 프로필이 그대로 오면 `binding.unit`에 아무도 못 알아보는
    -- 이름이 실린다 - 클릭 경로가 그 이름을 안 보고(`isClickCast`), 방출도 `SPECIAL_UNITS`와
    -- `BASIC_UNITS` 어느 쪽에서도 못 찾아서 대상 없이 나간다.
    test("개명 전 이름으로 고른 대상은 unitframe으로 읽힌다", function()
        check(spell({ unit = "hover" }).unit == "unitframe", "대상이 " .. tostring(spell({ unit = "hover" }).unit));
    end);

    test("대상이 멀쩡하면 \"@\"는 남는다", function()
        local b = spell({ unit = "focus", units = { ["@"] = true } });
        check(type(b.conditions.units["@"]) == "table", "멀쩡한 조건이 지워짐");
        check(b.unitStates.focus == Constants.UNITSTATE_EXISTS, "대상 유닛 축에 안 얹힘");
    end);

    ---------------------------------------------------------------------------
    -- An action that takes no unit keeps `"@"`
    --
    -- **`"@"` is the unit the press aims at, whether or not the action uses it** (2026-09-15,
    -- owner). Whether a spell or a macro body does anything with that unit cannot be known, and
    -- every action gets the self and focus twins, so the condition stays and asks what
    -- `ResolvedUnitOf` answers: `target` on the original with nothing aimed at.
    ---------------------------------------------------------------------------

    test("타입 때문에 대상을 잃어도 \"@\"는 target 칸에 선다", function()
        local b = normalize(nest({
            type = Constants.MACROTEXT, value = "/say hi",
            unit = "focus",
            units = { ["@"] = true },
        }), true);
        check(b.unit == nil, "대상이 안 지워짐 - 전제가 깨졌다");
        check(b.conditions.units and b.conditions.units["@"] ~= nil, "\"@\"가 지워짐");
        check(b.unitStates and b.unitStates.target == Constants.UNITSTATE_EXISTS,
            "target 칸: " .. tostring(b.unitStates and b.unitStates.target));
        check(not b.unitStatesOpaque, "바인딩이 통째로 판정에서 빠짐");
    end);

    test("펫 명령 때문에 대상을 잃어도 \"@\"는 target 칸에 선다", function()
        local b = normalize(nest({
            type = Constants.PETACTION, value = "PET_FOLLOW",
            unit = "focus",
            units = { ["@"] = true },
        }), true);
        check(b.unit == nil, "대상이 안 지워짐 - 전제가 깨졌다");
        check(b.unitStates and b.unitStates.target == Constants.UNITSTATE_EXISTS,
            "target 칸: " .. tostring(b.unitStates and b.unitStates.target));
        check(not b.unitStatesOpaque, "바인딩이 통째로 판정에서 빠짐");
    end);

    -- **대상을 못 갖는 타입의 원본은 `"@"`를 `target` 칸에 묻는다.** 대상이 지워지고 채워 넣는
    -- 것도 없으니, 게임이 놓는 대상이 그 누름이 겨누는 유닛이다.
    test("대상이 지워진 매크로의 \"@\"는 target 칸에 선다", function()
        local help = spell({ unit = "focus", units = { ["@"] = "help" } }).unitStates.focus;
        local b = normalize(nest({
            type = Constants.MACROTEXT, value = "/say hi",
            unit = "focus", hover = true,
            units = { ["@"] = "help" },
        }), true);
        check(b.unit == nil, "대상이 남았다: " .. tostring(b.unit));
        check(b.unitStates.target == help, "target 칸: " .. tostring(b.unitStates.target));
    end);

    ---------------------------------------------------------------------------
    -- `"@"`와 명시 유닛 조건이 같은 유닛에서 만날 때
    --
    -- `"@"`가 focus를 가리키는데 focus에 명시 조건도 걸려 있으면 둘은 한 축에서 만난다.
    -- 같은 말이면 한쪽으로 접고, 어긋나면 **둘 다 남겨서** 마스크가 0이 되게 둔다 -
    -- 조용히 한쪽을 이기게 하면 사용자가 건 조건이 소리 없이 사라진다.
    ---------------------------------------------------------------------------

    local function atAnd(atValue, unitValue)
        return spell({ unit = "focus", units = { ["@"] = atValue, focus = unitValue } });
    end

    -- **어느 키에 남았는지는 계약이 아니다.** 예전에는 여기서 손으로 한쪽으로 접었는데, 지금은
    -- 두 소비자가 각자 교집합을 낸다(`BuildUnitStates`의 band, 방출의 `mergeUnitConditions`).
    -- 그래서 검사할 것은 키의 생김새가 아니라 **겨눈 유닛의 축이 어디로 좁혀졌는가**다.
    test("같은 말이면 축이 그 값으로 좁혀진다", function()
        check(atAnd("help", "help").unitStates.focus == Constants.UNITSTATE_HELP, "우호");
    end);

    -- "존재"는 "우호"를 포섭한다. 좁은 쪽이 남아야 조건이 안 넓어진다.
    test("포섭 관계면 좁은 쪽으로 좁혀진다", function()
        check(atAnd(true, "help").unitStates.focus == Constants.UNITSTATE_HELP,
            "\"@\"가 존재, 명시가 우호");
        check(atAnd("harm", true).unitStates.focus == Constants.UNITSTATE_HARM,
            "\"@\"가 적대, 명시가 존재");
    end);

    test("어긋나면 둘 다 남아서 마스크가 0이 된다", function()
        local b = atAnd("help", "harm");
        check(b.conditions.units["@"] ~= nil, "조용히 한쪽이 지워짐");
        check(b.unitStates.focus == 0, "모순이 마스크에 안 드러남");
    end);

    test("존재 x 부재도 마스크가 0이 된다", function()
        local b = atAnd(false, true);
        check(b.unitStates.focus == 0, "모순이 마스크에 안 드러남");
    end);

    ---------------------------------------------------------------------------
    -- 유닛 조건이 마스크로 접히는 값 대응
    --
    -- solver가 유닛에 대해 읽는 것은 `unitStates`뿐이다. 저장된 스칼라가 여기서 축 위의
    -- 점으로 바뀐다.
    ---------------------------------------------------------------------------

    test("유닛 조건 스칼라가 축 위의 마스크가 된다", function()
        check(spell({ units = { target = true } }).unitStates.target
            == Constants.UNITSTATE_EXISTS, "존재");
        check(spell({ units = { target = false } }).unitStates.target
            == Constants.UNITSTATE_NONE, "부재");
        check(spell({ units = { target = "help" } }).unitStates.target
            == Constants.UNITSTATE_HELP, "우호");
        check(spell({ units = { target = "harm" } }).unitStates.target
            == Constants.UNITSTATE_HARM, "적대");
    end);

    test("\"@\"는 겨누는 유닛의 축으로 펴진다", function()
        local b = spell({ unit = "focus", units = { ["@"] = "help" } });
        check(b.unitStates.focus == Constants.UNITSTATE_HELP, "대상 유닛 축에 안 얹힘");
        check(b.unitStates["@"] == nil, "\"@\"가 제 축을 가짐");
    end);

    ---------------------------------------------------------------------------
    -- 저장 형식: 축별 마스크 (`Profile.lua`의 `dbver <= 4`)
    --
    -- 값 하나에 열거를 packing하지 않는다. 축이 늘 때 같은 숫자의 뜻이 바뀌면 마이그레이션을
    -- 또 해야 하고, "제약 안 함"과 "전부 선택"이 구분되지 않는다. 축마다 필드를 두면
    -- **필드가 없다는 것 자체가 "이 축은 제약 안 함"**이라 옛 데이터가 그대로 유효하다.
    ---------------------------------------------------------------------------

    test("빈 테이블은 존재만 요구한다", function()
        check(spell({ units = { target = {} } }).unitStates.target
            == Constants.UNITSTATE_EXISTS, "존재로 안 접힘");
    end);

    test("반응 필드가 유닛 축을 좁힌다", function()
        check(spell({ units = { target = { reaction = Constants.REACTION_HELP } } })
            .unitStates.target == Constants.UNITSTATE_HELP, "우호");
        check(spell({ units = { target = { reaction = Constants.REACTION_HARM } } })
            .unitStates.target == Constants.UNITSTATE_HARM, "적대");
        check(spell({ units = { target = { reaction = Constants.REACTION_OTHER } } })
            .unitStates.target == Constants.UNITSTATE_OTHER, "기타");
    end);

    -- 스칼라로는 못 쓰던 것. 축별 마스크가 생긴 이유의 절반이다.
    test("반응을 여럿 고를 수 있다", function()
        local b = spell({ units = {
            target = { reaction = Constants.REACTION_HELP + Constants.REACTION_OTHER },
        } });
        check(b.unitStates.target == Constants.UNITSTATE_HELP + Constants.UNITSTATE_OTHER,
            "합집합이 안 실림");
    end);

    -- 새 축이 오면 필드가 하나 늘 뿐이다. 모르는 필드가 섞여 있어도 지금 아는 축의 판정은
    -- 그대로여야 한다 - 옛 버전이 새 프로필을 읽는 경우가 이 모양이다.
    test("모르는 축 필드는 지금 판정을 안 바꾼다", function()
        local b = spell({ units = {
            target = { reaction = Constants.REACTION_HELP, somethingLater = 3 },
        } });
        check(b.unitStates.target == Constants.UNITSTATE_HELP, "모르는 필드에 흔들림");
    end);

    ---------------------------------------------------------------------------
    -- 생사 축
    --
    -- 생사는 **제 컬럼이 아니라 곱의 절반을 덜어내는 것**이다. "없거나, 있으면서 살아있거나"가
    -- (반응, 생사) 평면에서 직사각형이 아니라서 - 없음 점에는 제약할 생사 값이 없다.
    -- 생사를 따로 컬럼으로 두면 그 조건의 절반이 상자에서 빠지고, 좁아진 상자는 지워진다.
    ---------------------------------------------------------------------------

    test("생사를 안 걸면 축이 안 좁아진다", function()
        check(spell({ units = { target = {} } }).unitStates.target
            == Constants.UNITSTATE_EXISTS, "존재 6점 전부여야 한다");
    end);

    test("살아있음이 죽은 절반을 덜어낸다", function()
        check(spell({ units = { target = { dead = false } } }).unitStates.target
            == Constants.UNITSTATE_ALIVE, "살아있는 3점이어야 한다");
    end);

    test("죽음이 살아있는 절반을 덜어낸다", function()
        check(spell({ units = { target = { dead = true } } }).unitStates.target
            == Constants.UNITSTATE_DEAD, "죽은 3점이어야 한다");
    end);

    -- 축 둘이 함께 걸리면 교집합이다. 스칼라 시절에는 이 조합 자체를 저장할 수 없었다.
    test("반응과 생사가 같이 걸리면 한 점이 된다", function()
        local b = spell({ units = {
            target = { reaction = Constants.REACTION_HELP, dead = false },
        } });
        check(b.unitStates.target == Constants.UNITSTATE_HELP_ALIVE, "우호 x 살아있음 한 점");
    end);

    test("반응 여럿과 생사가 같이 걸려도 맞는다", function()
        local b = spell({ units = {
            target = { reaction = Constants.REACTION_HELP + Constants.REACTION_OTHER, dead = true },
        } });
        check(b.unitStates.target
            == Constants.UNITSTATE_HELP_DEAD + Constants.UNITSTATE_OTHER_DEAD,
            "우호·기타 x 죽음 두 점");
    end);

    -- "없을 때"에는 제약할 생사가 없다. 없음 점은 축 위의 점이 아니다.
    test("없을 때는 생사가 축을 안 건드린다", function()
        check(spell({ units = { target = false } }).unitStates.target
            == Constants.UNITSTATE_NONE, "없음 한 점");
    end);

    -- **옛 스칼라는 여기서 끝난다.** 아래를 지나간 뒤로는 축별 표 하나만 존재해야 한다.
    -- 방출·메뉴·이슈 검사가 저마다 타입 검사를 하게 두면, 잊은 한 곳이 불리언을 색인한다 -
    -- 실제로 그렇게 터졌다(`/debtest`의 CheckedUnits, 2026-08-12). 그때 헤드리스가 못 본 이유는
    -- 하네스가 `UpdateBindings.lua`를 안 읽어서였는데, **지금은 읽는다**(2026-08-21,
    -- `.zzz/resolved.md` 10+31번). 같은 종류가 다시 나면 이 층에서 잡힌다.
    test("옛 스칼라는 바인딩에서 축별 표로 올라온다", function()
        local b = spell({ unit = "focus", units = {
            target = true, mouseover = "help", tank = "harm", healer = false, ["@"] = true,
        } });
        check(type(b.conditions.units.target) == "table" and b.conditions.units.target.reaction == nil,
            "존재");
        check(b.conditions.units.mouseover.reaction == Constants.REACTION_HELP, "우호");
        check(b.conditions.units.tank.reaction == Constants.REACTION_HARM, "적대");
        check(b.conditions.units.healer == false, "부재는 그대로여야 한다");
        check(type(b.conditions.units["@"]) == "table", "\"@\"도 같이 올라와야 한다");
    end);

    -- 마이그레이션이 아직 안 돈 데이터(가져오기 도중, 손으로 고친 프로필)도 지나간다.
    test("옛 스칼라도 여전히 읽힌다", function()
        check(spell({ units = { target = "help" } }).unitStates.target
            == Constants.UNITSTATE_HELP, "스칼라 경로가 끊김");
    end);

    ---------------------------------------------------------------------------
    -- hover 조건도 같은 축을 탄다
    --
    -- 가리킨 프레임의 유닛은 `"unitframe"`이라는 이름의 유닛일 뿐이다. 따로 두면 solver가
    -- hover 조건과 같은 유닛의 조건이 서로 모순인 것을 못 본다.
    ---------------------------------------------------------------------------

    test("hover만 켜면 호버 유닛이 존재로 좁혀진다", function()
        check(spell({ hover = true }).unitStates["unitframe"] == Constants.UNITSTATE_EXISTS,
            "존재로 안 좁혀짐");
    end);

    test("hover 반응이 호버 유닛 축을 좁힌다", function()
        check(spell({ hover = true, reactions = Constants.REACTION_HELP }).unitStates["unitframe"]
            == Constants.UNITSTATE_HELP, "반응이 축에 안 실림");
    end);

    test("hover가 false면 호버 유닛이 부재로 좁혀진다", function()
        check(spell({ hover = false }).unitStates["unitframe"] == Constants.UNITSTATE_NONE,
            "부재로 안 좁혀짐");
    end);

    -- 마우스 클릭은 커서가 이미 있는 자리에서 발동한다. 유닛 프레임 위였다면 프레임이
    -- 그 클릭을 먹으므로, 이 경로로 오는 것은 "호버 중이 아님"뿐이다.
    test("마우스 버튼 키는 호버 유닛이 부재로 좁혀진다", function()
        check(spell({ key = "BUTTON3" }).unitStates["unitframe"] == Constants.UNITSTATE_NONE,
            "마우스 버튼이 호버 축을 안 좁힘");
    end);

    ---------------------------------------------------------------------------
    -- 나머지 갈래
    ---------------------------------------------------------------------------

    -- 펫 배틀 중에는 특수바가 뜨지 않는다. 둘을 같이 요구하면 남는 상태가 없다.
    test("펫 배틀 조건이 있으면 특수바 조건이 사라진다", function()
        check(spell({ petbattle = true, specialbar = true }).specialbar == nil, "특수바가 남음");
    end);

    -- 전체 비트를 넘는 값은 정규 전체값으로 자른다. 손으로 고친 프로필이 들어오면
    -- 같은 조건이 두 숫자로 존재하게 되고, solver가 그걸 다른 상자로 본다.
    test("범위를 넘는 마스크는 정규 전체값으로 잘린다", function()
        local b = spell({
            groups = Constants.GROUP_ALL * 2 + 1,
            forms = Constants.FORM_ALL * 2 + 1,
            bonusbars = Constants.BONUSBAR_ALL * 2 + 1,
        });
        check(b.conditions.groups == Constants.GROUP_ALL, "groups가 안 잘림");
        check(b.conditions.forms == Constants.FORM_ALL, "forms가 안 잘림");
        check(b.conditions.bonusbars == Constants.BONUSBAR_ALL, "bonusbars가 안 잘림");
    end);

    -- 바인딩은 액션에서 다시 만들어질 뿐 되돌아 쓰이지 않는다. 이게 깨지면 정규화가
    -- **사용자가 입력한 값을 지우는** 것이 된다 - 화면에서 조건이 사라진다.
    test("정규화가 액션을 건드리지 않는다", function()
        local action = {
            type = Constants.MACROTEXT, value = "/say hi",
            unit = "focus",
            reactions = Constants.REACTION_HELP,
            units = { ["@"] = true, target = "help" },
        };
        normalize(action, true);
        check(action.unit == "focus", "액션의 대상이 지워짐");
        check(action.reactions == Constants.REACTION_HELP, "액션의 reactions가 지워짐");
        check(action.units["@"] == true, "액션의 \"@\"가 지워짐");
    end);

    --- **This one classification answers for three readers now**, so it is pinned over its whole
    --- domain rather than through whichever caller happens to be under test.
    ---
    --- It decides what a binding means, what the tooltip says, and -- since the second copy in
    --- `DropDownMenus.lua`'s `UnitConditionMode` was taken out -- which radio the menu shows. That
    --- copy is why this exists: two readings of "is this [when there is one] or [when there is
    --- not]" could part, and the symptom would be a screen that disagrees with the key, which is
    --- the hardest kind to notice. The menu asks `off` for itself before coming here; nothing else
    --- is left over there.
    local function mode(stored)
        local answer = DebindPrivate.UnitConditionForBinding(stored);
        if (answer == nil) then
            return "none";
        elseif (answer == false) then
            return "absent";
        end
        return "exists";
    end

    test("유닛 조건 읽기 - 정의역 전체", function()
        check(mode(nil) == "none", "조건 없음이 없음으로 안 읽힘");
        check(mode(true) == "exists", "true가 있을 때로 안 읽힘");
        check(mode(false) == "absent", "false가 없을 때로 안 읽힘");
        check(mode("help") == "exists", "help가 있을 때로 안 읽힘");
        check(mode("harm") == "exists", "harm이 있을 때로 안 읽힘");
        check(mode({}) == "exists", "빈 표가 있을 때로 안 읽힘");
        check(mode({ reaction = Constants.REACTION_HELP }) == "exists", "반응 표가 있을 때로 안 읽힘");
        check(mode({ dead = true }) == "exists", "생사 표가 있을 때로 안 읽힘");
        check(mode({ exists = false }) == "absent", "exists=false가 없을 때로 안 읽힘");
        check(mode({ disabled = true }) == "none", "꺼진 축이 없음으로 안 읽힘");
        -- `off`가 먼저다. 껐다가 되돌릴 때 골라둔 값이 그대로 있어야 하므로 둘이 같이 선다.
        check(mode({ disabled = true, exists = false }) == "none", "꺼진 축보다 exists가 먼저 읽힘");
    end);

    --- **모르는 값을 떨어뜨리면 그 바인딩이 걸어둔 것보다 넓어진다.** 옛 버전이 쓴 스칼라를
    --- 우리가 모를 수 있고, 조건이 조용히 사라진 바인딩은 남의 키를 가져간다.
    test("유닛 조건 읽기 - 모르는 스칼라는 좁은 쪽으로", function()
        check(mode("mostly") == "absent", "모르는 문자열이 없을 때로 안 떨어짐");
        check(mode(7) == "absent", "모르는 숫자가 없을 때로 안 떨어짐");
    end);

    --- **A value this build cannot read is not put on an axis, because reading it there is not
    --- narrower but elsewhere.**
    ---
    --- The absent point is smaller than "there" but not inside it. Read as the absent point, the
    --- binding **covers a real [when there is none] binding whole** and the solver deletes it. The
    --- reader's condition disappears with no issue shown: the mask is `UNITSTATE_NONE`, not 0, so
    --- the binding is not `dead` either.
    ---
    --- `Solver.lua`'s header gives the answer: a condition that cannot be placed on an axis is not
    --- ignored, **it makes the binding opaque and takes it out of both roles.** It neither covers
    --- nor is covered.
    ---
    --- **The way in is an import.** `Import.lua` checks only that `units` is a table and copies what
    --- is inside it with `CopyTable`, so a value a newer version wrote arrives here.
    local function opaqueFor(value)
        local b = normalize(nest({
            type = Constants.SPELL, value = 585, key = "T",
            units = { target = value },
        }), true);
        return b.unitStatesOpaque and true or false;
    end

    test("모르는 유닛 조건 값은 바인딩을 두 역할에서 뺀다", function()
        check(opaqueFor("mostly"), "모르는 문자열이 축에 올라갔다");
        check(opaqueFor(7), "모르는 숫자가 축에 올라갔다");
    end);

    --- 아는 값 전부가 그대로여야 한다. 이 쪽이 안 서면 위 검사는 **모든 유닛 조건을 판정에서
    --- 빼버린 것**과 구별이 안 된다.
    test("아는 유닛 조건 값은 그대로 축에 오른다", function()
        check(not opaqueFor(true), "true가 빠졌다");
        check(not opaqueFor(false), "false가 빠졌다");
        check(not opaqueFor("help"), "help가 빠졌다");
        check(not opaqueFor("harm"), "harm이 빠졌다");
        check(not opaqueFor({}), "빈 표가 빠졌다");
        check(not opaqueFor({ exists = false }), "exists=false가 빠졌다");
        check(not opaqueFor({ reaction = Constants.REACTION_HELP }), "반응 표가 빠졌다");
    end);

    ---------------------------------------------------------------------------
    -- 액션 하나가 내는 바인딩 목록. `[1]`이 원본이고 그 뒤가 파생이다
    -- (`devdocs/splitting-an-action-into-bindings.md`).
    ---------------------------------------------------------------------------

    --- 쌍둥이를 세우는 것은 이제 액션의 Casting 값이고, 값을 안 적은 액션은 설정 탭의 모드를
    --- 따라 쌍둥이를 받는다(`devdocs/which-action-a-key-runs.md` §6). 이 아래 대부분이 그 쌍둥이를
    --- 안 재므로 `listFor`는 Skip this action으로 액션을 세우고, 쌍둥이를 재는 자리만 켠다.
    local hoverCastOn = false;

    local function listFor(fields)
        local action = { type = Constants.SPELL, value = 100, key = "F" };
        for k, v in pairs(fields or {}) do
            action[k] = v;
        end
        nest(action);
        if (not hoverCastOn) then
            require("casting").skipHover(action);
        end
        return DebindPrivate.GetBindingsForAction(action), action;
    end

    --- 쌍둥이를 세우는 것은 계정 스위치다. 프로필이 서야 `Options`를 읽을 수 있고, 스위치는
    --- 재는 동안만 켠다 - 켜 둔 채로 두면 바로 위의 "옵션 없는 액션" 테스트가 쌍둥이를 받는다.
    _G.DebindVars = {
        dbver = Constants.DB_VERSION,
        shared = { GENERAL = {}, classes = { [Constants.PLAYER_CLASS] = {} } },
        characters = {},
        migrated = {},
        switches = {},
    };
    DebindPrivate.InitDB();

    local function withHoverCast(fn)
        hoverCastOn = true;
        local ok, err = pcall(fn);
        hoverCastOn = false;
        if (not ok) then error(err, 0); end
    end

    local castmod = require("castmod");

    test("옵션 없는 액션의 목록은 원본 하나다", function()
        local list, action = listFor();
        check(#castmod.without(Constants, list) == 1, "길이 " .. #castmod.without(Constants, list));
        check(list[1] == normalize(action), "[1]이 원본 표가 아니다");
    end);

    ---------------------------------------------------------------------------
    -- 주시 대상 시전과 자기 자신 시전의 쌍둥이
    -- (`devdocs/implementing-focus-and-self-cast.md` §3-4)
    ---------------------------------------------------------------------------

    --- 쌍둥이 하나를 조합키 값으로 찾는다. 없으면 nil.
    local function twinFor(list, castModifier)
        for i = 2, #list do
            if (list[i].castModifier == castModifier) then
                return list[i];
            end
        end
    end

    --- **A held key moves an action with no target and never a unit the reader picked** (2026-09-15,
    --- owner). A modifier carried over from the key pressed just before reads as held, so moving a
    --- picked unit on it sends the action somewhere nobody chose. Both twins stand either way, which
    --- keeps the action's place in the tier a held key is decided in.
    test("대상이 없으면 쌍둥이가 player와 focus로, 고른 대상이 있으면 그 대상으로 나간다", function()
        local list = listFor({});
        check(#list == 3, "대상 없음: 길이 " .. #list);
        check(list[1].castModifier == Constants.CASTMOD_NONE,
            "원본의 조합키 칸: " .. tostring(list[1].castModifier));
        -- 뒤에서부터 채우므로 [3]이 키에서 제일 앞에 서는 self다.
        check(list[3].castModifier == Constants.CASTMOD_SELF and list[3].unit == "player",
            "[3]: " .. tostring(list[3].castModifier) .. " " .. tostring(list[3].unit));
        check(list[2].castModifier == Constants.CASTMOD_FOCUS and list[2].unit == "focus",
            "[2]: " .. tostring(list[2].castModifier) .. " " .. tostring(list[2].unit));

        for _, unit in ipairs({ "target", "focus", "player", "tank", "healer", "custom1", "unitframe", "mouseover" }) do
            list = listFor({ unit = unit });
            check(#list == 3, unit .. ": 길이 " .. #list);
            for _, castModifier in ipairs({ Constants.CASTMOD_SELF, Constants.CASTMOD_FOCUS }) do
                local twin = twinFor(list, castModifier);
                check(twin and twin.unit == unit,
                    unit .. ": " .. castModifier .. " 쌍둥이 unit: " .. tostring(twin and twin.unit));
            end
        end
    end);

    --- **`@` goes with each twin to the unit that twin aims at** (§3-6). With no target the original
    --- asks `target` and the twins ask `player` and `focus`; on a picked unit all three ask that unit.
    test("@ 조건이 쌍둥이가 겨누는 유닛 칸에 선다", function()
        local list = listFor({ units = { ["@"] = "help" } });
        local help = list[1].unitStates and list[1].unitStates.target;
        check(help, "원본에 target 칸이 없다");
        for _, case in ipairs({ { Constants.CASTMOD_SELF, "player" }, { Constants.CASTMOD_FOCUS, "focus" } }) do
            local twin = twinFor(list, case[1]);
            check(twin, case[2] .. " 쌍둥이가 없다");
            check(twin.unitStates[case[2]] == help,
                case[2] .. " 칸: " .. tostring(twin.unitStates[case[2]]));
            check(twin.unitStates.target == nil, case[2] .. " 쌍둥이가 target 조건을 들고 있다");
        end

        list = listFor({ unit = "target", units = { ["@"] = "help" } });
        for _, castModifier in ipairs({ Constants.CASTMOD_SELF, Constants.CASTMOD_FOCUS }) do
            local twin = twinFor(list, castModifier);
            check(twin.unitStates.target == help,
                castModifier .. " 쌍둥이의 target 칸: " .. tostring(twin.unitStates.target));
            check(twin.unitStates.player == nil and twin.unitStates.focus == nil,
                castModifier .. " 쌍둥이가 고른 대상 말고 다른 칸에 @를 세웠다");
        end
    end);

    --- 대상이 이미 `player`나 `focus`여도 만든다. 원본은 [없음]에만 서므로 조합키를 누른 누름을
    --- 받을 레코드가 쌍둥이뿐이다 (§3-4, 2026-09-13 소유자).
    test("대상이 focus나 player여도 쌍둥이를 낸다", function()
        for _, unit in ipairs({ "focus", "player" }) do
            local list = listFor({ unit = unit });
            check(twinFor(list, Constants.CASTMOD_SELF) and twinFor(list, Constants.CASTMOD_FOCUS),
                "대상 " .. unit .. "에 쌍둥이가 빠졌다");
        end
    end);

    --- **`none` is aimed like an action with no target, and only the cast asks** (2026-09-15, owner).
    --- It settles nothing before the press, so a held key moves what the press aims at and what `@` is
    --- asked of, and whichever binding wins goes out as `none`.
    test("대상 none은 대상 없는 액션처럼 겨누고 시전만 none으로 나간다", function()
        local help = listFor({ unit = "target", units = { ["@"] = "help" } })[1].unitStates.target;
        local list = listFor({ unit = "none", units = { ["@"] = "help" } });
        check(#list == 3, "길이 " .. #list);
        local original = list[1];
        check(original.castModifier == Constants.CASTMOD_NONE, "원본의 조합키 칸: " .. tostring(original.castModifier));
        check(original.unit == nil, "원본 unit: " .. tostring(original.unit));
        check(original.unitStates and original.unitStates.target == help,
            "원본의 target 칸: " .. tostring(original.unitStates and original.unitStates.target));
        check(DebindPrivate.CastUnitOf(original) == "none",
            "원본이 나가는 곳: " .. tostring(DebindPrivate.CastUnitOf(original)));
        for _, case in ipairs({ { Constants.CASTMOD_SELF, "player" }, { Constants.CASTMOD_FOCUS, "focus" } }) do
            local twin = twinFor(list, case[1]);
            check(twin and twin.unit == case[2], case[2] .. " 쌍둥이 unit: " .. tostring(twin and twin.unit));
            check(twin.unitStates and twin.unitStates[case[2]] == help,
                case[2] .. " 칸: " .. tostring(twin.unitStates and twin.unitStates[case[2]]));
            check(DebindPrivate.CastUnitOf(twin) == "none",
                case[2] .. " 쌍둥이가 나가는 곳: " .. tostring(DebindPrivate.CastUnitOf(twin)));
        end
    end);

    --- **대상을 받지 않는 타입도 쌍둥이를 내고, 쌍둥이만 유닛을 싣는다** (§3-4). 클라이언트의
    --- `UnitExists` 가드가 그 유닛을 읽어, 주시 대상이 없으면 액션 바처럼 누름이 멈춘다.
    test("대상을 못 받는 타입도 쌍둥이를 내고 쌍둥이만 유닛을 싣는다", function()
        local list = listFor({ type = Constants.MACROTEXT, value = "/cast x" });
        check(#list == 3, "길이 " .. #list);
        check(list[1].castModifier == Constants.CASTMOD_NONE and list[1].unit == nil,
            "원본: " .. tostring(list[1].castModifier) .. " " .. tostring(list[1].unit));
        check(twinFor(list, Constants.CASTMOD_SELF).unit == "player",
            "self 쌍둥이 unit: " .. tostring(twinFor(list, Constants.CASTMOD_SELF).unit));
        check(twinFor(list, Constants.CASTMOD_FOCUS).unit == "focus",
            "focus 쌍둥이 unit: " .. tostring(twinFor(list, Constants.CASTMOD_FOCUS).unit));
    end);

    --- **What decides is whether the reader picked a unit, not what `unit` holds.** A macro keeps no
    --- unit an old profile left on it, and a unit frame condition picks nothing, so both are aimed
    --- like an action with no target.
    test("고르지 않은 대상은 조합키를 따른다", function()
        for _, case in ipairs({
            { label = "매크로에 남은 focus", fields = { type = Constants.MACROTEXT, value = "/cast x", unit = "focus" } },
            { label = "개체창 조건만 걸린 액션", fields = { units = { unitframe = {} } } },
        }) do
            local list = listFor(case.fields);
            check(list[1].unit == case.unit, case.label .. ": 원본 unit이 " .. tostring(list[1].unit));
            check(twinFor(list, Constants.CASTMOD_SELF).unit == "player",
                case.label .. ": self 쌍둥이 unit: " .. tostring(twinFor(list, Constants.CASTMOD_SELF).unit));
            check(twinFor(list, Constants.CASTMOD_FOCUS).unit == "focus",
                case.label .. ": focus 쌍둥이 unit: " .. tostring(twinFor(list, Constants.CASTMOD_FOCUS).unit));
        end
    end);

    --- `[우호일 때]`가 한 유닛 칸에 선 마스크. 기댓값을 손으로 적지 않고 대상 있는 액션에서 읽는다.
    local function helpMask()
        return listFor({ unit = "target", units = { ["@"] = "help" } })[1].unitStates.target;
    end

    --- **`@`는 대상과 따로 고른다** (§3-6). 대상이 `player`인 액션의 `@`는 `player` 칸에 서고,
    --- 원본과 self 쌍둥이가 같은 칸에 같은 값을 든다.
    test("대상 player의 @는 원본과 self 쌍둥이의 player 칸에 선다", function()
        local help = helpMask();
        local list = listFor({ unit = "player", units = { ["@"] = "help" } });
        check(list[1].unitStates and list[1].unitStates.player == help,
            "원본의 player 칸: " .. tostring(list[1].unitStates and list[1].unitStates.player));
        local twin = twinFor(list, Constants.CASTMOD_SELF);
        check(twin.unitStates and twin.unitStates.player == help,
            "self 쌍둥이의 player 칸: " .. tostring(twin.unitStates and twin.unitStates.player));
    end);

    --- 대상을 안 고른 액션도 쌍둥이는 자기가 겨누는 유닛이 정해져 있으므로 `@`가 그 칸에 선다.
    test("대상 없는 액션의 쌍둥이는 @를 자기 유닛 칸에 얹는다", function()
        local help = helpMask();
        withHoverCast(function()
            local list = listFor({ units = { ["@"] = "help" } });
            for _, case in ipairs({ { Constants.CASTMOD_SELF, "player" }, { Constants.CASTMOD_FOCUS, "focus" } }) do
                local twin = twinFor(list, case[1]);
                check(twin and twin.unitStates and twin.unitStates[case[2]] == help,
                    case[2] .. " 칸: " .. tostring(twin and twin.unitStates and twin.unitStates[case[2]]));
            end
            local hoverTwin = castmod.without(Constants, list)[2];
            check(hoverTwin and hoverTwin.unit == "unitframe", "hover 쌍둥이가 없다");
            check(hoverTwin.unitStates.unitframe == help,
                "hover 칸: " .. tostring(hoverTwin.unitStates.unitframe));
        end);
    end);

    --- **대상 없는 원본은 `@`를 `target` 칸에서 검사하고 `unit`은 비워 둔다** (§3-6, 2026-09-13
    --- 소유자). 시전은 게임이 대상과 Auto Self Cast로 정하고, 조건만 게임이 겨눌 대상에게 묻는다.
    --- `""`(가리킨 유닛을 안 쓴다)도 게임이 정하는 누름이라 같다. 원본이 조건을 지켜야 조건부로
    --- 분류되어 순서와 행 표시가 맞는다.
    test("대상 없는 원본은 @를 target 칸에 지키고 unit은 비워 둔다", function()
        local help = helpMask();
        for _, case in ipairs({
            { fields = { units = { ["@"] = "help" } }, unit = nil },
        }) do
            local list = listFor(case.fields);
            local original = list[1];
            local label = "unit=" .. tostring(case.unit) .. ": ";
            check(original.unit == case.unit, label .. "원본의 unit이 " .. tostring(original.unit));
            check(original.conditions.units and original.conditions.units["@"] ~= nil,
                label .. "원본이 @를 지웠다");
            check(original.unitStates and original.unitStates.target == help,
                label .. "target 칸: " .. tostring(original.unitStates and original.unitStates.target));
            check(not original.unitStatesOpaque, label .. "원본이 판정에서 빠졌다");
            check(DebindPrivate.IsConditionalBinding(original), label .. "원본이 조건 없음으로 읽힌다");
            check(twinFor(list, Constants.CASTMOD_SELF).unitStates.player == help,
                label .. "self 쌍둥이가 @를 잃었다");
        end
    end);

    --- **개체창 조건이 걸려 있어도 원본의 `@`는 `target` 칸이다.** 조건은 대상을 안 정하므로
    --- (§5), 그 원본이 겨누는 것은 여전히 게임이 놓는 대상이다. 개체창 조건 자체는 제 유닛 칸에
    --- 그대로 서고, 둘은 다른 축이다.
    test("개체창 조건이 걸린 원본도 @를 target 칸에 얹는다", function()
        local help = helpMask();
        local original = listFor({ units = { ["@"] = "help", unitframe = {} } })[1];
        check(original.unit == nil, "원본의 unit: " .. tostring(original.unit));
        check(original.unitStates and original.unitStates.target == help,
            "target 칸: " .. tostring(original.unitStates and original.unitStates.target));
        check(original.unitStates.unitframe == Constants.UNITSTATE_EXISTS,
            "개체창 칸: " .. tostring(original.unitStates.unitframe));
    end);

    test("Hover Cast가 켜지면 hover 쌍둥이가 따라온다", function()
        withHoverCast(function()
            local list, action = listFor({ units = { ["@"] = "help" } });
            list = castmod.without(Constants, list);
            check(#list == 2, "길이 " .. #list);
            check(list[1] == normalize(action), "[1]이 원본이 아니다");
            local original, twin = list[1], list[2];
            check(original.conditions.units == nil or original.conditions.units.unitframe == nil,
                "원본에 개체창 조건이 생겼다");
            check(original.unit == nil, "원본 unit: " .. tostring(original.unit));
            check(twin.unit == "unitframe", "쌍둥이 unit: " .. tostring(twin.unit));
            check(twin.conditions.units.unitframe ~= nil, "쌍둥이에 개체창 조건이 없다");
            check(twin.type == original.type and twin.value == original.value and twin.key == original.key,
                "쌍둥이가 액션의 값을 잃었다");
            -- `"@"`는 겨누는 개체를 가리키는 포인터라, 쌍둥이에서는 hover 개체에게 묻는다.
            check(twin.unitStates and twin.unitStates.unitframe == original.unitStates.target,
                "쌍둥이의 hover 마스크가 원본의 @ 마스크와 다르다");
            check(twin.unitStates.target == nil, "쌍둥이가 target 조건을 들고 있다");
        end);
    end);

    --- **Hover Cast does not move a picked unit either** (2026-09-15, owner). The twin still stands in
    --- the pointed tier and goes out at the unit the reader picked, with `@` asked of that unit.
    test("고른 대상이 있으면 hover 쌍둥이도 그 대상으로 나간다", function()
        withHoverCast(function()
            local list = castmod.without(Constants, (listFor({ unit = "focus", units = { ["@"] = "help" } })));
            check(#list == 2, "길이 " .. #list);
            local original, twin = list[1], list[2];
            check(twin.hoverTwin and twin.unit == "focus", "쌍둥이 unit: " .. tostring(twin.unit));
            check(twin.unitStates.focus == original.unitStates.focus,
                "쌍둥이의 focus 칸: " .. tostring(twin.unitStates.focus));
        end);
    end);

    --- The pointed half of `none` being aimed like an action with no target: the hover twin asks the
    --- pointed unit and still goes out asking.
    test("대상 none의 hover 쌍둥이는 가리킨 유닛에 묻고 none으로 나간다", function()
        withHoverCast(function()
            local list = castmod.without(Constants, (listFor({ unit = "none", units = { ["@"] = "help" } })));
            check(#list == 2, "길이 " .. #list);
            local original, twin = list[1], list[2];
            check(twin.hoverTwin and twin.unit == "unitframe", "쌍둥이 unit: " .. tostring(twin.unit));
            check(twin.unitStates.unitframe == original.unitStates.target,
                "쌍둥이의 hover 칸: " .. tostring(twin.unitStates.unitframe));
            check(DebindPrivate.CastUnitOf and DebindPrivate.CastUnitOf(twin) == "none",
                "쌍둥이가 나가는 곳: " .. tostring(DebindPrivate.CastUnitOf and DebindPrivate.CastUnitOf(twin)));
        end);
    end);

    --- hover 조건으로 대상이 채워진 원본도 hover 쌍둥이를 내고, 쌍둥이는 원본처럼 `hover`로 나간다.
    test("hover 조건이 켜진 액션의 쌍둥이는 원본의 대상으로 나간다", function()
        withHoverCast(function()
            local list = castmod.without(Constants, (listFor({ units = { unitframe = {} } })));
            check(#list == 2, "길이 " .. #list);
            check(list[2].hoverTwin and list[2].unit == "unitframe", "쌍둥이 unit: " .. tostring(list[2].unit));
        end);
    end);

    --- **`unitframe`을 고른 원본의 쌍둥이는 Mouseover 모드에서도 그 유닛으로 나간다** (§5). 고른
    --- 유닛은 고정이고, `mouseover`로 바꾸면 명판까지 닿아 사용자가 고른 뜻이 달라진다. 조건은 그
    --- 모드가 가리키는 유닛에 선다.
    test("대상 unitframe의 쌍둥이는 Mouseover 모드에서도 unitframe으로 나간다", function()
        DebindPrivate.Options.hoverCastMode = "mouseover";
        local ok, err = pcall(function()
            withHoverCast(function()
                local list = castmod.without(Constants, (listFor({ unit = "unitframe" })));
                check(#list == 2, "길이 " .. #list);
                check(list[2].unit == "unitframe", "쌍둥이 unit: " .. tostring(list[2].unit));
                check(list[2].unitStates and list[2].unitStates.mouseover == Constants.UNITSTATE_EXISTS,
                    "mouseover 칸: " .. tostring(list[2].unitStates and list[2].unitStates.mouseover));
            end);
        end);
        DebindPrivate.Options.hoverCastMode = nil;
        if (not ok) then error(err, 0); end
    end);

    -- Clique가 있어도 쌍둥이는 나온다 (코드 리뷰, 2026-09-08). 블리자드 개체창은 Clique와 무관하게
    -- 우리가 등록하고, 물러난 상태의 `GetUnitFrameUnit`은 우리 행에서 먼저, 없으면 Clique의 hover
    -- 버튼에서 답하니 쌍둥이가 겨눌 개체가 있다.
    test("Clique가 있어도 쌍둥이를 낸다", function()
        local was = DebindPrivate.CliqueDetected;
        DebindPrivate.CliqueDetected = true;
        local ok, err = pcall(function()
            withHoverCast(function()
                local list = castmod.without(Constants, (listFor()));
                check(#list == 2, "길이 " .. #list);
            end);
        end);
        DebindPrivate.CliqueDetected = was;
        if (not ok) then error(err, 0); end
    end);

    --- **대상을 못 싣는 타입도 hover 쌍둥이를 내고, 그 쌍둥이도 가리킨 유닛을 싣는다** (§3,
    --- 2026-09-15 소유자). 유닛을 실어 주되 그것을 쓸 수 있는지는 그 액션의 몫이다 - 매크로
    --- 본문은 버튼의 유닛을 안 보고, 그래도 그 액션은 가리킨 누름의 층에서 제 차례를 지킨다.
    test("대상을 못 싣는 타입의 쌍둥이도 가리킨 유닛을 싣는다", function()
        withHoverCast(function()
            for _, fields in ipairs({
                { type = Constants.MACROTEXT, value = "/cast x" },
                { type = Constants.SETCUSTOM, value = 1 },
            }) do
                local list = castmod.without(Constants, (listFor(fields)));
                check(#list == 2, fields.type .. " 길이 " .. #list);
                check(list[2].hoverTwin and list[2].unit == "unitframe",
                    fields.type .. " 쌍둥이 unit: " .. tostring(list[2].unit));
                check(list[1].unit == nil,
                    fields.type .. " 원본 unit: " .. tostring(list[1].unit));
                check(list[2].unitStates and list[2].unitStates.unitframe == Constants.UNITSTATE_EXISTS,
                    fields.type .. " 쌍둥이가 hover 축에 안 섰다");
            end
        end);
    end);

    test("목록은 리빌드마다 같은 표를 다시 채운다", function()
        local action = nest({ type = Constants.SPELL, value = 100, key = "F" });
        local first = DebindPrivate.GetBindingsForAction(action);
        local a1, a2 = first[1], first[2];
        local second = DebindPrivate.GetBindingsForAction(action);
        check(second == first and second[1] == a1 and second[2] == a2, "표가 새로 만들어졌다");

        require("casting").skipHover(action);
        local third = DebindPrivate.GetBindingsForAction(action);
        check(third == first, "표가 새로 만들어졌다");
        check(#castmod.without(Constants, third) == 1, "Hover Cast를 껐는데 쌍둥이가 남았다");
    end);

    return T;
end
