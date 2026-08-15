-- 키 그룹째 키를 주는 것. `Profile.lua`의 `SetKeyForActions`와 그 앞에 서는 두 수집 함수.
--
-- **이 파일이 지키는 것은 보낸 사람의 순서다.** 키가 빠진 문자열에서 `importOrder`는 설계의
-- 유일한 잔존물인데(`devdocs/building-export-import.md`), 액션에 하나씩 키를 주면 그 순서가
-- 조용히 사라진다 - `seq`는 만진 차례대로 발급되지 그 액션이 몇 번째였는지를 안 본다.
-- 그래서 그룹째 주는 조작은 편의가 아니라 순서를 지키는 유일한 길이다.
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

    --- One member of an arrival group. No key and no `seq` -- a keyless action is never given a
    --- number (`PlaceInKeyGroup`), and `importOrder` holds that slot instead.
    local function Arrived(value, group, order)
        return {
            type = Constants.SPELL, value = value,
            imported = 1, importGroup = group, importOrder = order,
        };
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

    -- **저장 배열의 차례와 `importOrder`를 일부러 어긋나게 세운다.** 둘이 같으면 이 테스트는
    -- 아무것도 안 재는데, 정확히 그 어긋남이 한 액션씩 키를 줄 때 순서가 사라지는 자리다.
    -- 그리고 레이어에 이미 번호 7이 나가 있어서, 새 번호는 8부터 나온다.
    test("그룹째 키를 주면 seq가 importOrder 차례로 나온다", function()
        ResetProfile({
            general = {
                Bound(99, "G", 7),
                Arrived(30, 1, 3),
                Arrived(10, 1, 1),
                Arrived(20, 1, 2),
            },
        });

        local group = DebindPrivate.CollectImportGroupActions(1);
        check(#group == 3, "그룹 크기 " .. #group);
        DebindPrivate.SetKeyForActions(group, "F");

        -- 발동 순서를 그리는 쪽에 물어본다. `seq`를 직접 읽으면 방금 넣은 값을 되읽는 셈이다.
        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "10 20 30", "차례: " .. Values(rows));
    end);

    test("이미 나간 번호 뒤에서 시작한다", function()
        ResetProfile({
            general = { Bound(99, "F", 7), Arrived(10, 1, 1), Arrived(20, 1, 2) },
        });

        DebindPrivate.SetKeyForActions(DebindPrivate.CollectImportGroupActions(1), "F");

        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "99 10 20", "차례: " .. Values(rows));
    end);

    -- **잠깐 키를 걸었다 뗀 멤버가 자기 그룹을 앞지르면 안 된다.** 키를 떼도 `seq`는 남는데
    -- (`SetActionKey`), 그 남은 번호를 그대로 두면 그 액션만 다른 번호 공간에서 줄을 선다.
    test("남아 있는 seq가 importOrder를 이기지 않는다", function()
        ResetProfile({
            general = {
                Arrived(30, 1, 3),
                Arrived(10, 1, 1),
                Arrived(20, 1, 2),
            },
        });
        -- 30을 잠깐 걸었다 뗀 자국. 하필 제일 작은 번호라, 이것을 자리로 읽으면 30이 맨
        -- 앞으로 온다.
        DebindPrivate.GetProfileLayer(1):GetAction(1).seq = 1;

        DebindPrivate.SetKeyForActions(DebindPrivate.CollectImportGroupActions(1), "F");

        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "10 20 30", "차례: " .. Values(rows));
    end);

    -- **레이어마다 자기 번호를 낸다.** `seq`는 한 레이어 안에서만 뜻이 있어서 그래야 맞고,
    -- 그룹 안의 차례는 레이어 안에서 지켜지면 된다 - 레이어끼리는 비교자가 먼저 가른다.
    test("레이어를 가로지르는 그룹도 각 레이어 안에서 importOrder 차례다", function()
        ResetProfile({
            general = { Arrived(30, 1, 3), Arrived(10, 1, 1) },
            class = { [0] = { Bound(99, "F", 4), Arrived(40, 1, 4), Arrived(20, 1, 2) } },
        });

        local group = DebindPrivate.CollectImportGroupActions(1);
        check(#group == 4, "그룹 크기 " .. #group);
        DebindPrivate.SetKeyForActions(group, "F");

        -- 직업/공용이 일반보다 위다(스코프). 그 안에서 99는 이미 4번을 들고 있으므로 앞이다.
        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "99 20 40 10 30", "차례: " .. Values(rows));
    end);

    test("키를 주면 배지와 그룹과 순서가 같이 사라진다", function()
        ResetProfile({ general = { Arrived(10, 1, 1), Arrived(20, 1, 2) } });

        local group = DebindPrivate.CollectImportGroupActions(1);
        DebindPrivate.SetKeyForActions(group, "F");

        for _, action in ipairs(group) do
            check(action.key == "F", "키가 안 걸렸다: " .. tostring(action.value));
            check(action.imported == nil, "배지가 남았다: " .. tostring(action.value));
            check(action.importGroup == nil, "그룹이 남았다: " .. tostring(action.value));
            check(action.importOrder == nil, "순서가 남았다: " .. tostring(action.value));
        end
        check(#DebindPrivate.CollectImportGroupActions(1) == 0, "그룹이 아직 모인다");
    end);

    ---------------------------------------------------------------------------
    -- 키를 이미 들고 있던 그룹을 옮기는 것
    ---------------------------------------------------------------------------

    -- Merging, replacing and overwriting all stand on this. These actions have no `importOrder`, so
    -- `seq` is what says where each one stands, and the set that moved lands at the back of the
    -- destination group -- what `PlaceInKeyGroup` does for anything arriving.
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
        return DebindPrivate.CollectImportGroupActions(1), DebindPrivate.CollectKeyGroupActions("F");
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

        local group = DebindPrivate.CollectImportGroupActions(2);
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

        check(#DebindPrivate.CollectImportGroupActions(1) == 2,
            "그룹 " .. #DebindPrivate.CollectImportGroupActions(1));
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

        local group = DebindPrivate.CollectImportGroupActions(1);
        check(#group == 1, "그룹 크기 " .. #group);
        check(#DebindPrivate.CollectKeyGroupActions("F") == 0,
            "점유자 " .. #DebindPrivate.CollectKeyGroupActions("F"));

        DebindPrivate.SetKeyForActions(group, "F");

        local stranger = _G.DebindVars.shared.classes.MAGE[0];
        check(stranger[1].key == nil, "남의 레이어에 키가 걸렸다");
        check(stranger[1].importGroup == 1, "남의 레이어에서 그룹이 지워졌다");
        check(stranger[2].seq == 1, "남의 레이어의 번호가 바뀌었다");
    end);

    test("nil을 주면 아무것도 안 모은다", function()
        ResetProfile({ general = { Bound(10, "F", 1), Arrived(20, 1, 1) } });

        check(#DebindPrivate.CollectImportGroupActions(nil) == 0, "그룹 nil이 뭔가를 모았다");
        check(#DebindPrivate.CollectKeyGroupActions(nil) == 0, "키 nil이 뭔가를 모았다");
    end);

    return T;
end
