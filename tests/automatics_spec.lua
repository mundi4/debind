-- 클라이언트의 자동 동작 네 줄. 켬과 끔은 액션이 들고, 셋째 값인 "게임 설정 그대로"는 이름이
-- 없다 -- 값이 없는 것이 그것이다
-- (`setting-the-clients-cast-automatics-per-action.md` §1).

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

    --- 액션 하나만 든 계정 층으로 시작한다. `CleanUpDB`가 훑는 것이 층이라 액션을 거기 둔다.
    local function FreshDB(casting)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = {
                GENERAL = { { type = Constants.SPELL, value = 774, key = "F", seq = 1,
                    casting = casting } },
                classes = { [Constants.PLAYER_CLASS] = {} },
            },
            characters = {},
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        return _G.DebindVars.shared.GENERAL[1];
    end

    test("켬과 끔은 그대로 답하고, 안 적힌 줄은 게임 설정 그대로다", function()
        local action = { casting = { autoSelfCast = true, autoUnshift = false } };
        check(DebindPrivate.CastAutomaticOf(action, "autoSelfCast") == true,
            "켬이 안 나왔다");
        check(DebindPrivate.CastAutomaticOf(action, "autoUnshift") == false,
            "끔이 안 나왔다");
        check(DebindPrivate.CastAutomaticOf(action, "autoDismount") == nil,
            "안 적힌 줄이 게임 설정 그대로가 아니다");
    end);

    --- **저장된 표가 우리가 아는 값을 든다고 믿지 않는다.** 공유 문자열은 무엇이 적혀서든 올 수
    --- 있고, 셋째 값에 이름이 없으므로 모르는 값은 그 셋째로 읽혀야 한다.
    test("불리언이 아닌 값은 게임 설정 그대로로 읽힌다", function()
        local action = { casting = { autoDismount = "on", autoDismountFlying = 1 } };
        check(DebindPrivate.CastAutomaticOf(action, "autoDismount") == nil,
            "문자열이 값으로 읽혔다");
        check(DebindPrivate.CastAutomaticOf(action, "autoDismountFlying") == nil,
            "숫자가 값으로 읽혔다");
    end);

    test("액션이 없어도 답한다", function()
        check(DebindPrivate.CastAutomaticOf(nil, "autoSelfCast") == nil,
            "액션 없이 물었을 때 게임 설정 그대로가 아니다");
    end);

    --- 네 이름이 한 자리에 있어야 메뉴와 툴팁과 정리기가 같은 줄을 센다.
    test("네 줄의 이름이 한 자리에 있다", function()
        local rows = DebindPrivate.CAST_AUTOMATIC_ROWS;
        check(type(rows) == "table" and #rows == 4, "네 줄이 아니다");
        local want = { autoSelfCast = true, autoUnshift = true,
            autoDismount = true, autoDismountFlying = true };
        for i = 1, #rows do
            check(want[rows[i]], rows[i] .. "은 네 줄에 없는 이름이다");
            want[rows[i]] = nil;
        end
        check(next(want) == nil, "네 줄 중 빠진 것이 있다");
    end);

    --- **기본값은 저장에 안 남는다.** 값이 없는 것이 "게임 설정 그대로"이므로, 불리언이 아닌
    --- 것은 읽는 쪽에서 이미 기본으로 읽히고 저장에만 남는다.
    test("정리기가 불리언이 아닌 값을 걷는다", function()
        local action = FreshDB({ autoSelfCast = true, autoUnshift = "on", autoDismount = false });
        DebindPrivate.CleanUpDB();

        local casting = action.casting;
        check(casting ~= nil, "표가 통째로 사라졌다");
        check(casting.autoSelfCast == true, "켬이 안 남았다");
        check(casting.autoDismount == false, "끔이 안 남았다");
        check(casting.autoUnshift == nil, "불리언이 아닌 값이 남았다");
    end);

    test("네 줄만 들었다가 전부 걷히면 표도 안 남는다", function()
        local action = FreshDB({ autoDismountFlying = "usual" });
        DebindPrivate.CleanUpDB();
        check(action.casting == nil, "빈 표가 남았다");
    end);

    return T;
end
