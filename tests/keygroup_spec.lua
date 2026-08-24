-- 키 그룹째 키를 주는 것. `Profile.lua`의 `SetKeyForActions`와 그 앞에 서는 수집 함수.
--
-- **이 파일이 지키는 것은 보낸 사람의 순서다.** 도착분이 나르는 설계의 잔존물이 그것뿐인데
-- (`devdocs/building-export-import.md`), 액션에 하나씩 키를 주면 조용히 사라진다 - `seq`는 만진
-- 차례대로 발급되지 그 액션이 몇 번째였는지를 안 본다. 그래서 그룹째 주는 조작은 편의가 아니라
-- 순서를 지키는 유일한 길이다.
--
-- 나머지 셋:
--
--   * **그룹은 `(key, arrivalID)` 쌍이다.** 도착분은 보낸 사람의 실키를 그대로 들고 오므로 한
--     키 위에 두 벌이 앉는 것이 예사다. 키만 보고 모으면 격리된 것이 점유자로 세어진다.
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

    --- 한 arrival이 놓고 간 액션. **키는 보낸 사람의 실키 그대로**이고, 발동에서 빠져 있다는
    --- 것과 어느 그룹이냐를 `arrivalID`가 함께 답한다. `seq`는 그 그룹 안의 자리다.
    local function Arrived(value, key, seq, arrivalID)
        return { type = Constants.SPELL, value = value, key = key, seq = seq,
                 arrivalID = arrivalID or 1 };
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
    -- 그리고 레이어에 이미 번호 7이 나가 있어서, 승인된 셋은 그 뒤에 서야 한다.
    test("그룹째 키를 주면 실려온 차례가 지켜진다", function()
        ResetProfile({
            general = {
                Bound(99, "G", 7),
                Arrived(30, "Q", 3),
                Arrived(10, "Q", 1),
                Arrived(20, "Q", 2),
            },
        });

        local group = DebindPrivate.CollectKeyGroupActions("Q", 1);
        check(#group == 3, "그룹 크기 " .. #group);
        DebindPrivate.SetKeyForActions(group, "F");

        -- 발동 순서를 그리는 쪽에 물어본다. `seq`를 직접 읽으면 방금 넣은 값을 되읽는 셈이다.
        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "10 20 30", "차례: " .. Values(rows));
    end);

    test("이미 그 키에 있던 것 뒤에 선다", function()
        ResetProfile({
            general = { Bound(99, "F", 7), Arrived(10, "Q", 1), Arrived(20, "Q", 2) },
        });

        DebindPrivate.SetKeyForActions(DebindPrivate.CollectKeyGroupActions("Q", 1), "F");

        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "99 10 20", "차례: " .. Values(rows));
    end);

    -- **레이어마다 자기 번호를 낸다.** `seq`는 한 레이어 안에서만 뜻이 있어서 그래야 맞고,
    -- 그룹 안의 차례는 레이어 안에서 지켜지면 된다 - 레이어끼리는 비교자가 먼저 가른다.
    test("레이어를 가로지르는 그룹도 각 레이어 안에서 차례를 지킨다", function()
        ResetProfile({
            general = { Arrived(30, "Q", 3), Arrived(10, "Q", 1) },
            class = { [0] = { Bound(99, "F", 4), Arrived(40, "Q", 4), Arrived(20, "Q", 2) } },
        });

        local group = DebindPrivate.CollectKeyGroupActions("Q", 1);
        check(#group == 4, "그룹 크기 " .. #group);
        DebindPrivate.SetKeyForActions(group, "F");

        -- 직업/공용이 일반보다 위다(스코프). 그 안에서 99는 이미 4번을 들고 있으므로 앞이다.
        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "99 20 40 10 30", "차례: " .. Values(rows));
    end);

    test("키를 주면 배지가 같이 떨어진다", function()
        ResetProfile({ general = { Arrived(10, "Q", 1), Arrived(20, "Q", 2) } });

        local group = DebindPrivate.CollectKeyGroupActions("Q", 1);
        DebindPrivate.SetKeyForActions(group, "F");

        for _, action in ipairs(group) do
            check(action.key == "F", "키가 안 걸렸다: " .. tostring(action.value));
            check(action.arrivalID == nil, "배지가 남았다: " .. tostring(action.value));
        end
        check(#DebindPrivate.CollectKeyGroupActions("Q", 1) == 0, "옛 자리로 아직 모인다");
    end);

    -- **떠난 그룹도 번호를 다시 매긴다.** 승인은 `(Q, 1)`에서 `(Q, nil)`로 옮기는 것이기도
    -- 한데, 키만 보면 그 둘이 한 그룹이라 떠난 자리는 영영 안 훑인다.
    test("한 명만 승인해도 남은 동료들의 번호가 닫힌다", function()
        ResetProfile({
            general = { Arrived(10, "Q", 1), Arrived(20, "Q", 2), Arrived(30, "Q", 3) },
        });

        local group = DebindPrivate.CollectKeyGroupActions("Q", 1);
        DebindPrivate.SetKeyForActions({ group[1] }, "Q");

        local left = DebindPrivate.CollectKeyGroupActions("Q", 1);
        check(#left == 2, "남은 그룹 크기 " .. #left);
        local seqs = {};
        for i, action in ipairs(left) do seqs[i] = action.seq; end
        table.sort(seqs);
        check(seqs[1] == 1 and seqs[2] == 2,
            "번호가 안 닫혔다: " .. tostring(seqs[1]) .. " " .. tostring(seqs[2]));
    end);

    ---------------------------------------------------------------------------
    -- 한 키 위의 두 그룹
    ---------------------------------------------------------------------------

    -- **배지가 붙어 있는 동안은 실키를 들고도 키맵에 안 선다.** 이 개편 전체가 그 한 줄 위에
    -- 서 있다(`BuildKeyMap`) - 도착분이 보낸 사람의 실키를 그대로 들고 오니 키 값으로는 내 것과
    -- 구분이 안 되고, 막아주는 것은 배지 하나뿐이다. 예전에는 키가 숫자라는 것이 두 번째 자물쇠
    -- 였는데 그 숫자를 없앴다(`devdocs/building-export-import.md` 12절). 여기가 빨개지면 남의
    -- 문자열을 받는 순간 남의 키가 내 키보드에서 돈다.
    test("배지 달린 것은 실키를 들고도 키맵에 안 선다", function()
        ResetProfile({ general = { Arrived(10, "F", 1, 7) } });

        DebindPrivate.BuildKeyMap();
        check(DebindPrivate.KeyMap["F"] == nil, "배지 달린 것이 키맵에 섰다");

        -- **승인하면 선다.** 이게 없으면 위 줄은 "F는 원래 안 선다"와 구분이 안 되고, 게이트가
        -- 통째로 막혀 있어도 통과한다.
        DebindPrivate.SetKeyForActions(DebindPrivate.CollectKeyGroupActions("F", 7), "F");
        DebindPrivate.BuildKeyMap();
        check(DebindPrivate.KeyMap["F"] ~= nil, "승인했는데 키맵에 안 선다");
    end);

    -- **도착분이 보낸 사람의 실키를 그대로 들고 온다.** 그러면 내 것과 같은 키 위에 앉는데, 그
    -- 둘은 서로 다른 그룹이어야 한다 - 격리된 것은 아무 키도 안 차지하고 있으므로
    -- (`BuildKeyMap`이 건너뛴다), 점유자로 세면 사용자가 설명할 수 없는 숫자가 나온다.
    test("같은 키라도 arrival이 다르면 다른 그룹이다", function()
        ResetProfile({
            general = {
                Bound(50, "F", 1),
                Arrived(10, "F", 1, 7),
                Arrived(20, "F", 2, 7),
                Arrived(30, "F", 1, 9),
            },
        });

        check(#DebindPrivate.CollectKeyGroupActions("F", nil) == 1, "내 것만 나와야 한다");
        check(#DebindPrivate.CollectKeyGroupActions("F", 7) == 2, "7번 arrival이 둘");
        check(#DebindPrivate.CollectKeyGroupActions("F", 9) == 1, "9번 arrival이 하나");
    end);

    -- **승인이 도착분을 내 그룹 뒤에 세운다.** `/debtest`가 재던 것인데 거기서 두 번 빨개졌고
    -- 둘 다 이 층에서 1초면 났을 것이다. 여기 있는 이유가 그거다.
    --
    -- **둘 다 조건을 지되 축이 다르다.** 축이 달라야 둘 다 남고, 둘 다 조건부여야 비교자가
    -- `seq`까지 내려온다 - `isConditional`이 3단계고 `seq`는 6단계다(`Ordering.lua`). 한쪽만
    -- 조건부면 이 테스트는 순서와 무관하게 그쪽을 먼저 낸다.
    test("승인하면 도착분이 내 그룹 뒤에 선다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F", seq = 1,
                  conditions = { stealth = true } },
                { type = Constants.SPELL, value = 2, key = "F", seq = 1, arrivalID = 7,
                  conditions = { combat = true } },
            },
        });

        local group = DebindPrivate.CollectKeyGroupActions("F", 7);
        check(#group == 1, "도착 그룹 " .. #group);
        DebindPrivate.SetKeyForActions(group, "F");

        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "1 2", "차례: " .. Values(rows));
    end);

    -- 같은 자리에서 **한쪽만 조건부이면 순서가 뒤집힌다**는 것도 못 박는다. 위 테스트가 그
    -- 이유로 두 번 빨개졌으니, 그것이 규칙이라는 것을 여기 적어두지 않으면 다음 사람이 위
    -- 테스트의 조건 하나를 지우고 같은 하루를 다시 산다.
    test("한쪽만 조건부면 조건부가 먼저다 - seq는 안 읽힌다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F", seq = 1 },
                { type = Constants.SPELL, value = 2, key = "F", seq = 1, arrivalID = 7,
                  conditions = { combat = true } },
            },
        });

        DebindPrivate.SetKeyForActions(DebindPrivate.CollectKeyGroupActions("F", 7), "F");

        local rows = DebindPrivate.CollectActionsForKey("F");
        check(Values(rows) == "2 1", "차례: " .. Values(rows));
    end);

    -- 한쪽에 키를 줘도 다른 쪽 번호는 그대로다. 번호가 그룹 밖으로 새면 조용히 순서가 밀린다.
    test("한 arrival을 승인해도 옆 arrival의 번호는 그대로다", function()
        ResetProfile({
            general = {
                Arrived(10, "F", 1, 7), Arrived(20, "F", 2, 7),
                Arrived(30, "F", 1, 9), Arrived(40, "F", 2, 9),
            },
        });

        DebindPrivate.SetKeyForActions(DebindPrivate.CollectKeyGroupActions("F", 7), "F");

        local other = DebindPrivate.CollectKeyGroupActions("F", 9);
        check(#other == 2, "옆 그룹 크기 " .. #other);
        for _, action in ipairs(other) do
            check(action.arrivalID == 9, "옆 그룹의 배지가 떨어졌다: " .. tostring(action.value));
            check(action.seq == 1 or action.seq == 2, "번호가 밀렸다: " .. tostring(action.seq));
        end
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
                Arrived(10, "Q", 1),
                Arrived(20, "Q", 2),
            },
        });
        return DebindPrivate.CollectKeyGroupActions("Q", 1),
            DebindPrivate.CollectKeyGroupActions("F");
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
            -- Nothing is deleted, though the set itself is gone: four keyless actions are four
            -- keyless actions, which is why the caller asks first.
            check(action.seq == nil, "번호가 남았다: " .. tostring(action.value));
        end
    end);

    -- **격리된 것은 점유자가 아니다.** 배지를 단 채로 F에 앉아 있는 것은 아무것도 안 차지하고
    -- 있으므로, F를 달라는 그룹이 그것을 밀어낼 이유가 없다.
    test("덮어쓰기는 같은 키의 격리된 것을 안 건드린다", function()
        ResetProfile({
            general = {
                Bound(50, "F", 1),
                Arrived(70, "F", 1, 7),
                Arrived(10, "Q", 1, 9),
            },
        });

        local group = DebindPrivate.CollectKeyGroupActions("Q", 9);
        local occupants = DebindPrivate.CollectKeyGroupActions("F");
        check(#occupants == 1, "점유자 " .. #occupants);

        DebindPrivate.MoveKeyGroupToKey(group, "F", occupants, true);

        local quarantined = DebindPrivate.CollectKeyGroupActions("F", 7);
        check(#quarantined == 1, "격리된 것이 없어졌다");
        check(quarantined[1].key == "F", "격리된 것의 키가 풀렸다");
        check(quarantined[1].arrivalID == 7, "격리된 것의 배지가 떨어졌다");
    end);

    ---------------------------------------------------------------------------
    -- 어디까지 모으나
    ---------------------------------------------------------------------------

    -- **오프스펙 레이어는 범위 안이다.** 그 액션들은 이제 왼쪽 열에 그려지고, 지금 안 돈다는
    -- 것만 사유 칸이 말한다(`devdocs/legacy/showing-off-spec-actions.md`).
    test("그룹도 점유자도 오프스펙 레이어까지 모은다", function()
        ResetProfile({
            class = {
                [1] = { Arrived(10, "Q", 1), Bound(50, "F", 1) },
                [3] = { Arrived(20, "Q", 2), Bound(60, "F", 1) },
            },
        });

        check(#DebindPrivate.CollectKeyGroupActions("Q", 1) == 2,
            "그룹 " .. #DebindPrivate.CollectKeyGroupActions("Q", 1));
        check(#DebindPrivate.CollectKeyGroupActions("F") == 2,
            "점유자 " .. #DebindPrivate.CollectKeyGroupActions("F"));
    end);

    -- **다른 직업의 레이어는 범위 밖이다.** 이 세션의 `LayerArray`에 없고, 그쪽 키보드는 이
    -- 결정이 서 있는 키보드가 아니다. 그룹은 거기서 배지를 단 채로 남아 그 직업으로 접속했을
    -- 때 자기 키를 받는다.
    test("다른 직업의 레이어는 모으지도 건드리지도 않는다", function()
        ResetProfile({
            general = { Arrived(10, "Q", 1) },
            otherClass = { [0] = { Arrived(20, "Q", 2), Bound(60, "F", 1) } },
        });

        local group = DebindPrivate.CollectKeyGroupActions("Q", 1);
        check(#group == 1, "그룹 크기 " .. #group);
        check(#DebindPrivate.CollectKeyGroupActions("F") == 0,
            "점유자 " .. #DebindPrivate.CollectKeyGroupActions("F"));

        DebindPrivate.SetKeyForActions(group, "F");

        local stranger = _G.DebindVars.shared.classes.MAGE[0];
        check(stranger[1].key == "Q", "남의 레이어의 멤버까지 키가 바뀌었다");
        check(stranger[2].seq == 1, "남의 레이어의 번호가 바뀌었다");
    end);

    test("nil을 주면 아무것도 안 모은다", function()
        ResetProfile({ general = { Bound(10, "F", 1), Arrived(20, "Q", 1) } });

        check(#DebindPrivate.CollectKeyGroupActions(nil) == 0, "키 nil이 뭔가를 모았다");
    end);

    ---------------------------------------------------------------------------
    -- 그룹째 키를 빼는 것
    --
    -- **키를 지우면 그룹이 없어진다.** 붙들어 둘 번호가 없다 - 그것이 합성 키였고, 없앤 사유는
    -- `devdocs/building-export-import.md` 12절에 있다. 그래서 이 조작은 되돌릴 수 없고, 묻는
    -- 것은 `DebindUI.UnbindActions`의 몫이다.
    ---------------------------------------------------------------------------

    test("여러 개짜리 그룹을 풀면 낱개로 흩어진다", function()
        ResetProfile({
            general = { Bound(10, "F", 1), Bound(20, "F", 2), Bound(30, "F", 3) },
        });

        local group = DebindPrivate.CollectKeyGroupActions("F");
        check(#group == 3, "그룹 크기 " .. #group);
        DebindPrivate.ClearKeyForActions(group);

        for _, action in ipairs(group) do
            check(action.key == nil, "키가 남았다: " .. tostring(action.value));
            check(action.seq == nil, "번호가 남았다: " .. tostring(action.value));
        end
        check(#DebindPrivate.CollectKeyGroupActions("F") == 0, "F에 남은 것이 있다");
    end);

    test("하나짜리를 풀면 키가 없어진다", function()
        ResetProfile({ general = { Bound(10, "F", 1) } });

        local group = DebindPrivate.CollectKeyGroupActions("F");
        check(#group == 1, "그룹 크기 " .. #group);
        DebindPrivate.ClearKeyForActions(group);

        check(group[1].key == nil, "키가 남았다: " .. tostring(group[1].key));
        check(group[1].seq == nil, "번호가 남았다: " .. tostring(group[1].seq));
    end);

    -- **푼 그룹은 배지를 안 얻는다.** 키를 잃는 것은 어디서 왔느냐에 대해 아무 말도 아니고,
    -- 배지를 붙이면 사용자가 승인한 적 없는 대기 줄이 저절로 생긴다.
    test("풀어도 배지가 생기지 않는다", function()
        ResetProfile({ general = { Bound(10, "F", 1), Bound(20, "F", 2) } });

        local group = DebindPrivate.CollectKeyGroupActions("F");
        DebindPrivate.ClearKeyForActions(group);

        for _, action in ipairs(group) do
            check(action.arrivalID == nil, "배지가 붙었다: " .. tostring(action.value));
        end
    end);

    -- **격리된 것을 풀면 배지는 남는다.** 키를 잃는 것은 어디서 왔느냐에 대한 답이 아니다.
    test("격리된 그룹을 풀어도 배지는 남는다", function()
        ResetProfile({ general = { Arrived(10, "F", 1, 7), Arrived(20, "F", 2, 7) } });

        local group = DebindPrivate.CollectKeyGroupActions("F", 7);
        check(#group == 2, "그룹 크기 " .. #group);
        DebindPrivate.ClearKeyForActions(group);

        for _, action in ipairs(group) do
            check(action.key == nil, "키가 남았다: " .. tostring(action.value));
            check(action.arrivalID == 7, "배지가 떨어졌다: " .. tostring(action.value));
        end
    end);

    -- **한 벌인지 골라놓은 것인지를 이 함수 하나가 답한다**(`SharedKeyOf`). 창도 커밋도 여기서
    -- 갈리므로, 둘이 서로 다른 답을 보면 화면이 그리는 것과 눌렀을 때 일어나는 일이 어긋난다.
    --
    -- **nil이 두 번 나오는 자리라 플래그를 같이 잰다.** "키를 안 나눠 쓴다"와 "다 같이 키가
    -- 없다"는 첫 반환값이 똑같고, 둘을 섞으면 키 없는 여럿이 한 벌로 취급된다.
    test("SharedKeyOf: 같은 키면 그 키와 참", function()
        local shared = { { key = "F" }, { key = "F" }, { key = "F" } };
        local key, ok = DebindPrivate.SharedKeyOf(shared);
        check(key == "F", "키가 다르다: " .. tostring(key));
        check(ok == true, "한 벌로 안 봤다");
    end);

    test("SharedKeyOf: 제각각이면 nil과 거짓", function()
        local key, ok = DebindPrivate.SharedKeyOf({ { key = "F" }, { key = "G" } });
        check(key == nil, "키가 나왔다: " .. tostring(key));
        check(ok == false, "제각각인데 한 벌로 봤다");

        -- 하나만 키가 없어도 제각각이다.
        key, ok = DebindPrivate.SharedKeyOf({ { key = "F" }, {} });
        check(ok == false, "키 없는 하나가 섞였는데 한 벌로 봤다");
    end);

    -- **키가 같아도 arrival이 갈리면 한 벌이 아니다.** 그 둘은 화면에서도 머리글이 둘이고, 한
    -- 벌로 읽으면 [키 설정]이 격리된 것까지 같이 옮긴다.
    test("SharedKeyOf: arrival이 갈리면 한 벌이 아니다", function()
        local key, ok = DebindPrivate.SharedKeyOf({
            { key = "F" }, { key = "F", arrivalID = 7 },
        });
        check(key == nil, "키가 나왔다: " .. tostring(key));
        check(ok == false, "arrival이 갈렸는데 한 벌로 봤다");

        _, ok = DebindPrivate.SharedKeyOf({
            { key = "F", arrivalID = 7 }, { key = "F", arrivalID = 9 },
        });
        check(ok == false, "다른 두 arrival을 한 벌로 봤다");

        key, ok = DebindPrivate.SharedKeyOf({
            { key = "F", arrivalID = 7 }, { key = "F", arrivalID = 7 },
        });
        check(key == "F" and ok == true, "같은 arrival의 한 벌을 못 알아봤다");
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

    return T;
end
