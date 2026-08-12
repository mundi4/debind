-- 진짜 SavedVariables 파일로 마이그레이션을 검증한다. 와우 클라이언트 불필요.
--
-- **마이그레이션은 입력을 파괴한다.** 한 번 돌면 옛 형식의 데이터가 사라지고, 나중에 버그를
-- 찾아 고쳐도 **고친 코드를 먹여볼 입력이 없다.** 그래서 각 버전의 파일을 하나씩 얼려두고
-- 그것으로 다시 태운다. 표본은 `.zzz/savedvars/<dbverN>/*.lua`에 있다.
--
-- 검사하는 것은 값의 생김새가 아니라 **뜻**이다. 마이그레이션은 표현만 바꿔야 하므로,
-- 액션 하나하나에 대해 소비자가 보는 것이 전후로 같아야 한다:
--
--   solver  `binding.unitStates` (유닛 축 마스크) 와 `unitStatesOpaque`
--   런타임  스니펫에 내려가는 스칼라
--
-- 하나라도 다르면 그 액션은 사용자가 걸어둔 것과 다른 일을 하게 된 것이다.
--
-- ⚠ `.zzz`는 gitignore다. 표본이 없는 환경(CI, 새로 받은 저장소)에서는 **아무것도 검사하지
-- 않으므로**, 몇 개를 봤는지 항상 찍는다. 0을 조용히 통과로 읽으면 이 파일은 없는 것만
-- 못하다.

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

    ---------------------------------------------------------------------------
    -- 표본 찾기
    ---------------------------------------------------------------------------

    --- 저장소 루트. `run.lua`가 `arg[0]`을 자기 경로로 채워준다.
    local repoRoot = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]run%.lua$") or ".";
    local fixtureDir = repoRoot .. "/.zzz/savedvars/dbver4";

    --- 디렉터리 목록을 못 읽으므로(순수 Lua) 이름을 하나씩 열어본다. 표본은 계정 폴더에서
    --- 옮겨온 것이라 이름이 정해져 있다.
    local FIXTURE_NAMES = { "Debind-account1.lua", "Debind-account5.lua" };

    local function LoadFixture(name)
        local path = fixtureDir .. "/" .. name;
        local chunk = loadfile(path);
        if (not chunk) then
            return nil;
        end
        -- SavedVariables는 전역에 대입하는 평범한 Lua 파일이다.
        _G.DebindVars = nil;
        _G.DebounceVars = nil;
        _G.DebounceVarsPerChar = nil;
        chunk();
        return _G.DebindVars;
    end

    ---------------------------------------------------------------------------
    -- 액션 모으기
    --
    -- 액션이 사는 곳 셋을 전부 훑는다. 여기서 한 곳을 빠뜨리면 그 레이어는 검사 없이
    -- 지나가는데, 그게 정확히 마이그레이션이 빠뜨릴 수 있는 자리와 같은 목록이다.
    ---------------------------------------------------------------------------

    local function CollectLayer(out, layerTbl, where)
        if (type(layerTbl) ~= "table") then
            return;
        end
        for i = 1, #layerTbl do
            out[#out + 1] = { action = layerTbl[i], where = where .. "[" .. i .. "]" };
        end
    end

    local function CollectSpecTable(out, specTbl, where)
        if (type(specTbl) ~= "table") then
            return;
        end
        for spec = 0, 5 do
            CollectLayer(out, specTbl[spec], where .. "[" .. spec .. "]");
        end
    end

    local function CollectActions(db)
        local out = {};
        if (db.shared) then
            CollectLayer(out, db.shared.GENERAL, "shared.GENERAL");
            if (db.shared.classes) then
                for class, classTbl in pairs(db.shared.classes) do
                    CollectSpecTable(out, classTbl, "shared.classes." .. class);
                end
            end
        end
        if (db.characters) then
            for guid, charEntry in pairs(db.characters) do
                CollectSpecTable(out, charEntry.layers, "characters." .. guid .. ".layers");
            end
        end
        return out;
    end

    ---------------------------------------------------------------------------
    -- 한 액션이 소비자에게 어떻게 보이는가
    ---------------------------------------------------------------------------

    local function DerivedOf(action)
        local binding = DebindPrivate.GetBindingInfoForAction(action, true);

        local states;
        if (binding.unitStates) then
            states = {};
            for unit, mask in pairs(binding.unitStates) do
                states[unit] = mask;
            end
        end

        local scalars;
        if (binding.checkedUnits) then
            scalars = {};
            for unit, value in pairs(binding.checkedUnits) do
                scalars[unit] = DebindPrivate.UnitConditionToRuntimeScalar(value);
            end
        end

        return { states = states, scalars = scalars, opaque = binding.unitStatesOpaque };
    end

    local function DiffMaps(a, b, label, where)
        a, b = a or {}, b or {};
        for k, v in pairs(a) do
            if (b[k] ~= v) then
                error(("%s: %s[%s]가 %s -> %s로 바뀜")
                    :format(where, label, tostring(k), tostring(v), tostring(b[k])), 0);
            end
        end
        for k, v in pairs(b) do
            if (a[k] ~= v) then
                error(("%s: %s[%s]가 없다가 %s로 생김")
                    :format(where, label, tostring(k), tostring(v)), 0);
            end
        end
    end

    ---------------------------------------------------------------------------
    -- 본 검사
    ---------------------------------------------------------------------------

    local totalActions, totalFiles = 0, 0;

    for _, name in ipairs(FIXTURE_NAMES) do
        local db = LoadFixture(name);
        if (db) then
            totalFiles = totalFiles + 1;

            test(name .. ": migration keeps every action meaning the same thing", function()
                check(db.dbver and db.dbver < DebindPrivate.Constants.DB_VERSION,
                    ("표본이 이미 최신이다(dbver=%s) - 검사할 것이 없다")
                        :format(tostring(db.dbver)));

                local actions = CollectActions(db);
                check(#actions > 0, "액션이 하나도 없는 표본이다");

                -- 마이그레이션 **전**의 뜻. `UnitConditionToState`가 옛 스칼라를 여전히
                -- 읽으므로 여기서 계산할 수 있다.
                local before = {};
                for i = 1, #actions do
                    before[i] = DerivedOf(actions[i].action);
                end

                DebindPrivate.InitDB();

                check(_G.DebindVars.dbver == DebindPrivate.Constants.DB_VERSION,
                    "dbver가 안 올라감 - 마이그레이션이 안 돌았다");

                -- 마이그레이션은 제자리에서 고치므로 액션 테이블의 정체는 그대로다.
                for i = 1, #actions do
                    local entry = actions[i];
                    local after = DerivedOf(entry.action);
                    DiffMaps(before[i].states, after.states, "unitStates", entry.where);
                    DiffMaps(before[i].scalars, after.scalars, "런타임 스칼라", entry.where);
                    check(before[i].opaque == after.opaque,
                        entry.where .. ": unitStatesOpaque가 바뀜");
                end

                totalActions = totalActions + #actions;
            end);

            -- 올라간 데이터에 같은 단계를 다시 먹여도 유닛 조건이 상하면 안 된다. 실제로는
            -- `dbver` 게이트가 두 번째를 막지만, 두 판 밀린 프로필은 한 번의 호출 안에서
            -- 여러 단계를 연달아 밟으므로 **단계 자체가 제 결과 위에서 안전해야** 한다
            -- (`MigrateLayer` 머리 주석).
            --
            -- 유닛 조건만 본다. `dbver <= 2` 단계는 액션을 한 개짜리 레이어에 넣으면 `seq`를
            -- 1로 다시 매기는데, 그건 이 단계의 관심사가 아니라 표본을 자른 방식의 결과다.
            test(name .. ": re-running the unit-condition step is safe", function()
                local actions = CollectActions(_G.DebindVars);
                local before = {};
                for i = 1, #actions do
                    before[i] = DerivedOf(actions[i].action);
                end

                for i = 1, #actions do
                    DebindPrivate.MigrateLayer({ actions[i].action }, 4);
                end

                for i = 1, #actions do
                    local entry = actions[i];
                    local after = DerivedOf(entry.action);
                    DiffMaps(before[i].states, after.states, "unitStates", entry.where);
                    DiffMaps(before[i].scalars, after.scalars, "런타임 스칼라", entry.where);
                end
            end);
        end
    end

    -- **몇 개를 봤는지 항상 말한다.** 표본이 없으면 이 파일은 아무것도 검사하지 않는데,
    -- 그때 조용히 통과하면 "마이그레이션이 실제 데이터로 검증됐다"고 잘못 읽게 된다.
    if (totalFiles == 0) then
        io.write(("  savedvars: 표본 없음 - 아무것도 검사하지 않았다 (%s)\n"):format(fixtureDir));
    else
        io.write(("  savedvars: 파일 %d개 / 액션 %d개를 실제 데이터로 대조했다\n")
            :format(totalFiles, totalActions));
    end

    return T;
end
