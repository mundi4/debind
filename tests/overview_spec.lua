-- 오버뷰 왼쪽 열이 무엇을 모으고 어떤 차례로 내는가. `Profile.lua`의 두 수집 함수.
--
-- **오프스펙 액션이 여기 들어온다.** 한때 활성 레이어만 훑었고, 그래서 다른 전문화에 걸어둔
-- 것은 이 화면 어디에도 안 나왔다. 지금은 **자기가 활성이었다면 섰을 자리**에 선다 - 즉
-- 레이어 비교는 스코프까지만 보고, 그 안에서 활성이 먼저, 오프끼리는 특성 번호 차례다.
--
-- 이 파일이 지키는 것 둘:
--
--   * **활성 액션끼리의 차례는 한 칸도 안 바뀐다.** 바뀌면 저장 데이터는 그대로인데 전 사용자의
--     발동 순서가 조용히 달라지고, 공유 레이어 때문에 되돌리는 마이그레이션을 쓸 수가 없다.
--   * **A group that arrived without a key keeps the sender's order.** Those actions have no `seq`
--     (`ClearActionKey`, `PlaceInKeyGroup`), and in a string sent without keys `importOrder` is the
--     only thing the design has left.

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

    -- 이 스펙은 shim의 세계를 전제로 쓰였다: 드루이드(4특성), 활성 특성 1.
    check(CLASS == "DRUID", "드루이드 전제: " .. tostring(CLASS));
    check(C_SpecializationInfo.GetSpecialization() == 1,
        "활성 특성 1 전제: " .. tostring(C_SpecializationInfo.GetSpecialization()));

    --- `InitDB`가 읽는 모양 그대로 세운다. `class`/`char`는 특성 번호를 열쇠로 하는 표다.
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

    --- 행들이 어느 레이어에서 왔는지를 한 줄로. 실패했을 때 자리가 이름으로 나온다.
    local function LayerIDs(rows)
        local out = {};
        for i, row in ipairs(rows) do
            out[i] = tostring(row.layerID);
        end
        return table.concat(out, " ");
    end

    local function Spell(value, key, seq)
        return { type = Constants.SPELL, value = value, key = key, seq = seq };
    end

    ---------------------------------------------------------------------------
    -- 오프스펙이 자리를 갖는다
    ---------------------------------------------------------------------------

    -- `LAYER_INFOS`(Profile.lua)의 번호: 1 일반, 2~6 직업 특성0~4, 7~11 캐릭터 특성0~4.
    local GENERAL, CLASS_ALL, CLASS_SPEC1, CLASS_SPEC2 = 1, 2, 3, 4;
    local CHAR_ALL, CHAR_SPEC3 = 7, 10;

    -- **오프스펙은 자기 스코프 안에서 활성 바로 뒤에 선다.** 캐릭터/특성3은 활성이 아닌데도
    -- 직업/특성1(활성)보다 위인데, 그것이 이 규칙의 요점이다 - 자리는 "활성이었다면 어디였을까"가
    -- 정하고, 지금 안 돈다는 것은 사유 칸이 말한다.
    test("오프스펙 액션이 활성이었을 자리에 들어온다", function()
        ResetProfile({
            general = { Spell(1, "F", 1) },
            class = {
                [0] = { Spell(2, "F", 1) },
                [1] = { Spell(3, "F", 1) },
                [2] = { Spell(4, "F", 1) },
            },
            char = {
                [0] = { Spell(5, "F", 1) },
                [3] = { Spell(6, "F", 1) },
            },
        });

        local rows = DebindPrivate.CollectActionsForKey("F");
        local expected = table.concat({ CHAR_SPEC3, CHAR_ALL, CLASS_SPEC1, CLASS_SPEC2,
            CLASS_ALL, GENERAL }, " ");
        check(LayerIDs(rows) == expected, "차례: " .. LayerIDs(rows) .. " / 기대 " .. expected);
    end);

    test("활성 레이어의 행은 오프스펙 표를 안 단다", function()
        ResetProfile({
            class = { [1] = { Spell(1, "F", 1) }, [2] = { Spell(2, "F", 1) } },
        });

        local rows = DebindPrivate.CollectActionsForKey("F");
        check(#rows == 2, "행 수 " .. #rows);
        check((rows[1].specRank or 0) == 0, "활성 행에 특성 번호가 붙었다");
        check(rows[2].specRank == 2, "오프스펙 행의 특성 번호 " .. tostring(rows[2].specRank));
    end);

    -- **오프스펙끼리는 특성 번호 차례다.** `seq`로 가르면 안 된다 - 서로 다른 레이어의 번호라
    -- 같은 번호 공간이 아니고, 둘 다 1번을 들고 있는 것이 정상이다.
    test("오프스펙끼리는 특성 번호 차례", function()
        ResetProfile({
            class = {
                [4] = { Spell(1, "F", 1) },
                [2] = { Spell(2, "F", 9) },
                [3] = { Spell(3, "F", 5) },
            },
        });

        local rows = DebindPrivate.CollectActionsForKey("F");
        local expected = table.concat({ CLASS_SPEC2, CLASS_SPEC2 + 1, CLASS_SPEC2 + 2 }, " ");
        check(LayerIDs(rows) == expected, "차례: " .. LayerIDs(rows) .. " / 기대 " .. expected);
    end);

    -- **활성 액션끼리의 차례는 그대로다.** 오프스펙을 열면서 layerRank의 값이 바뀌었으므로
    -- (순회 번호 -> 스코프 순위), 그 값에 기대던 순서가 흔들리지 않았는지 여기서 못 박는다.
    test("활성끼리의 차례는 예전 그대로", function()
        ResetProfile({
            general = { Spell(1, "F", 1) },
            class = { [0] = { Spell(2, "F", 1) }, [1] = { Spell(3, "F", 1) } },
            char = { [0] = { Spell(4, "F", 1) }, [1] = { Spell(5, "F", 1) } },
        });

        local rows = DebindPrivate.CollectActionsForKey("F");
        local expected = table.concat({ CHAR_SPEC3 - 2, CHAR_ALL, CLASS_SPEC1, CLASS_ALL,
            GENERAL }, " ");
        check(LayerIDs(rows) == expected, "차례: " .. LayerIDs(rows) .. " / 기대 " .. expected);
    end);

    -- 중요도가 먼저 갈리면 레이어도 특성도 안 본다. 새 단계가 앞의 것들을 밀어내지 않았다는 것.
    test("중요도가 레이어보다 먼저다", function()
        ResetProfile({
            general = { { type = Constants.SPELL, value = 1, key = "F", seq = 1, priority = 1 } },
            char = { [3] = { Spell(2, "F", 1) } },
        });

        local rows = DebindPrivate.CollectActionsForKey("F");
        check(rows[1].layerID == GENERAL, "중요도 높은 쪽이 먼저여야 한다: " .. LayerIDs(rows));
    end);

    ---------------------------------------------------------------------------
    -- 키 없는 것들
    ---------------------------------------------------------------------------

    -- With no key there is no `seq` at all (`ClearActionKey`, `PlaceInKeyGroup`). The sender's order
    -- is in `importOrder`, and the comparator reads it in `seq`'s slot.
    test("도착 그룹은 importOrder 차례로 선다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 3, imported = 1, importGroup = 7, importOrder = 3 },
                { type = Constants.SPELL, value = 1, imported = 1, importGroup = 7, importOrder = 1 },
                { type = Constants.SPELL, value = 2, imported = 1, importGroup = 7, importOrder = 2 },
            },
        });

        local rows = DebindPrivate.CollectKeylessActionRows(7);
        check(#rows == 3, "행 수 " .. #rows);
        for i, row in ipairs(rows) do
            check(row.action.value == i,
                i .. "번째가 value=" .. tostring(row.action.value));
        end
    end);

    -- 한 그룹이 레이어를 넘어도 한 묶음으로 선다. 도착할 때부터 그렇고(`PlanImport`), 도착한 뒤
    -- `MoveAction`이 더 벌려놓을 수도 있다.
    test("도착 그룹이 레이어를 넘어도 한 묶음으로 모인다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 2, imported = 1, importGroup = 7, importOrder = 2 },
            },
            class = {
                [0] = {
                    { type = Constants.SPELL, value = 1, imported = 1, importGroup = 7, importOrder = 1 },
                },
            },
        });

        local rows = DebindPrivate.CollectKeylessActionRows(7);
        check(#rows == 2, "행 수 " .. #rows);
        check(rows[1].action.value == 1 and rows[2].action.value == 2,
            "importOrder 차례가 아니다");
    end);

    -- **키를 뗀 액션은 번호를 남긴다**(`SetActionKey` - 뗐다 다시 걸 때 자리를 지키려는 것).
    -- 그 남은 번호가 순서까지 정하면, 잠깐 키를 걸었다 뗀 도착 그룹 멤버가 자기 `importOrder`를
    -- 잃고 엉뚱한 자리로 간다. 저장은 그대로 두고 읽는 쪽에서 무시한다.
    test("키를 뗀 뒤 남은 seq가 importOrder를 못 이긴다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, imported = 1, importGroup = 7, importOrder = 1 },
                -- 한 번 키가 걸렸다 떨어진 것. 저장에는 번호가 남아 있다.
                { type = Constants.SPELL, value = 2, imported = 1, importGroup = 7, importOrder = 2,
                  seq = 99 },
                { type = Constants.SPELL, value = 3, imported = 1, importGroup = 7, importOrder = 3 },
            },
        });

        local rows = DebindPrivate.CollectKeylessActionRows(7);
        check(#rows == 3, "행 수 " .. #rows);
        for i, row in ipairs(rows) do
            check(row.action.value == i,
                i .. "번째가 value=" .. tostring(row.action.value));
        end
    end);

    test("그룹 없는 키 없는 액션은 그룹 목록에 안 섞인다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, imported = 1, importGroup = 7, importOrder = 1 },
                { type = Constants.SPELL, value = 2 },
            },
        });

        check(#DebindPrivate.CollectKeylessActionRows(7) == 1, "그룹에 남이 끼었다");
        local plain = DebindPrivate.CollectKeylessActionRows(nil);
        check(#plain == 1 and plain[1].action.value == 2, "그룹 없는 쪽이 안 나왔다");
    end);

    return T;
end
