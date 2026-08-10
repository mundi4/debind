-- 클릭캐스팅 라우팅 색인 테스트. 와우 클라이언트 불필요.
--
-- 유닛 프레임은 클릭을 `type="click"`으로 우리 클릭 프레임에 넘긴다. 그 길은 **버튼 이름을
-- 못 싣는다** - `SECURE_ACTIONS.click`이 `delegate:Click(button)`이라 원래 마우스 버튼만
-- 도착한다. 그래서 "어느 키였는가"를 도착한 버튼 번호와 지금 눌린 수식어로 되찾는다.
--
-- `GetModifierIndex`는 그 색인의 **굽는 쪽**이다. 저장된 키에서 떼어낸 접두사를 번호로
-- 접는다. 푸는 쪽은 `SecureBindings.lua`의 OnClick 래퍼에 있는데 제한 환경이라 이 함수를
-- 못 부르고 같은 자릿값을 손으로 다시 쓴다.
--
-- **그래서 여기서 볼 수 있는 것은 절반이다.** 이 테스트는 굽는 쪽이 스스로 일관된지만
-- 본다 - 두 쪽이 어긋나는 것은 잡지 못한다. 자릿값을 바꾸면 래퍼도 같이 바꿔야 하고,
-- 어긋나면 수식어가 걸린 클릭캐스팅만 조용히 다른 목록을 찾는다(오류도 로그도 없다).
--
-- 자릿값: ALT=1, CTRL=2, SHIFT=4.

return function(DebindPrivate)
    local GetModifierIndex = DebindPrivate.GetModifierIndex;
    local GetMouseButtonAndPrefix = DebindPrivate.GetMouseButtonAndPrefix;

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

    local function expect(prefix, want)
        local got = GetModifierIndex(prefix);
        check(got == want,
            ("%s -> %s, 기대한 것은 %s"):format(tostring(prefix), tostring(got), tostring(want)));
    end

    ---------------------------------------------------------------------------
    -- 수식어 없음
    ---------------------------------------------------------------------------

    test("수식어가 없으면 0", function()
        expect(nil, 0);
        expect("", 0);
    end);

    ---------------------------------------------------------------------------
    -- 하나씩
    ---------------------------------------------------------------------------

    test("수식어 하나는 자기 자릿값", function()
        expect("ALT-", 1);
        expect("CTRL-", 2);
        expect("SHIFT-", 4);
    end);

    ---------------------------------------------------------------------------
    -- 조합
    ---------------------------------------------------------------------------

    test("조합은 자릿값의 합", function()
        expect("ALT-CTRL-", 3);
        expect("ALT-SHIFT-", 5);
        expect("CTRL-SHIFT-", 6);
        expect("ALT-CTRL-SHIFT-", 7);
    end);

    test("여덟 가지가 전부 다른 번호를 받는다", function()
        local seen = {};
        local prefixes = {
            "", "ALT-", "CTRL-", "SHIFT-",
            "ALT-CTRL-", "ALT-SHIFT-", "CTRL-SHIFT-", "ALT-CTRL-SHIFT-",
        };
        for _, p in ipairs(prefixes) do
            local n = GetModifierIndex(p);
            check(not seen[n], ("%s와 %s가 같은 번호 %d를 받았다"):format(seen[n] or "?", p, n));
            check(n >= 0 and n <= 7, ("%s가 범위 밖 %d"):format(p, n));
            seen[n] = p;
        end
    end);

    ---------------------------------------------------------------------------
    -- 순서에 기대지 않는다
    ---------------------------------------------------------------------------

    -- 접두사는 우리가 만든 것이 아니라 저장된 키 문자열에서 떼어낸 것이다. 와우의 정규
    -- 순서는 `ALT-CTRL-SHIFT-`지만 거기 기대면 옛 프로필이나 손으로 고친 값에서 깨진다.
    test("수식어 순서가 달라도 같은 번호", function()
        check(GetModifierIndex("SHIFT-ALT-") == GetModifierIndex("ALT-SHIFT-"),
            "순서만 다른 두 접두사가 갈렸다");
        check(GetModifierIndex("SHIFT-CTRL-ALT-") == GetModifierIndex("ALT-CTRL-SHIFT-"),
            "세 개짜리가 순서로 갈렸다");
    end);

    ---------------------------------------------------------------------------
    -- 키 문자열에서 오는 실제 입력
    ---------------------------------------------------------------------------

    -- `GetMouseButtonAndPrefix`가 내놓는 것을 그대로 먹는지 본다. 두 함수 사이에서 접두사
    -- 모양이 어긋나면(대소문자, 붙임표) 여기서 걸린다.
    test("GetMouseButtonAndPrefix가 준 접두사를 그대로 받는다", function()
        local cases = {
            { "BUTTON1", 1, 0 },
            { "BUTTON2", 2, 0 },
            { "SHIFT-BUTTON1", 1, 4 },
            { "CTRL-BUTTON2", 2, 2 },
            { "ALT-BUTTON4", 4, 1 },
            { "ALT-CTRL-SHIFT-BUTTON5", 5, 7 },
        };
        for _, c in ipairs(cases) do
            local key, wantButton, wantMod = c[1], c[2], c[3];
            local button, prefix = GetMouseButtonAndPrefix(key);
            check(button == wantButton,
                ("%s의 버튼이 %s, 기대한 것은 %d"):format(key, tostring(button), wantButton));
            check(GetModifierIndex(prefix) == wantMod,
                ("%s의 수식어가 %d, 기대한 것은 %d"):format(key, GetModifierIndex(prefix), wantMod));
        end
    end);

    return T;
end
