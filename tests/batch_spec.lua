-- What happens to a received string before it is committed: `DebindStorage/Import.lua`, and the
-- two functions that decide the reader's lines (`CollectImportLines` in `Debind/ImportUI.lua`).
--
-- Two things live here and they fail differently.
--
-- **Addressing** decides where a batch's actions end up. Getting it wrong is not a display bug:
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
-- SavedVariables and read back. What it stores is the payload, and the store carries a version so
-- that what an older one wrote can be brought forward instead of refused.

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

    ---------------------------------------------------------------------------
    -- The lines the reader is offered
    --
    -- Four checkboxes, not one per layer. Which line a layer belongs to comes out of **where it
    -- sits in the payload**, which is also the address it will land at - so a line the reader can
    -- tick and a place an action can go cannot come apart.
    ---------------------------------------------------------------------------

    --- A payload built from `{ scope, class, spec, count }` entries, one layer each.
    --- `count = 0` stands an **empty** layer up, and `junk` puts a non-action in the list -- both
    --- are shapes a hand-made string carries and neither may raise.
    local function Payload(layers)
        local payload = { v = 1, class = CLASS };

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

    local function LineIDs(payload)
        local out = {};
        for i, entry in ipairs(DebindPrivate.CollectImportLines(payload)) do
            out[i] = entry.line;
        end
        return table.concat(out, " ");
    end

    test("전문화 레이어는 자기 줄에 딸려 들어간다", function()
        local lines = DebindPrivate.CollectImportLines(Payload({
            { scope = "class", class = CLASS, spec = 2, key = "F", count = 2 },
            { scope = "class", class = CLASS, spec = 0, key = "G", count = 3 },
            { scope = "general", key = "H", count = 1 },
        }));

        check(#lines == 2, "줄 수 " .. #lines);
        check(lines[1].line == "shared.general", "일반이 먼저다");
        check(lines[1].actionCount == 1, "일반 개수 " .. lines[1].actionCount);
        check(lines[2].line == "shared.class", "직업 줄이 없다");
        check(lines[2].actionCount == 5, "직업 개수 " .. lines[2].actionCount);
    end);

    -- **Another class's string still stands a class line.** It really does go to that class's own
    -- place, so there is nothing to grey out and nothing to warn about.
    test("차례는 창의 탭 차례고 남의 직업도 줄이 선다", function()
        local order = LineIDs(Payload({
            { scope = "character", spec = 2 },
            { scope = "class", class = "MAGE", spec = 1 },
            { scope = "general" },
            { scope = "character", spec = 0 },
        }));
        check(order == "shared.general shared.class character.general character.spec",
            "차례: " .. order);
    end);

    -- A checkbox for something the string does not carry reads as a choice, and unticking it would
    -- do nothing at all.
    test("아무것도 없는 줄은 안 선다", function()
        local order = LineIDs(Payload({ { scope = "general" } }));
        check(order == "shared.general", "빈 줄이 섰다: " .. order);
    end);

    -- **갈 데가 없는 것은 줄을 안 세운다.** A line whose every action has nowhere to land is a
    -- checkbox that does nothing either way, and the reader has no means of telling it from one
    -- that would. The shim's character has four specializations, so spec 5 is one nothing here can
    -- hold.
    test("갈 데 없는 것만 있는 줄도 안 선다", function()
        local order = LineIDs(Payload({
            { scope = "character", spec = 5 },
            { scope = "general" },
        }));
        check(order == "shared.general", "놓을 데 없는 줄이 섰다: " .. order);
    end);

    -- **0은 "조금 있음"이 아니다.** 개수를 `if (count)`로 물으면 Lua에서 0이 참이라 빈 레이어도
    -- 체크박스를 세운다. 읽는 사람은 아무것도 안 놓는 줄을 켜고, 방금 그 선택을 내준 대화상자에게
    -- 오류로 답을 받는다.
    test("빈 레이어는 줄을 안 세운다", function()
        local order = LineIDs(Payload({
            { scope = "character", spec = 0, count = 0 },
            { scope = "general" },
        }));
        check(order == "shared.general", "빈 줄이 섰다: " .. order);
    end);

    -- **주소를 먼저 검증한다.** `ImportLineFor`는 특성을 0과 견주는데 그 값이 숫자인지 보는 곳은
    -- `ImportAddress` 하나뿐이라, 순서가 뒤집히면 손으로 만든 문자열 하나가 서랍을 여는 순간
    -- 터진다 - 읽는 사람에게는 죽은 버튼으로 보인다.
    test("특성 자리에 숫자가 아닌 것이 와도 안 터진다", function()
        local order = LineIDs(Payload({
            { scope = "character", spec = "2" },
            { scope = "general" },
        }));
        check(order == "shared.general", "이상한 특성이 줄을 만들었다: " .. order);
    end);

    -- 액션 자리에 액션이 아닌 것. 걸러내는 자리가 하나여야 세는 쪽도 넣는 쪽도 `ipairs`로
    -- 끝난다.
    test("액션이 아닌 원소는 걸러진다", function()
        local lines = DebindPrivate.CollectImportLines(Payload({
            { scope = "general", count = 2, junk = 5 },
        }));
        check(#lines == 1 and lines[1].actionCount == 2,
            "쓰레기까지 세었다: " .. tostring(lines[1] and lines[1].actionCount));
    end);

    test("모르는 직업 이름은 줄을 안 만든다", function()
        local order = LineIDs(Payload({
            { scope = "class", class = "NOSUCHCLASS", spec = 0 },
            { scope = "general" },
        }));
        check(order == "shared.general", "모르는 직업이 줄을 만들었다: " .. order);
    end);

    -- **직업 줄은 자기가 갈 직업을 부른다.** `payload.class` is what the string says about the
    -- sender, and a hand-made one can put another class's layer under it - then the label would
    -- print the sender's class over somebody else's layer.
    test("직업 줄은 그 레이어의 직업을 달고 나온다", function()
        local lines = DebindPrivate.CollectImportLines(Payload({
            { scope = "class", class = "MAGE", spec = 1 },
        }));
        check(#lines == 1 and lines[1].class == "MAGE",
            "직업이 안 실렸다: " .. tostring(lines[1] and lines[1].class));

        -- Two classes on one line: there is no single name to print, so none is offered and the
        -- dialog falls back to what the string says about the sender.
        lines = DebindPrivate.CollectImportLines(Payload({
            { scope = "class", class = "MAGE", spec = 1 },
            { scope = "class", class = CLASS, spec = 1 },
        }));
        check(#lines == 1 and lines[1].class == nil,
            "둘 중 하나를 골라 적었다: " .. tostring(lines[1] and lines[1].class));
    end);

    -- One key group can put actions on two lines, which is why the count is over actions. There is
    -- no number of groups a line owns.
    test("한 키가 두 줄에 걸쳐도 양쪽이 다 센다", function()
        local lines = DebindPrivate.CollectImportLines(Payload({
            { scope = "general", key = "F" },
            { scope = "character", spec = 0, key = "F" },
        }));
        check(#lines == 2, "줄 수 " .. #lines);
        check(lines[1].actionCount == 1 and lines[2].actionCount == 1, "개수");
    end);

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

        local batch = DebindStorage.AddBatch(GOOD, "친구");
        check(batch, "배치가 안 만들어짐");
        check(batch.source == "친구", "출처");
        check(#DebindStorage.GetBatches() == 1, "서랍에 안 들어감");
        check(DebindStorage.GetBatch(batch.id) == batch, "id로 못 찾음");
    end);

    -- Counted off the payload every time the row asks, because the payload is what the batch
    -- holds. The two numbers were stored fields while the string was.
    test("개수는 저장된 페이로드에서 나온다", function()
        ResetDrawer();
        local text = "DEB1:여럿";
        STORED[text] = Payload({
            { scope = "general", key = "F", count = 2 },
            { scope = "class", class = CLASS, spec = 1, key = "G", count = 3 },
        });

        local batch = DebindStorage.AddBatch(text);
        -- **A key is a group**, so two keys is two groups however the five actions are spread.
        local groupCount, actionCount = DebindStorage.CountBatch(batch);
        check(groupCount == 2, "그룹 수 " .. tostring(groupCount));
        check(actionCount == 5, "액션 수 " .. tostring(actionCount));
        check(batch.payload.class == CLASS, "보낸 쪽 클래스");
        check(batch.groupCount == nil and batch.actionCount == nil,
            "개수를 배치에 또 적어뒀다 - 페이로드와 갈릴 자리가 생긴다");
    end);

    -- Refused where the user is looking at it, rather than becoming a row that fails every time it
    -- is opened.
    test("못 읽는 문자열은 서랍에 안 들어간다", function()
        ResetDrawer();

        local batch, reason = DebindStorage.AddBatch("DEB1:쓰레기");
        check(batch == nil, "받아들였다");
        check(reason == "BAD_PAYLOAD", "이유 " .. tostring(reason));
        check(#DebindStorage.GetBatches() == 0, "서랍에 들어갔다");
    end);

    -- What SavedVariables holds is the payload. The string is refused outright once the schema
    -- moves past it, so a drawer of strings is a drawer nothing can bring forward.
    test("서랍에 남는 것은 페이로드지 문자열이 아니다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;

        local batch = DebindStorage.AddBatch("  " .. GOOD .. "\n");
        check(batch.payload == GOOD_PAYLOAD, "페이로드를 저장 안 했다");
        check(batch.text == nil, "문자열이 남아 있다: " .. tostring(batch.text));
        check(DebindStorage.GetBatchPayload(batch) == GOOD_PAYLOAD, "다시 못 읽음");
    end);

    ---------------------------------------------------------------------------
    -- Coming forward from store v1
    ---------------------------------------------------------------------------

    --- A drawer written by store v1: the string, the three values read out of it at paste time, and
    --- the empty tables a folded workbench left in the record.
    local function V1Drawer(batches)
        _G.DebindStorageVars = {
            version = 1,
            nextID  = #batches + 1,
            batches = batches,
        };
    end

    test("v1 배치가 페이로드로 올라온다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;
        V1Drawer({
            {
                id = 1, received = 100, source = "친구", committed = 200,
                text = GOOD, class = CLASS, groupCount = 1, actionCount = 1,
                layers = {}, keys = {}, excluded = {}, states = {},
            },
        });

        local batch = DebindStorage.GetBatch(1);
        check(batch.payload == GOOD_PAYLOAD, "페이로드로 안 옮겨졌다");
        check(batch.text == nil, "문자열이 남아 있다");
        check(batch.received == 100 and batch.source == "친구" and batch.committed == 200,
            "v2가 아는 것까지 같이 버렸다");
        check(batch.class == nil and batch.groupCount == nil and batch.actionCount == nil,
            "페이로드에서 읽을 수 있는 것을 또 들고 있다");
        check(batch.layers == nil and batch.keys == nil and batch.excluded == nil
            and batch.states == nil, "접힌 작업대가 남긴 빈 테이블이 그대로다");
        check(_G.DebindStorageVars.version == 2, "판 번호를 안 올렸다");
    end);

    -- **Nothing disappears from the drawer on login.** A string this cannot read was already
    -- unopenable, and the answer to it is the reader being told why - not the row being gone when
    -- they next look.
    test("못 읽는 v1 배치는 남고, 열 때 이유를 말한다", function()
        ResetDrawer();
        V1Drawer({
            { id = 1, received = 100, text = "DEB1:못읽음", groupCount = 3, actionCount = 9 },
        });

        local batch = DebindStorage.GetBatch(1);
        check(batch ~= nil, "배치가 사라졌다");
        check(batch.payload == nil, "못 읽는 것을 읽었다고 한다");
        check(batch.text == "DEB1:못읽음", "이유를 말할 근거까지 버렸다");

        local payload, reason = DebindStorage.GetBatchPayload(batch);
        check(payload == nil, "페이로드를 냈다");
        check(reason == "BAD_PAYLOAD", "이유 " .. tostring(reason));

        local groupCount, actionCount = DebindStorage.CountBatch(batch);
        check(groupCount == 0 and actionCount == 0,
            "셀 것이 없는데 개수를 냈다: " .. groupCount .. "/" .. actionCount);
    end);

    -- **거절이 다 영구적인 것은 아니다.** `LIBS_MISSING`은 이번 세션에 라이브러리를 못 읽었다는
    -- 말이고, 판 번호는 한 배치라도 옮겨졌는지와 무관하게 올라간다. 그러면 마이그레이션이 한 번
    -- 헛돈 서랍은 멀쩡한 문자열을 든 채로 영영 안 열린다.
    test("마이그레이션이 못 읽은 배치는 다음에 다시 묻는다", function()
        ResetDrawer();
        V1Drawer({ { id = 1, received = 100, text = GOOD } });

        -- 여기서 마이그레이션이 돈다. 아직 STORED가 비어 있어 디코더가 거절한다.
        local batch = DebindStorage.GetBatch(1);
        check(batch.payload == nil, "못 읽을 것을 읽었다");
        check(_G.DebindStorageVars.version == 2, "판 번호가 안 올라갔다 - 이 케이스의 전제다");

        -- 설치가 고쳐졌다. 서랍은 이미 v2라 마이그레이션은 다시 안 돈다.
        STORED[GOOD] = GOOD_PAYLOAD;

        check(DebindStorage.GetBatchPayload(batch) == GOOD_PAYLOAD, "다시 안 물었다");
        check(batch.payload == GOOD_PAYLOAD, "물어놓고 안 옮겼다");
        check(batch.text == nil, "옮기고도 문자열을 들고 있다");
    end);

    test("id는 지워도 다시 안 쓰인다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;

        local first = DebindStorage.AddBatch(GOOD);
        DebindStorage.DeleteBatch(first.id);
        local second = DebindStorage.AddBatch(GOOD);

        check(second.id ~= first.id, "지운 id가 재활용됐다 - 그 배치에 붙은 배지가 남의 것이 된다");
        check(#DebindStorage.GetBatches() == 1, "배치 수");
        check(DebindStorage.GetBatch(first.id) == nil, "지운 것이 남아 있다");
    end);

    test("없는 것을 지우면 아무 일도 안 난다", function()
        ResetDrawer();
        check(DebindStorage.DeleteBatch(999) == false, "지웠다고 답했다");
    end);

    -- A batch has to be openable after a `/reload`, and a reload is exactly what SavedVariables
    -- being a plain table has to survive. Nothing here may be a closure, a metatable, or a
    -- reference to a live profile table.
    test("배치는 저장 가능한 값만 들고 있다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;
        local batch = DebindStorage.AddBatch(GOOD);

        check(getmetatable(batch) == nil, "메타테이블이 붙어 있다");
        for k, v in pairs(batch) do
            local vt = type(v);
            check(vt == "string" or vt == "number" or vt == "boolean" or vt == "table",
                "저장 못 하는 값: " .. tostring(k) .. " = " .. vt);
        end
    end);

    -- **만료 케이스 셋이 여기 있었다** (`GetSecondsUntilExpiry` / `IsExpiringSoon` / 핀).
    -- 판정만 있고 쓸어내는 코드가 없어서, 그 셋은 화면에 아무 일도 안 일어나는 날짜를 띄우는
    -- 계산을 검사하고 있었다. 판정과 핀이 같이 빠지면서 스펙도 같이 나간다 — 되살릴 때는
    -- 쓸어내는 쪽이 아니라 **묻는** 쪽으로 짓는다(`devdocs/building-export-import.md`).

    DebindStorage.DecodeExportString = realDecode;

    return T;
end
