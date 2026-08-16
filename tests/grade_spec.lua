-- 문제 코드의 등급(`Constants.BINDING_ISSUE_GRADES`)과 Clique 경고가 나가는 조건.
-- 와우 클라이언트 불필요.
--
-- **등급이 틀리면 화면이 조용히 거짓말한다.** 빨강이어야 할 것이 회색이 되면 안 도는 바인딩이
-- "활성이 없어서 없는 셈 쳐도 되는 것"으로 그려지고, 사용자는 고칠 것이 있다는 말을 어디서도
-- 못 듣는다. 반대 방향은 시끄럽기만 하다. `npm run check`가 색은 못 보므로 색을 정하는 값을
-- 여기서 잡는다.
--
-- Clique 쪽은 성격이 다르다. 그 줄은 **로그인당 한 번**만 나가므로(`Events.lua`) 조건이 좁으면
-- 다음 기회가 다음 로그인이다. 어느 레이어까지 세는지가 그래서 조건의 일부다 - 오프스펙만
-- 세지 않으면, 그 특성으로 갈아탄 사람은 아무 말도 못 들은 채로 지정을 잃는다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local IsIssueMinor = DebindPrivate.IsIssueMinor;

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

    --- 모든 문제 코드를 훑는다. `BINDING_ISSUE_GRADES`는 표라서 걸러진다 - 이름이 같은 접두사로
    --- 시작하지만 값이 문자열이 아니다.
    local function ForEachIssueCode(fn)
        local seen = 0;
        for name, code in pairs(Constants) do
            if (type(name) == "string" and name:match("^BINDING_ISSUE_")
                    and type(code) == "string") then
                seen = seen + 1;
                fn(name, code);
            end
        end
        check(seen > 0, "문제 코드를 하나도 못 찾았다 - 접두사가 바뀌었나");
    end

    ---------------------------------------------------------------------------
    -- 등급
    ---------------------------------------------------------------------------

    test("도달불가는 회색이다", function()
        check(IsIssueMinor(Constants.BINDING_ISSUE_UNREACHABLE), "도달불가가 회색이 아니다");
    end);

    -- 회색은 "이 행의 잘못이 아니다"이고, 그 판정에 이웃이 필요한 코드는 도달불가뿐이다.
    -- 나머지가 하나라도 회색이 되면 그 키는 안 도는데 화면은 흐린 글씨로 넘어간다.
    test("나머지 코드는 전부 빨강이다", function()
        ForEachIssueCode(function(name, code)
            if (code ~= Constants.BINDING_ISSUE_UNREACHABLE) then
                check(not IsIssueMinor(code), name .. "이 회색이다");
            end
        end);
    end);

    -- **표에 없는 코드는 빨강으로 떨어져야 한다.** 회색이 기본값이면 등급을 안 적은 새 코드가
    -- 조용히 흐려진다 - 시끄러운 쪽으로 틀리는 것이 이 애드온에서 안전한 방향이다.
    test("모르는 코드와 nil은 빨강이다", function()
        check(not IsIssueMinor("NO_SUCH_ISSUE_CODE"), "모르는 코드가 회색이다");
        check(not IsIssueMinor(nil), "nil이 회색이다");
    end);

    -- 위 기본값은 안전하지만 **의도한 등급인지는 아무에게도 안 물어본다.** 코드를 늘리면서
    -- 표의 한 줄을 빠뜨리는 자리를 여기서 막는다.
    test("모든 코드에 등급이 적혀 있다", function()
        ForEachIssueCode(function(name, code)
            check(Constants.BINDING_ISSUE_GRADES[code] ~= nil, name .. "에 등급이 없다");
        end);
    end);

    ---------------------------------------------------------------------------
    -- Clique 경고가 나가는 조건
    ---------------------------------------------------------------------------

    local CLASS = Constants.PLAYER_CLASS;
    local GUID = "Player-1-TESTGUID";

    -- shim의 세계: 드루이드(4특성), 활성 특성 1. 아래 오프스펙 사례가 그 전제 위에 선다.
    check(C_SpecializationInfo.GetSpecialization() == 1,
        "활성 특성 1 전제: " .. tostring(C_SpecializationInfo.GetSpecialization()));

    --- `InitDB`가 읽는 모양 그대로. `class`/`char`는 특성 번호를 열쇠로 하는 표다.
    local function ResetProfile(layout)
        layout = layout or {};
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = {
                GENERAL = layout.general or {},
                classes = { [CLASS] = layout.class or {} },
            },
            characters = { [GUID] = { layers = layout.char or {} } },
            migrated = {},
        };
        DebindPrivate.InitDB();
    end

    --- 대상이 개체창인 액션. `GetBindingIssue`의 `"unit"` 갈래가 이걸 잡는다.
    local function HoverTargetAction(fields)
        local action = { type = Constants.SPELL, value = 100, key = "F1", unit = "hover", seq = 1 };
        for k, v in pairs(fields or {}) do
            action[k] = v;
        end
        return action;
    end

    --- 대상은 평범한데 **hover 조건**이 걸린 액션. 이쪽은 `"hover"` 갈래가 잡는다. 두 갈래가
    --- 따로 있어서 둘 다 확인한다 - 한쪽만 물으면 나머지 절반이 조용히 빠진다.
    local function HoverConditionAction()
        return {
            type = Constants.SPELL, value = 100, key = "F1", unit = "target", seq = 1,
            checkedUnits = { hover = { exists = true } },
        };
    end

    local function PlainAction()
        return { type = Constants.SPELL, value = 100, key = "F1", seq = 1 };
    end

    --- Clique를 켠 채로 답을 받는다. 이 플래그는 파일 로드 때 한 번 정해지는 것이라
    --- (`Debind.lua`) 하네스에는 아예 없다 - 여기서 세우고 되돌린다.
    local function BlockedWithClique(on)
        local saved = DebindPrivate.CliqueDetected;
        DebindPrivate.CliqueDetected = on;
        local ok, answer = pcall(DebindPrivate.HasBindingBlockedByClique);
        DebindPrivate.CliqueDetected = saved;
        if (not ok) then
            error(answer, 0);
        end
        return answer;
    end

    test("Clique가 없으면 개체창 지정이 있어도 조용하다", function()
        ResetProfile({ general = { HoverTargetAction() } });
        check(BlockedWithClique(false) == false, "Clique가 없는데 경고가 나간다");
    end);

    test("대상이 개체창인 지정을 센다", function()
        ResetProfile({ general = { HoverTargetAction() } });
        check(BlockedWithClique(true) == true, "경고가 안 나간다");
    end);

    test("hover 조건만 걸린 지정도 센다", function()
        ResetProfile({ general = { HoverConditionAction() } });
        check(BlockedWithClique(true) == true, "hover 조건 갈래를 안 본다");
    end);

    test("개체창과 무관한 지정은 안 센다", function()
        ResetProfile({ general = { PlainAction() } });
        check(BlockedWithClique(true) == false, "멀쩡한 지정에 경고가 나간다");
    end);

    -- 아래 둘은 Clique가 없어도 안 나가는 것들이다. Clique 탓으로 셀 수 없다.
    test("키가 아직 없는 세트는 안 센다", function()
        ResetProfile({ general = { HoverTargetAction({ key = 1 }) } });
        check(BlockedWithClique(true) == false, "합성 번호 키를 센다");
    end);

    test("승인 전 배지가 붙은 것은 안 센다", function()
        ResetProfile({ general = { HoverTargetAction({ imported = "F1" }) } });
        check(BlockedWithClique(true) == false, "격리된 액션을 센다");
    end);

    -- **이 줄은 로그인당 한 번이고 특성을 바꿔도 다시 안 온다.** 활성 레이어만 세면, 충돌이
    -- 다른 특성에만 있는 사람은 아무 말도 못 들은 채로 그 특성에 갈아타서 지정을 잃는다.
    test("오프스펙 레이어에만 있어도 센다", function()
        ResetProfile({ class = { [3] = { HoverTargetAction() } } });
        check(BlockedWithClique(true) == true, "오프스펙을 안 센다");
    end);

    return T;
end
