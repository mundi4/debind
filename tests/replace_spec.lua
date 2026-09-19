-- 이미 저장된 액션의 타입과 값을 바꾸는 것. `Profile.lua`의 `SetActionEntry`.
--
-- **이 파일이 지키는 것은 남는 쪽과 지워지는 쪽의 경계다**
-- (`changing-what-an-action-does.md`). 키와 키 그룹 안의 자리와 조건은 그대로 있어야
-- 하고, `known`과 못 가지는 타입의 `unit`은 없어져야 한다. 두 쪽 다 틀려도 화면에는 안 나온다 -
-- 남겨진 조건은 행에 그려지면서 키에는 안 나가고, 지워야 할 것을 안 지우면 낡은 이름이 새 타입
-- 위에 남는다.

return function(DebindPrivate)
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

    local Constants = DebindPrivate.Constants;
    local SetActionEntry = DebindPrivate.SetActionEntry;

    --- 키에 걸려 있고 조건도 붙은 주문 액션. 바꾸기가 건드리면 안 되는 것을 전부 들고 있다.
    local function BoundSpell()
        return {
            type = Constants.SPELL,
            value = 774,
            name = "회복",
            icon = 136081,
            key = "SHIFT-Q",
            seq = 2,
            unit = "focus",
            priority = 7,
            arrivalID = 3,
            casting = { hoverCast = "cast" },
            conditions = { combat = true, known = "자연의 부름" },
        };
    end

    test("키와 자리와 나머지 조건은 그대로 남는다", function()
        local action = BoundSpell();
        SetActionEntry(action, Constants.ITEM, 5512);

        check(action.key == "SHIFT-Q", "키: " .. tostring(action.key));
        check(action.seq == 2, "seq: " .. tostring(action.seq));
        check(action.priority == 7, "priority: " .. tostring(action.priority));
        check(action.arrivalID == 3, "arrivalID: " .. tostring(action.arrivalID));
        check(action.casting.hoverCast == "cast", "casting이 바뀌었다");
        check(action.conditions.combat == true, "전투 조건이 없어졌다");
    end);

    test("타입과 값이 덮인다", function()
        local action = BoundSpell();
        SetActionEntry(action, Constants.ITEM, 5512);

        check(action.type == Constants.ITEM, "타입: " .. tostring(action.type));
        check(action.value == 5512, "값: " .. tostring(action.value));
    end);

    test("이름과 아이콘은 안 주면 지워진다", function()
        local action = BoundSpell();
        SetActionEntry(action, Constants.ITEM, 5512);

        check(action.name == nil, "이름이 남았다: " .. tostring(action.name));
        check(action.icon == nil, "아이콘이 남았다: " .. tostring(action.icon));
    end);

    test("저장해둬야 하는 타입은 props가 이름과 아이콘을 준다", function()
        local action = BoundSpell();
        SetActionEntry(action, Constants.PETACTION, "Growl", nil, nil,
            { name = "으르렁", icon = 132270 });

        check(action.name == "으르렁", "이름: " .. tostring(action.name));
        check(action.icon == 132270, "아이콘: " .. tostring(action.icon));
    end);

    test("습득 조건은 주문에서 주문으로 바꿔도 없어진다", function()
        local action = BoundSpell();
        SetActionEntry(action, Constants.SPELL, 8936);

        check(action.conditions.known == nil,
            "습득 조건이 남았다: " .. tostring(action.conditions.known));
    end);

    test("조건이 습득 하나뿐이었으면 조건 표째 없어진다", function()
        local action = BoundSpell();
        action.conditions = { known = "자연의 부름" };
        SetActionEntry(action, Constants.SPELL, 8936);

        check(action.conditions == nil, "빈 조건 표가 남았다");
    end);

    test("대상을 가질 수 있는 타입으로 바꾸면 대상이 남는다", function()
        local action = BoundSpell();
        SetActionEntry(action, Constants.ITEM, 5512);

        check(action.unit == "focus", "대상: " .. tostring(action.unit));
    end);

    test("대상을 못 가지는 타입으로 바꾸면 대상이 없어진다", function()
        local action = BoundSpell();
        SetActionEntry(action, Constants.MOUNT, 6);

        check(Constants.TYPES_WITH_UNIT[Constants.MOUNT] == nil, "탈것 전제가 깨졌다");
        check(action.unit == nil, "대상이 남았다: " .. tostring(action.unit));
    end);

    -- 타입만으로는 안 갈리는 쪽. 행동 단축키는 대상을 가질 수 있는 타입인데 태세 버튼은 클릭으로
    -- 눌려서 대상을 못 싣는다. 바인딩이 `ActionTakesUnit`으로 묻는 것을 여기서도 묻는다.
    test("같은 타입 안에서 대상을 못 싣는 값이면 대상이 없어진다", function()
        local action = BoundSpell();
        SetActionEntry(action, Constants.ACTIONBUTTON, "SHAPESHIFTBUTTON1");

        check(Constants.TYPES_WITH_UNIT[Constants.ACTIONBUTTON] == true, "행동 단축키 전제가 깨졌다");
        check(action.unit == nil, "대상이 남았다: " .. tostring(action.unit));
    end);

    -- **이 케이스가 재는 것은 값이 합쳐지지 않는다는 것뿐이다.** `SetActionEntry`는
    -- `SPEC_RESOLVED_TYPES`를 읽지 않는다. 그 셋의 값이 비는 것은 카탈로그가 값을 안 보내기
    -- 때문이고, 여기서는 안 보낸 값이 옛 값을 남기지 않는지를 본다.
    test("값을 안 주면 옛 값이 안 남는다", function()
        local action = BoundSpell();
        SetActionEntry(action, Constants.DISPEL);

        check(action.type == Constants.DISPEL, "타입: " .. tostring(action.type));
        check(action.value == nil, "값이 남았다: " .. tostring(action.value));
    end);

    return T;
end
