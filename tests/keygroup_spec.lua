-- 키 그룹째 키를 주는 것. `Profile.lua`의 `SetKeyForActions`와 그 앞에 서는 수집 함수.
--
-- **이 파일이 지키는 것은 보낸 사람의 순서다.** 키가 빠진 문자열이 나르는 설계의 잔존물이
-- 그것뿐인데(`devdocs/building-export-import.md`), 액션에 하나씩 키를 주면 조용히 사라진다 -
-- `seq`는 만진 차례대로 발급되지 그 액션이 몇 번째였는지를 안 본다. 그래서 그룹째 주는 조작은
-- 편의가 아니라 순서를 지키는 유일한 길이다.
--
-- 나머지 둘:
--
--   * **그룹과 점유자는 같은 범위에서 모은다.** 한쪽만 모자라면 교체가 반만 일어나고
--     덮어쓰기는 "이 키는 이제 이 그룹 것"이라 해놓고 다른 자리에 그대로 남긴다.
--   * **다른 직업의 레이어는 그 범위 밖이다.** 그쪽은 이 캐릭터의 키보드가 아니다.

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
    local CLASS = Constants.PLAYER_CLASS;
    local GUID = "Player-1-TESTGUID";

    -- overview_spec과 같은 전제: 드루이드(4특성), 활성 특성 1.
    check(CLASS == "DRUID", "드루이드 전제: " .. tostring(CLASS));
    check(C_SpecializationInfo.GetSpecialization() == 1,
        "활성 특성 1 전제: " .. tostring(C_SpecializationInfo.GetSpecialization()));

    --- `InitDB`가 읽는 모양 그대로. `otherClass`는 이 세션이 못 보는 자리를 세우는 칸이다 -
    --- 드루이드 세션에서 `classes.MAGE`는 `LayerArray`에 아예 없다.
    local function ResetProfile(layout)
        layout = layout or {};
        local classes = { [CLASS] = layout.class or {} };
        if (layout.otherClass) then
            classes.MAGE = layout.otherClass;
        end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = layout.general or {}, classes = classes },
            characters = { [GUID] = { layers = layout.char or {} } },
            migrated = {},
        };
        DebindPrivate.InitDB();
    end

    --- One member of a set that arrived with no key of its own. **The key is a number**, which is
    --- what a key group whose key has not been decided yet carries (`NextSyntheticKey`), and `seq`
    --- is its place in that group like anywhere else.
    local function Arrived(value, key, seq)
        return { type = Constants.SPELL, value = value, imported = 1, key = key, seq = seq };
    end

    local function Bound(value, key, seq)
        return { type = Constants.SPELL, value = value, key = key, seq = seq };
    end

    --- 행들이 무엇이었는지 한 줄로. 실패했을 때 차례가 눈에 보인다.
    local function Values(rows)
        local out = {};
        for i, row in ipairs(rows) do
            out[i] = tostring((row.action or row).value);
        end
        return table.concat(out, " ");
    end

    ---------------------------------------------------------------------------
    -- 보낸 사람의 순서
    ---------------------------------------------------------------------------

    -- **저장 배열의 차례와 `seq`를 일부러 어긋나게 세운다.** 둘이 같으면 이 테스트는 아무것도
    -- 안 재는데, 정확히 그 어긋남이 한 액션씩 키를 줄 때 순서가 사라지는 자리다.
    -- 그리고 레이어에 이미 번호 7이 나가 있어서, 도착한 셋은 그 뒤에 서야 한다.
    test("그룹째 키를 주면 실려온 차례가 지켜진다", function()
        ResetProfile({
            general = {
                Bound(99, "G", 7),
                Arrived(30, 1, 3),
                Arrived(10, 1, 1),
                Arrived(20, 1, 2),
            },
        });

        local group = DebindPrivate.CollectKeyGroupActions(1);
        check(#group == 3, "그룹 크기 " .. #group);
        DebindPrivate.SetKeyForActions(group, "F");

        -- 발동 순서를 그리는 쪽에 물어본다. `seq`를 직접 읽으면 방금 넣은 값을 되읽는 셈이다.
        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "10 20 30", "차례: " .. Values(rows));
    end);

    test("이미 그 키에 있던 것 뒤에 선다", function()
        ResetProfile({
            general = { Bound(99, "F", 7), Arrived(10, 1, 1), Arrived(20, 1, 2) },
        });

        DebindPrivate.SetKeyForActions(DebindPrivate.CollectKeyGroupActions(1), "F");

        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "99 10 20", "차례: " .. Values(rows));
    end);

    -- **레이어마다 자기 번호를 낸다.** `seq`는 한 레이어 안에서만 뜻이 있어서 그래야 맞고,
    -- 그룹 안의 차례는 레이어 안에서 지켜지면 된다 - 레이어끼리는 비교자가 먼저 가른다.
    test("레이어를 가로지르는 그룹도 각 레이어 안에서 차례를 지킨다", function()
        ResetProfile({
            general = { Arrived(30, 1, 3), Arrived(10, 1, 1) },
            class = { [0] = { Bound(99, "F", 4), Arrived(40, 1, 4), Arrived(20, 1, 2) } },
        });

        local group = DebindPrivate.CollectKeyGroupActions(1);
        check(#group == 4, "그룹 크기 " .. #group);
        DebindPrivate.SetKeyForActions(group, "F");

        -- 직업/공용이 일반보다 위다(스코프). 그 안에서 99는 이미 4번을 들고 있으므로 앞이다.
        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "99 20 40 10 30", "차례: " .. Values(rows));
    end);

    test("키를 주면 배지가 같이 떨어진다", function()
        ResetProfile({ general = { Arrived(10, 1, 1), Arrived(20, 1, 2) } });

        local group = DebindPrivate.CollectKeyGroupActions(1);
        DebindPrivate.SetKeyForActions(group, "F");

        for _, action in ipairs(group) do
            check(action.key == "F", "키가 안 걸렸다: " .. tostring(action.value));
            check(action.imported == nil, "배지가 남았다: " .. tostring(action.value));
        end
        check(#DebindPrivate.CollectKeyGroupActions(1) == 0, "옛 번호로 아직 모인다");
    end);

    ---------------------------------------------------------------------------
    -- 키를 이미 들고 있던 그룹을 옮기는 것
    ---------------------------------------------------------------------------

    -- Merging, replacing and overwriting all stand on this. `seq` is what says where each one
    -- stands, and the set that moved lands at the back of the destination group -- what
    -- `PlaceInKeyGroup` does for anything arriving.
    test("키 그룹을 옮겨도 그룹 안의 차례는 그대로다", function()
        ResetProfile({
            general = {
                Bound(10, "F", 5),
                Bound(20, "F", 2),
                Bound(99, "G", 1),
            },
        });

        local group = DebindPrivate.CollectKeyGroupActions("F");
        check(#group == 2, "그룹 크기 " .. #group);
        DebindPrivate.SetKeyForActions(group, "G");

        local rows = DebindPrivate.CollectActionsForKey("G");
        check(Values(rows) == "99 20 10", "차례: " .. Values(rows));
        check(#DebindPrivate.CollectActionsForKey("F") == 0, "F에 뭔가 남았다");
    end);

    ---------------------------------------------------------------------------
    -- 차 있는 키에 주는 세 가지 답
    ---------------------------------------------------------------------------

    --- 도착 그룹 하나(일반 레이어)와 F를 들고 있는 내 액션 둘.
    local function ArrivedGroupAndOccupiedF()
        ResetProfile({
            general = {
                Bound(50, "F", 1),
                Bound(60, "F", 2),
                Arrived(10, 1, 1),
                Arrived(20, 1, 2),
            },
        });
        return DebindPrivate.CollectKeyGroupActions(1), DebindPrivate.CollectKeyGroupActions("F");
    end

    -- 한 키에 조건으로 갈린 액션 여럿이 이 애드온의 정상 상태다. 병합은 점유자를 안 건드린다.
    test("병합 - 점유자는 그대로 있고 도착 그룹이 뒤에 선다", function()
        local group, occupants = ArrivedGroupAndOccupiedF();
        check(#occupants == 2, "점유자 " .. #occupants);

        DebindPrivate.MoveKeyGroupToKey(group, "F", occupants, false);

        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "50 60 10 20", "차례: " .. Values(rows));
    end);

    test("덮어쓰기 - 점유자는 키를 잃고 지워지지는 않는다", function()
        local group, occupants = ArrivedGroupAndOccupiedF();

        DebindPrivate.MoveKeyGroupToKey(group, "F", occupants, true);

        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "10 20", "차례: " .. Values(rows));
        check(DebindPrivate.GetProfileLayer(1):GetNumActions() == 4, "액션이 지워졌다");
        for _, action in ipairs(occupants) do
            check(action.key == nil, "키가 안 풀렸다: " .. tostring(action.value));
            -- **The number goes with the key.** A place means "which of this key's actions goes
            -- first", so one held while there is no key is not a place but a number from somewhere.
            -- The action stays and only the number goes -- an overwrite is a state that can be
            -- walked back because nothing is deleted, not because a number was kept.
            check(action.seq == nil, "번호가 남았다: " .. tostring(action.value));
        end
    end);

    test("덮어쓰기가 점유자의 배지는 안 뗀다", function()
        -- 키까지 실려 온 배치(키 빼고 보내지 않은 경우)라 점유자 쪽에도 배지가 달려 있다.
        local badgedOccupant = Bound(50, "F", 1);
        badgedOccupant.imported = 7;
        ResetProfile({ general = { badgedOccupant, Arrived(10, 2, 1) } });

        local group = DebindPrivate.CollectKeyGroupActions(2);
        local occupants = DebindPrivate.CollectKeyGroupActions("F");
        DebindPrivate.MoveKeyGroupToKey(group, "F", occupants, true);

        check(occupants[1].imported == 7, "점유자의 배지가 떨어졌다");
    end);

    ---------------------------------------------------------------------------
    -- 어디까지 모으나
    ---------------------------------------------------------------------------

    -- **오프스펙 레이어는 범위 안이다.** 그 액션들은 이제 왼쪽 열에 그려지고, 지금 안 돈다는
    -- 것만 사유 칸이 말한다(`devdocs/showing-off-spec-actions.md`).
    test("그룹도 점유자도 오프스펙 레이어까지 모은다", function()
        ResetProfile({
            class = {
                [1] = { Arrived(10, 1, 1), Bound(50, "F", 1) },
                [3] = { Arrived(20, 1, 2), Bound(60, "F", 1) },
            },
        });

        check(#DebindPrivate.CollectKeyGroupActions(1) == 2,
            "그룹 " .. #DebindPrivate.CollectKeyGroupActions(1));
        check(#DebindPrivate.CollectKeyGroupActions("F") == 2,
            "점유자 " .. #DebindPrivate.CollectKeyGroupActions("F"));
    end);

    -- **다른 직업의 레이어는 범위 밖이다.** 이 세션의 `LayerArray`에 없고, 그쪽 키보드는 이
    -- 결정이 서 있는 키보드가 아니다. 그룹은 거기서 배지를 단 채로 남아 그 직업으로 접속했을
    -- 때 자기 키를 받는다.
    test("다른 직업의 레이어는 모으지도 건드리지도 않는다", function()
        ResetProfile({
            general = { Arrived(10, 1, 1) },
            otherClass = { [0] = { Arrived(20, 1, 2), Bound(60, "F", 1) } },
        });

        local group = DebindPrivate.CollectKeyGroupActions(1);
        check(#group == 1, "그룹 크기 " .. #group);
        check(#DebindPrivate.CollectKeyGroupActions("F") == 0,
            "점유자 " .. #DebindPrivate.CollectKeyGroupActions("F"));

        DebindPrivate.SetKeyForActions(group, "F");

        local stranger = _G.DebindVars.shared.classes.MAGE[0];
        check(stranger[1].key == 1, "남의 레이어의 멤버까지 키가 바뀌었다");
        check(stranger[2].seq == 1, "남의 레이어의 번호가 바뀌었다");
    end);

    test("nil을 주면 아무것도 안 모은다", function()
        ResetProfile({ general = { Bound(10, "F", 1), Arrived(20, 1, 1) } });

        check(#DebindPrivate.CollectKeyGroupActions(nil) == 0, "키 nil이 뭔가를 모았다");
    end);

    ---------------------------------------------------------------------------
    -- 그룹째 키를 빼는 것
    --
    -- **키를 지우면 그룹이 없어진다.** `key == nil`인 액션은 어느 그룹의 것도 아니고
    -- (`CollectKeyGroupForAction`), 그 넷이 한 벌이었다는 것을 적어두는 데가 없다. 그래서
    -- 그룹째 빼는 조작은 키를 지우는 게 아니라 **아직 정하지 않은 키로 옮기는 것**이다.
    ---------------------------------------------------------------------------

    test("여러 개짜리 그룹을 풀어도 한 덩어리로 남는다", function()
        ResetProfile({
            general = { Bound(10, "F", 1), Bound(20, "F", 2), Bound(30, "F", 3) },
        });

        local group = DebindPrivate.CollectKeyGroupActions("F");
        check(#group == 3, "그룹 크기 " .. #group);
        DebindPrivate.UnbindKeyGroup(group);

        local key = group[1].key;
        check(type(key) == "number", "키가 숫자가 아니다: " .. tostring(key));
        check(#DebindPrivate.CollectKeyGroupActions("F") == 0, "F에 남은 것이 있다");

        -- 셋이 같은 번호에 있고, 실려온 차례도 그대로다. `seq`를 직접 읽지 않고 발동 순서를
        -- 그리는 쪽에 묻는 것은 이 파일의 다른 테스트와 같은 이유다.
        local rows = DebindPrivate.CollectActionsForKey(key);
        check(Values(rows) == "10 20 30", "차례: " .. Values(rows));
    end);

    test("하나짜리를 풀면 키가 없어진다", function()
        ResetProfile({ general = { Bound(10, "F", 1) } });

        local group = DebindPrivate.CollectKeyGroupActions("F");
        check(#group == 1, "그룹 크기 " .. #group);
        DebindPrivate.UnbindKeyGroup(group);

        check(group[1].key == nil, "키가 남았다: " .. tostring(group[1].key));
        check(group[1].seq == nil, "번호가 남았다: " .. tostring(group[1].seq));
    end);

    -- **번호를 나눠주는 쪽까지 같이 본다.** 둘을 연달아 풀었을 때 같은 번호가 나가면 서로
    -- 남남인 두 벌이 한 머리글 아래로 합쳐지고, 그건 화면에 나오기 전까지 조용하다.
    test("연달아 풀어도 두 덩어리가 섞이지 않는다", function()
        ResetProfile({
            general = {
                Bound(10, "F", 1), Bound(20, "F", 2),
                Bound(30, "G", 1), Bound(40, "G", 2),
            },
        });

        local f = DebindPrivate.CollectKeyGroupActions("F");
        local g = DebindPrivate.CollectKeyGroupActions("G");
        DebindPrivate.UnbindKeyGroup(f);
        DebindPrivate.UnbindKeyGroup(g);

        check(f[1].key == f[2].key, "F였던 둘이 갈라졌다");
        check(g[1].key == g[2].key, "G였던 둘이 갈라졌다");
        check(f[1].key ~= g[1].key, "두 덩어리가 같은 번호를 받았다: " .. tostring(f[1].key));
    end);

    -- **한 벌인지 골라놓은 것인지를 이 함수 하나가 답한다**(`SharedKeyOf`). 창도 커밋도 여기서
    -- 갈리므로, 둘이 서로 다른 답을 보면 화면이 그리는 것과 눌렀을 때 일어나는 일이 어긋난다.
    --
    -- **nil이 두 번 나오는 자리라 플래그를 같이 잰다.** "키를 안 나눠 쓴다"와 "다 같이 키가
    -- 없다"는 첫 반환값이 똑같고, 둘을 섞으면 키 없는 한 벌이 제각각인 선택으로 취급된다 -
    -- [키 설정 해제]가 그 벌을 합성 키로 안 묶고 흩어버린다.
    test("SharedKeyOf: 같은 키면 그 키와 참", function()
        local shared = { { key = "F" }, { key = "F" }, { key = "F" } };
        local key, ok = DebindPrivate.SharedKeyOf(shared);
        check(key == "F", "키가 다르다: " .. tostring(key));
        check(ok == true, "한 벌로 안 봤다");

        local synthetic = { { key = 7 }, { key = 7 } };
        key, ok = DebindPrivate.SharedKeyOf(synthetic);
        check(key == 7, "합성 번호가 다르다: " .. tostring(key));
        check(ok == true, "합성 키 한 벌을 한 벌로 안 봤다");
    end);

    test("SharedKeyOf: 제각각이면 nil과 거짓", function()
        local key, ok = DebindPrivate.SharedKeyOf({ { key = "F" }, { key = "G" } });
        check(key == nil, "키가 나왔다: " .. tostring(key));
        check(ok == false, "제각각인데 한 벌로 봤다");

        -- 하나만 키가 없어도 제각각이다.
        key, ok = DebindPrivate.SharedKeyOf({ { key = "F" }, {} });
        check(ok == false, "키 없는 하나가 섞였는데 한 벌로 봤다");
    end);

    test("SharedKeyOf: 다 키가 없으면 nil과 참", function()
        local key, ok = DebindPrivate.SharedKeyOf({ {}, {}, {} });
        check(key == nil, "없는 키가 나왔다: " .. tostring(key));
        check(ok == true, "키가 없는 것을 나눠 쓰는 것도 한 벌이다");
    end);

    test("SharedKeyOf: 빈 목록은 한 벌이 아니다", function()
        local key, ok = DebindPrivate.SharedKeyOf({});
        check(key == nil, "빈 목록에서 키가 나왔다: " .. tostring(key));
        check(ok == false, "빈 목록을 한 벌로 봤다");
        check(select(2, DebindPrivate.SharedKeyOf(nil)) == false, "nil을 한 벌로 봤다");
    end);

    -- **머리글과 캡처 창과 확인창이 도착분을 같은 이름으로 부르는 근거**(`ArrivalKeyOf`). 셋이
    -- 각자 걸으면 한 묶음이 자리마다 다르게 불리고, 읽는 쪽에는 서로 다른 묶음으로 보인다.
    test("ArrivalKeyOf: 다 같은 키로 왔으면 그 키", function()
        check(DebindPrivate.ArrivalKeyOf({
            { imported = "SHIFT-Q" }, { imported = "SHIFT-Q" },
        }) == "SHIFT-Q", "온 키를 못 냈다");
    end);

    -- 한 벌의 일부만 받아들인 상태. 배지를 뗀 쪽은 아무 말도 안 하므로, 남은 배지가 그 벌의
    -- 이름을 계속 진다.
    test("ArrivalKeyOf: 일부가 승인됐어도 남은 배지가 답한다", function()
        check(DebindPrivate.ArrivalKeyOf({
            { imported = nil }, { imported = "CTRL-3" },
        }) == "CTRL-3", "남은 배지를 못 읽었다");
    end);

    test("ArrivalKeyOf: 온 키가 갈리면 nil", function()
        check(DebindPrivate.ArrivalKeyOf({
            { imported = "F" }, { imported = "G" },
        }) == nil, "둘 중 하나를 골랐다");
    end);

    -- `true`는 "키 없이 왔다"다. 이름이 될 키가 없으므로 문자열과 같이 셀 수 없다.
    test("ArrivalKeyOf: 키 없이 온 것과 도착분이 아닌 것은 nil", function()
        check(DebindPrivate.ArrivalKeyOf({ { imported = true }, { imported = true } }) == nil,
            "키 없이 온 것에서 키가 나왔다");
        check(DebindPrivate.ArrivalKeyOf({ {}, {} }) == nil, "도착분이 아닌데 키가 나왔다");
        check(DebindPrivate.ArrivalKeyOf(nil) == nil, "nil에서 키가 나왔다");
    end);

    return T;
end
