-- 매크로텍스트 파서(`Misc.lua` `ParseMacroText`) 테스트. 와우 클라이언트 불필요.
--
-- 이 파서가 하는 일: 매크로 본문에서 애드온 전용 토큰(@tank 같은 특수 유닛,
-- $state1 같은 커스텀 상태)을 찾아 **보안 환경이 런타임에 갈아끼울 자리**로
-- 바꿔 놓는다. 놓치면 토큰이 글자 그대로 와우에 넘어가고, 와우는 모르는
-- 유닛이라 조용히 실패한다 -- 오류 한 줄 없이.
--
-- 세 층:
--   1. 이름 붙은 회귀 테스트 - 각 버그가 무엇이었는지 문서화
--   2. 계약 테스트 - SecureBindings.lua가 의존하는 반환값 모양
--   3. 무차별 대조 테스트 - 조건 그룹을 조합해서 정답을 직접 만들고 대조.
--      "N번째 그룹만 안 된다" 부류는 이쪽이 잡는다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local ParseMacroText = DebindPrivate.ParseMacroText;
    local ClearMacroTextCache = DebindPrivate.ClearMacroTextCache;
    local SPECIAL_UNITS = Constants.SPECIAL_UNITS;
    local ARG_UNIT = Constants.MACROTEXT_ARG_UNIT;
    local ARG_STATE = Constants.MACROTEXT_ARG_SWITCH;

    local T = { passed = 0, failures = {} };

    local function fail(name, msg)
        T.failures[#T.failures + 1] = name .. ": " .. msg;
    end

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            fail(name, tostring(err));
        end
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "assertion failed", 2);
        end
    end

    ---------------------------------------------------------------------------
    -- 도우미
    ---------------------------------------------------------------------------

    --- 파싱 결과에서 인자 이름만 순서대로.
    local function argNames(macrotext)
        local _, args = ParseMacroText(macrotext);
        if (not args) then
            return {};
        end
        local names = {};
        for i = 1, #args do
            names[i] = args[i].name;
        end
        return names;
    end

    local function join(t)
        return "{" .. table.concat(t, ", ") .. "}";
    end

    local function expectArgs(macrotext, expected)
        local got = argNames(macrotext);
        check(#got == #expected and table.concat(got, "\1") == table.concat(expected, "\1"),
            format("%q\n     기대 %s\n     실제 %s", macrotext, join(expected), join(got)));
    end

    --- 대괄호/세미콜론/쉼표 주변 공백만 지운 형태. 파서는 이 공백을 정규화하므로
    --- 그것만 무시하고 나머지가 온전히 보존됐는지 본다.
    --- 줄바꿈은 일부러 안 건드린다 -- 줄 경계가 뭉개지면 아무것도 못 잡는다.
    local function canon(s)
        return (s:gsub("[ \t]*([%[%]%;,])[ \t]*", "%1"));
    end

    --- 조건 그룹에 공백을 잔뜩 끼워 넣는다. `[@tank,exists]` -> `[ @tank , exists ]`
    local function padded(s)
        return (s:gsub("%[", "[ "):gsub("%]", " ]"):gsub(",", " , "));
    end

    --- The macro body as the parser read it. The even slots still hold the source token, so
    --- concatenating the fragments gives the text back with the parser's whitespace
    --- normalization applied and nothing else changed. The parser used to hand this out as a
    --- fourth return value; it stopped, because the caller can build it in one line and only
    --- this file ever wanted it.
    local function normalizedOf(macrotext)
        local fragments, args = ParseMacroText(macrotext);
        if (not args) then
            return nil; -- Nothing for the parser to pick up, so there is no normalized text
        end
        return table.concat(fragments), args;
    end

    local function expectRoundTrip(macrotext)
        local normalized = normalizedOf(macrotext);
        if (not normalized) then
            return; -- Not a body this parser has anything to say about
        end
        check(canon(normalized) == canon(macrotext),
            format("정규화가 내용을 바꿈\n     원문 %q\n     결과 %q", macrotext, normalized));
    end

    --- Mirrors the substitution `UpdateMacroTexts` does in `SecureBindings.lua`, so this file
    --- can see the string the restricted environment actually hands the game.
    ---
    --- One branch is correct here. A body carrying only units and one carrying a switch take
    --- the same path.
    local function resolve(macrotext, units, states)
        units, states = units or {}, states or {};
        local fragments, args = ParseMacroText(macrotext);
        if (not args) then
            return fragments; -- No token of ours in it, so the parser hands back the source
        end

        local frags = {};
        for i = 1, #fragments do
            frags[i] = fragments[i];
        end
        for i = 1, #args do
            local arg = args[i];
            local value;
            if (arg.type == ARG_UNIT) then
                value = units[arg.name] or "raid41";
            else
                local on = states[arg.name] and true or false;
                if (arg.reverse) then
                    on = not on;
                end
                value = on and "" or "known:0";
            end
            frags[i * 2] = value;
        end
        return table.concat(frags);
    end

    local LEAKABLE = { "@tank", "@healer", "@maintank", "@mainassist", "@custom1", "@custom2", "@hover", "$state" };

    --- 치환 후에도 애드온 전용 토큰이 남아 있으면 그건 와우로 새어나간 것.
    local function expectNoLeak(macrotext, units, states)
        local out = resolve(macrotext, units, states);
        for i = 1, #LEAKABLE do
            check(not out:find(LEAKABLE[i], 1, true),
                format("%q 가 치환 후에도 남음\n     원문 %q\n     결과 %q", LEAKABLE[i], macrotext, out));
        end
    end

    ---------------------------------------------------------------------------
    -- 1. 이름 붙은 회귀 테스트
    ---------------------------------------------------------------------------

    -- §1-1: `([^%;]*)` 가 `]` 다음부터 `;` 까지를 통째로 삼켜서 두 번째 이후
    --       대괄호 그룹이 파서에 도달하지 못했다. README가 광고하던 형태.
    test("두 번째 그룹의 특수 유닛도 파싱된다", function()
        expectArgs("/cast [@custom2,exists][@healer,exists][] Innervate", { "custom2", "healer" });
        expectNoLeak("/cast [@custom2,exists][@healer,exists][] Innervate");
    end);

    test("첫 그룹에 특수 토큰이 없어도 나머지를 포기하지 않는다", function()
        -- 이전엔 `_fragments`가 1개뿐이라 파싱 자체를 포기하고 원문을 돌려줬다
        expectArgs("/cast [mod:shift][@healer,exists] Innervate", { "healer" });
        expectNoLeak("/cast [mod:shift][@healer,exists] Innervate");
    end);

    test("그룹이 셋 이상이어도 전부 파싱된다", function()
        expectArgs("/cast [@tank][@healer][@custom1] Foo", { "tank", "healer", "custom1" });
        expectNoLeak("/cast [@tank][@healer][@custom1] Foo");
    end);

    test("그룹 사이 공백도 조건 이어짐으로 본다", function()
        -- 와우는 `[a] [b] Foo`를 "a 또는 b"로 읽는다
        expectArgs("/cast [@tank] [@healer] Foo", { "tank", "healer" });
    end);

    test("커스텀 상태가 두 번째 그룹에 있어도 파싱된다", function()
        expectArgs("/cast [nocombat][$state1] Foo", { "$state1" });
        expectNoLeak("/cast [nocombat][$state1] Foo", nil, { ["$state1"] = true });
    end);

    test("세미콜론과 다중 그룹이 섞여도 전부 파싱된다", function()
        expectArgs("/cast [@tank][@healer] A; [@custom1][@custom2] B",
            { "tank", "healer", "custom1", "custom2" });
        expectNoLeak("/cast [@tank][@healer] A; [@custom1][@custom2] B");
    end);

    test("여러 줄에서도 줄마다 다중 그룹이 파싱된다", function()
        expectArgs("/cast [@tank][@healer] A\n/use [@custom1][@custom2] B",
            { "tank", "healer", "custom1", "custom2" });
    end);

    test("특수 토큰이 마지막 그룹에만 있어도 파싱된다", function()
        expectArgs("/cast [combat][mod:alt][@hover] Foo", { "hover" });
    end);

    ---------------------------------------------------------------------------
    -- 2. 와우 문법 준수 -- "그냥 욕심내서 다 먹기"로 고치면 여기서 깨진다
    ---------------------------------------------------------------------------

    -- 와우의 SecureCmdOptionParse는 절 맨 앞의 `[...]` 들만 조건으로 읽고,
    -- 조건이 아닌 글자가 한 번 나오면 그 뒤는 전부 액션 텍스트다.
    test("본문 뒤의 대괄호는 조건이 아니라 글자다", function()
        expectArgs("/cast [@tank] Foo [@healer] Bar", { "tank" });
        expectRoundTrip("/cast [@tank] Foo [@healer] Bar");
    end);

    test("본문 뒤 대괄호를 건너뛰어도 다음 절은 계속 파싱한다", function()
        expectArgs("/cast [@tank] Foo [@healer] Bar; [@custom1] Baz", { "tank", "custom1" });
    end);

    test("본문 안의 리터럴 토큰은 그대로 보존된다", function()
        local out = resolve("/cast [@tank] @healer 라는 이름의 주문", { tank = "party1" });
        check(out:find("@healer", 1, true), "액션 텍스트가 손상됨: " .. out);
        check(not out:find("@tank", 1, true), "조건의 @tank가 치환되지 않음: " .. out);
    end);

    ---------------------------------------------------------------------------
    -- 3. 공백
    ---------------------------------------------------------------------------

    -- 와우는 조건절 안팎의 공백에 관대하다. 사람이 손으로 친 매크로는 여기가
    -- 제각각이라, 공백 하나 때문에 토큰을 놓치면 곧바로 "가끔 안 되는" 애드온이 된다.

    test("대괄호 안쪽 공백", function()
        expectArgs("/cast [ @tank ] Foo", { "tank" });
        expectArgs("/cast [\t@tank\t] Foo", { "tank" });
        expectRoundTrip("/cast [ @tank ] Foo");
    end);

    test("쉼표 주변 공백", function()
        expectArgs("/cast [@tank , exists] Foo", { "tank" });
        expectArgs("/cast [ @tank , exists , nocombat ] Foo", { "tank" });
        expectArgs("/cast [ $state1 , @tank ] Foo", { "$state1", "tank" });
        expectRoundTrip("/cast [ @tank , exists , nocombat ] Foo");
    end);

    test("안쪽 공백 + 다중 그룹", function()
        expectArgs("/cast [ @tank ][ @healer ] Foo", { "tank", "healer" });
        expectArgs("/cast [ @tank ] [ @healer ] Foo", { "tank", "healer" });
        expectArgs("/cast [ $state1 ][ @tank ] Foo", { "$state1", "tank" });
        expectNoLeak("/cast [ @tank ][ @healer ] Foo");
    end);

    test("공백만 있는 그룹", function()
        expectArgs("/cast [ ][ @healer ] Foo", { "healer" });
        expectRoundTrip("/cast [ ][ @healer ] Foo");
    end);

    test("세미콜론 주변 공백", function()
        expectArgs("/cast [ @tank ] Foo ; [ @healer ] Bar", { "tank", "healer" });
        expectRoundTrip("/cast [ @tank ] Foo ; [ @healer ] Bar");
    end);

    test("안쪽 공백 + 부정/접미사", function()
        expectArgs("/cast [ no$state1 ] Foo", { "$state1" });
        expectArgs("/cast [ @tanktarget ] Foo", { "tank" });
        local _, args = ParseMacroText("/cast [ no$state1 ] Foo");
        check(args[1].reverse == true, "안쪽 공백 때문에 reverse를 놓침");
        check(args[1].sourceString == "no$state1",
            "sourceString에 공백이 남음: " .. tostring(args[1].sourceString));
    end);

    -- §3-1: 슬래시 명령 매칭이 `^(/[%S]+%s+)()`였다. `%S`가 `[`까지 먹어버리는데
    --       뒤에 공백을 **하나 이상** 요구해서, 붙여 쓰면 줄 전체를 포기했다.
    test("명령 뒤에 공백이 없어도 파싱한다", function()
        expectArgs("/cast[@tank] Foo", { "tank" });
        expectArgs("/cast[@tank][@healer]Foo", { "tank", "healer" });
        expectNoLeak("/cast[@tank] Foo");
    end);

    -- §3-2: 같은 패턴이 `^/`로 시작할 것을 요구해서, 줄 앞 공백에도 포기했다.
    test("줄 앞 공백이 있어도 파싱한다", function()
        expectArgs("  /cast [@tank] Foo", { "tank" });
        expectArgs("/cast [@tank] A\n  /use [@healer] B", { "tank", "healer" });
    end);

    test("명령 뒤 공백은 여러 개여도 보존된다", function()
        local normalized = normalizedOf("/cast  [@tank]  Foo");
        check(normalized == "/cast  [@tank]Foo", "정규화 결과가 " .. tostring(normalized));
    end);

    test("슬래시 명령이 없는 줄", function()
        expectArgs("[@tank] Foo", { "tank" });
        expectArgs("  [@tank][@healer] Foo", { "tank", "healer" });
    end);

    test("조건이 없는 명령은 건드리지 않는다", function()
        local a, args = ParseMacroText("/cast Regrowth");
        check(args == nil, "조건이 없는데 args를 돌려줌");
        check(a == "/cast Regrowth", "원문이 바뀜: " .. tostring(a));

        -- 인자가 아예 없는 명령(뒤에 공백도 없음)에서 죽지 않아야 한다
        local b, args2 = ParseMacroText("/dismount");
        check(args2 == nil and b == "/dismount", "원문이 바뀜: " .. tostring(b));
    end);

    ---------------------------------------------------------------------------
    -- 4. 기존 동작 회귀 방지
    ---------------------------------------------------------------------------

    test("단일 그룹", function()
        expectArgs("/cast [@tank] Heal", { "tank" });
        expectArgs("/cast [@custom1,exists] Heal", { "custom1" });
    end);

    test("세미콜론으로 나뉜 절", function()
        expectArgs("/cast [@custom2,exists] Innervate; [@healer,exists] Innervate",
            { "custom2", "healer" });
        expectArgs("/cast [$state1] Heal; Smite", { "$state1" });
    end);

    test("특수 토큰이 없으면 파싱 대상이 아니다", function()
        local a, args = ParseMacroText("/cast [mod:shift] Foo; Bar");
        check(args == nil, "특수 토큰이 없는데 args를 돌려줌");
        check(a == "/cast [mod:shift] Foo; Bar", "원문이 그대로 돌아오지 않음: " .. tostring(a));

        local b, args2 = ParseMacroText("/cast Regrowth");
        check(args2 == nil, "대괄호도 없는데 args를 돌려줌");
        check(b == "/cast Regrowth", "원문이 그대로 돌아오지 않음: " .. tostring(b));
    end);

    test("유닛 접미사", function()
        expectArgs("/cast [@tanktarget] Foo", { "tank" });
        expectArgs("/cast [@custom2pettarget] Foo", { "custom2" });
        local out = resolve("/cast [@tanktarget] Foo", { tank = "raid7" });
        check(out:find("@raid7target", 1, true), "접미사가 붙어 나오지 않음: " .. out);
    end);

    test("알 수 없는 @유닛은 건드리지 않는다", function()
        local a, args = ParseMacroText("/cast [@notaunit] Foo");
        check(args == nil, "모르는 유닛을 인자로 잡음");
        check(a == "/cast [@notaunit] Foo", "원문이 바뀜: " .. tostring(a));
        -- 진짜 와우 유닛도 마찬가지로 그냥 통과해야 한다
        local b, args2 = ParseMacroText("/cast [@focus] Foo");
        check(args2 == nil, "와우 기본 유닛 @focus를 건드림");
        check(b == "/cast [@focus] Foo", "원문이 바뀜: " .. tostring(b));
    end);

    test("커스텀 상태 부정(no$state)", function()
        local _, args = ParseMacroText("/cast [no$state1] Foo");
        check(args and #args == 1, "인자를 못 찾음");
        check(args[1].name == "$state1", "이름이 " .. tostring(args[1].name));
        check(args[1].reverse == true, "reverse가 안 붙음");
        check(args[1].sourceString == "no$state1", "sourceString이 " .. tostring(args[1].sourceString));

        -- reverse는 값의 의미를 뒤집는다: 상태가 켜져 있으면 조건은 거짓
        check(resolve("/cast [no$state1] Foo", nil, { ["$state1"] = true }):find("known:0", 1, true),
            "상태가 켜졌는데 no$state1이 참으로 나옴");
        check(not resolve("/cast [no$state1] Foo", nil, { ["$state1"] = false }):find("known:0", 1, true),
            "상태가 꺼졌는데 no$state1이 거짓으로 나옴");
    end);

    --- `UpdateBindings.lua`의 `UpdateMacroTextsMap`이 상태 인자마다 내리는 결정의 **거울**이다.
    --- 컴파일 시점에 정의를 못 찾은 이름은 런타임 참조가 아니라 리터럴로 굽힌다.
    ---
    --- ⚠ 거울이지 그 파일의 검사가 아니다. `UpdateBindings.lua`는 로드에 프레임을 만들어서
    --- 헤드리스 러너가 안 싣는다(`tests/run.lua`). 저쪽 규칙이 바뀌면 여기는 조용히 통과한다 -
    --- 그래서 이 함수가 지키는 것은 "정의되지 않은 이름은 거짓" 하나뿐이고, 결정에 필요한
    --- 것(`arg.name` / `arg.reverse`)을 파서가 실제로 넘겨준다는 것까지다.
    local function bakeFixed(arg, defined)
        if (defined[arg.name]) then
            return nil;
        end
        return "known:0";
    end

    --- 정의된 상태가 하나도 없을 때 실제로 와우에 넘어가는 문자열.
    local function resolveWithDefinitions(macrotext, defined)
        local frags, args = ParseMacroText(macrotext);
        check(args ~= nil, "상태 인자를 못 찾음");
        local out = {};
        for i = 1, #frags do
            out[i] = frags[i];
        end
        for i = 1, #args do
            out[i * 2] = bakeFixed(args[i], defined) or "";
        end
        return table.concat(out);
    end

    -- ⚑2. 정의되지 않은 이름을 `""`로 구우면 `[$typo]`가 `[]`가 되고, 빈 조건 그룹은
    -- **항상 참**이다(위 "빈 조건 그룹" 테스트가 그 형태를 그대로 보여준다). 오타 하나로
    -- 바인딩이 조건 없이 상시 발동하게 되는 자리라, 굽는 값은 거짓이어야 한다.
    test("정의되지 않은 상태는 거짓으로 굽는다", function()
        local out = resolveWithDefinitions("/cast [$typo] Foo", {});
        check(out:find("known:0", 1, true), "거짓으로 안 굽힘: " .. out);
        check(not out:find("[]", 1, true), "빈 조건 그룹이 됐다 - 항상 참이다: " .. out);

        -- 부정형은 원래도 거짓이었다. 같은 답이 나오는지만 확인한다.
        local rev = resolveWithDefinitions("/cast [no$typo] Foo", {});
        check(rev:find("known:0", 1, true), "부정형이 거짓으로 안 굽힘: " .. rev);
    end);

    test("정의된 상태는 굽지 않고 런타임에 남긴다", function()
        local _, args = ParseMacroText("/cast [$state1] Foo");
        check(bakeFixed(args[1], { ["$state1"] = true }) == nil,
            "정의된 이름까지 리터럴로 굳으면 상태가 켜져도 안 바뀐다");
    end);

    test("unitsOnly면 커스텀 상태를 무시한다", function()
        local _, args = ParseMacroText("/cast [@tank,$state1] Foo", true);
        check(args and #args == 1, "인자 수가 " .. tostring(args and #args));
        check(args[1].name == "tank", "이름이 " .. tostring(args[1].name));
    end);

    test("한 그룹 안에 인자가 여럿", function()
        expectArgs("/cast [@tank,exists,nocombat] Foo", { "tank" });
        expectRoundTrip("/cast [@tank,exists,nocombat] Foo");
        expectArgs("/cast [$state1,@tank] Foo", { "$state1", "tank" });
        expectRoundTrip("/cast [$state1,@tank] Foo");
    end);

    test("빈 조건 그룹", function()
        expectArgs("/cast [@tank][] Foo", { "tank" });
        expectRoundTrip("/cast [@tank][] Foo");
    end);

    test("닫히지 않은 대괄호는 그대로 흘려보낸다", function()
        local normalized, args = normalizedOf("/cast [@tank][@healer Foo");
        check(args and #args == 1, "첫 그룹은 파싱됐어야 함");
        check(args[1].name == "tank", "이름이 " .. tostring(args[1].name));
        check(normalized:find("[@healer Foo", 1, true), "망가진 꼬리가 보존되지 않음");
    end);

    ---------------------------------------------------------------------------
    -- 5. SecureBindings.lua가 의존하는 반환값 계약
    ---------------------------------------------------------------------------

    --- **There is one shape.** A body carrying only units and a body carrying a switch come
    --- back as the same thing.
    ---
    --- The two used to differ. Units only produced a `%N$s` format string where `N` was the
    --- number in `SPECIAL_UNITS`, and that number was written down in three places (the table,
    --- the site that baked it, seven hand-written arguments on the restricted side), so
    --- **adding or removing one special unit silently misaligned the rest**. With the branch
    --- gone there is no number left to keep aligned.
    local function checkFragmentShape(macrotext, argCount)
        local frags, args = ParseMacroText(macrotext);
        check(type(frags) == "table", macrotext .. ": fragments가 테이블이 아님");
        check(#args == argCount, macrotext .. ": 인자 수가 " .. #args);
        -- Odd slots are text, even slots are argument slots (`SecureBindings` overwrites
        -- `fragments[i * 2]`).
        check(#frags == #args * 2 + 1, macrotext .. ": fragments 길이가 " .. #frags);
        for i = 1, #args do
            check(frags[i * 2] == (args[i].sourceString or args[i].name),
                format("%s: fragments[%d]가 %q, 인자는 %q",
                    macrotext, i * 2, frags[i * 2], args[i].name));
        end
        return frags, args;
    end

    test("계약: 특수 유닛만 있어도 fragments다", function()
        local _, args = checkFragmentShape("/cast [@tank][@healer] Foo", 2);
        check(args[1].type == ARG_UNIT and args[2].type == ARG_UNIT, "타입이 UNIT이 아님");
    end);

    test("계약: 스위치가 끼어도 같은 모양이다", function()
        local _, args = checkFragmentShape("/cast [$state1][@tank] Foo", 2);
        check(args[1].type == ARG_STATE, "첫 인자가 스위치가 아님");
        check(args[2].type == ARG_UNIT, "둘째 인자가 UNIT이 아님");
    end);

    test("계약: 특수 유닛 일곱이 전부 같은 모양으로 나온다", function()
        -- This used to check, per unit, that the `N` in `%N$s` matched that unit's number. With
        -- no number left to keep, what remains is **whether all seven are picked up as
        -- arguments**. One that leaks through as literal text hands `@tank` to the game as is.
        for name in pairs(SPECIAL_UNITS) do
            local _, args = checkFragmentShape("/cast [@" .. name .. "] Foo", 1);
            check(args[1].name == name, name .. "이 인자로 안 잡힘");
            check(args[1].type == ARG_UNIT, name .. "의 타입이 UNIT이 아님");
        end
    end);

    test("계약: 캐시가 같은 결과를 준다", function()
        -- A hit hands back **the same table**; after a clear, **a different table holding the
        -- same thing**. This used to be one `==` between two first return values, and that one
        -- comparison answered both questions at once because they were strings. They are tables
        -- now, so `==` answers identity only and the two questions have to be asked separately.
        local text = "/cast [@tank][@healer] Foo";
        local frags1, args1 = ParseMacroText(text);
        local frags2, args2 = ParseMacroText(text);
        check(frags1 == frags2 and args1 == args2, "캐시가 다른 표를 돌려줌");

        ClearMacroTextCache();
        local frags3, args3 = ParseMacroText(text);
        check(frags3 ~= frags1, "캐시를 비웠는데 같은 표가 나옴");
        check(table.concat(frags3) == table.concat(frags1), "비운 뒤 정규화 결과가 달라짐");
        check(#args3 == #args1, "비운 뒤 인자 수가 달라짐");
        for i = 1, #frags1 do
            check(frags3[i] == frags1[i],
                format("비운 뒤 fragments[%d]가 %q에서 %q로", i, frags1[i], frags3[i]));
        end
        for i = 1, #args1 do
            check(args3[i].name == args1[i].name and args3[i].type == args1[i].type,
                format("비운 뒤 인자 %d가 달라짐", i));
        end
    end);

    ---------------------------------------------------------------------------
    -- 6. 무차별 대조 -- 조건 그룹을 조합해서 정답을 직접 만든다
    ---------------------------------------------------------------------------

    -- 각 항목: { 그룹 문자열, 그 그룹이 내놓아야 할 인자 이름들 }
    local GROUPS = {
        { "[@tank]",             { "tank" } },
        { "[@healer,exists]",    { "healer" } },
        { "[mod:shift]",         {} },
        { "[]",                  {} },
        { "[$state1]",           { "$state1" } },
        { "[@custom1,nocombat]", { "custom1" } },
        { "[@custom2target]",    { "custom2" } },
        { "[nocombat,@hover]",   { "hover" } },
    };

    --- 그룹 인덱스 목록으로 절 하나와 기대 인자 목록을 만든다.
    local function buildClause(indices)
        local parts, expected = {}, {};
        for i = 1, #indices do
            local g = GROUPS[indices[i]];
            parts[#parts + 1] = g[1];
            for j = 1, #g[2] do
                expected[#expected + 1] = g[2][j];
            end
        end
        return table.concat(parts), expected;
    end

    --- 길이 n인 모든 그룹 조합을 훑는다.
    local function eachCombo(n, fn)
        local idx = {};
        local function rec(depth)
            if (depth > n) then
                fn(idx);
                return;
            end
            for i = 1, #GROUPS do
                idx[depth] = i;
                rec(depth + 1);
            end
            idx[depth] = nil;
        end
        rec(1);
    end

    --- 같은 조합을 세 가지 표기로 돌린다. 공백 차이가 결과를 바꾸면 안 된다.
    local SPELLINGS = {
        { "보통", function(clause) return "/cast " .. clause .. " Foo"; end },
        { "공백 낀 조건", function(clause) return "/cast " .. padded(clause) .. " Foo"; end },
        { "명령에 붙임", function(clause) return "/cast" .. clause .. " Foo"; end },
    };

    local function checkMacrotext(macrotext, expected)
        local got = argNames(macrotext);
        check(table.concat(got, "\1") == table.concat(expected, "\1"),
            format("%q\n     기대 %s\n     실제 %s", macrotext, join(expected), join(got)));

        expectRoundTrip(macrotext);

        if (#expected == 0) then
            local a, args = ParseMacroText(macrotext);
            check(args == nil, macrotext .. ": 인자가 없는데 args를 돌려줌");
            check(a == macrotext, macrotext .. ": 원문이 바뀜 -> " .. tostring(a));
        else
            expectNoLeak(macrotext, nil, { ["$state1"] = true });
            expectNoLeak(macrotext, nil, { ["$state1"] = false });
        end
    end

    test("무차별: 그룹 1~3개 조합 × 표기 3종", function()
        local count = 0;
        for n = 1, 3 do
            eachCombo(n, function(indices)
                local clause, expected = buildClause(indices);
                count = count + 1;
                for s = 1, #SPELLINGS do
                    checkMacrotext(SPELLINGS[s][2](clause), expected);
                end
            end);
        end
        check(count == 8 + 64 + 512, "조합 수가 " .. count);
    end);

    test("무차별: 세미콜론으로 이어붙인 두 절", function()
        -- 조합 폭발을 막으려고 2개짜리 조합끼리만 곱한다
        eachCombo(2, function(a)
            local clauseA, expectedA = buildClause(a);
            eachCombo(1, function(b)
                local clauseB, expectedB = buildClause(b);
                local macrotext = "/cast " .. clauseA .. " Foo; " .. clauseB .. " Bar";

                local expected = {};
                for i = 1, #expectedA do expected[#expected + 1] = expectedA[i]; end
                for i = 1, #expectedB do expected[#expected + 1] = expectedB[i]; end

                local got = argNames(macrotext);
                check(table.concat(got, "\1") == table.concat(expected, "\1"),
                    format("%q\n     기대 %s\n     실제 %s", macrotext, join(expected), join(got)));

                expectRoundTrip(macrotext);
            end);
        end);
    end);

    test("무차별: 줄바꿈으로 이어붙인 두 줄", function()
        eachCombo(2, function(a)
            local clauseA, expectedA = buildClause(a);
            eachCombo(1, function(b)
                local clauseB, expectedB = buildClause(b);
                local macrotext = "/cast " .. clauseA .. " Foo\n/use " .. clauseB .. " Bar";

                local expected = {};
                for i = 1, #expectedA do expected[#expected + 1] = expectedA[i]; end
                for i = 1, #expectedB do expected[#expected + 1] = expectedB[i]; end

                local got = argNames(macrotext);
                check(table.concat(got, "\1") == table.concat(expected, "\1"),
                    format("%q\n     기대 %s\n     실제 %s", macrotext, join(expected), join(got)));

                expectRoundTrip(macrotext);
            end);
        end);
    end);

    ---------------------------------------------------------------------------
    -- 7. 아이콘 뽑기용 `$상태` 제거 (StripSwitchConditions)
    --
    -- 아이콘은 매크로텍스트를 **진짜 매크로 슬롯에 써넣어** 와우에게 계산시킨다
    -- (DebindUI.lua `GetMacrotextIcon`). `$state1`이 그대로 넘어가면 와우가 대화창에
    -- "Unknown macro option: $state1"을 찍는다 -- 아이콘 하나에 채팅창이 더러워진다.
    --
    -- 계약은 둘:
    --   (a) `$`로 시작하는 조건 토큰은 하나도 안 남는다
    --   (b) `$`가 없는 매크로텍스트는 **글자 하나 안 바뀐다** (본문 속 대괄호 포함)
    ---------------------------------------------------------------------------

    local Strip = DebindPrivate.StripSwitchConditions;

    local function expectStrip(input, expected)
        local got = Strip(input);
        check(got == expected,
            format("%q\n     기대 %q\n     실제 %q", input, expected, tostring(got)));
    end

    test("상태만 있던 그룹은 빈 그룹이 된다", function()
        -- 빈 조건은 와우에서 항상 참 = 커스텀 상태를 켜진 것으로 친다
        expectStrip("/cast [$state1] Foo", "/cast [] Foo");
        expectStrip("/cast [ $state1 ] Foo", "/cast [] Foo");
    end);

    test("같은 그룹의 다른 조건은 자리를 지킨다", function()
        -- 쉼표까지 같이 빠진다. 남은 조건만으로 이루어진 멀쩡한 그룹이어야 한다
        expectStrip("/cast [$state1,combat] Foo", "/cast [combat] Foo");
        expectStrip("/cast [combat,$state1] Foo", "/cast [combat] Foo");
        expectStrip("/cast [@custom1,$state1] Foo", "/cast [@custom1] Foo");
        expectStrip("/cast [combat,$state1,@tank] Foo", "/cast [combat,@tank] Foo");
    end);

    test("부정형도 제거된다", function()
        expectStrip("/cast [no$state1] Foo", "/cast [] Foo");
        expectStrip("/cast [ no$state1 , combat ] Foo", "/cast [ combat ] Foo");
    end);

    test("파서가 인자로 안 잡는 $토큰도 제거된다", function()
        -- `ParseMacroText`는 `$[a-zA-Z0-9_]+`만 인자로 인정하고 나머지는 리터럴로
        -- 흘려보낸다. 와우는 **그것도** 똑같이 "Unknown macro option"을 찍는다.
        expectStrip("/cast [$foo-bar] Foo", "/cast [] Foo");
        expectStrip("/cast [$] Foo", "/cast [] Foo");
    end);

    -- 무작위 조합 검사는 **닫힌 그룹만** 만들어내므로 이 자리를 못 본다.
    --
    -- 한때 본문 패턴이 `[^%]]*`였다. 대괄호가 하나 빠지면 그게 **다음 그룹까지 통째로 삼켜서**
    -- `[combat [$state1]`이 본문 하나가 되고, 콤마로 가르면 `combat [$state1`이 한 덩어리라
    -- `$`로 시작하지 않는다. 멀쩡한 안쪽 그룹의 토큰이 그냥 통과해서, 이 함수가 막으려던
    -- 오류가 그대로 찍혔다.
    --
    -- **보장하는 것은 여기까지다.** `$`가 닫히지 않은 그룹 **안에** 있으면(`[$state1 [combat]`)
    -- 여전히 남는다. 그건 우리 패턴이 만든 문제가 아니라 매크로 자체가 깨진 경우고, 닫히지
    -- 않은 그룹까지 손대려면 "조건이 아닌 대괄호(`/say [안녕]`)는 글자 하나 안 건드린다"는
    -- 규칙을 포기해야 한다. 깨진 매크로는 어차피 와우가 따로 나무란다.
    test("닫히지 않은 그룹이 뒤 그룹의 $토큰을 숨기지 않는다", function()
        local leaky = {
            "/cast [combat [$state1] Foo",
            "/cast [[$state1] Foo",
        };
        for _, input in ipairs(leaky) do
            local got = Strip(input);
            check(not strfind(got, "$", 1, true),
                format("%q -> %q : $토큰이 남았다", input, tostring(got)));
        end
    end);

    test("여러 그룹·세미콜론·여러 줄을 전부 훑는다", function()
        expectStrip("/cast [$state1][@tank] A; [no$state2] B\n/use [$state3] C",
            "/cast [][@tank] A; [] B\n/use [] C");
    end);

    test("$가 없으면 글자 하나 안 바뀐다", function()
        local untouched = {
            "/cast [@tank,exists][@healer] Regrowth",
            "/cast [ @custom1 , nocombat ] Foo",
            "#showtooltip\n/cast [mod:shift] A; B",
            "/say [안녕]",            -- 조건이 아닌 대괄호
            "/cast Regrowth",
            "",
        };
        for i = 1, #untouched do
            expectStrip(untouched[i], untouched[i]);
        end
        check(Strip(nil) == nil, "nil에서 죽거나 값을 만들어냄");
    end);

    test("무차별: 어떤 조합에서도 $가 살아남지 않는다", function()
        for n = 1, 3 do
            eachCombo(n, function(indices)
                local clause = buildClause(indices);
                for s = 1, #SPELLINGS do
                    local macrotext = SPELLINGS[s][2](clause);
                    local got = Strip(macrotext);
                    check(not got:find("$", 1, true),
                        format("$가 남음\n     원문 %q\n     결과 %q", macrotext, got));
                    if (not macrotext:find("$", 1, true)) then
                        check(got == macrotext,
                            format("$도 없는데 바뀜\n     원문 %q\n     결과 %q", macrotext, got));
                    end
                end
            end);
        end
    end);

    return T;
end
