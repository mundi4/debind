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
-- **The payload's own ladder is `export_spec`'s**; what the drawer adds is that its stored payloads
-- walk it too. The drawer's one step of its own is `ENTRY_VERSION` 2, which moved the row's name into
-- the payload.

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
            layers = {
                account = { GENERAL = { [0] = {} } },
                [GUID] = { [CLASS] = {} },
            },
            characters = { [GUID] = {} },
            migrated = {},
        };
        DebindPrivate.InitDB();
    end

    ResetProfile();

    ---------------------------------------------------------------------------
    -- Where an action goes
    --
    -- Asked with the payload's own cell, `(owner, class, spec)`, and answered with the address the
    -- profile stores by - `(scope, class, spec)`, the same three `layers.account.GENERAL[0]` /
    -- `layers.account[class][spec]` / `layers[guid][class][spec]` are keyed on. Not a layer ID:
    -- those are this character's view of the store, and half of what arrives has no ID in it at all.
    ---------------------------------------------------------------------------

    local Address = DebindStorage.ImportAddress;

    --- A character cell's key. What it is does not matter, only that it is not `"account"`.
    local SOMEONE = "1";

    test("일반은 일반으로", function()
        check(Address("account", "GENERAL", 0) == "general", "일반이 아니다");
    end);

    -- `GENERAL` holds one layer, the one at 0. A number past it is a hand-made string.
    test("일반의 다른 번호는 자리가 없다", function()
        check(Address("account", "GENERAL", 2) == nil, "일반 2를 받았다");
    end);

    test("내 직업 레이어는 그 자리 그대로", function()
        local scope, class, spec = Address("account", CLASS, 0);
        check(scope == "class" and class == CLASS and spec == 0, "직업 공용");

        scope, class, spec = Address("account", CLASS, 2);
        check(scope == "class" and class == CLASS and spec == 2, "특성 2");
    end);

    test("캐릭터 레이어는 이 캐릭터로", function()
        local scope, class, spec = Address(SOMEONE, CLASS, 0);
        check(scope == "character" and class == nil and spec == 0, "캐릭터 공용");

        scope, _, spec = Address(GUID, CLASS, 2);
        check(scope == "character" and spec == 2, "특성 2");
    end);

    test("다른 직업의 캐릭터 레이어는 자리가 없고 그렇다고 말한다", function()
        local scope, reason = Address(SOMEONE, "MAGE", 2);
        check(scope == nil, "남의 직업 캐릭터 칸을 받았다");
        check(reason == "OTHER_CLASS", "이유 " .. tostring(reason));
    end);

    test("모르는 직업의 캐릭터 레이어도 자리가 없다", function()
        local scope, reason = Address(SOMEONE, "NOSUCHCLASS", 0);
        check(scope == nil, "받았다");
        check(reason == "UNKNOWN_CLASS", "이유 " .. tostring(reason));
    end);

    -- **The case a same-class test cannot reach, and the one that used to be wrong.** Spec 2 is
    -- Feral for a druid and Fire for a mage, and the old mapping answered "the reader's class,
    -- no spec" - a mage's fire bindings sitting in "all my druids", every line a spell the reader
    -- cannot learn, and nothing on screen they could judge.
    --
    -- It goes to the mage's own spec 2 instead, which is where it belongs on every account. The
    -- reader does not see it in this session; they see it when they log a mage.
    test("남의 직업 레이어는 직업도 특성도 그대로 간다", function()
        local scope, class, spec = Address("account", "MAGE", 2);
        check(scope == "class" and class == "MAGE" and spec == 2,
            "남의 좌표를 내 것으로 밀어 넣었다: " .. tostring(class) .. "/" .. tostring(spec));

        scope, class, spec = Address("account", "MAGE", 0);
        check(scope == "class" and class == "MAGE" and spec == 0, "직업 공용");
    end);

    -- **The one address with nowhere to go.** A character-scoped layer means *this* character, and
    -- a spec this character's class does not have is a table nothing would ever read and nothing
    -- would ever clean up. Answering nil is what gets it counted and said out loud.
    --
    -- The class side is not the same question: `layers.account.MAGE[4]` is a coordinate that stops being
    -- ours to judge, so it travels and waits.
    test("이 캐릭터에 없는 특성은 자리가 없다", function()
        check(Address(SOMEONE, CLASS, 5) == nil, "5는 어디에도 없다");
        -- The shim's class is a druid (four specs), so spec 4 is the last one that does exist.
        check(Address(SOMEONE, CLASS, 4) ~= nil, "있는 특성을 거절했다");
    end);

    test("저장이 담지 못하는 번호는 거절한다", function()
        check(Address("account", CLASS, 5) == nil, "5번 칸은 없다");
        check(Address("account", CLASS, -1) == nil, "음수");
        check(Address("account", CLASS, nil) == nil, "번호가 없다");
    end);

    -- **In range is not the same as a slot number.** What this function is there to refuse is "a
    -- place no screen reads and `CleanUpDB` never walks", and a fraction passes all three range
    -- checks and makes `layers.account.DRUID[1.5]`, an orphan every paste adds to the account file.
    -- NaN is worse: every comparison is false, so it passes and raises where it is used as an index.
    test("정수가 아닌 특성 번호는 자리를 안 만든다", function()
        check(Address("account", CLASS, 1.5) == nil, "소수");
        check(Address(SOMEONE, CLASS, 1.5) == nil, "캐릭터 쪽 소수");
        check(Address("account", CLASS, 0 / 0) == nil, "NaN");
        check(Address("account", CLASS, 1 / 0) == nil, "무한대");
        check(Address("account", CLASS, "2") == nil, "문자열 번호");
        check(Address("account", CLASS, 2) ~= nil, "멀쩡한 번호를 거절했다");
    end);

    -- **A class name is a key straight into storage.** `layers.account[<name>]` gets made on the
    -- spot, no screen reaches it, and `CleanUpDB` walks the eleven loaded layers so it never sees
    -- it either - every paste of a made-up name would leave one more behind in the account file.
    test("직업 이름이 아닌 것은 자리를 안 만든다", function()
        check(Address("account", "NOSUCHCLASS", 0) == nil, "지어낸 이름");
        check(Address("account", 3, 0) == nil, "문자열이 아닌 것");
        check(Address("account", "MAGE", 0) ~= nil, "진짜 직업을 거절했다");
    end);

    test("주인 키가 없으면 주소가 없다", function()
        check(Address(nil, CLASS, 0) == nil, "nil");
    end);

    --- A payload built from `{ scope, class, spec, count }` entries, one layer each.
    --- `count = 0` stands an **empty** layer up, and `junk` puts a non-action in the list -- both
    --- are shapes a hand-made string carries and neither may raise.
    local function Payload(layers)
        -- Reads the constants. A number written here would turn every case in this file red **over
        -- the version** the day `PAYLOAD_VERSION` goes up, and what these ask is how the drawer
        -- behaves, not the version. The cases that ask about the version build their values below.
        --
        -- **Both are carried.** `v` counts the payload's own shape and `dbver` the shape of the
        -- actions inside it (`unifying-action-migration.md` §3-3). With only one, the drawer's door
        -- refuses it.
        local payload = {
            v = DebindStorage.PAYLOAD_VERSION,
            dbver = Constants.DB_VERSION,
            layers = {},
        };

        --- `layers[owner][class][spec]`, made on the way down.
        local function Cell(owner, class, spec, actions)
            payload.layers[owner] = payload.layers[owner] or {};
            payload.layers[owner][class] = payload.layers[owner][class] or {};
            payload.layers[owner][class][spec] = actions;
        end

        for _, entry in ipairs(layers) do
            local actions = {};
            for i = 1, (entry.count or 1) do
                actions[i] = { type = Constants.SPELL, value = i, key = entry.key, seq = i };
            end
            if (entry.junk) then
                actions[#actions + 1] = entry.junk;
            end

            if (entry.scope == "general") then
                Cell("account", "GENERAL", 0, actions);
            elseif (entry.scope == "class") then
                Cell("account", entry.class, entry.spec or 0, actions);
            elseif (entry.scope == "character") then
                Cell(GUID, CLASS, entry.spec or 0, actions);
                payload.characters = { [GUID] = { name = "Tester", class = CLASS } };
            else
                payload[entry.scope] = actions;
            end
        end

        return payload;
    end

    --- `payload.layers[owner][class][spec]`, or nil anywhere along the way.
    local function LayerAt(payload, owner, class, spec)
        local classes = payload.layers and payload.layers[owner];
        local specTbl = classes and classes[class];
        return specTbl and specTbl[spec];
    end

    ---------------------------------------------------------------------------
    -- The drawer
    --
    -- **The decoder is stubbed here on purpose.** Whether a real string survives the trip is
    -- `export_spec`'s question and it answers it against the real libraries; this file's question
    -- is what the drawer does with an answer once it has one.
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
        check(entry.payload.name == "친구 세팅", "이름 " .. tostring(entry.payload.name));
        check(entry.name == nil, "이름이 행에도 남았다");
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

    -- What SavedVariables holds is the payload. The string is refused outright once `payload.v`
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
    -- While there is one payload version the two doors answer alike. **They part once
    -- `PAYLOAD_VERSION` goes up, and then what was sitting in the drawer walks into the new code
    -- unasked** - which is what happens, silently, if a step is added on the paste side only. So a
    -- stored entry is built by hand and asked.
    local function StoredEntryWithVersion(version)
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;
        local entry = DebindStorage.ImportEntry(GOOD);
        -- 문을 지나 저장된 뒤에 버전만 바꾼다. 붙여넣는 쪽 문은 이 값을 이미 봤으므로,
        -- 여기서 걸리는 것은 **서랍에서 여는 문**뿐이다.
        if (version == 1) then
            entry.payload = { v = version, class = CLASS, shared = { GENERAL = {} } };
        else
            entry.payload = Payload({ { scope = "general", key = "F", count = 0 } });
            entry.payload.v = version;
        end
        return entry;
    end

    -- **The drawer holds payloads, and the ones from before 3 are v2.** The row is drawn from its
    -- payload before anyone opens it (`CountEntry`), so the step has to have run by then, not only
    -- when the entry is opened.
    test("서랍의 v2 배치는 서랍을 열 때 v3로 올라간다", function()
        ResetDrawer();
        _G.DebindStorageVars = { version = 1, nextID = 2, entries = { {
            id = 1, received = 0,
            payload = { v = 2, dbver = 7, class = CLASS, shared = { GENERAL = {
                { type = Constants.SPELL, value = 1, key = "F", seq = 1 },
                { type = Constants.SPELL, value = 2, key = "G", seq = 1 } } } },
        } } };

        local entry = DebindStorage.GetEntries()[1];
        check(entry.payload.v == DebindStorage.PAYLOAD_VERSION,
            "판이 안 올라갔다: " .. tostring(entry.payload.v));
        local groups, actions = DebindStorage.CountEntry(entry);
        check(groups == 2 and actions == 2, "그룹 " .. groups .. ", 액션 " .. actions);
    end);

    -- **One entry the ladder raises on must not take the drawer with it.** Its row still has to
    -- draw, because deleting it is the one thing left to do with it and the button is on the row.
    test("올리다 터지는 배치가 서랍 전체를 막지 않는다", function()
        ResetDrawer();
        _G.DebindStorageVars = { version = 1, nextID = 3, entries = {
            { id = 1, received = 0, payload = { v = 2, dbver = 7, class = CLASS } },
            { id = 2, received = 0, payload = { v = 2, dbver = 7, class = CLASS } },
        } };
        local real = DebindStorage.BringPayloadForward;
        DebindStorage.BringPayloadForward = function(payload)
            if (payload == _G.DebindStorageVars.entries[1].payload) then
                error("a step raised");
            end
            return real(payload);
        end;

        local ok, entries = pcall(DebindStorage.GetEntries);
        DebindStorage.BringPayloadForward = real;
        check(ok, "서랍이 터졌다: " .. tostring(entries));
        check(#entries == 2, "배치 수 " .. #entries);
        check(entries[2].payload.v == DebindStorage.PAYLOAD_VERSION, "뒤의 배치가 안 올라갔다");
        check(DebindStorage.DeleteEntry(1), "터진 배치를 못 지웠다");
    end);

    test("서랍에 있는 배치가 더 새 판이면 거절한다", function()
        local entry = StoredEntryWithVersion(DebindStorage.PAYLOAD_VERSION + 1);
        local payload, reason = DebindStorage.GetEntryPayload(entry);
        check(payload == nil, "읽어버렸다");
        check(reason == "PAYLOAD_TOO_NEW", "이유 " .. tostring(reason));
    end);

    -- **This is the place marked as where the answer would change.** The day v1 had to be read,
    -- refusing was to become migrating, and that day came (`PAYLOAD_VERSION` 2, when the conditions
    -- moved into `action.conditions`).
    --
    -- **서랍에 쌓인 배치가 이 길로 온다.** 여기서 거절하면 받아둔 것이 전부 못 읽히고,
    -- 조용히 통과시키면 조건이 전부 버려진 채 무조건 액션으로 도착한다.
    test("서랍에 있는 v1 배치는 사다리를 타고 올라온다", function()
        local entry = StoredEntryWithVersion(1);
        local payload, reason = DebindStorage.GetEntryPayload(entry);
        check(payload ~= nil, "거절당했다: " .. tostring(reason));
        check(payload.v == DebindStorage.PAYLOAD_VERSION,
            "판 번호가 안 올라갔다: " .. tostring(payload.v));
    end);

    test("사다리에 단계가 없는 판은 거절한다", function()
        local entry = StoredEntryWithVersion(0);
        local payload, reason = DebindStorage.GetEntryPayload(entry);
        check(payload == nil, "읽어버렸다");
        check(reason == "PAYLOAD_TOO_OLD", "이유 " .. tostring(reason));
    end);

    test("버전이 숫자가 아닌 배치도 거절한다", function()
        local entry = StoredEntryWithVersion(nil);
        local payload, reason = DebindStorage.GetEntryPayload(entry);
        check(payload == nil, "읽어버렸다");
        check(reason == "PAYLOAD_TOO_NEW", "이유 " .. tostring(reason));
    end);

    -- **There is a second ladder under `payload.v`.** `v` counts the addressing and `dbver` counts
    -- the shape of the actions inside it. They used to ride on one number, and splitting them is
    -- why something is still left to ask once `v` has passed.
    --
    -- v1은 이 자리에 안 걸린다. 판 번호가 곧 답이라 어댑터가 5를 찍고 지나간다.
    local function StoredEntryWithDbver(dbver)
        local entry = StoredEntryWithVersion(DebindStorage.PAYLOAD_VERSION);
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
        check(reason == "PAYLOAD_TOO_NEW", "이유 " .. tostring(reason));
    end);

    -- **바닥은 공유가 나간 판이다.** 그 밑으로 내려가면 `MigrateLayer`의 옛 단계들에 닿는데,
    -- 그것들은 프로필만 지나가던 시절에 쓰여서 필드가 제 타입이라고 믿는다. 붙여넣기는 에러를
    -- 내면 안 되는 자리라 읽기 전에 거절한다.
    test("공유가 나가기 전 dbver를 든 배치는 거절한다", function()
        local payload, reason = DebindStorage.GetEntryPayload(StoredEntryWithDbver(4));
        check(payload == nil, "읽어버렸다");
        check(reason == "PAYLOAD_TOO_OLD", "이유 " .. tostring(reason));
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
    -- 쓸어내는 쪽이 아니라 **묻는** 쪽으로 짓는다(`building-export-import.md`).

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
        local list = LayerAt(payload, "account", "GENERAL", 0);
        local doomed = list[2];

        local removed = DebindStorage.RemoveEntryActions(EntryOf(payload), { [doomed] = true });

        check(removed == 1, "지운 수 " .. tostring(removed));
        check(#list == 2, "남은 수 " .. #list);
        for _, action in ipairs(list) do
            check(action ~= doomed, "지운 것이 남아 있다");
        end
    end);

    test("여러 레이어에 걸친 것도 한 번에 빠진다", function()
        local payload = Payload({
            { scope = "general", key = "F", count = 2 },
            { scope = "character", spec = 1, key = "F", count = 2 },
        });
        local general = LayerAt(payload, "account", "GENERAL", 0);
        local char = LayerAt(payload, GUID, CLASS, 1);
        local doomed = { [general[1]] = true, [char[1]] = true };

        check(DebindStorage.RemoveEntryActions(EntryOf(payload), doomed) == 2, "지운 수");
        check(#general == 1, "일반이 안 줄었다");
        check(#char == 1, "캐릭터가 안 줄었다");
    end);

    -- **빈 자리는 자리가 아니다.** 액션이 하나도 없는 주소가 남으면 그리는 쪽은 머리글을 세우고
    -- `PlanArrival`는 놓을 데를 내주는데, 놓을 것이 없다.
    test("비워진 레이어는 주소째 걷힌다", function()
        local payload = Payload({
            { scope = "general", key = "F", count = 1 },
            { scope = "class", class = CLASS, spec = 2, key = "G", count = 1 },
            { scope = "character", spec = 0, key = "H", count = 1 },
        });
        local doomed = {
            [LayerAt(payload, "account", "GENERAL", 0)[1]] = true,
            [LayerAt(payload, "account", CLASS, 2)[1]] = true,
            [LayerAt(payload, GUID, CLASS, 0)[1]] = true,
        };

        check(DebindStorage.RemoveEntryActions(EntryOf(payload), doomed) == 3, "지운 수");
        check(payload.layers.account == nil, "빈 계정 칸이 남았다");
        check(payload.layers[GUID] == nil, "빈 캐릭터 칸이 남았다");
    end);

    -- `characters` holds the character keys the payload names and no others.
    test("캐릭터 칸이 비면 그 신원도 걷힌다", function()
        local payload = Payload({
            { scope = "general", key = "F", count = 1 },
            { scope = "character", spec = 0, key = "H", count = 1 },
        });
        DebindStorage.RemoveEntryActions(EntryOf(payload),
            { [LayerAt(payload, GUID, CLASS, 0)[1]] = true });
        check(payload.characters == nil or payload.characters[GUID] == nil, "칸 없는 신원이 남았다");
    end);

    test("스위치 칸이 남은 캐릭터의 신원은 그대로 둔다", function()
        local payload = Payload({ { scope = "character", spec = 0, key = "H", count = 1 } });
        payload.switches = { [GUID] = { [CLASS] = { [0] = { ["$burst"] = { mode = "manual" } } } } };
        DebindStorage.RemoveEntryActions(EntryOf(payload),
            { [LayerAt(payload, GUID, CLASS, 0)[1]] = true });
        check(payload.characters and payload.characters[GUID], "스위치 칸의 신원을 걷었다");
    end);

    test("일부만 지운 레이어는 그대로 선다", function()
        local payload = Payload({ { scope = "general", key = "F", count = 2 } });
        local list = LayerAt(payload, "account", "GENERAL", 0);
        DebindStorage.RemoveEntryActions(EntryOf(payload), { [list[1]] = true });
        check(LayerAt(payload, "account", "GENERAL", 0) == list, "안 빈 목록을 걷었다");
        check(#list == 1, "남은 수");
    end);

    -- 원래 비어 있던 것을 치우지 않는다. 아무것도 안 지운 호출이 페이로드를 바꾸면, 눌러도
    -- 아무 일도 없는 메뉴 항목이 디스크의 내용을 건드리는 것이 된다.
    test("아무것도 안 지우면 아무것도 안 건드린다", function()
        local payload = Payload({ { scope = "general", key = "F", count = 0 } });
        local stranger = { type = Constants.SPELL, value = 99 };

        check(DebindStorage.RemoveEntryActions(EntryOf(payload), { [stranger] = true }) == 0,
            "없는 것을 지웠다고 답했다");
        check(LayerAt(payload, "account", "GENERAL", 0) ~= nil, "원래 비어 있던 목록을 걷었다");
    end);

    -- 매니페스트는 안 건드린다. 무엇을 참조했었나는 만들 때의 사실이고, 실제로 나가는 것만
    -- 남기는 것은 문자열을 만드는 순간의 일이다(`FilterPayload`).
    test("매니페스트는 그대로 둔다", function()
        local payload = Payload({ { scope = "general", key = "F", count = 1 } });
        payload.switches = { account = { GENERAL = { [0] = { ["$state3"] = { mode = "manual" } } } } };

        DebindStorage.RemoveEntryActions(EntryOf(payload),
            { [LayerAt(payload, "account", "GENERAL", 0)[1]] = true });
        check(payload.switches.account.GENERAL[0]["$state3"], "매니페스트가 사라졌다");
    end);

    ---------------------------------------------------------------------------
    -- The name lives in the payload (`ENTRY_VERSION` 2)
    ---------------------------------------------------------------------------

    -- A string can carry its sender's name now; the reader's own, when typed, is the one kept.
    test("이름 없이 붙이면 문자열의 이름이 남고, 붙이며 적은 이름이 그 위에 선다", function()
        ResetDrawer();
        local sent = Payload({ { scope = "general", key = "F" } });
        sent.name = "보낸 이름";
        STORED["DEB2:named"] = sent;
        check(DebindStorage.ImportEntry("DEB2:named").payload.name == "보낸 이름", "보낸 이름이 사라졌다");

        local again = Payload({ { scope = "general", key = "F" } });
        again.name = "보낸 이름";
        STORED["DEB2:again"] = again;
        check(DebindStorage.ImportEntry("DEB2:again", "내 이름").payload.name == "내 이름",
            "적은 이름이 안 섰다");
    end);

    -- A drawer from 4.1 holds the name on the row. Nothing but this step moves it, and a row whose
    -- name stayed behind would draw as if it had none.
    test("옛 서랍의 행 이름은 페이로드로 옮겨진다", function()
        ResetDrawer();
        local named = Payload({ { scope = "general", key = "F" } });
        _G.DebindStorageVars = { version = 1, nextID = 2, entries = {
            { id = 1, received = 0, name = "옛 이름", payload = named },
        } };

        local entries = DebindStorage.GetEntries();
        check(_G.DebindStorageVars.version == 2, "판 " .. tostring(_G.DebindStorageVars.version));
        check(entries[1].payload.name == "옛 이름", "이름이 안 옮겨졌다: " .. tostring(entries[1].payload.name));
        check(entries[1].name == nil, "행에 이름이 남았다");
    end);

    -- Whose cells a payload holds is the payload's own `characters`. A drawer from 4.1 also has who
    -- made the row beside it, and left there it is a second answer for the next reader to pick up.
    test("옛 서랍의 행이 든 만든 캐릭터·서버·guid는 걷힌다", function()
        ResetDrawer();
        _G.DebindStorageVars = { version = 1, nextID = 3, entries = {
            { id = 1, received = 100, character = "Tester", realm = "Test Realm", guid = "Player-1-A",
              payload = Payload({ { scope = "general", key = "F" } }) },
            { id = 2, received = 200, payload = Payload({ { scope = "general", key = "G" } }) },
        } };

        local entries = DebindStorage.GetEntries();
        check(_G.DebindStorageVars.version == 2, "판 " .. tostring(_G.DebindStorageVars.version));
        check(entries[1].character == nil and entries[1].realm == nil and entries[1].guid == nil,
            "행에 만든 캐릭터가 남았다");
        check(#entries == 2 and entries[1].payload and entries[2].payload, "행이나 페이로드가 사라졌다");
    end);

    -- The character beside a 4.1 row is the only record of it having been made here, so it has to
    -- become `receivedFrom` in the step that drops it. A 4.1 Clique row counts as read off a
    -- profile whichever way it came in (owner, 2026-10-03).
    test("옛 서랍의 행은 어디서 받았는지를 얻는다", function()
        ResetDrawer();
        local clique = { v = 2, dbver = Constants.DB_VERSION, source = "clique",
            shared = { GENERAL = { { type = Constants.SPELL, value = 1, key = "H", seq = 1 } } } };
        _G.DebindStorageVars = { version = 1, nextID = 4, entries = {
            { id = 1, received = 100, character = "Tester", payload = Payload({ { scope = "general", key = "F" } }) },
            { id = 2, received = 200, payload = Payload({ { scope = "general", key = "G" } }) },
            { id = 3, received = 300, payload = clique },
        } };

        local entries = DebindStorage.GetEntries();
        check(entries[1].receivedFrom == "profile", "만든 행 " .. tostring(entries[1].receivedFrom));
        check(entries[2].receivedFrom == "string", "붙여 넣은 행 " .. tostring(entries[2].receivedFrom));
        check(entries[3].receivedFrom == "profile", "Clique 행 " .. tostring(entries[3].receivedFrom));
        check(clique.fromAddon == "clique" and clique.source == nil, "Clique 표시가 안 옮겨졌다");
    end);

    -- A 4.1 payload has no `created`, and what said a row was made here was the character beside it.
    -- Made here, it was made the moment it was received; that has to reach the payload before the
    -- character goes, or the row's making is lost.
    test("옛 서랍의 여기서 만든 행은 받은 시각을 만든 시각으로 넘긴다", function()
        ResetDrawer();
        local made = Payload({ { scope = "general", key = "F" } });
        local pasted = Payload({ { scope = "general", key = "G" } });
        _G.DebindStorageVars = { version = 1, nextID = 3, entries = {
            { id = 1, received = 100, character = "Tester", payload = made },
            { id = 2, received = 200, payload = pasted },
        } };

        DebindStorage.GetEntries();
        check(made.created == 100, "만든 시각 " .. tostring(made.created));
        check(pasted.created == nil, "붙여 넣은 행에 만든 시각이 생겼다: " .. tostring(pasted.created));
    end);

    ---------------------------------------------------------------------------
    -- What a payload holds (`DescribePayload`), which names a row that has no name
    ---------------------------------------------------------------------------

    local Describe = DebindStorage.DescribePayload;

    test("액션 하나는 그 액션이고 키도 그 키다", function()
        local held = Describe(Payload({ { scope = "general", key = "F" } }));
        check(held.actions == 1 and held.action and held.action.value == 1, "액션");
        check(held.key == "F", "키 " .. tostring(held.key));
    end);

    test("한 키에 여럿이면 키만 선다", function()
        local held = Describe(Payload({
            { scope = "general", key = "F", count = 2 },
            { scope = "class", class = "MAGE", key = "F" },
        }));
        check(held.action == nil, "액션 하나로 읽었다");
        check(held.key == "F", "키 " .. tostring(held.key));
    end);

    test("키가 둘이거나 키 없는 것이 섞이면 키도 안 선다", function()
        check(Describe(Payload({
            { scope = "general", key = "F" }, { scope = "class", class = "MAGE", key = "G" },
        })).key == nil, "두 키");
        check(Describe(Payload({
            { scope = "general", key = "F" }, { scope = "class", class = "MAGE" },
        })).key == nil, "키 없는 것");
    end);

    test("일반, 직업, 캐릭터를 액션이 든 칸에서만 센다", function()
        local held = Describe(Payload({
            { scope = "general" },
            { scope = "class", class = "PRIEST" },
            { scope = "class", class = "MAGE", spec = 2 },
            { scope = "class", class = "SHAMAN", count = 0 },
            { scope = "character" },
        }));
        check(held.general, "일반");
        check(#held.classes == 3 and held.classes[1] == CLASS and held.classes[2] == "MAGE"
            and held.classes[3] == "PRIEST", "직업 " .. table.concat(held.classes, ","));
        check(#held.characters == 1 and held.characters[1] == GUID, "캐릭터");
        check(not held.anonymous, "이름 있는 캐릭터를 익명으로 읽었다");
    end);

    -- **Two axes, counted apart** (owner, 2026-09-29). A character's class is a class the payload
    -- holds whether or not an account layer of it is there too, and the character is counted on
    -- its own axis as well.
    test("캐릭터 칸의 직업도 직업으로 센다", function()
        local held = Describe(Payload({ { scope = "class", class = "MAGE" }, { scope = "character" } }));
        check(#held.classes == 2, "직업 " .. table.concat(held.classes, ","));
        check(#held.characters == 1, "캐릭터 " .. #held.characters);

        held = Describe(Payload({ { scope = "class", class = CLASS }, { scope = "character" } }));
        check(#held.classes == 1 and held.classes[1] == CLASS,
            "같은 직업을 두 번 셌다: " .. table.concat(held.classes, ","));
    end);

    -- A v2 string's character layer becomes a key with no `characters` entry, and nothing else marks it.
    test("신원 없는 캐릭터 칸이 있으면 익명이다", function()
        local payload = Payload({ { scope = "character" } });
        payload.characters = nil;
        check(Describe(payload).anonymous, "익명이 아니라고 읽었다");
        check(not Describe(Payload({ { scope = "general" } })).anonymous, "캐릭터 없는 것을 익명으로 읽었다");
    end);

    -- **Scopes nest** (3-2): a character's layers come with its class and general, so the one
    -- character is the whole answer - as long as no other class and no other character is in it.
    test("가장 좁은 범위 하나가 나머지를 품을 때만 선다", function()
        local only = Describe(Payload({
            { scope = "general" }, { scope = "class", class = CLASS }, { scope = "character" },
        })).only;
        check(only and only.kind == "character" and only.owner == GUID and only.class == CLASS,
            "캐릭터 " .. tostring(only and only.kind));

        only = Describe(Payload({ { scope = "general" }, { scope = "class", class = "MAGE", spec = 2 } })).only;
        check(only and only.kind == "class" and only.class == "MAGE", "직업");

        only = Describe(Payload({ { scope = "general" } })).only;
        check(only and only.kind == "general", "일반");

        -- Another class's layer beside the character is not covered by it.
        check(Describe(Payload({ { scope = "class", class = "MAGE" }, { scope = "character" } })).only == nil,
            "다른 직업을 캐릭터가 품었다");
        check(Describe(Payload({ { scope = "class", class = "MAGE" }, { scope = "class", class = "PRIEST" } })).only
            == nil, "직업 둘");
        check(Describe(Payload({})).only == nil, "빈 것");

        local two = Payload({ { scope = "character" } });
        two.layers["Player-1-OTHER"] = { [CLASS] = { [0] = { { type = Constants.SPELL, value = 9, seq = 1 } } } };
        check(Describe(two).only == nil, "캐릭터 둘을 하나로 불렀다");
    end);

    ---------------------------------------------------------------------------
    -- What the reader types as a name and a description (`SetEntryText`)
    ---------------------------------------------------------------------------

    test("이름과 설명은 앞뒤를 잘라 저장하고 빈 것은 nil이다", function()
        local entry = { payload = Payload({ { scope = "general" } }) };
        check(DebindStorage.SetEntryText(entry, "  이름 ", "\n 첫 줄\n둘째 줄 \n"), "저장 못 함");
        check(entry.payload.name == "이름", "이름 " .. tostring(entry.payload.name));
        check(entry.payload.description == "첫 줄\n둘째 줄", "설명 " .. tostring(entry.payload.description));

        DebindStorage.SetEntryText(entry, "   ", "\n\t\n");
        check(entry.payload.name == nil and entry.payload.description == nil, "빈 글이 남았다");
        check(not DebindStorage.SetEntryText({}, "x", "y"), "페이로드 없는 행에 썼다");
    end);

    -- One field of each, in the payload: the sender's own is replaced, which is the point.
    test("받은 행의 이름과 설명도 그 자리에서 바뀐다", function()
        local payload = Payload({ { scope = "general" } });
        payload.name, payload.description = "보낸 이름", "보낸 설명";
        local entry = { payload = payload };
        DebindStorage.SetEntryText(entry, "내 이름", "");
        check(payload.name == "내 이름" and payload.description == nil, "보낸 것이 남았다");
    end);

    ---------------------------------------------------------------------------
    -- A sender's text on our screen (`PlainText`)
    ---------------------------------------------------------------------------

    local Plain = DebindPrivate.PlainText;

    test("설명은 줄바꿈을 살리고 이름은 한 줄로 접는다", function()
        check(Plain("첫\r\n둘\r셋\t넷", 100, true) == "첫\n둘\n셋 넷", tostring(Plain("첫\r\n둘\r셋\t넷", 100, true)));
        check(Plain("첫\n둘", 100) == "첫 둘", "이름이 두 줄이 됐다");
    end);

    test("마크업은 글자 그대로 그려진다", function()
        check(Plain("|cffff0000빨강|r |Hitem:1|h[링크]|h |T1:0|t", 100)
            == "||cffff0000빨강||r ||Hitem:1||h[링크]||h ||T1:0||t", Plain("|cffff0000빨강|r", 100));
    end);

    test("줄바꿈은 한 줄로, 앞뒤 공백은 떼고, 빈 것은 없다", function()
        check(Plain("  첫 줄\n둘째\r\n셋째  ", 100) == "첫 줄 둘째 셋째", Plain("  첫 줄\n둘째\r\n셋째  ", 100));
        check(Plain(" \n ", 100) == nil, "빈 글");
        check(Plain(5, 100) == nil and Plain(nil, 100) == nil, "글이 아닌 것");
    end);

    test("글자 수로 자르고 한글을 가르지 않는다", function()
        check(Plain("가나다라", 3) == "가나다...", tostring(Plain("가나다라", 3)));
        check(Plain("가나다", 3) == "가나다", "딱 맞는 것을 잘랐다");
    end);

    -- Cut before it is escaped: escaped first, the cut could fall between the two of a `||`.
    test("자른 끝에 살아 있는 |가 안 남는다", function()
        check(Plain("ab|c", 3) == "ab||...", tostring(Plain("ab|c", 3)));
    end);

    ---------------------------------------------------------------------------
    -- Sanitized going in and coming out (`sanitizing-actions-with-one-function.md` §2-2)
    --
    -- **Both, because the preview, the counts and a string made again read the stored payload as
    -- it is.** A world marker with no value raises where a row names it.
    ---------------------------------------------------------------------------

    --- A general cell holding a spell with a field nothing saves and an arrival number no wire
    --- carries, then a world marker with no value.
    local function BrokenPayload()
        local payload = Payload({ { scope = "general", key = "F", count = 1,
            junk = { type = Constants.WORLDMARKER, key = "F", seq = 2 } } });
        local spell = payload.layers.account.GENERAL[0][1];
        spell.junk = 1;
        spell.arrivalID = "x";
        return payload;
    end

    --- The two actions of `BrokenPayload`, asked as they must come out.
    local function CheckSanitized(payload, what)
        local list = payload.layers.account.GENERAL[0];
        check(#list == 2, what .. ": " .. #list .. " actions");
        check(list[1].junk == nil, what .. ": a field nothing saves stayed");
        check(list[1].arrivalID == nil, what .. ": an arrival number stayed");
        check(list[2].type == Constants.INVALID, what .. ": the world marker is " .. tostring(list[2].type));
    end

    test("a pasted payload is sanitized as it is stored", function()
        ResetDrawer();
        STORED[GOOD] = BrokenPayload();
        local entry = DebindStorage.ImportEntry(GOOD);
        check(entry, "refused");
        CheckSanitized(entry.payload, "stored");
    end);

    test("a converted payload is sanitized as it is stored", function()
        ResetDrawer();
        local entry = DebindStorage.StorePayload(BrokenPayload());
        check(entry, "refused");
        CheckSanitized(entry.payload, "stored");
    end);

    test("what is already in the drawer is sanitized when the drawer is read", function()
        ResetDrawer();
        _G.DebindStorageVars = { version = 2, nextID = 2, entries = {
            { id = 1, received = 0, receivedFrom = "string", payload = BrokenPayload() },
        } };
        CheckSanitized(DebindStorage.GetEntries()[1].payload, "in the drawer");
    end);

    test("an entry is sanitized again when it is opened", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;
        local entry = DebindStorage.ImportEntry(GOOD);
        entry.payload = BrokenPayload();
        local payload = DebindStorage.GetEntryPayload(entry);
        check(payload, "refused");
        CheckSanitized(payload, "opened");
    end);

    DebindStorage.DecodeExportString = realDecode;

    return T;
end
