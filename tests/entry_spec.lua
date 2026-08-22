-- What happens to a received string before it is committed: `DebindStorage/Import.lua`.
--
-- Two things live here and they fail differently.
--
-- **Addressing** decides where an entry's actions end up. Getting it wrong is not a display bug:
-- the same actions on the same keys behave differently one layer over, with nothing missing and
-- nothing overwritten, which is the failure mode this whole design is built around. The cases that
-- matter are the ones a single-class test cannot produce - a string from a class with more specs
-- than ours, or from a class whose spec numbers mean something else entirely.
--
-- The answer to those is that **there is nothing to map**: both profiles use the same coordinate
-- system, so a layer travels verbatim and only the character has to be re-read. What these cases
-- guard is that nothing quietly reintroduces a translation.
--
-- **The drawer** holds work across a `/reload`, so what it stores has to survive being written to
-- SavedVariables and read back. What it stores is the payload.
--
-- **There is no migration to test.** `PAYLOAD_VERSION` versions the payload's shape, and that shape
-- has never changed. A block of cases here brought a "v1" store forward: what it converted was a
-- record holding the string instead of the payload, which is the same payload either way.

return function(DebindPrivate, DebindStorage)
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

    -- The shim's class is a druid, which has four specs. That is what makes "a spec we do not
    -- have" reachable below: a class with five would be needed otherwise.
    check(CLASS == "DRUID", "이 스펙은 드루이드(4특성) 전제로 쓰였다: " .. tostring(CLASS));

    --- A profile with every layer stood up. The layers themselves are what mapping asks about, so
    --- they have to exist even though nothing here reads an action out of them.
    local function ResetProfile()
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = {}, classes = { [CLASS] = {} } },
            characters = { [GUID] = { layers = {} } },
            migrated = {},
        };
        DebindPrivate.InitDB();
    end

    ResetProfile();

    ---------------------------------------------------------------------------
    -- Where an action goes
    --
    -- The answer is the address the profile stores by - `(scope, class, spec)`, the same three
    -- `shared.GENERAL` / `shared.classes[class][spec]` / `characters[guid].layers[spec]` are keyed
    -- on. Not a layer ID: those are this character's view of the store, and half of what arrives
    -- has no ID in it at all.
    ---------------------------------------------------------------------------

    local Address = DebindStorage.ImportAddress;

    test("일반은 일반으로", function()
        check(Address("general") == "general", "일반이 아니다");
    end);

    test("내 직업 레이어는 그 자리 그대로", function()
        local scope, class, spec = Address("class", CLASS, 0);
        check(scope == "class" and class == CLASS and spec == 0, "직업 공용");

        scope, class, spec = Address("class", CLASS, 2);
        check(scope == "class" and class == CLASS and spec == 2, "특성 2");
    end);

    test("캐릭터 레이어는 이 캐릭터로", function()
        local scope, class, spec = Address("character", nil, 0);
        check(scope == "character" and class == nil and spec == 0, "캐릭터 공용");

        scope, _, spec = Address("character", nil, 2);
        check(scope == "character" and spec == 2, "특성 2");
    end);

    -- **The case a same-class test cannot reach, and the one that used to be wrong.** Spec 2 is
    -- Feral for a druid and Fire for a mage, and the old mapping answered "the reader's class,
    -- no spec" - a mage's fire bindings sitting in "all my druids", every line red because the
    -- reader cannot learn any of it, and nothing on screen they could judge.
    --
    -- It goes to the mage's own spec 2 instead, which is where it belongs on every account. The
    -- reader does not see it in this session; they see it when they log a mage.
    test("남의 직업 레이어는 직업도 특성도 그대로 간다", function()
        local scope, class, spec = Address("class", "MAGE", 2);
        check(scope == "class" and class == "MAGE" and spec == 2,
            "남의 좌표를 내 것으로 밀어 넣었다: " .. tostring(class) .. "/" .. tostring(spec));

        scope, class, spec = Address("class", "MAGE", 0);
        check(scope == "class" and class == "MAGE" and spec == 0, "직업 공용");
    end);

    -- `spec` absent and `spec = 0` are the same layer. A hand-made string can leave the number out,
    -- and both spellings have to mean the layer the profile stores at 0.
    test("빠진 spec은 0과 같다", function()
        local _, _, spec = Address("class", CLASS);
        check(spec == 0, "직업 " .. tostring(spec));
        _, _, spec = Address("character");
        check(spec == 0, "캐릭터 " .. tostring(spec));
    end);

    -- **The one address with nowhere to go.** A character-scoped layer means *this* character, and
    -- a spec this character's class does not have is a table nothing would ever read and nothing
    -- would ever clean up. Answering nil is what gets it counted and said out loud.
    --
    -- The class side is not the same question: `classes.MAGE[4]` is a coordinate that stops being
    -- ours to judge, so it travels and waits.
    test("이 캐릭터에 없는 특성은 자리가 없다", function()
        check(Address("character", nil, 5) == nil, "5는 어디에도 없다");
        -- The shim's class is a druid (four specs), so spec 4 is the last one that does exist.
        check(Address("character", nil, 4) ~= nil, "있는 특성을 거절했다");
    end);

    test("저장이 담지 못하는 번호는 거절한다", function()
        check(Address("class", CLASS, 5) == nil, "5번 칸은 없다");
        check(Address("class", CLASS, -1) == nil, "음수");
        check(Address("class", nil, 0) == nil, "직업 이름이 없다");
    end);

    -- **범위 안이라고 칸 번호인 것은 아니다.** 이 함수가 막으라고 있는 것이 "아무 화면도 안 읽고
    -- `CleanUpDB`도 안 훑는 자리"인데, 소수는 범위 검사 셋을 그대로 통과해서
    -- `shared.classes.DRUID[1.5]`를 만든다 - 붙여넣을 때마다 계정 파일에 하나씩 쌓이는 고아다.
    -- NaN은 더 나쁘다: 비교 셋이 전부 거짓이라 통과한 뒤 인덱스로 쓰이는 자리에서 터진다.
    test("정수가 아닌 특성 번호는 자리를 안 만든다", function()
        check(Address("class", CLASS, 1.5) == nil, "소수");
        check(Address("character", nil, 1.5) == nil, "캐릭터 쪽 소수");
        check(Address("class", CLASS, 0 / 0) == nil, "NaN");
        check(Address("class", CLASS, 1 / 0) == nil, "무한대");
        check(Address("class", CLASS, 2) ~= nil, "멀쩡한 번호를 거절했다");
    end);

    -- **A class name is a key straight into storage.** `shared.classes[<name>]` gets made on the
    -- spot, no screen reaches it, and `CleanUpDB` walks the eleven loaded layers so it never sees
    -- it either - every paste of a made-up name would leave one more behind in the account file.
    test("직업 이름이 아닌 것은 자리를 안 만든다", function()
        check(Address("class", "NOSUCHCLASS", 0) == nil, "지어낸 이름");
        check(Address("class", 3, 0) == nil, "문자열이 아닌 것");
        check(Address("class", "MAGE", 0) ~= nil, "진짜 직업을 거절했다");
    end);

    test("모르는 scope는 주소가 없다", function()
        check(Address("raid") == nil, "주소를 지어냈다");
        check(Address(nil) == nil, "nil");
    end);

    --- A payload built from `{ scope, class, spec, count }` entries, one layer each.
    --- `count = 0` stands an **empty** layer up, and `junk` puts a non-action in the list -- both
    --- are shapes a hand-made string carries and neither may raise.
    local function Payload(layers)
        -- 상수를 읽는다. 숫자를 적어두면 스키마가 올라가는 날 이 파일의 케이스가 전부
        -- **버전 때문에** 빨개지는데, 여기서 묻는 것은 버전이 아니라 서랍의 행동이다.
        -- 버전을 묻는 케이스는 아래에서 값을 직접 만들어 쓴다.
        --
        -- **둘을 다 든다.** 봉투 모양은 `v`가, 그 안의 액션 모양은 `dbver`가 센다
        -- (`devdocs/legacy/unifying-action-migration.md` §3-3). 하나만 들면 서랍 문이 거절한다.
        local payload = {
            v = DebindStorage.EXPORT_SCHEMA_VERSION,
            dbver = Constants.DB_VERSION,
            class = CLASS,
        };

        for _, entry in ipairs(layers) do
            local actions = {};
            for i = 1, (entry.count or 1) do
                actions[i] = { type = Constants.SPELL, value = i, key = entry.key, seq = i };
            end
            if (entry.junk) then
                actions[#actions + 1] = entry.junk;
            end

            if (entry.scope == "general") then
                payload.shared = payload.shared or {};
                payload.shared.GENERAL = actions;
            elseif (entry.scope == "class") then
                payload.shared = payload.shared or {};
                payload.shared.classes = payload.shared.classes or {};
                payload.shared.classes[entry.class] = payload.shared.classes[entry.class] or {};
                payload.shared.classes[entry.class][entry.spec or 0] = actions;
            elseif (entry.scope == "character") then
                payload.char = payload.char or {};
                payload.char[entry.spec or 0] = actions;
            else
                payload[entry.scope] = actions;
            end
        end

        return payload;
    end

    ---------------------------------------------------------------------------
    -- The drawer
    --
    -- **The decoder is stubbed here on purpose.** Whether a real string survives the trip is
    -- `export_spec`'s question and it answers it against the real libraries; this file's question
    -- is what the drawer does with an answer once it has one. Stubbing also keeps these cases
    -- running under fengari, where LibDeflate cannot decompress - gated on the real decoder they
    -- would be skipped by `npm test` and only ever run by hand.
    ---------------------------------------------------------------------------

    local realDecode = DebindStorage.DecodeExportString;
    local STORED = {};

    DebindStorage.DecodeExportString = function(str)
        local payload = type(str) == "string" and STORED[strtrim(str)] or nil;
        if (not payload) then
            return nil, "BAD_PAYLOAD";
        end
        return payload;
    end

    local function ResetDrawer()
        _G.DebindStorageVars = nil;
        STORED = {};
    end

    local GOOD = "DEB1:good";
    local GOOD_PAYLOAD = Payload({ { scope = "general", key = "F", count = 1 } });

    test("받아들인 문자열이 배치가 된다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;

        local entry = DebindStorage.ImportEntry(GOOD, "친구 세팅");
        check(entry, "배치가 안 만들어짐");
        check(entry.name == "친구 세팅", "이름");
        check(#DebindStorage.GetEntries() == 1, "서랍에 안 들어감");
        check(DebindStorage.GetEntry(entry.id) == entry, "id로 못 찾음");
    end);

    -- Counted off the payload every time the row asks, because the payload is what the entry
    -- holds. The two numbers were stored fields while the string was.
    test("개수는 저장된 페이로드에서 나온다", function()
        ResetDrawer();
        local text = "DEB1:여럿";
        STORED[text] = Payload({
            { scope = "general", key = "F", count = 2 },
            { scope = "class", class = CLASS, spec = 1, key = "G", count = 3 },
        });

        local entry = DebindStorage.ImportEntry(text);
        -- **A key is a group**, so two keys is two groups however the five actions are spread.
        local groupCount, actionCount = DebindStorage.CountEntry(entry);
        check(groupCount == 2, "그룹 수 " .. tostring(groupCount));
        check(actionCount == 5, "액션 수 " .. tostring(actionCount));
        check(entry.payload.class == CLASS, "보낸 쪽 클래스");
        check(entry.groupCount == nil and entry.actionCount == nil,
            "개수를 배치에 또 적어뒀다 - 페이로드와 갈릴 자리가 생긴다");
    end);

    -- Refused where the user is looking at it, rather than becoming a row that fails every time it
    -- is opened.
    test("못 읽는 문자열은 서랍에 안 들어간다", function()
        ResetDrawer();

        local entry, reason = DebindStorage.ImportEntry("DEB1:쓰레기");
        check(entry == nil, "받아들였다");
        check(reason == "BAD_PAYLOAD", "이유 " .. tostring(reason));
        check(#DebindStorage.GetEntries() == 0, "서랍에 들어갔다");
    end);

    -- What SavedVariables holds is the payload. The string is refused outright once the schema
    -- moves past it, so a drawer of strings is a drawer nothing can bring forward.
    test("서랍에 남는 것은 페이로드지 문자열이 아니다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;

        local entry = DebindStorage.ImportEntry("  " .. GOOD .. "\n");
        check(entry.payload == GOOD_PAYLOAD, "페이로드를 저장 안 했다");
        check(entry.text == nil, "문자열이 남아 있다: " .. tostring(entry.text));
        check(DebindStorage.GetEntryPayload(entry) == GOOD_PAYLOAD, "다시 못 읽음");
    end);

    -- **서랍에서 여는 문도 버전을 묻는다.** 붙여넣는 쪽은 `DecodeExportString`이 물어서
    -- `export_spec`이 그것을 잡고 있는데, 서랍은 저장된 페이로드를 그대로 내주고 있었다.
    --
    -- 스키마가 하나뿐인 동안은 두 경로가 같은 답을 낸다. **갈리는 것은 스키마가 올라간
    -- 다음이고, 그때 서랍에 쌓여 있던 것이 검사 없이 새 코드로 들어간다** - 붙여넣기 쪽에만
    -- 마이그레이션을 얹으면 조용히 그렇게 된다. 그래서 저장된 배치를 손으로 만들어 묻는다.
    local function StoredEntryWithVersion(version)
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;
        local entry = DebindStorage.ImportEntry(GOOD);
        -- 문을 지나 저장된 뒤에 버전만 바꾼다. 붙여넣는 쪽 문은 이 값을 이미 봤으므로,
        -- 여기서 걸리는 것은 **서랍에서 여는 문**뿐이다.
        entry.payload = { v = version, class = CLASS, shared = { GENERAL = {} } };
        return entry;
    end

    test("서랍에 있는 배치가 더 새 스키마면 거절한다", function()
        local entry = StoredEntryWithVersion(DebindStorage.EXPORT_SCHEMA_VERSION + 1);
        local payload, reason = DebindStorage.GetEntryPayload(entry);
        check(payload == nil, "읽어버렸다");
        check(reason == "UNSUPPORTED_SCHEMA", "이유 " .. tostring(reason));
    end);

    -- **여기가 갈릴 자리라고 적어둔 그 자리다.** v1을 읽어야 하는 날 답이 거절에서
    -- 마이그레이션으로 바뀐다고 되어 있었고, 그날이 왔다(`SCHEMA_VERSION` 2, 조건이
    -- `action.conditions` 안으로 들어감).
    --
    -- **서랍에 쌓인 배치가 이 길로 온다.** 여기서 거절하면 받아둔 것이 전부 못 읽히고,
    -- 조용히 통과시키면 조건이 전부 버려진 채 무조건 액션으로 도착한다.
    test("서랍에 있는 v1 배치는 사다리를 타고 올라온다", function()
        local entry = StoredEntryWithVersion(1);
        local payload, reason = DebindStorage.GetEntryPayload(entry);
        check(payload ~= nil, "거절당했다: " .. tostring(reason));
        check(payload.v == DebindStorage.EXPORT_SCHEMA_VERSION,
            "판 번호가 안 올라갔다: " .. tostring(payload.v));
    end);

    test("사다리에 단계가 없는 판은 거절한다", function()
        local entry = StoredEntryWithVersion(0);
        local payload, reason = DebindStorage.GetEntryPayload(entry);
        check(payload == nil, "읽어버렸다");
        check(reason == "SCHEMA_TOO_OLD", "이유 " .. tostring(reason));
    end);

    test("버전이 숫자가 아닌 배치도 거절한다", function()
        local entry = StoredEntryWithVersion(nil);
        local payload, reason = DebindStorage.GetEntryPayload(entry);
        check(payload == nil, "읽어버렸다");
        check(reason == "UNSUPPORTED_SCHEMA", "이유 " .. tostring(reason));
    end);

    -- **봉투 위에 사다리가 하나 더 있다.** `v`는 주소 체계를 세고 `dbver`는 그 안의 액션
    -- 모양을 센다. 두 질문이 한 숫자에 얹혀 있던 것을 가른 것이 이 변경이고, 그래서 봉투가
    -- 통과한 뒤에도 물어볼 것이 남는다.
    --
    -- v1은 이 자리에 안 걸린다. 판 번호가 곧 답이라 어댑터가 5를 찍고 지나간다.
    local function StoredEntryWithDbver(dbver)
        local entry = StoredEntryWithVersion(DebindStorage.EXPORT_SCHEMA_VERSION);
        entry.payload.dbver = dbver;
        return entry;
    end

    -- 이 판이 v2를 내면서 `dbver`를 같이 싣기 시작했으므로, 안 든 v2는 어느 빌드도 만든 적이
    -- 없는 모양이다. 추측으로 읽으면 액션을 어느 사다리에 태울지를 지어내게 된다.
    test("dbver를 안 든 v2 배치는 거절한다", function()
        local payload, reason = DebindStorage.GetEntryPayload(StoredEntryWithDbver(nil));
        check(payload == nil, "읽어버렸다");
        check(reason == "BAD_PAYLOAD", "이유 " .. tostring(reason));
    end);

    test("이 빌드보다 새 dbver를 든 배치는 거절한다", function()
        local payload, reason = DebindStorage.GetEntryPayload(
            StoredEntryWithDbver(Constants.DB_VERSION + 1));
        check(payload == nil, "읽어버렸다");
        check(reason == "UNSUPPORTED_SCHEMA", "이유 " .. tostring(reason));
    end);

    -- **바닥은 공유가 나간 판이다.** 그 밑으로 내려가면 `MigrateLayer`의 옛 단계들에 닿는데,
    -- 그것들은 프로필만 지나가던 시절에 쓰여서 필드가 제 타입이라고 믿는다. 붙여넣기는 에러를
    -- 내면 안 되는 자리라 읽기 전에 거절한다.
    test("공유가 나가기 전 dbver를 든 배치는 거절한다", function()
        local payload, reason = DebindStorage.GetEntryPayload(StoredEntryWithDbver(4));
        check(payload == nil, "읽어버렸다");
        check(reason == "SCHEMA_TOO_OLD", "이유 " .. tostring(reason));
    end);

    -- NaN은 위아래 비교를 전부 빠져나간다. 통과시키면 어느 단계도 안 맞는 판으로 사다리에
    -- 들어가고, 그건 아무 단계도 안 밟은 액션을 이 판의 것이라고 도장 찍는 것이다.
    test("dbver가 NaN인 배치도 거절한다", function()
        local payload, reason = DebindStorage.GetEntryPayload(StoredEntryWithDbver(0 / 0));
        check(payload == nil, "읽어버렸다");
        check(reason == "BAD_PAYLOAD", "이유 " .. tostring(reason));
    end);

    -- **행은 그려지는데 열면 터지던 자리.** 서랍 행을 그리는 둘(`CountEntry`,
    -- `EntryClassText`)은 페이로드가 없는 배치를 막고 있어서 날짜만 달고 멀쩡히 선다. 그
    -- 행을 누르면 문이 페이로드를 그대로 인덱싱했다.
    --
    -- **나가는 빌드에서 그런 배치는 안 생긴다** - `ImportEntry`가 언제나 채우고, 이 애드온이
    -- 이번에 처음 나가므로 그 문을 안 지난 배치가 남의 디스크에 있을 수 없다. 닿는 것은
    -- 문자열 대신 페이로드를 저장하기로 바뀌기 전에 만들어진 개발용 `DebindStorageVars`다.
    -- 거절이 답인 자리에서 던지지는 말아야 한다.
    test("페이로드가 없는 배치는 던지지 않고 거절한다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;
        local entry = DebindStorage.ImportEntry(GOOD);
        entry.payload = nil;

        local payload, reason = DebindStorage.GetEntryPayload(entry);
        check(payload == nil, "읽어버렸다");
        check(reason == "BAD_PAYLOAD", "이유 " .. tostring(reason));
    end);


    test("id는 지워도 다시 안 쓰인다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;

        local first = DebindStorage.ImportEntry(GOOD);
        DebindStorage.DeleteEntry(first.id);
        local second = DebindStorage.ImportEntry(GOOD);

        check(second.id ~= first.id, "지운 id가 재활용됐다 - 그 배치에 붙은 배지가 남의 것이 된다");
        check(#DebindStorage.GetEntries() == 1, "배치 수");
        check(DebindStorage.GetEntry(first.id) == nil, "지운 것이 남아 있다");
    end);

    test("없는 것을 지우면 아무 일도 안 난다", function()
        ResetDrawer();
        check(DebindStorage.DeleteEntry(999) == false, "지웠다고 답했다");
    end);

    -- An entry has to be openable after a `/reload`, and a reload is exactly what SavedVariables
    -- being a plain table has to survive. Nothing here may be a closure, a metatable, or a
    -- reference to a live profile table.
    test("배치는 저장 가능한 값만 들고 있다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;
        local entry = DebindStorage.ImportEntry(GOOD);

        check(getmetatable(entry) == nil, "메타테이블이 붙어 있다");
        for k, v in pairs(entry) do
            local vt = type(v);
            check(vt == "string" or vt == "number" or vt == "boolean" or vt == "table",
                "저장 못 하는 값: " .. tostring(k) .. " = " .. vt);
        end
    end);

    -- **만료 케이스 셋이 여기 있었다** (`GetSecondsUntilExpiry` / `IsExpiringSoon` / 핀).
    -- 판정만 있고 쓸어내는 코드가 없어서, 그 셋은 화면에 아무 일도 안 일어나는 날짜를 띄우는
    -- 계산을 검사하고 있었다. 판정과 핀이 같이 빠지면서 스펙도 같이 나간다 — 되살릴 때는
    -- 쓸어내는 쪽이 아니라 **묻는** 쪽으로 짓는다(`devdocs/building-export-import.md`).

    ---------------------------------------------------------------------------
    -- Cutting actions out of an entry
    --
    -- **The only edit an entry has** (12절). It changes a payload that is already on disk, so what
    -- it leaves behind has to be a payload every other reader of one can walk: no list holding an
    -- action that is gone, and no address holding an empty list.
    ---------------------------------------------------------------------------

    --- An entry standing on `payload`, without going near the store.
    local function EntryOf(payload)
        return { id = 1, received = 0, payload = payload };
    end

    test("고른 것만 빠진다", function()
        local payload = Payload({ { scope = "general", key = "F", count = 3 } });
        local list = payload.shared.GENERAL;
        local doomed = list[2];

        local removed = DebindStorage.RemoveEntryActions(EntryOf(payload), { [doomed] = true });

        check(removed == 1, "지운 수 " .. tostring(removed));
        check(#payload.shared.GENERAL == 2, "남은 수 " .. #payload.shared.GENERAL);
        for _, action in ipairs(payload.shared.GENERAL) do
            check(action ~= doomed, "지운 것이 남아 있다");
        end
    end);

    test("여러 레이어에 걸친 것도 한 번에 빠진다", function()
        local payload = Payload({
            { scope = "general", key = "F", count = 2 },
            { scope = "character", spec = 1, key = "F", count = 2 },
        });
        local doomed = {
            [payload.shared.GENERAL[1]] = true,
            [payload.char[1][1]] = true,
        };

        check(DebindStorage.RemoveEntryActions(EntryOf(payload), doomed) == 2, "지운 수");
        check(#payload.shared.GENERAL == 1, "일반이 안 줄었다");
        check(#payload.char[1] == 1, "캐릭터가 안 줄었다");
    end);

    -- **빈 자리는 자리가 아니다.** 액션이 하나도 없는 주소가 남으면 그리는 쪽은 머리글을 세우고
    -- `PlanImport`는 놓을 데를 내주는데, 놓을 것이 없다.
    test("비워진 레이어는 주소째 걷힌다", function()
        local payload = Payload({
            { scope = "general", key = "F", count = 1 },
            { scope = "class", class = CLASS, spec = 2, key = "G", count = 1 },
            { scope = "character", spec = 0, key = "H", count = 1 },
        });
        local doomed = {
            [payload.shared.GENERAL[1]] = true,
            [payload.shared.classes[CLASS][2][1]] = true,
            [payload.char[0][1]] = true,
        };

        check(DebindStorage.RemoveEntryActions(EntryOf(payload), doomed) == 3, "지운 수");
        check(payload.shared.GENERAL == nil, "빈 일반 목록이 남았다");
        check(payload.shared.classes[CLASS] == nil, "빈 직업 표가 남았다");
        check(payload.char[0] == nil, "빈 캐릭터 목록이 남았다");
    end);

    test("일부만 지운 레이어는 그대로 선다", function()
        local payload = Payload({ { scope = "general", key = "F", count = 2 } });
        DebindStorage.RemoveEntryActions(EntryOf(payload),
            { [payload.shared.GENERAL[1]] = true });
        check(payload.shared.GENERAL ~= nil, "안 빈 목록을 걷었다");
        check(#payload.shared.GENERAL == 1, "남은 수");
    end);

    -- 원래 비어 있던 것을 치우지 않는다. 아무것도 안 지운 호출이 페이로드를 바꾸면, 눌러도
    -- 아무 일도 없는 메뉴 항목이 디스크의 내용을 건드리는 것이 된다.
    test("아무것도 안 지우면 아무것도 안 건드린다", function()
        local payload = Payload({ { scope = "general", key = "F", count = 0 } });
        local stranger = { type = Constants.SPELL, value = 99 };

        check(DebindStorage.RemoveEntryActions(EntryOf(payload), { [stranger] = true }) == 0,
            "없는 것을 지웠다고 답했다");
        check(payload.shared.GENERAL ~= nil, "원래 비어 있던 목록을 걷었다");
    end);

    -- 매니페스트는 안 건드린다. 무엇을 참조했었나는 만들 때의 사실이고, 실제로 나가는 것만
    -- 남기는 것은 문자열을 만드는 순간의 일이다(`FilterPayload`).
    test("매니페스트는 그대로 둔다", function()
        local payload = Payload({ { scope = "general", key = "F", count = 1 } });
        payload.states = { ["$state3"] = { mode = "manual" } };

        DebindStorage.RemoveEntryActions(EntryOf(payload),
            { [payload.shared.GENERAL[1]] = true });
        check(payload.states and payload.states["$state3"], "매니페스트가 사라졌다");
    end);

    DebindStorage.DecodeExportString = realDecode;

    return T;
end
