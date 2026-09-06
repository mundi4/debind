-- 옵션(`preferHoverUnit`)이 만드는 **쌍둥이 바인딩**과, Clique가 그것을 가져갔을 때 나오는
-- 말. 와우 클라이언트 불필요.
--
-- 액션 하나가 바인딩 둘일 수 있다는 것이 여기서 재는 전부다: 둘 다 덮여야 도달 불가이고,
-- 쌍둥이가 아예 안 만들어지는 대상들이 있고, Clique가 있으면 만들지 못한다.
--
-- 툴팁이 이 답을 실제로 그리는지는 여기서 못 본다. 그건 `GameTooltip`의 줄이라
-- `tests/display_spec.lua`와 `/debtest`의 `Tooltip:` 둘이 본다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local GetBindingIssue = DebindPrivate.GetBindingIssue;
    local GetBindingInfoForAction = DebindPrivate.GetBindingInfoForAction;
    local CheckUnreachableBindings = DebindPrivate.CheckUnreachableBindings;
    local ClearUnreachableBindingCache = DebindPrivate.ClearUnreachableBindingCache;

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

    ---------------------------------------------------------------------------
    -- 1. 바인딩이 둘인 액션은 둘 다 죽어야 도달 불가다
    -- (`devdocs/splitting-an-action-into-bindings.md` §3-1)
    ---------------------------------------------------------------------------

    --- 옵션 켠 액션을 `cover` 뒤에 세운다. `KeyMap`과 같은 순서로(쌍둥이가 원본 앞).
    ---
    --- 액션에서 바인딩을 얻는 통로가 `GetBindingInfoForAction`이고 `IsUnreachableAction`도
    --- 같은 통로로 캐시를 조회하므로, 솔버에 넣는 테이블과 조회되는 테이블이 같은 것이다.
    local function coveredPair(cover)
        local subject = { type = Constants.SPELL, value = 586, key = cover.key, preferHoverUnit = true };
        local list = DebindPrivate.GetBindingsForAction(subject);
        check(#list == 2, "쌍둥이가 안 생겼다");
        local bindings = { GetBindingInfoForAction(cover), list[2], list[1] };
        ClearUnreachableBindingCache();
        CheckUnreachableBindings(bindings);
        return subject;
    end

    --- 반만 죽은 액션은 도달 불가가 아니다. 원본이든 쌍둥이든 하나는 여전히 나가므로, 그 키는
    --- 개체창 위에서든 밖에서든 한쪽에서 그대로 발동한다.
    ---
    --- **어느 쪽이 죽었는지는 이제 아무 데도 안 적힌다** (2026-09-06, 소유자). 조건이 다른
    --- 액션을 한 키에 여럿 두면 일부가 겹치는 것이 이 애드온의 정상 동작이라, 겹친 자리를
    --- 문제라고 부를 자리가 없다.
    test("쌍둥이만 덮인 액션은 도달 불가가 아니다", function()
        local subject = coveredPair({ type = Constants.SPELL, value = 585, key = "T",
            conditions = { units = { hover = {} } } });
        check(not DebindPrivate.IsUnreachableAction(subject), "원본이 살아 있는데 액션이 죽었다");
        check(GetBindingIssue(subject) == nil, "나온 것: " .. tostring(GetBindingIssue(subject)));
    end);

    --- 원본만 죽는 것은 마우스 버튼에서만 생긴다. 키보드 키에서는 원본이 제일 넓은 상자라
    --- 그걸 덮는 것은 쌍둥이도 덮는다. 마우스 버튼은 hover 없는 원본이 "hover 없음"으로 좁혀져
    --- 있어서(`BuildUnitStates`), 같은 버튼의 hover 없는 이웃이 원본만 덮는다.
    test("원본만 덮인 액션도 도달 불가가 아니다", function()
        local subject = coveredPair({ type = Constants.SPELL, value = 585, key = "BUTTON3" });
        check(not DebindPrivate.IsUnreachableAction(subject), "쌍둥이가 살아 있는데 액션이 죽었다");
        check(GetBindingIssue(subject) == nil, "나온 것: " .. tostring(GetBindingIssue(subject)));
    end);

    --- **도달 불가는 문제 코드가 아니다** (2026-09-06, 소유자). 액션 자신의 잘못이 아니라 같은
    --- 키의 이웃과의 관계라, `GetBindingIssue`가 아니라 이쪽이 답한다. 한 칸에 같이 있던 동안에는
    --- 덮인 액션이 자기 경고 대신 도달 불가를 냈고, 경고가 화면에서 사라졌다.
    test("둘 다 덮이면 도달 불가고, 그래도 문제 코드는 안 난다", function()
        local subject = coveredPair({ type = Constants.SPELL, value = 585, key = "T" });
        check(DebindPrivate.IsUnreachableAction(subject), "둘 다 덮였는데 액션이 살아 있다");
        check(GetBindingIssue(subject) == nil, "나온 것: " .. tostring(GetBindingIssue(subject)));
    end);

    --- **쌍둥이는 개체창 종류 조건을 안 물려받는다** (2026-09-06). `frameTypes`는 hover 조건을
    --- 꺼도 안 지워진다(`Profile.lua`의 `dbver` 주석: 끄는 것과 지우는 것은 다르다). 그런데
    --- 조건을 끄면 옵션이 다시 살아나 쌍둥이가 생기고, 쌍둥이는 `hover`가 참이라 원본을
    --- 정리하는 갈래를 안 지난다. 그대로 두면 쌍둥이만 옛 마스크로 좁혀진다.
    ---
    --- 마스크가 0이면 더 조용하다. 쌍둥이가 어떤 개체창에도 안 걸리는데 `GetBindingIssue`의
    --- frameTypes 검사는 **원본의** `hover`(=nil)로 게이트되어 아무 말도 안 나온다.
    test("쌍둥이는 꺼진 hover 조건이 남긴 frameTypes를 안 가져온다", function()
        for _, mask in ipairs({ Constants.FRAMETYPE_GROUP, 0 }) do
            local action = { type = Constants.SPELL, value = 585, key = "T", unit = "focus",
                preferHoverUnit = true, conditions = { frameTypes = mask } };
            local list = DebindPrivate.GetBindingsForAction(action);
            check(list[1].conditions.frameTypes == nil,
                "원본이 안 지워졌다: " .. tostring(list[1].conditions.frameTypes));
            check(list[2] ~= nil, "쌍둥이가 안 생겼다");
            check(list[2].conditions.frameTypes == nil,
                "마스크 " .. mask .. "가 쌍둥이에 남았다: "
                    .. tostring(list[2].conditions.frameTypes));
        end
    end);

    ---------------------------------------------------------------------------
    -- 2. Clique가 있으면 옵션은 잠기고, 액션은 빨갛지 않다
    ---------------------------------------------------------------------------

    local function withClique(fn)
        local was = DebindPrivate.CliqueDetected;
        DebindPrivate.CliqueDetected = true;
        local ok, err = pcall(fn);
        DebindPrivate.CliqueDetected = was;
        if (not ok) then error(err, 0); end
    end

    test("Clique가 있으면 옵션 켠 액션은 주황 문장 하나다", function()
        withClique(function()
            local action = { type = Constants.SPELL, value = 585, key = "T", preferHoverUnit = true };
            local issue = GetBindingIssue(action);
            check(issue == Constants.BINDING_ISSUE_HOVER_UNIT_WITH_CLIQUE, "나온 것: " .. tostring(issue));
            check(DebindPrivate.GetIssueColor(issue) == _G.ORANGE_FONT_COLOR, "주황이 아니다");
            -- **갈래는 상자 제 것이다.** 잘못된 것은 체크박스이지 그 옆의 대상이 아니다 -
            -- 사용자가 고른 대상은 멀쩡하고 액션도 거기로 나간다. `unit`에 얹으면 그 대상 줄이
            -- 빨개지면서 남의 문장을 밑에 달고, `hover`에 얹으면 상관없는 조건 메뉴가 칠해진다.
            check(GetBindingIssue(action, "preferHoverUnit") == issue,
                "상자 갈래로 물으니 안 나온다");
            check(GetBindingIssue(action, "unit") == nil, "대상 갈래가 이 문제를 들고 있다");
            check(GetBindingIssue(action, "hover") == nil, "hover 갈래가 이 문제를 들고 있다");
        end);
    end);

    -- **대상 `none`과 `hover`에서는 쌍둥이를 안 만든다** (2026-09-06, 소유자). `hover`는 이미
    -- 그 개체를 겨누고, `none`은 대상 입력을 받는 시전이라 겨눔을 가로챌 자리가 아니다.
    -- 만드는 쪽이 안 만들므로 Clique가 뺏을 것도 없고, 그래서 할 말도 없다.
    test("대상이 none이나 hover면 옵션이 켜져 있어도 쌍둥이가 없다", function()
        for _, unit in ipairs({ "none", "hover" }) do
            local action = { type = Constants.SPELL, value = 585, key = "T",
                unit = unit, preferHoverUnit = true };
            check(DebindPrivate.GetBindingsForAction(action)[2] == nil,
                "대상 " .. unit .. "인데 쌍둥이가 생겼다");
        end

        -- 대상 `none`은 Clique와 아무 상관이 없으므로 할 말이 없어야 한다. 대상 `hover`는
        -- 다르다 - 그건 옵션과 무관하게 Clique가 정말로 못 쓰게 만드는 겨눔이라, 원래의
        -- 빨강이 그대로 나와야 한다. 옵션의 주황이 그것을 밀어내면 안 된다.
        withClique(function()
            local none = { type = Constants.SPELL, value = 585, key = "T",
                unit = "none", preferHoverUnit = true };
            check(GetBindingIssue(none) == nil,
                "대상 none에 문장이 붙었다: " .. tostring(GetBindingIssue(none)));

            local hover = { type = Constants.SPELL, value = 585, key = "T",
                unit = "hover", preferHoverUnit = true };
            check(GetBindingIssue(hover) == Constants.BINDING_ISSUE_CANNOT_USE_HOVER_WITH_CLIQUE,
                "대상 hover의 빨강이 옵션의 주황에 밀렸다: " .. tostring(GetBindingIssue(hover)));
        end);
    end);

    -- **hover 조건이 [안 올렸을 때]여도 쌍둥이는 없다** (2026-09-06, 소유자). 그 액션은 개체창
    -- 위에서 아예 발동하지 않으므로 개체창의 개체로 나갈 가능성이 0이다. 메뉴도 같은 이유로
    -- 상자를 잠근다 - 여기서 재는 것은 그 짝의 실행 쪽이고, 잠금 자체는 화면에서만 보인다.
    test("hover 조건이 안 올렸을 때여도 쌍둥이가 없다", function()
        local action = { type = Constants.SPELL, value = 585, key = "T",
            unit = "focus", preferHoverUnit = true,
            conditions = { units = { hover = false } } };
        check(DebindPrivate.GetBindingsForAction(action)[2] == nil,
            "개체창 위에서 안 도는 액션에 쌍둥이가 생겼다");
    end);

    -- 반대쪽. 없으면 위 테스트는 "언제나 쌍둥이가 없다"로도 통과한다.
    test("평범한 대상에는 쌍둥이가 생긴다", function()
        local action = { type = Constants.SPELL, value = 585, key = "T",
            unit = "focus", preferHoverUnit = true };
        local bindings = DebindPrivate.GetBindingsForAction(action);
        check(bindings[2] ~= nil, "대상 focus인데 쌍둥이가 없다");
        check(bindings[2].unit == "hover", "쌍둥이가 겨누는 것: " .. tostring(bindings[2].unit));
    end);

    test("Clique가 있어도 hover 조건이 켜진 액션의 답은 그대로 빨강이다", function()
        withClique(function()
            local action = { type = Constants.SPELL, value = 585, key = "T", preferHoverUnit = true,
                conditions = { units = { hover = {} } } };
            check(GetBindingIssue(action) == Constants.BINDING_ISSUE_CANNOT_USE_HOVER_WITH_CLIQUE,
                "hover 조건의 빨강이 옵션의 주황에 밀렸다");
        end);
    end);

    --- **덮인 액션도 자기 경고를 그대로 낸다** (2026-09-06, 소유자). 이웃에 덮였다는 것은 액션
    --- 자신의 잘못이 아니라 같은 키에 무엇이 더 걸려 있는가이고, 축이 다르므로 서로를 가리지
    --- 않는다. 둘이 한 칸에 있던 동안에는 덮인 쪽이 잡혀서 이 경고가 화면에서 사라졌고,
    --- 오른쪽 레이어 패널의 표시까지 같이 없어졌다.
    ---
    --- 오류는 이렇게 못 만든다 - 등급 때문에 `KeyMap`에서 빠져 솔버에 안 들어가므로 덮일 일이
    --- 없다. 그래서 이 조합을 만드는 코드는 경고 하나뿐이다.
    test("이웃에 덮여도 Clique 경고는 그대로 나온다", function()
        withClique(function()
            local cover = { type = Constants.SPELL, value = 585, key = "T" };
            local subject = { type = Constants.SPELL, value = 586, key = "T", preferHoverUnit = true };
            check(#DebindPrivate.GetBindingsForAction(subject) == 1,
                "Clique를 켰는데 쌍둥이가 생겼다");

            ClearUnreachableBindingCache();
            CheckUnreachableBindings({
                GetBindingInfoForAction(cover), GetBindingInfoForAction(subject) });
            check(DebindPrivate.IsUnreachableAction(subject), "솔버가 덮인 쪽을 안 떨궜다");

            check(GetBindingIssue(subject) == Constants.BINDING_ISSUE_HOVER_UNIT_WITH_CLIQUE,
                "나온 것: " .. tostring(GetBindingIssue(subject)));
        end);
    end);

    test("Clique가 있어도 옵션을 못 받는 타입은 아무 말이 없다", function()
        withClique(function()
            local action = { type = Constants.MACROTEXT, value = "/cast x", key = "T", preferHoverUnit = true };
            check(GetBindingIssue(action) == nil, "나온 것: " .. tostring(GetBindingIssue(action)));
        end);
    end);

    return T;
end
