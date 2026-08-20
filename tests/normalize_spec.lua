-- `GetBindingInfoForAction`의 정규화 테스트. 와우 클라이언트 불필요.
--
-- 이 함수는 액션(프로필이 저장하는 것)에서 바인딩(solver와 `UpdateBindings`가 읽는 것)을
-- 만들면서, **뜻이 없어진 조건들을 지운다.** 그 판정이 여기 다 모여 있다.
--
-- 왜 테스트가 필요한가: 지우는 순서가 곧 의미다. 검사 하나가 그것을 무효로 만드는 코드보다
-- 위에 있으면 조용히 통과하고, 잘못 지우면 조건이 사라진 채 바인딩이 나간다. 어느 쪽도
-- 화면에 아무 표시가 없다.
--
-- `"@"`가 특히 그렇다. 유닛 이름이 아니라 **그 액션이 겨누는 대상을 가리키는 포인터**라,
-- 대상이 사라지면 같이 사라져야 한다. 대상을 지우는 자리가 셋이고 채워 넣는 자리가 하나라
-- 순서가 얽힌다.

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
    local function spell(fields)
        local action = { type = Constants.SPELL, value = 100 };
        for k, v in pairs(fields or {}) do
            action[k] = v;
        end
        return normalize(action, true);
    end

    ---------------------------------------------------------------------------
    -- 호버 조건은 `checkedUnits["hover"]`에 산다
    --
    -- 저장에는 그 키 하나뿐이고, `hover`/`reactions`는 거기서 파생된 값이다
    -- (`Misc.DeriveHoverFields`). 아래 다른 절들이 옛 이름으로 액션을 만드는 것은 **그쪽이
    -- 들어올림 경로를 지나기 때문**이고, 여기가 그 두 모양이 같은 답을 낸다는 것을 잠근다.
    ---------------------------------------------------------------------------

    test("저장된 호버 조건이 hover/reactions로 파생된다", function()
        local b = spell({ checkedUnits = { hover = { reaction = Constants.REACTION_HELP } } });
        check(b.hover == true, "hover가 안 파생됨");
        check(b.reactions == Constants.REACTION_HELP, "reactions가 안 파생됨");
        check(b.unitStates["hover"] == Constants.UNITSTATE_HELP, "축에 안 실림");
    end);

    test("저장된 호버 조건이 false면 부재로 파생된다", function()
        local b = spell({ checkedUnits = { hover = false } });
        check(b.hover == false, "false가 안 파생됨 - nil과 다른 답이다");
        check(b.unitStates["hover"] == Constants.UNITSTATE_NONE, "부재로 안 좁혀짐");
    end);

    test("반응을 전부 고른 저장값은 제약이 없는 것과 같다", function()
        local b = spell({ checkedUnits = { hover = { reaction = Constants.REACTION_ALL } } });
        check(b.reactions == nil, "전체 비트가 안 접힘");
        check(b.unitStates["hover"] == Constants.UNITSTATE_EXISTS, "축이 좁아짐");
    end);

    test("호버 유닛에도 생사가 걸린다", function()
        local b = spell({ checkedUnits = { hover = { dead = true } } });
        check(b.unitStates["hover"] == Constants.UNITSTATE_DEAD, "생사가 축에 안 실림");
    end);

    ---------------------------------------------------------------------------
    -- 끈 조건은 **기억하되 판정에서 뺀다**
    --
    -- 라디오를 [사용 안 함]이나 [없을 때]로 옮겼다고 골라둔 반응·생사를 지우면, 되돌렸을 때
    -- 처음부터 다시 골라야 한다. 옵션을 끄는 것이지 지우는 것이 아니다 - `frameTypes`가
    -- hover를 껐다 켜도 남아 있는 것과 같은 규칙이고, 무시하는 것은 코드가 한다.
    ---------------------------------------------------------------------------

    test("꺼진 조건은 바인딩에 안 나온다", function()
        local b = spell({ checkedUnits = {
            target = { off = true, reaction = Constants.REACTION_HELP, dead = true },
        } });
        check(b.checkedUnits == nil, "꺼진 조건이 바인딩까지 갔다");
        check(b.unitStates == nil or b.unitStates.target == nil, "축을 좁혔다");
    end);

    test("\"없을 때\"는 기억한 축을 안 읽는다", function()
        local b = spell({ checkedUnits = {
            target = { exists = false, reaction = Constants.REACTION_HELP, dead = true },
        } });
        check(b.unitStates.target == Constants.UNITSTATE_NONE,
            "기억만 해야 할 축이 판정에 실렸다");
    end);

    test("표시가 없는 표는 \"있을 때\"다", function()
        -- 손으로 쓴 값과 아직 안 옮겨진 프로필이 이 모양으로 온다. 조건 없음으로 읽으면
        -- 걸어둔 것보다 넓어져 남의 키를 가져간다.
        check(spell({ checkedUnits = { target = {} } }).unitStates.target
            == Constants.UNITSTATE_EXISTS, "빈 표가 조건 없음으로 읽힘");
    end);

    test("꺼진 조건만 있으면 조건부 액션이 아니다", function()
        local action = { type = Constants.SPELL, value = 100,
            checkedUnits = { target = { off = true, reaction = Constants.REACTION_HELP } } };
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
        check(b.unitStates["hover"] == Constants.UNITSTATE_HELP, "새 모양과 답이 다름");
        check(action.hover == true, "액션이 고쳐졌다 - 들어올림은 사본에만 일어나야 한다");
        check(action.checkedUnits == nil, "액션에 checkedUnits가 생겼다");
    end);

    -- 두 메뉴가 다 살아 있던 시절의 프로필이면 같은 유닛에 조건이 둘 있을 수 있다. 덮으면
    -- 걸어둔 것보다 넓어지므로 교집합하고, 안 겹치면 어떤 유닛도 못 드는 조건이 된다.
    test("옛 hover가 같은 유닛의 조건과 교집합된다", function()
        local b = normalize({ type = Constants.SPELL, value = 100,
            hover = true, reactions = Constants.REACTION_HELP,
            checkedUnits = { hover = { reaction = Constants.REACTION_HARM } } }, true);
        check(b.unitStates["hover"] == 0, "안 겹치는 두 조건이 0이 안 됨");
    end);

    test("옛 hover=false가 존재 조건과 만나면 0이 된다", function()
        local b = normalize({ type = Constants.SPELL, value = 100,
            hover = false, checkedUnits = { hover = {} } }, true);
        check(b.unitStates["hover"] == 0, "부재와 존재가 0이 안 됨");
    end);

    ---------------------------------------------------------------------------
    -- hover가 꺼져 있으면 hover에 딸린 것들은 뜻이 없다
    --
    -- 이 셋은 "마우스를 올린 프레임"에 대한 이야기라, 그 조건 자체가 없으면 말할 대상이
    -- 없다. 남겨두면 solver가 없는 축을 좁히고, 사용자는 끄고 나서도 예전 값에 걸린다.
    ---------------------------------------------------------------------------

    test("hover가 없으면 reactions/frameTypes/ignoreHoverUnit이 사라진다", function()
        local b = spell({
            reactions = Constants.REACTION_HELP,
            frameTypes = Constants.FRAMETYPE_PLAYER,
            ignoreHoverUnit = true,
        });
        check(b.reactions == nil, "reactions가 남음");
        check(b.frameTypes == nil, "frameTypes가 남음");
        check(b.ignoreHoverUnit == nil, "ignoreHoverUnit이 남음");
    end);

    -- `false`는 "호버 중이 **아닐** 때"라는 진짜 조건이다. 그래도 반응·프레임종류는
    -- 여전히 말할 대상이 없다 - 올라간 프레임이 없으니까.
    test("hover가 false여도 딸린 것들은 사라진다", function()
        local b = spell({
            hover = false,
            reactions = Constants.REACTION_HELP,
            frameTypes = Constants.FRAMETYPE_PLAYER,
        });
        check(b.hover == false, "hover 조건 자체는 남아야 한다");
        check(b.reactions == nil, "reactions가 남음");
        check(b.frameTypes == nil, "frameTypes가 남음");
    end);

    ---------------------------------------------------------------------------
    -- 전부 고른 마스크는 조건이 아니다
    --
    -- 같은 조건이 두 형태(nil과 전체비트)로 저장되면 solver가 서로 다른 상자로 본다.
    ---------------------------------------------------------------------------

    test("hover 반응을 전부 고르면 nil로 접힌다", function()
        local b = spell({ hover = true, reactions = Constants.REACTION_ALL });
        check(b.reactions == nil, "전체 비트가 안 접힘");
    end);

    test("hover 프레임종류를 전부 고르면 nil로 접힌다", function()
        local b = spell({ hover = true, frameTypes = Constants.FRAMETYPE_ALL });
        check(b.frameTypes == nil, "전체 비트가 안 접힘");
    end);

    test("일부만 고른 마스크는 그대로 남는다", function()
        local b = spell({
            hover = true,
            reactions = Constants.REACTION_HELP,
            frameTypes = Constants.FRAMETYPE_PLAYER,
        });
        check(b.reactions == Constants.REACTION_HELP, "reactions가 바뀜");
        check(b.frameTypes == Constants.FRAMETYPE_PLAYER, "frameTypes가 바뀜");
    end);

    ---------------------------------------------------------------------------
    -- 주문이 아니면 "배웠는가"를 물을 수 없다
    ---------------------------------------------------------------------------

    test("주문이 아니면 known이 사라진다", function()
        check(normalize({ type = Constants.ITEM, value = 1, known = true }, true).known == nil,
            "known이 남음");
    end);

    test("주문이면 known이 남는다", function()
        check(spell({ known = true }).known == true, "known이 사라짐");
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
        check(normalize({ type = Constants.MACROTEXT, value = "/cast Foo", known = false }, true).known == nil,
            "known=false가 남음");
    end);

    ---------------------------------------------------------------------------
    -- 대상 유닛 자체의 정규화
    --
    -- `binding.unit`은 "사용자가 고른 대상"이 아니라 **매크로가 실제로 겨눌 유닛**이다.
    -- 못 갖는 타입이면 지우고, hover 액션이 제 대상이 없으면 채워 넣는다.
    ---------------------------------------------------------------------------

    test("대상을 못 갖는 타입이면 대상이 사라진다", function()
        local b = normalize({ type = Constants.MACROTEXT, value = "/say hi", unit = "focus" }, true);
        check(b.unit == nil, "대상이 남음");
    end);

    test("대상을 안 받는 펫 명령이면 대상이 사라진다", function()
        local b = normalize({ type = Constants.PETACTION, value = "PET_FOLLOW", unit = "focus" }, true);
        check(b.unit == nil, "대상이 남음");
    end);

    test("대상을 받는 펫 명령은 대상을 지킨다", function()
        local b = normalize({ type = Constants.PETACTION, value = "PET_ATTACK", unit = "focus" }, true);
        check(b.unit == "focus", "대상이 사라짐");
    end);

    test("hover 액션이 제 대상이 없으면 호버한 유닛을 겨눈다", function()
        check(spell({ hover = true }).unit == "hover", "채워넣기가 안 일어남");
    end);

    -- `ignoreHoverUnit`은 "올라간 프레임은 조건으로만 쓰고 대상으로는 안 쓴다"는 뜻이다.
    -- 그래서 채워 넣을 유닛이 없고, 빈 문자열이 그 자리를 표시한다.
    test("ignoreHoverUnit이면 겨눌 유닛이 빈 문자열이 된다", function()
        check(spell({ hover = true, ignoreHoverUnit = true }).unit == "", "빈 문자열이 아님");
    end);

    test("제 대상이 있으면 hover 채워넣기가 일어나지 않는다", function()
        check(spell({ hover = true, unit = "focus" }).unit == "focus", "대상이 덮어써짐");
    end);

    ---------------------------------------------------------------------------
    -- 대상이 없으면 `"@"`도 없다
    --
    -- 아래 넷은 "가리킬 것이 처음부터 없다"에 해당한다. `"none"`은 대상 없음이 아니라
    -- **대상 지정 모드**(사용자가 찍는다)라 바인딩을 걸 시점에 검사할 유닛이 없고,
    -- `"player"`는 자기 자신이라 존재도 반응도 언제나 참이라 아무 말도 안 한다.
    ---------------------------------------------------------------------------

    test("대상을 안 골랐으면 \"@\"가 사라진다", function()
        check(spell({ checkedUnits = { ["@"] = true } }).checkedUnits == nil, "\"@\"가 남음");
    end);

    test("대상이 \"none\"이면 \"@\"가 사라진다", function()
        check(spell({ unit = "none", checkedUnits = { ["@"] = true } }).checkedUnits == nil,
            "\"@\"가 남음");
    end);

    test("대상이 \"player\"면 \"@\"가 사라진다", function()
        check(spell({ unit = "player", checkedUnits = { ["@"] = true } }).checkedUnits == nil,
            "\"@\"가 남음");
    end);

    -- 저장된 대상이 빈 문자열인 프로필. 대상 메뉴는 그런 값을 못 쓰지만 공유 프로필로는
    -- 들어온다.
    test("대상이 빈 문자열이면 \"@\"가 사라진다", function()
        check(spell({ unit = "", checkedUnits = { ["@"] = true } }).checkedUnits == nil,
            "\"@\"가 남음");
    end);

    -- truthy 검사였다면 `false`("없을 때")를 못 잡고 걸 축이 없는 조건이 `UpdateBindings`
    -- 까지 갔다. UI로는 못 만들지만 공유 프로필로는 들어오는 값이다.
    test("\"@\"가 false여도 사라진다", function()
        check(spell({ unit = "player", checkedUnits = { ["@"] = false } }).checkedUnits == nil,
            "falsy라 검사에서 빠짐");
    end);

    test("대상이 멀쩡하면 \"@\"는 남는다", function()
        local b = spell({ unit = "focus", checkedUnits = { ["@"] = true } });
        check(type(b.checkedUnits["@"]) == "table", "멀쩡한 조건이 지워짐");
        check(b.unitStates.focus == Constants.UNITSTATE_EXISTS, "대상 유닛 축에 안 얹힘");
    end);

    ---------------------------------------------------------------------------
    -- 대상을 **나중에** 뺏겼을 때도 `"@"`가 사라진다
    --
    -- 위 검사는 대상 메뉴가 쓴 값을 본다. 그런데 그 뒤에서 `binding.unit`을 도로 지우는
    -- 자리가 둘 있다(대상을 못 갖는 타입, 대상을 안 받는 펫 명령). 거기서 안 치우면 갈 곳
    -- 없는 `"@"`가 그대로 흘러간다.
    --
    -- 지금 UI로는 못 만드는 상태다. 옛 프로필과 공유 프로필로 들어온다.
    ---------------------------------------------------------------------------

    test("타입 때문에 대상을 잃으면 \"@\"도 같이 사라진다", function()
        local b = normalize({
            type = Constants.MACROTEXT, value = "/say hi",
            unit = "focus",
            checkedUnits = { ["@"] = true },
        }, true);
        check(b.unit == nil, "대상이 안 지워짐 - 전제가 깨졌다");
        check(b.checkedUnits == nil, "갈 곳 없는 \"@\"가 남음");
        check(not b.unitStatesOpaque, "바인딩이 통째로 판정에서 빠짐");
    end);

    test("펫 명령 때문에 대상을 잃어도 \"@\"가 사라진다", function()
        local b = normalize({
            type = Constants.PETACTION, value = "PET_FOLLOW",
            unit = "focus",
            checkedUnits = { ["@"] = true },
        }, true);
        check(b.unit == nil, "대상이 안 지워짐 - 전제가 깨졌다");
        check(b.checkedUnits == nil, "갈 곳 없는 \"@\"가 남음");
        check(not b.unitStatesOpaque, "바인딩이 통째로 판정에서 빠짐");
    end);

    -- 대상이 비면 hover 채워넣기가 `"hover"`를 넣는다. 그 전에 안 치우면 남은 `"@"`가
    -- 그것을 가리켜서, **focus를 겨누고 켠 조건이 호버한 유닛 조건이 된다.** 판정에서
    -- 빠지는 것과 달리 이건 멀쩡히 동작하는 얼굴로 다른 일을 하므로 아무 데도 안 걸린다.
    test("hover 채워넣기가 대상 잃은 \"@\"를 물려받지 않는다", function()
        local b = normalize({
            type = Constants.MACROTEXT, value = "/say hi",
            unit = "focus", hover = true,
            checkedUnits = { ["@"] = "help" },
        }, true);
        check(b.unit == "hover", "hover 채워넣기가 안 일어남 - 전제가 깨졌다");
        check(b.unitStates["hover"] == Constants.UNITSTATE_EXISTS,
            "\"@\"가 호버 유닛 조건으로 둔갑함");
    end);

    ---------------------------------------------------------------------------
    -- `"@"`와 명시 유닛 조건이 같은 유닛에서 만날 때
    --
    -- `"@"`가 focus를 가리키는데 focus에 명시 조건도 걸려 있으면 둘은 한 축에서 만난다.
    -- 같은 말이면 한쪽으로 접고, 어긋나면 **둘 다 남겨서** 마스크가 0이 되게 둔다 -
    -- 조용히 한쪽을 이기게 하면 사용자가 건 조건이 소리 없이 사라진다.
    ---------------------------------------------------------------------------

    local function atAnd(atValue, unitValue)
        return spell({ unit = "focus", checkedUnits = { ["@"] = atValue, focus = unitValue } });
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
        check(b.checkedUnits["@"] ~= nil, "조용히 한쪽이 지워짐");
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
        check(spell({ checkedUnits = { target = true } }).unitStates.target
            == Constants.UNITSTATE_EXISTS, "존재");
        check(spell({ checkedUnits = { target = false } }).unitStates.target
            == Constants.UNITSTATE_NONE, "부재");
        check(spell({ checkedUnits = { target = "help" } }).unitStates.target
            == Constants.UNITSTATE_HELP, "우호");
        check(spell({ checkedUnits = { target = "harm" } }).unitStates.target
            == Constants.UNITSTATE_HARM, "적대");
    end);

    test("\"@\"는 겨누는 유닛의 축으로 펴진다", function()
        local b = spell({ unit = "focus", checkedUnits = { ["@"] = "help" } });
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
        check(spell({ checkedUnits = { target = {} } }).unitStates.target
            == Constants.UNITSTATE_EXISTS, "존재로 안 접힘");
    end);

    test("반응 필드가 유닛 축을 좁힌다", function()
        check(spell({ checkedUnits = { target = { reaction = Constants.REACTION_HELP } } })
            .unitStates.target == Constants.UNITSTATE_HELP, "우호");
        check(spell({ checkedUnits = { target = { reaction = Constants.REACTION_HARM } } })
            .unitStates.target == Constants.UNITSTATE_HARM, "적대");
        check(spell({ checkedUnits = { target = { reaction = Constants.REACTION_OTHER } } })
            .unitStates.target == Constants.UNITSTATE_OTHER, "기타");
    end);

    -- 스칼라로는 못 쓰던 것. 축별 마스크가 생긴 이유의 절반이다.
    test("반응을 여럿 고를 수 있다", function()
        local b = spell({ checkedUnits = {
            target = { reaction = Constants.REACTION_HELP + Constants.REACTION_OTHER },
        } });
        check(b.unitStates.target == Constants.UNITSTATE_HELP + Constants.UNITSTATE_OTHER,
            "합집합이 안 실림");
    end);

    -- 새 축이 오면 필드가 하나 늘 뿐이다. 모르는 필드가 섞여 있어도 지금 아는 축의 판정은
    -- 그대로여야 한다 - 옛 버전이 새 프로필을 읽는 경우가 이 모양이다.
    test("모르는 축 필드는 지금 판정을 안 바꾼다", function()
        local b = spell({ checkedUnits = {
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
        check(spell({ checkedUnits = { target = {} } }).unitStates.target
            == Constants.UNITSTATE_EXISTS, "존재 6점 전부여야 한다");
    end);

    test("살아있음이 죽은 절반을 덜어낸다", function()
        check(spell({ checkedUnits = { target = { dead = false } } }).unitStates.target
            == Constants.UNITSTATE_ALIVE, "살아있는 3점이어야 한다");
    end);

    test("죽음이 살아있는 절반을 덜어낸다", function()
        check(spell({ checkedUnits = { target = { dead = true } } }).unitStates.target
            == Constants.UNITSTATE_DEAD, "죽은 3점이어야 한다");
    end);

    -- 축 둘이 함께 걸리면 교집합이다. 스칼라 시절에는 이 조합 자체를 저장할 수 없었다.
    test("반응과 생사가 같이 걸리면 한 점이 된다", function()
        local b = spell({ checkedUnits = {
            target = { reaction = Constants.REACTION_HELP, dead = false },
        } });
        check(b.unitStates.target == Constants.UNITSTATE_HELP_ALIVE, "우호 x 살아있음 한 점");
    end);

    test("반응 여럿과 생사가 같이 걸려도 맞는다", function()
        local b = spell({ checkedUnits = {
            target = { reaction = Constants.REACTION_HELP + Constants.REACTION_OTHER, dead = true },
        } });
        check(b.unitStates.target
            == Constants.UNITSTATE_HELP_DEAD + Constants.UNITSTATE_OTHER_DEAD,
            "우호·기타 x 죽음 두 점");
    end);

    -- "없을 때"에는 제약할 생사가 없다. 없음 점은 축 위의 점이 아니다.
    test("없을 때는 생사가 축을 안 건드린다", function()
        check(spell({ checkedUnits = { target = false } }).unitStates.target
            == Constants.UNITSTATE_NONE, "없음 한 점");
    end);

    -- **옛 스칼라는 여기서 끝난다.** 아래를 지나간 뒤로는 축별 표 하나만 존재해야 한다.
    -- 방출·메뉴·이슈 검사가 저마다 타입 검사를 하게 두면, 잊은 한 곳이 불리언을 색인한다 -
    -- 실제로 그렇게 터졌다(`/debtest`의 CheckedUnits, 2026-08-12). 헤드리스는 못 봤다:
    -- 하네스가 `UpdateBindings.lua`를 안 읽는다(`refactor-candidates.md` 31번).
    test("옛 스칼라는 바인딩에서 축별 표로 올라온다", function()
        local b = spell({ unit = "focus", checkedUnits = {
            target = true, mouseover = "help", tank = "harm", healer = false, ["@"] = true,
        } });
        check(type(b.checkedUnits.target) == "table" and b.checkedUnits.target.reaction == nil,
            "존재");
        check(b.checkedUnits.mouseover.reaction == Constants.REACTION_HELP, "우호");
        check(b.checkedUnits.tank.reaction == Constants.REACTION_HARM, "적대");
        check(b.checkedUnits.healer == false, "부재는 그대로여야 한다");
        check(type(b.checkedUnits["@"]) == "table", "\"@\"도 같이 올라와야 한다");
    end);

    -- 마이그레이션이 아직 안 돈 데이터(가져오기 도중, 손으로 고친 프로필)도 지나간다.
    test("옛 스칼라도 여전히 읽힌다", function()
        check(spell({ checkedUnits = { target = "help" } }).unitStates.target
            == Constants.UNITSTATE_HELP, "스칼라 경로가 끊김");
    end);

    ---------------------------------------------------------------------------
    -- hover 조건도 같은 축을 탄다
    --
    -- 마우스를 올린 프레임의 유닛은 `"hover"`라는 이름의 유닛일 뿐이다. 따로 두면 solver가
    -- hover 조건과 같은 유닛의 조건이 서로 모순인 것을 못 본다.
    ---------------------------------------------------------------------------

    test("hover만 켜면 호버 유닛이 존재로 좁혀진다", function()
        check(spell({ hover = true }).unitStates["hover"] == Constants.UNITSTATE_EXISTS,
            "존재로 안 좁혀짐");
    end);

    test("hover 반응이 호버 유닛 축을 좁힌다", function()
        check(spell({ hover = true, reactions = Constants.REACTION_HELP }).unitStates["hover"]
            == Constants.UNITSTATE_HELP, "반응이 축에 안 실림");
    end);

    test("hover가 false면 호버 유닛이 부재로 좁혀진다", function()
        check(spell({ hover = false }).unitStates["hover"] == Constants.UNITSTATE_NONE,
            "부재로 안 좁혀짐");
    end);

    -- 마우스 클릭은 커서가 이미 있는 자리에서 발동한다. 유닛 프레임 위였다면 프레임이
    -- 그 클릭을 먹으므로, 이 경로로 오는 것은 "호버 중이 아님"뿐이다.
    test("마우스 버튼 키는 호버 유닛이 부재로 좁혀진다", function()
        check(spell({ key = "BUTTON3" }).unitStates["hover"] == Constants.UNITSTATE_NONE,
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
        check(b.groups == Constants.GROUP_ALL, "groups가 안 잘림");
        check(b.forms == Constants.FORM_ALL, "forms가 안 잘림");
        check(b.bonusbars == Constants.BONUSBAR_ALL, "bonusbars가 안 잘림");
    end);

    -- 바인딩은 액션에서 다시 만들어질 뿐 되돌아 쓰이지 않는다. 이게 깨지면 정규화가
    -- **사용자가 입력한 값을 지우는** 것이 된다 - 화면에서 조건이 사라진다.
    test("정규화가 액션을 건드리지 않는다", function()
        local action = {
            type = Constants.MACROTEXT, value = "/say hi",
            unit = "focus",
            reactions = Constants.REACTION_HELP,
            checkedUnits = { ["@"] = true, target = "help" },
        };
        normalize(action, true);
        check(action.unit == "focus", "액션의 대상이 지워짐");
        check(action.reactions == Constants.REACTION_HELP, "액션의 reactions가 지워짐");
        check(action.checkedUnits["@"] == true, "액션의 \"@\"가 지워짐");
    end);

    return T;
end
