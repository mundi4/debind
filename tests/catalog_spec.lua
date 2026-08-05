-- 카탈로그 필터 테스트. 와우 클라이언트 불필요.
--
-- `ActionCatalog.Filter`는 주문 선택 창에서 **유일하게 순수한** 조각이다. 나머지(주문서
-- 열거, 프레임)는 게임 API 없이는 못 돈다. 그래서 여기 고정하는 것은 두 가지다:
--
--   1. 기본값 - **다른 특성 주문은 넣는다.** 이 애드온에 특성별 레이어가 있어서 지금 아닌
--      특성의 주문을 미리 걸어두는 게 정상 사용이기 때문이다 (Clique와 반대다. 베끼면
--      안 되는 자리라 검사로 내린다)
--   2. 검색이 **패턴이 아니라 평문**이라는 것. 주문 이름에는 `(`, `-`, `[`가 흔하다.
--      패턴으로 해석하면 사용자가 그걸 치는 순간 오류거나 빈 목록이 된다
--
-- 패시브에 대한 항목은 없다. 필터가 아니라 **카탈로그가 아예 안 만들기** 때문이다 -
-- 시전할 수 없는 것은 단축키에 걸 대상이 아니다. 그 판정은 주문서 API를 타므로 여기서
-- 못 본다.

return function(DebouncePrivate)
    local ActionCatalog = DebouncePrivate.ActionCatalog;

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

    --- 엔트리 하나. 실제 소스가 만드는 것과 같은 모양이어야 하므로 검색용 사본도 채운다.
    local function entry(name, props)
        local e = props or {};
        e.type = "spell";
        e.value = e.value or name;
        e.name = name;
        e.searchName = strlower(name);
        e.searchSubName = e.subName and strlower(e.subName) or nil;
        return e;
    end

    local function names(list)
        local out = {};
        for i = 1, #list do
            out[i] = list[i].name;
        end
        return table.concat(out, ",");
    end

    local ALL = {
        entry("Fireball"),
        entry("Frostbolt", { subName = "Rank 2" }),
        entry("Ice Block", { isOffSpec = true }),
        entry("Arcane Blast (Instant)"),
    };

    ---------------------------------------------------------------------------
    -- 기본값
    ---------------------------------------------------------------------------

    test("기본값 - 오프스펙은 들어온다", function()
        local out = ActionCatalog.Filter(ALL, { includeOffSpec = true });
        check(names(out) == "Fireball,Frostbolt,Ice Block,Arcane Blast (Instant)", names(out));
    end);

    test("오프스펙을 끄면 빠진다", function()
        local out = ActionCatalog.Filter(ALL, { includeOffSpec = false });
        check(names(out) == "Fireball,Frostbolt,Arcane Blast (Instant)", names(out));
    end);

    test("원래 순서를 지킨다", function()
        local out = ActionCatalog.Filter(ALL, { includeOffSpec = true });
        check(out[1].name == "Fireball" and out[4].name == "Arcane Blast (Instant)", names(out));
    end);

    ---------------------------------------------------------------------------
    -- 검색
    ---------------------------------------------------------------------------

    test("이름 일부로 찾는다", function()
        local out = ActionCatalog.Filter(ALL, { search = "bol", includeOffSpec = true });
        check(names(out) == "Frostbolt", names(out));
    end);

    test("부제도 본다", function()
        local out = ActionCatalog.Filter(ALL, { search = "rank 2", includeOffSpec = true });
        check(names(out) == "Frostbolt", names(out));
    end);

    test("검색은 패턴이 아니라 평문이다", function()
        -- "(In"을 패턴으로 해석하면 여는 괄호가 캡처 시작이라 짝을 못 찾고 오류가 난다.
        -- 평문이면 그냥 한 줄이 걸린다.
        local out = ActionCatalog.Filter(ALL, { search = "(in", includeOffSpec = true });
        check(names(out) == "Arcane Blast (Instant)", names(out));

        -- 마침표는 "아무 글자 하나"가 아니다. 어느 이름에도 마침표가 없으므로 0개여야 한다.
        out = ActionCatalog.Filter(ALL, { search = ".", includeOffSpec = true });
        check(#out == 0, ("%d개"):format(#out));
    end);

    test("검색과 필터는 함께 걸린다", function()
        -- "ice"는 Ice Block(오프스펙)에만 걸린다. 오프스펙을 끄면 남는 게 없어야 한다.
        local out = ActionCatalog.Filter(ALL, { search = "ice", includeOffSpec = true });
        check(names(out) == "Ice Block", names(out));

        out = ActionCatalog.Filter(ALL, { search = "ice", includeOffSpec = false });
        check(#out == 0, ("%d개"):format(#out));
    end);

    ---------------------------------------------------------------------------
    -- 재사용 테이블
    ---------------------------------------------------------------------------

    test("out을 넘기면 그 테이블을 비우고 다시 채운다", function()
        -- 창이 프레임마다 새 테이블을 만들지 않도록 out을 재사용한다. 이전 결과가 남으면
        -- 검색어를 좁힐 때마다 목록이 길어진다.
        local out = {};
        ActionCatalog.Filter(ALL, { includeOffSpec = true }, out);
        check(#out == 4, ("%d개"):format(#out));

        local same = ActionCatalog.Filter(ALL, { search = "bol", includeOffSpec = true }, out);
        check(same == out, "같은 테이블을 돌려줘야 한다");
        check(#out == 1, ("%d개"):format(#out));
    end);

    return T;
end
