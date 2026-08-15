-- The export payload and the string layer. `DebindShare/Export.lua`.
--
-- Everything checked here is **a promise the format makes**. A format cannot be changed once a
-- string is in someone else's hands (that is what v1 being v1 means), so there is nowhere else
-- for a broken promise to be caught.
--
-- Two kinds go wrong silently even in the game:
--
--   * the action field whitelist. A field left out still saves and simply never exports, so it
--     arrives as an action with one condition missing and nobody sees an error.
--   * local references (macro names, state indices). Those "succeed" on the far side and point at
--     the wrong thing. Red text cannot catch that in principle, so only the format can.

return function(DebindPrivate, DebindShare)
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

    ---------------------------------------------------------------------------
    -- The macro store, stubbed
    --
    -- Only what wow_shim does not already provide. Looking up by name and splitting scope by index
    -- is the shape of the real API, and standing it up in that shape is what makes SnapshotMacro's
    -- branches actually run.
    ---------------------------------------------------------------------------

    local MACROS = {};

    _G.GetMacroInfo = function(nameOrIndex)
        local macro = MACROS[nameOrIndex];
        if (not macro) then
            return nil;
        end
        return macro.name, macro.icon, macro.body;
    end

    _G.GetMacroIndexByName = function(name)
        local macro = MACROS[name];
        return macro and macro.index or 0;
    end

    ---------------------------------------------------------------------------
    -- Standing up a profile
    ---------------------------------------------------------------------------

    --- Builds SavedVariables exactly as `InitDB` reads them and reopens the profile.
    --- Layer numbering follows `LAYER_INFOS` (Profile.lua): 1 = general, 2..6 = class (spec 0..4),
    --- 7..11 = character (spec 0..4).
    local function ResetProfile(layout)
        layout = layout or {};
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = {
                GENERAL = layout.general or {},
                classes = { [CLASS] = layout.class or {} },
            },
            characters = { [GUID] = { layers = layout.char or {} } },
            customStates = layout.customStates,
            migrated = {},
        };
        DebindPrivate.InitDB();
    end

    local function LayerActions(layerID)
        local layer = DebindPrivate.GetProfileLayer(layerID);
        check(layer, "no layer " .. layerID);
        local out = {};
        for _, action in layer:Enumerate() do
            out[#out + 1] = action;
        end
        return out;
    end

    --- Every action in the payload, whatever layer it is under. The nesting **is** the address
    --- now, so walking it is what a reader has to do too.
    local function AllActions(payload)
        local out = {};
        local function Take(list)
            for _, action in ipairs(list or {}) do
                out[#out + 1] = action;
            end
        end
        local function TakeSpecTable(specTbl)
            for _, list in pairs(specTbl or {}) do
                Take(list);
            end
        end

        Take(payload.shared and payload.shared.GENERAL);
        for _, classTbl in pairs(payload.shared and payload.shared.classes or {}) do
            TakeSpecTable(classTbl);
        end
        TakeSpecTable(payload.char);
        return out;
    end

    local function CountActions(payload)
        return #AllActions(payload);
    end

    --- One key group: everything sharing a key, in the order the payload lists it.
    local function GroupFor(payload, key)
        local out = {};
        for _, action in ipairs(AllActions(payload)) do
            if (action.key == key) then
                out[#out + 1] = action;
            end
        end
        return out;
    end

    --- The one action on `key`, so a test that means to look at a single action says so.
    local function OneOn(payload, key)
        local group = GroupFor(payload, key);
        check(#group == 1, "액션 수 " .. #group);
        return group[1];
    end

    ---------------------------------------------------------------------------
    -- Grouping
    ---------------------------------------------------------------------------

    test("한 레이어 한 키가 그룹 하나", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F", combat = true },
                { type = Constants.SPELL, value = 2, key = "F" },
                { type = Constants.SPELL, value = 3, key = "G" },
            },
        });

        local payload = DebindShare.BuildExportPayload();
        check(#GroupFor(payload, "F") == 2, "F 그룹 크기");
        check(#GroupFor(payload, "G") == 1, "G 그룹 크기");
    end);

    -- **A group is a key, and a key crosses layers.** It used to be one group per (layer, key), and
    -- that split is what the far side could never put back together: with the keys stripped the
    -- reader is handed two headings for one design, gives them two keys, and both fire. Nothing in
    -- the string by then could have told them otherwise.
    --
    -- Nothing declares the grouping now. The two halves sit under two addresses and are one group
    -- because they carry one key.
    test("같은 키면 레이어가 달라도 그룹 하나", function()
        ResetProfile({
            general = { { type = Constants.SPELL, value = 1, key = "F" } },
            class = { [0] = { { type = Constants.SPELL, value = 2, key = "F" } } },
        });

        local payload = DebindShare.BuildExportPayload();
        check(#GroupFor(payload, "F") == 2, "그룹이 갈렸다");
        check(#payload.shared.GENERAL == 1, "일반 자리");
        check(#payload.shared.classes[CLASS][0] == 1, "직업 공용 자리");
    end);

    test("키 없는 액션은 키 없이 나간다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1 },
                { type = Constants.SPELL, value = 2 },
            },
        });

        local actions = AllActions(DebindShare.BuildExportPayload());
        check(#actions == 2, "액션 수 " .. #actions);
        for _, action in ipairs(actions) do
            check(action.key == nil, "없던 키가 생겼다: " .. tostring(action.key));
        end
    end);

    -- **The ranking travels as a value, not as a position.** Relying on the array would mean the
    -- order survives only as long as nobody between decoding and placing rebuilds the list, and
    -- that is the kind of condition that breaks quietly later.
    test("그룹 안 차례는 seq가 말한다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 10, key = "F", seq = 20 },
                { type = Constants.SPELL, value = 20, key = "F", seq = 10 },
            },
        });

        local group = GroupFor(DebindShare.BuildExportPayload(), "F");
        for _, action in ipairs(group) do
            check(action.seq == (action.value == 10 and 20 or 10),
                "seq가 안 실렸다: " .. tostring(action.seq));
        end
    end);

    test("같은 프로필은 두 번 불러도 같은 문자열", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "SHIFT-F" },
                { type = Constants.SPELL, value = 2, key = "F" },
                { type = Constants.SPELL, value = 3, key = "G" },
            },
        });

        local first = AllActions(DebindShare.BuildExportPayload());
        local second = AllActions(DebindShare.BuildExportPayload());
        check(#first == #second, "액션 수가 흔들린다");
        for i = 1, #first do
            check(first[i].value == second[i].value, "자리 " .. i .. "이 흔들린다");
        end
    end);

    ---------------------------------------------------------------------------
    -- Selection, and dropping keys
    ---------------------------------------------------------------------------

    test("선택한 액션만 나간다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F" },
                { type = Constants.SPELL, value = 2, key = "G" },
            },
        });

        local stored = LayerActions(1);
        local payload = DebindShare.BuildExportPayload({ [stored[1]] = true });
        check(CountActions(payload) == 1, "액션 수 " .. CountActions(payload));
        check(AllActions(payload)[1].key == "F", "남은 키");
    end);

    -- **The set is what has to survive**, not the key. A conditional binding is several actions
    -- that only mean something together, so dropping the key outright would hand the reader a loose
    -- pile they cannot put back - and a wrong guess is silent, since two actions meant to share a
    -- key end up on two and both fire.
    test("키를 빼도 묶음은 살아남는다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F", combat = true },
                { type = Constants.SPELL, value = 2, key = "F" },
                { type = Constants.SPELL, value = 3, key = "G" },
            },
        });

        local payload = DebindShare.BuildExportPayload(nil, { stripKeys = true });
        local keys = {};
        for _, action in ipairs(AllActions(payload)) do
            check(type(action.key) == "number", "합성 키가 숫자가 아니다");
            keys[action.value] = action.key;
        end
        -- It has to still be 2 + 1, not one loose pile of actions.
        check(#GroupFor(payload, keys[1]) == 2, "묶음이 풀렸다");
        check(#GroupFor(payload, keys[3]) == 1, "안 묶인 것이 묶였다");
    end);

    -- **A never-bound action goes out with no key at all**, which is what says it was in nobody's
    -- set. Given a synthetic key it would arrive headed as a group whose key was withheld, and ask
    -- the reader what key something the sender does not use deserves.
    test("원래 키가 없던 액션은 합성 키도 안 받는다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F" },
                { type = Constants.SPELL, value = 2 },
            },
        });

        for _, action in ipairs(AllActions(DebindShare.BuildExportPayload(nil, { stripKeys = true }))) do
            if (action.value == 2) then
                check(action.key == nil, "안 묶였던 것에 키가 붙었다: " .. tostring(action.key));
            else
                check(type(action.key) == "number", "합성 키를 못 받았다");
            end
        end
    end);

    ---------------------------------------------------------------------------
    -- Action fields
    ---------------------------------------------------------------------------

    -- `imported` is the one field `KEYS_TO_SAVE` has and the wire does not. It says which batch an
    -- action arrived on **in this drawer**, so sending it would tell the far side that something
    -- they have just received had already been received, quarantined against a number that means
    -- nothing on their machine.
    test("imported는 안 실린다", function()
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });
        LayerActions(1)[1].imported = 4;

        check(OneOn(DebindShare.BuildExportPayload(), "F").imported == nil,
            "남의 서랍 번호가 나갔다");
    end);

    test("화이트리스트 밖 필드는 안 실리고 $상태 조건은 실린다", function()
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });

        -- Planted after `CleanUpDB`. Passing because that cleanup already removed it would mean
        -- this test never looked at the whitelist at all.
        local stored = LayerActions(1)[1];
        stored.somethingNobodyRegistered = true;
        stored["$state3"] = true;
        stored.combat = true;

        local action = OneOn(DebindShare.BuildExportPayload(), "F");
        check(action.somethingNobodyRegistered == nil, "모르는 필드가 나갔다");
        check(action["$state3"] == true, "$상태 조건이 빠졌다");
        check(action.combat == true, "combat이 빠졌다");
    end);

    test("페이로드는 사본이라 고쳐도 프로필이 안 바뀐다", function()
        ResetProfile({
            general = { { type = Constants.SPELL, value = 1, key = "F", checkedUnits = { target = 1 } } },
        });

        local payload = DebindShare.BuildExportPayload();
        local action = OneOn(payload, "F");
        action.value = 999;
        action.checkedUnits.target = 999;

        local stored = LayerActions(1)[1];
        check(stored.value == 1, "value가 프로필까지 바뀌었다");
        check(stored.checkedUnits.target == 1, "테이블이 참조로 나갔다");
    end);

    ---------------------------------------------------------------------------
    -- Describing layers
    ---------------------------------------------------------------------------

    -- **Layer IDs are the one thing that cannot travel** - 2..6 are "my class", so the sender's
    -- number does not point at the same layer on the reader's account. The path does: both profiles
    -- store under one general layer, then class by spec, then character by spec.
    test("레이어는 번호가 아니라 저장 경로로 나간다", function()
        ResetProfile({
            general = { { type = Constants.SPELL, value = 1, key = "F" } },
            class = { [0] = { { type = Constants.SPELL, value = 2, key = "G" } },
                      [1] = { { type = Constants.SPELL, value = 3, key = "H" } } },
            char = { [0] = { { type = Constants.SPELL, value = 4, key = "J" } } },
        });

        local payload = DebindShare.BuildExportPayload();
        check(payload.class == CLASS, "보내는 쪽 클래스가 없다");
        check(payload.shared.GENERAL[1].value == 1, "공용");
        check(payload.shared.classes[CLASS][0][1].value == 2, "클래스 스펙0");
        check(payload.shared.classes[CLASS][1][1].value == 3, "클래스 스펙1");
        -- The guid is dropped: "their character" means nothing here, so it says *this* character.
        check(payload.char[0][1].value == 4, "캐릭터 전용");
    end);

    test("비활성 스펙 레이어도 나간다", function()
        -- The live spec is 1 (wow_shim), so the spec 3 layer is one nothing is using right now.
        ResetProfile({ class = { [3] = { { type = Constants.SPELL, value = 1, key = "F" } } } });

        local payload = DebindShare.BuildExportPayload();
        check(CountActions(payload) == 1, "안 쓰는 스펙이 빠졌다");
        check(payload.shared.classes[CLASS][3][1].value == 1, "스펙 번호");
    end);

    -- An address with nothing at it is not the same as an address with nothing in it. Standing an
    -- empty list up in the string would give the far side something to walk that says nothing.
    test("빈 레이어는 경로 자체가 안 선다", function()
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });

        local payload = DebindShare.BuildExportPayload();
        check(payload.shared.classes == nil, "빈 직업 경로가 섰다");
        check(payload.char == nil, "빈 캐릭터 경로가 섰다");
    end);

    ---------------------------------------------------------------------------
    -- Local references: macros
    ---------------------------------------------------------------------------

    test("MACRO는 본문 스냅샷을 달고 나간다", function()
        MACROS = {
            ["내매크로"] = { name = "내매크로", icon = 123, body = "/cast 화염구", index = 4 },
        };
        ResetProfile({ general = { { type = Constants.MACRO, value = "내매크로", key = "F" } } });

        local action = OneOn(DebindShare.BuildExportPayload(), "F");
        check(action.type == Constants.MACRO, "타입은 그대로 유지한다");
        check(action.value == "내매크로", "이름도 그대로 남는다");
        check(action.macro, "스냅샷이 없다");
        check(action.macro.body == "/cast 화염구", "본문");
        check(action.macro.scope == "account", "인덱스 4는 계정 매크로");
    end);

    test("캐릭터 매크로는 스코프가 갈린다", function()
        local accountLimit = DebindPrivate.GetMacroSlotLimits();
        MACROS = {
            ["내것"] = { name = "내것", icon = 1, body = "/say hi", index = accountLimit + 2 },
        };
        ResetProfile({ general = { { type = Constants.MACRO, value = "내것", key = "F" } } });

        local action = OneOn(DebindShare.BuildExportPayload(), "F");
        check(action.macro.scope == "character", "스코프 " .. tostring(action.macro.scope));
    end);

    test("이미 끊어진 매크로도 그대로 싣는다", function()
        MACROS = {};
        ResetProfile({ general = { { type = Constants.MACRO, value = "없는것", key = "F" } } });

        local action = OneOn(DebindShare.BuildExportPayload(), "F");
        check(action.type == Constants.MACRO, "타입");
        check(action.value == "없는것", "이름");
        check(action.macro == nil, "없는 본문을 지어내면 안 된다");
    end);

    ---------------------------------------------------------------------------
    -- Local references: states
    ---------------------------------------------------------------------------

    test("SETSTATE는 인덱스가 아니라 이름으로 나간다", function()
        ResetProfile({
            general = {
                { type = Constants.SETSTATE, value = Constants.SETCUSTOM_MODE_TOGGLE + 3, key = "F" },
            },
        });

        local action = OneOn(DebindShare.BuildExportPayload(), "F");
        check(action.setstate, "정규화가 안 됐다");
        check(action.setstate.mode == "toggle", "모드 " .. tostring(action.setstate.mode));
        check(action.setstate.state == "$state3", "상태 " .. tostring(action.setstate.state));
        check(action.value == nil, "비트팩이 같이 나가면 어느 쪽이 진짜인지 모른다");
    end);

    test("SETCUSTOM은 손대지 않는다", function()
        -- Despite the name this is a custom **target** (a unit slot). Its index is structural, so
        -- it means the same thing in every install.
        ResetProfile({ general = { { type = Constants.SETCUSTOM, value = 2, key = "F" } } });

        local action = OneOn(DebindShare.BuildExportPayload(), "F");
        check(action.value == 2, "값이 바뀌었다");
        check(action.setstate == nil, "상태로 오해했다");
    end);

    ---------------------------------------------------------------------------
    -- The state manifest
    ---------------------------------------------------------------------------

    local function StatefulProfile(general)
        ResetProfile({
            general = general,
            customStates = {
                [1] = { mode = Constants.CUSTOM_STATE_MODES.MANUAL, initialValue = true,
                        displayMessage = "1번" },
                [3] = { mode = Constants.CUSTOM_STATE_MODES.MANUAL, displayMessage = "3번" },
                [4] = { mode = Constants.CUSTOM_STATE_MODES.MACRO_CONDITIONAL,
                        expr = "[$state5] [combat]" },
                [5] = { mode = Constants.CUSTOM_STATE_MODES.MANUAL, displayMessage = "5번" },
            },
        });
    end

    test("참조한 상태만 매니페스트에 담긴다", function()
        StatefulProfile({ { type = Constants.SPELL, value = 1, key = "F" } });
        local stored = LayerActions(1)[1];
        stored["$state3"] = true;

        local manifest = DebindShare.BuildExportPayload().states;
        check(manifest, "매니페스트가 없다");
        check(manifest["$state3"], "조건이 가리킨 상태가 빠졌다");
        check(manifest["$state3"].displayMessage == "3번", "정의가 안 실렸다");
        check(manifest["$state1"] == nil, "안 쓰는 상태까지 실렸다");
    end);

    test("아무 상태도 안 쓰면 매니페스트가 없다", function()
        StatefulProfile({ { type = Constants.SPELL, value = 1, key = "F" } });
        check(DebindShare.BuildExportPayload().states == nil, "빈 매니페스트가 붙었다");
    end);

    test("매크로텍스트에 손으로 적은 이름도 걷힌다", function()
        StatefulProfile({
            { type = Constants.MACROTEXT, value = "/cast [$state3] 화염구", key = "F" },
        });

        local manifest = DebindShare.BuildExportPayload().states;
        check(manifest and manifest["$state3"], "본문 안 이름이 안 걷혔다");
    end);

    test("SETSTATE가 가리킨 상태도 걷힌다", function()
        StatefulProfile({
            { type = Constants.SETSTATE, value = Constants.SETCUSTOM_MODE_ON + 3, key = "F" },
        });

        local manifest = DebindShare.BuildExportPayload().states;
        check(manifest and manifest["$state3"], "SETSTATE가 가리킨 상태가 빠졌다");
    end);

    test("상태의 expr이 부르는 상태까지 따라간다", function()
        StatefulProfile({ { type = Constants.SPELL, value = 1, key = "F" } });
        local stored = LayerActions(1)[1];
        stored["$state4"] = true;

        local manifest = DebindShare.BuildExportPayload().states;
        check(manifest["$state4"], "직접 참조");
        check(manifest["$state5"], "expr이 부르는 상태가 안 따라왔다");
    end);

    test("매니페스트에 런타임 값은 안 들어간다", function()
        StatefulProfile({ { type = Constants.SPELL, value = 1, key = "F" } });
        local stored = LayerActions(1)[1];
        stored["$state1"] = true;

        local definition = DebindShare.BuildExportPayload().states["$state1"];
        -- `BindDerivedTables` recomputes this from initialValue. It is a reading, not a setting.
        check(definition.value == nil, "value가 실렸다");
        check(definition.initialValue == true, "initialValue는 실려야 한다");
    end);

    ---------------------------------------------------------------------------
    -- The string round trip
    --
    -- The libraries are stood up for real. Both are pure Lua, so in principle all three runtimes
    -- see the same code.
    --
    -- WARNING: **LibDeflate cannot decompress under fengari.** Real lua 5.1 (luajit) and 5.4 both
    -- round-trip; only `node tests/run.js` fails inside `DecompressDeflate`. It is neither the
    -- library nor our code but fengari, and WoW is 5.1 so the game never reaches it.
    --
    -- So this splits in two. **Whether our format survives** is checked everywhere using
    -- LibSerialize alone, and the full trip with compression and encoding runs only on an
    -- interpreter that can do it. Which one ran is always printed: passing quietly without having
    -- run would make this file a liar.
    ---------------------------------------------------------------------------

    local repoRoot = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]run%.lua$") or ".";
    for _, path in ipairs({
        "/Debind/Libs/LibStub/LibStub.lua",
        "/DebindShare/Libs/LibDeflate/LibDeflate.lua",
        "/DebindShare/Libs/LibSerialize/LibSerialize.lua",
    }) do
        assert(loadfile(repoRoot .. path), "라이브러리를 못 읽었다: " .. path)();
    end

    local LibDeflate = LibStub("LibDeflate");

    --- **Ask with a sample long enough to actually compress.** A short input becomes a stored
    --- block instead, and that path round-trips fine even under fengari - asking with one gets a
    --- "yes" and then blows up on the real payload.
    local probe = ("debind "):rep(64);
    local deflateWorks = LibDeflate:DecompressDeflate(LibDeflate:CompressDeflate(probe)) == probe;

    --- Built once and read by both checks below.
    local function SamplePayload()
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 재생", index = 3 } };
        StatefulProfile({
            { type = Constants.SPELL, value = 774, key = "SHIFT-F", combat = true },
            { type = Constants.MACRO, value = "내매크로", key = "SHIFT-F" },
            { type = Constants.SETSTATE, value = Constants.SETCUSTOM_MODE_TOGGLE + 3, key = "G" },
        });
        return DebindShare.BuildExportPayload();
    end

    --- Is what came back what went out? Every value checked here exists to stop a local reference
    --- from resolving wrongly, so if this falls the format has stopped doing its whole job.
    local function CheckSurvived(payload)
        check(payload.v == DebindShare.EXPORT_SCHEMA_VERSION, "스키마 버전");
        check(payload.class == CLASS, "클래스");
        check(CountActions(payload) == 3, "액션 수 " .. CountActions(payload));
        local shiftF = GroupFor(payload, "SHIFT-F");
        check(#shiftF == 2, "SHIFT-F 그룹 크기 " .. #shiftF);
        check((shiftF[1].macro or shiftF[2].macro).body == "/cast 재생", "매크로 본문");
        check(OneOn(payload, "G").setstate.state == "$state3", "상태 이름");
        check(payload.states["$state3"].displayMessage == "3번", "매니페스트");
    end

    test("페이로드가 직렬화를 건너 살아 돌아온다", function()
        local LibSerialize = LibStub("LibSerialize");
        local ok, back = LibSerialize:Deserialize(LibSerialize:Serialize(SamplePayload()));
        check(ok, "역직렬화 실패");
        CheckSurvived(back);
    end);

    test("봉투 모양", function()
        local str = DebindShare.ExportSelection();
        check(type(str) == "string", "문자열이 아니다: " .. tostring(str));
        check(str:sub(1, 5) == "DEB1:", "봉투 머리 " .. str:sub(1, 8));
        check(not str:find("%s"), "공백이 섞이면 채팅으로 못 나른다");
    end);

    if (deflateWorks) then
        test("문자열로 나갔다 그대로 돌아온다", function()
            SamplePayload();
            local str = DebindShare.ExportSelection();
            local payload, err = DebindShare.DecodeExportString(str);
            check(payload, "디코드 실패: " .. tostring(err));
            CheckSurvived(payload);
        end);
    end

    io.write(deflateWorks
        and "  export: 압축까지 붙은 전체 왕복을 검사했다\n"
        or "  export: fengari라 압축 왕복은 못 돌았다 (직렬화 왕복만 검사). 실제 lua로 돌릴 것\n");

    ---------------------------------------------------------------------------
    -- The shape itself
    --
    -- **저장 구조 그대로**가 이 포맷의 결론이고, 그리는 코드를 번역 없이 재사용하려는 것이
    -- 그 이유다 (`devdocs/building-export-import.md`의 세 번째 ★ 절). 아래 넷이 그 결론이
    -- 실제로 선을 타고 나가는지를 본다.
    ---------------------------------------------------------------------------

    test("최상위가 저장 주소 그대로다", function()
        ResetProfile({
            general = { { type = Constants.SPELL, value = 1, key = "F" } },
            class = { [2] = { { type = Constants.SPELL, value = 2, key = "G" } } },
            char = { [0] = { { type = Constants.SPELL, value = 3, key = "H" } } },
        });

        local payload = DebindShare.BuildExportPayload();
        check(payload.groups == nil, "그룹 층이 아직 있다");
        check(payload.shared and #payload.shared.GENERAL == 1, "일반이 저장 경로에 없다");
        check(payload.shared.classes[CLASS][2][1].value == 2, "직업/특성2 경로");
        check(payload.char[0][1].value == 3, "캐릭터 경로");
        check(payload.shared.GENERAL[1].layer == nil, "레이어 서술이 남았다");
    end);

    test("key가 액션에 실려 그룹을 나른다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F", combat = true },
                { type = Constants.SPELL, value = 2, key = "F" },
            },
        });

        local actions = DebindShare.BuildExportPayload().shared.GENERAL;
        check(#actions == 2, "액션 수 " .. #actions);
        check(actions[1].key == "F" and actions[2].key == "F", "키가 액션에 없다");
    end);

    test("키를 빼면 숫자 키가 실린다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F", combat = true },
                { type = Constants.SPELL, value = 2, key = "F" },
                { type = Constants.SPELL, value = 3, key = "G" },
            },
        });

        local actions = DebindShare.BuildExportPayload(nil, { stripKeys = true }).shared.GENERAL;
        local byValue = {};
        for _, action in ipairs(actions) do
            check(type(action.key) == "number",
                "합성 키가 숫자가 아니다: " .. type(action.key));
            byValue[action.value] = action.key;
        end
        check(byValue[1] == byValue[2], "한 키였던 둘이 갈렸다");
        check(byValue[1] ~= byValue[3], "다른 키였던 것이 합쳐졌다");
    end);

    test("seq가 선에 실린다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 10, key = "F", seq = 1 },
                { type = Constants.SPELL, value = 20, key = "F", seq = 2 },
            },
        });

        for _, action in ipairs(DebindShare.BuildExportPayload().shared.GENERAL) do
            check(action.seq == (action.value == 10 and 1 or 2),
                "seq가 안 실렸다: " .. tostring(action.seq));
        end
    end);

    test("남의 문자열은 이유를 달고 거절한다", function()
        local cases = {
            { nil, "NOT_A_STRING" },
            { "", "NOT_A_DEBIND_STRING" },
            { "!WEAKAURAS:abcdef", "NOT_A_DEBIND_STRING" },
            { "DEB9:abcdef", "UNSUPPORTED_ENVELOPE" },
            { "DEB1:!!!!!!", "BAD_ENCODING" },
        };
        for _, case in ipairs(cases) do
            local payload, reason = DebindShare.DecodeExportString(case[1]);
            check(payload == nil, "받아들이면 안 된다: " .. tostring(case[1]));
            check(reason == case[2],
                tostring(case[1]) .. " -> " .. tostring(reason) .. " (기대 " .. case[2] .. ")");
        end
    end);

    return T;
end
