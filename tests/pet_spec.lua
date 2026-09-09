-- **소환수에 건 유닛 조건.** 와우 클라이언트 불필요.
--
-- 무엇이 여기서 답해지는가: `units.pet`이 리빌드를 지나 방출까지 가는가, 죽었느냐 축이
-- 그대로 나가는가, 그리고 소환수가 만들 수 없는 헤더를 요구하지 않는가.
--
-- **상태 루프가 소환수를 언제 재는지는 여기서 안 본다.** 그것을 정하는 것은 이 조건이 아니라
-- 키가 언제나 우리 것이냐다(`ClassifyKey`). 그 판정을 이 스펙이 재려 들면 소환수와 상관없는
-- 규칙을 소환수 이름으로 못박게 된다.
--
-- **이 스펙이 있는 이유는 메뉴가 소환수를 열어준 것이 파이프라인을 안 건드리는 변경이라는
-- 주장 때문이다.** 그 주장이 맞다는 것을 여기서 재고, 화면 쪽은 `/debtest`가 본다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;

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

    local GUID = "Player-1-TESTGUID";
    local CLASS = Constants.PLAYER_CLASS;

    local function Profile(actions)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
    end

    local function PlanFor(actions)
        Profile(actions);
        return DebindPrivate.BuildBindingPlan(DebindPrivate.CollectBindingContext());
    end

    local seq = 0;
    local function spell(t)
        seq = seq + 1;
        t.type = Constants.SPELL;
        t.value = t.value or 585;
        t.seq = seq;
        return t;
    end

    --- 죽은 소환수에 거는 소생 주문. 이 조건 하나가 이 스펙이 재는 전부다.
    local function revivePet()
        return spell({
            key = "CTRL-SHIFT-F9",
            conditions = { units = { pet = { exists = true, dead = true } } },
        });
    end

    test("a pet condition reaches the emitted snippet", function()
        local snippet = PlanFor({ revivePet() }).bindingsMapSnippet;

        check(snippet:find('t.units["pet"]', 1, true), "the pet condition was dropped");
        check(snippet:find("u.dead=true", 1, true), "the life axis was dropped");
    end);

    --- 소환수는 헤더가 없으므로 `plan.units`에 줄이 안 생긴다. 생기면 만들 수 없는 헤더를
    --- 만들라는 뜻이 된다.
    test("no unit watch row is asked for", function()
        local plan = PlanFor({ revivePet() });
        for i = 1, #plan.units do
            check(plan.units[i].alias ~= "pet", "a watch row was asked for the pet");
        end
    end);

    return T;
end
