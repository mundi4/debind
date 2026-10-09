-- The export payload and the string layer. `DebindStorage/Export.lua`.
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
--     the wrong thing. No issue mark can catch that in principle, so only the format can.

return function(DebindPrivate, DebindStorage, harness)
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
    -- Only what wow_shim does not already provide. Looking a macro up by name is the shape of the
    -- real API and the only shape the export ever needs: a `MACRO` value is a name.
    ---------------------------------------------------------------------------

    local MACROS = {};

    _G.GetMacroInfo = function(nameOrIndex)
        local macro = MACROS[nameOrIndex];
        if (not macro) then
            return nil;
        end
        return macro.name, macro.icon, macro.body;
    end

    ---------------------------------------------------------------------------
    -- Standing up a profile
    ---------------------------------------------------------------------------

    --- Builds SavedVariables exactly as `InitDB` reads them and reopens the profile.
    --- Layer numbering follows `LAYER_INFOS` (Profile.lua): 1 = general, 2..6 = class (spec 0..4),
    --- 7..11 = character (spec 0..4). `classOverrides` and `charOverrides` are override cells by
    --- spec, `switches[owner][CLASS][spec]`.
    local function ResetProfile(layout)
        layout = layout or {};
        harness.Numbered(layout.general or {});
        for _, cells in pairs({ layout.class or {}, layout.char or {} }) do
            for _, actions in pairs(cells) do
                harness.Numbered(actions);
            end
        end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            layers = {
                account = {
                    GENERAL = { [0] = layout.general or {} },
                    [CLASS] = layout.class or {},
                },
                [GUID] = { [CLASS] = layout.char or {} },
            },
            characters = { [GUID] = {
                name = "Tester", realm = "TestRealm", class = CLASS, level = 80,
                firstSeen = 1, lastSeen = 2,
            } },
            switches = {
                account = {
                    GENERAL = { [0] = layout.switches or {} },
                    [CLASS] = layout.classOverrides,
                },
                [GUID] = layout.charOverrides and { [CLASS] = layout.charOverrides } or nil,
            },
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
        for _, classes in pairs(payload.layers or {}) do
            for _, specTbl in pairs(classes) do
                for _, list in pairs(specTbl) do
                    for _, action in ipairs(list) do
                        out[#out + 1] = action;
                    end
                end
            end
        end
        return out;
    end

    --- `payload.layers[owner][class][spec]`, or nil anywhere along the way.
    local function LayerAt(payload, owner, class, spec)
        local classes = payload.layers and payload.layers[owner];
        local specTbl = classes and classes[class];
        return specTbl and specTbl[spec];
    end

    --- The general layer, `layers.account.GENERAL[0]`.
    local function General(payload)
        return LayerAt(payload, "account", "GENERAL", 0);
    end

    --- The switch definitions, `switches.account.GENERAL[0]`.
    local function Definitions(payload)
        local classes = payload.switches and payload.switches.account;
        return classes and classes.GENERAL and classes.GENERAL[0];
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
                { type = Constants.SPELL, value = 1, key = "F", conditions = { combat = true } },
                { type = Constants.SPELL, value = 2, key = "F" },
                { type = Constants.SPELL, value = 3, key = "G" },
            },
        });

        local payload = DebindStorage.BuildExportPayload();
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

        local payload = DebindStorage.BuildExportPayload();
        check(#GroupFor(payload, "F") == 2, "그룹이 갈렸다");
        check(#General(payload) == 1, "일반 자리");
        check(#LayerAt(payload, "account", CLASS, 0) == 1, "직업 공용 자리");
    end);

    test("키 없는 액션은 키 없이 나간다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1 },
                { type = Constants.SPELL, value = 2 },
            },
        });

        local actions = AllActions(DebindStorage.BuildExportPayload());
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

        local group = GroupFor(DebindStorage.BuildExportPayload(), "F");
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

        local first = AllActions(DebindStorage.BuildExportPayload());
        local second = AllActions(DebindStorage.BuildExportPayload());
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
        local payload = DebindStorage.BuildExportPayload({ [stored[1]] = true });
        check(CountActions(payload) == 1, "액션 수 " .. CountActions(payload));
        check(AllActions(payload)[1].key == "F", "남은 키");
    end);

    ---------------------------------------------------------------------------
    -- Action fields
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    -- 배지 달린 것은 안 나간다
    --
    -- **내보내기가 하는 말은 "이게 내 세팅이다"인데, 아직 결정 안 한 남의 것은 내 것이 아니다.**
    -- 실어 보내면 결정 안 된 것이 사람을 건너 퍼진다 - 받는 쪽에서 또 배지를 달고 서고, 그
    -- 사람도 판단할 근거가 없다.
    ---------------------------------------------------------------------------

    test("배지 달린 액션은 안 나간다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F" },
                { type = Constants.SPELL, value = 2, key = "G" },
            },
        });
        LayerActions(1)[2].arrivalID = 4;

        local payload = DebindStorage.BuildExportPayload();
        check(CountActions(payload) == 1, "액션 수 " .. CountActions(payload));
        check(#GroupFor(payload, "G") == 0, "격리 중인 것이 나갔다");
    end);

    -- **고른 것이어도 안 나간다.** 창은 자기 목록에서 같은 집합을 걸러내지만, 이 창은 메인 창에
    -- 수명이 안 묶여 있어서 열어둔 채로 배지가 붙거나 떨어질 수 있다. 여기가 그걸 지키는 자리다.
    test("골라도 배지 달린 것은 안 나간다", function()
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });
        local stored = LayerActions(1)[1];
        stored.arrivalID = 4;

        local payload = DebindStorage.BuildExportPayload({ [stored] = true });
        check(CountActions(payload) == 0, "고르면 나간다");
    end);

    -- **한 키가 반만 나갈 수 있고, 그게 맞다.** 배지 달린 하나는 아직 그 세팅의 일부가 아니다.
    test("한 키에 섞여 있으면 승인된 것만 나간다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F", conditions = { combat = true } },
                { type = Constants.SPELL, value = 2, key = "F" },
            },
        });
        LayerActions(1)[2].arrivalID = 4;

        check(#GroupFor(DebindStorage.BuildExportPayload(), "F") == 1, "반만 나가야 한다");
    end);

    ---------------------------------------------------------------------------
    -- Action fields
    ---------------------------------------------------------------------------

    -- `imported` is the one field `KEYS_TO_SAVE` has and the wire does not. Nothing carrying it
    -- goes out at all (above), so what this guards is the field arriving on something else - a
    -- copy made from a badged action, a hand-edited file.
    test("imported는 액션에 실리지 않는다", function()
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });

        check(OneOn(DebindStorage.BuildExportPayload(), "F").arrivalID == nil,
            "명단에 없는 필드가 나갔다");
    end);

    test("화이트리스트 밖 필드는 안 실리고 $상태 조건은 실린다", function()
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });

        -- Planted after `CleanUpDB`. Passing because that cleanup already removed it would mean
        -- this test never looked at the whitelist at all.
        local stored = LayerActions(1)[1];
        stored.somethingNobodyRegistered = true;
        stored.conditions = { ["$state3"] = true, combat = true,
            -- 조건 표 **안쪽**도 명단이 있다(`CONDITION_TYPES`). 바깥만 검사하고 안쪽을
            -- 통째로 복사하면 손으로 만든 문자열이 아무 이름이나 실어 보낼 수 있다.
            somethingNobodyRegistered = true };

        local action = OneOn(DebindStorage.BuildExportPayload(), "F");
        check(action.somethingNobodyRegistered == nil, "모르는 필드가 나갔다");
        check(action.conditions["$state3"] == true, "$상태 조건이 빠졌다");
        check(action.conditions.combat == true, "combat이 빠졌다");
    end);


    test("페이로드는 사본이라 고쳐도 프로필이 안 바뀐다", function()
        ResetProfile({
            general = { { type = Constants.SPELL, value = 1, key = "F",
                conditions = { units = { target = { exists = true, reaction = Constants.REACTION_HELP } } } } },
        });

        local payload = DebindStorage.BuildExportPayload();
        local action = OneOn(payload, "F");
        action.value = 999;
        action.conditions.units.target.reaction = Constants.REACTION_HARM;

        local stored = LayerActions(1)[1];
        check(stored.value == 1, "value가 프로필까지 바뀌었다");
        check(stored.conditions.units.target.reaction == Constants.REACTION_HELP, "테이블이 참조로 나갔다");
    end);

    ---------------------------------------------------------------------------
    -- Describing layers
    ---------------------------------------------------------------------------

    -- **Layer IDs are the one thing that cannot travel** - 2..6 are "my class", so the sender's
    -- number does not point at the same layer on the reader's account. The path does: it is the
    -- saved shape, `layers[owner][class][spec]`, and every cell carries its class as a key.
    test("레이어는 번호가 아니라 저장 경로로 나간다", function()
        ResetProfile({
            general = { { type = Constants.SPELL, value = 1, key = "F" } },
            class = { [0] = { { type = Constants.SPELL, value = 2, key = "G" } },
                      [1] = { { type = Constants.SPELL, value = 3, key = "H" } } },
            char = { [0] = { { type = Constants.SPELL, value = 4, key = "J" } } },
        });

        local payload = DebindStorage.BuildExportPayload();
        check(General(payload)[1].value == 1, "공용");
        check(LayerAt(payload, "account", CLASS, 0)[1].value == 2, "클래스 스펙0");
        check(LayerAt(payload, "account", CLASS, 1)[1].value == 3, "클래스 스펙1");
        check(LayerAt(payload, GUID, CLASS, 0)[1].value == 4, "캐릭터 전용");
        check(payload.class == nil, "직업은 칸의 키가 드는데 꼭대기에 또 섰다");
    end);

    test("비활성 스펙 레이어도 나간다", function()
        -- The live spec is 1 (wow_shim), so the spec 3 layer is one nothing is using right now.
        ResetProfile({ class = { [3] = { { type = Constants.SPELL, value = 1, key = "F" } } } });

        local payload = DebindStorage.BuildExportPayload();
        check(CountActions(payload) == 1, "안 쓰는 스펙이 빠졌다");
        check(LayerAt(payload, "account", CLASS, 3)[1].value == 1, "스펙 번호");
    end);

    -- An address with nothing at it is not the same as an address with nothing in it. Standing an
    -- empty list up in the string would give the far side something to walk that says nothing.
    test("빈 레이어는 경로 자체가 안 선다", function()
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });

        local payload = DebindStorage.BuildExportPayload();
        check(payload.layers.account[CLASS] == nil, "빈 직업 경로가 섰다");
        check(payload.layers[GUID] == nil, "빈 캐릭터 경로가 섰다");
        check(payload.characters == nil, "캐릭터 칸이 없는데 신원이 실렸다");
    end);

    ---------------------------------------------------------------------------
    -- Who a character cell is
    --
    -- **A cell keeps its guid and says who it is** (2026-09-27, owner; `reshaping-stored-layers.md`
    -- 1-1). Renumbered cells cannot be put back: a backup kept as a string would not know which
    -- character `"1"` was.
    ---------------------------------------------------------------------------

    test("캐릭터 칸의 신원이 실린다", function()
        ResetProfile({ char = { [0] = { { type = Constants.SPELL, value = 1, key = "F" } } } });

        local who = (DebindStorage.BuildExportPayload().characters or {})[GUID];
        check(who, "신원이 없다");
        check(who.name == "Tester" and who.realm == "TestRealm", "이름 " .. tostring(who.name));
        check(who.class == CLASS and who.level == 80, "직업 " .. tostring(who.class));
    end);

    -- They count this install's sightings of the character, and mean nothing on another one.
    test("이 설치의 기록은 신원에 안 실린다", function()
        ResetProfile({ char = { [0] = { { type = Constants.SPELL, value = 1, key = "F" } } } });

        local who = DebindStorage.BuildExportPayload().characters[GUID];
        for _, field in ipairs({ "firstSeen", "lastSeen" }) do
            check(who[field] == nil, field .. "가 실렸다");
        end
    end);

    test("신원은 사본이라 고쳐도 프로필이 안 바뀐다", function()
        ResetProfile({ char = { [0] = { { type = Constants.SPELL, value = 1, key = "F" } } } });

        DebindStorage.BuildExportPayload().characters[GUID].name = "바꾼이름";
        check(_G.DebindVars.characters[GUID].name == "Tester", "프로필의 신원이 바뀌었다");
    end);

    ---------------------------------------------------------------------------
    -- Local references: macros
    ---------------------------------------------------------------------------

    -- **The body does not travel** (2026-08-18, `building-export-import.md`). It is text
    -- the user wrote freely and we do not know what is in it, and the sender knows only that this
    -- action calls one of their macros, not that its contents ride along. The name goes, and that
    -- is all that goes.
    test("MACRO는 이름만 나가고 본문은 안 나간다", function()
        MACROS = {
            ["내매크로"] = { name = "내매크로", icon = 123, body = "/cast 화염구", index = 4 },
        };
        ResetProfile({ general = { { type = Constants.MACRO, value = "내매크로", key = "F" } } });

        local action = OneOn(DebindStorage.BuildExportPayload(), "F");
        check(action.type == Constants.MACRO, "타입은 그대로 유지한다");
        check(action.value == "내매크로", "이름은 그대로 남는다");
        check(action.macro == nil, "본문 스냅샷이 실렸다");
        for _, field in ipairs({ "body", "scope" }) do
            check(action[field] == nil, "본문 필드가 다른 이름으로 실렸다: " .. field);
        end
    end);

    test("이미 끊어진 매크로도 그대로 싣는다", function()
        MACROS = {};
        ResetProfile({ general = { { type = Constants.MACRO, value = "없는것", key = "F" } } });

        local action = OneOn(DebindStorage.BuildExportPayload(), "F");
        check(action.type == Constants.MACRO, "타입");
        check(action.value == "없는것", "이름");
        check(action.macro == nil, "없는 본문을 지어내면 안 된다");
    end);

    ---------------------------------------------------------------------------
    -- Local references: states
    ---------------------------------------------------------------------------

    -- **The one field the export used to rewrite.** A `setstate = { mode, state }` subtable was
    -- hung on the copy and `value` was cleared, which put the same action in two shapes and the
    -- migration for it in two copies (`unifying-action-migration.md`). What is asked
    -- now is that nothing is rewritten at all.
    test("SETSWITCH도 저장된 모양 그대로 나간다", function()
        ResetProfile({
            general = {
                { type = Constants.SETSWITCH_TOGGLE, value = "$state3", key = "F" },
            },
        });

        local action = OneOn(DebindStorage.BuildExportPayload(), "F");
        check(action.type == Constants.SETSWITCH_TOGGLE, "타입 " .. tostring(action.type));
        check(action.value == "$state3", "값 " .. tostring(action.value));
        check(action.setstate == nil, "선에만 있는 모양을 아직 만들고 있다");
    end);

    test("SETCUSTOM은 손대지 않는다", function()
        -- Despite the name this is a custom **target** (a unit slot). Its index is structural, so
        -- it means the same thing in every install.
        ResetProfile({ general = { { type = Constants.SETCUSTOM, value = 2, key = "F" } } });

        local action = OneOn(DebindStorage.BuildExportPayload(), "F");
        check(action.value == 2, "값이 바뀌었다");
        check(action.setstate == nil, "상태로 오해했다");
    end);

    ---------------------------------------------------------------------------
    -- The state manifest
    ---------------------------------------------------------------------------

    local function StatefulProfile(general)
        ResetProfile({
            general = general,
            switches = {
                ["$state1"] = { mode = Constants.SWITCH_MODES.MANUAL, resetValue = true },
                ["$state3"] = { mode = Constants.SWITCH_MODES.MANUAL, resetValue = false },
                ["$state4"] = { mode = Constants.SWITCH_MODES.EXPR,
                        expr = "[$state5] [combat]" },
                ["$state5"] = { mode = Constants.SWITCH_MODES.MANUAL },
            },
        });
    end

    test("참조한 상태만 매니페스트에 담긴다", function()
        StatefulProfile({ { type = Constants.SPELL, value = 1, key = "F" } });
        local stored = LayerActions(1)[1];
        stored.conditions = { ["$state3"] = true };

        local manifest = Definitions(DebindStorage.BuildExportPayload());
        check(manifest, "매니페스트가 없다");
        check(manifest["$state3"], "조건이 가리킨 상태가 빠졌다");
        check(manifest["$state3"].resetValue == false, "정의가 안 실렸다");
        check(manifest["$state1"] == nil, "안 쓰는 상태까지 실렸다");
    end);

    test("아무 상태도 안 쓰면 매니페스트가 없다", function()
        StatefulProfile({ { type = Constants.SPELL, value = 1, key = "F" } });
        check(DebindStorage.BuildExportPayload().switches == nil, "빈 매니페스트가 붙었다");
    end);

    test("매크로텍스트에 손으로 적은 이름도 걷힌다", function()
        StatefulProfile({
            { type = Constants.MACROTEXT, value = "/cast [$state3] 화염구", key = "F" },
        });

        local manifest = Definitions(DebindStorage.BuildExportPayload());
        check(manifest and manifest["$state3"], "본문 안 이름이 안 걷혔다");
    end);

    test("SETSWITCH가 가리킨 스위치도 걷힌다", function()
        StatefulProfile({
            { type = Constants.SETSWITCH_ON, value = "$state3", key = "F" },
        });

        local manifest = Definitions(DebindStorage.BuildExportPayload());
        check(manifest and manifest["$state3"], "SETSWITCH가 가리킨 스위치가 빠졌다");
    end);

    test("상태의 expr이 부르는 상태까지 따라간다", function()
        StatefulProfile({ { type = Constants.SPELL, value = 1, key = "F" } });
        local stored = LayerActions(1)[1];
        stored.conditions = { ["$state4"] = true };

        local manifest = Definitions(DebindStorage.BuildExportPayload());
        check(manifest["$state4"], "직접 참조");
        check(manifest["$state5"], "expr이 부르는 상태가 안 따라왔다");
    end);

    test("매니페스트에 런타임 값은 안 들어간다", function()
        StatefulProfile({ { type = Constants.SPELL, value = 1, key = "F" } });
        local stored = LayerActions(1)[1];
        stored.conditions = { ["$state1"] = true };

        local definition = Definitions(DebindStorage.BuildExportPayload())["$state1"];
        -- `BindDerivedTables` recomputes this from resetValue. It is a reading, not a setting.
        check(definition.value == nil, "value가 실렸다");
        check(definition.resetValue == true, "resetValue는 실려야 한다");
    end);

    -- **Override rows travel now**, in the cell they sit in (`reshaping-stored-layers.md` 1-1). v2
    -- left them home because their key named this install's characters; a cell's key is the layer's
    -- own address now, the same one `layers` uses.
    test("참조한 스위치의 오버라이드 행이 제 칸으로 실린다", function()
        ResetProfile({
            general = { { type = Constants.SETSWITCH_TOGGLE, value = "$state3", key = "F" } },
            switches = {
                ["$state1"] = { mode = Constants.SWITCH_MODES.MANUAL },
                ["$state3"] = { mode = Constants.SWITCH_MODES.MANUAL },
            },
            classOverrides = { [2] = {
                ["$state3"] = { mode = Constants.SWITCH_MODES.MANUAL, resetValue = true },
                ["$state1"] = { mode = Constants.SWITCH_MODES.MANUAL, resetValue = true },
            } },
            charOverrides = { [0] = {
                ["$state3"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]" },
            } },
        });

        local switches = DebindStorage.BuildExportPayload().switches;
        local classRow = switches.account[CLASS] and switches.account[CLASS][2]["$state3"];
        check(classRow and classRow.resetValue == true, "직업 칸의 행이 빠졌다");
        check(switches.account[CLASS][2]["$state1"] == nil, "안 쓰는 스위치의 행이 실렸다");
        local charRow = switches[GUID] and switches[GUID][CLASS][0]["$state3"];
        check(charRow and charRow.expr == "[combat]", "캐릭터 칸의 행이 빠졌다");
    end);

    -- `characters` holds every character key the payload names, and `switches` names one too.
    test("오버라이드만 있는 캐릭터 칸도 신원을 든다", function()
        ResetProfile({
            general = { { type = Constants.SETSWITCH_TOGGLE, value = "$state3", key = "F" } },
            switches = { ["$state3"] = { mode = Constants.SWITCH_MODES.MANUAL } },
            charOverrides = { [0] = { ["$state3"] = { mode = Constants.SWITCH_MODES.MANUAL } } },
        });

        local payload = DebindStorage.BuildExportPayload();
        check(payload.layers[GUID] == nil, "전제: 캐릭터 레이어는 비어 있다");
        check(payload.characters and payload.characters[GUID], "신원이 없다");
    end);

    -- A switch a row's expression names has to travel too, or the row arrives naming nothing.
    test("오버라이드 행의 expr이 부르는 스위치도 따라간다", function()
        ResetProfile({
            general = { { type = Constants.SETSWITCH_TOGGLE, value = "$state3", key = "F" } },
            switches = {
                ["$state3"] = { mode = Constants.SWITCH_MODES.MANUAL },
                ["$state5"] = { mode = Constants.SWITCH_MODES.MANUAL },
            },
            classOverrides = { [0] = {
                ["$state3"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[$state5]" },
            } },
        });

        check(Definitions(DebindStorage.BuildExportPayload())["$state5"],
            "행의 expr이 부르는 스위치가 안 따라왔다");
    end);

    ---------------------------------------------------------------------------
    -- The string round trip
    --
    -- **`DEB2:` is packed by the client** (`C_EncodingUtil`, CBOR), which headless does not have.
    -- The stand-in below keeps what the probes measured on both clients, a table coming back with
    -- its key types, by serializing with LibSerialize, which keeps them too. What CBOR itself does
    -- with our shape is the probes' answer (`reshaping-stored-layers.md` 1-2), not this file's.
    --
    -- `DEB1:` still goes through the two libraries, stood up for real.
    ---------------------------------------------------------------------------

    local repoRoot = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]run%.lua$") or ".";
    for _, path in ipairs({
        "/Debind/Libs/LibStub/LibStub.lua",
        "/DebindStorage/Libs/LibDeflate/LibDeflate.lua",
        "/DebindStorage/Libs/LibSerialize/LibSerialize.lua",
    }) do
        assert(loadfile(repoRoot .. path), "라이브러리를 못 읽었다: " .. path)();
    end

    do
        local LibSerialize, LibDeflate = LibStub("LibSerialize"), LibStub("LibDeflate");
        --- The client raises on input it cannot read, so the stand-in does too.
        local function Must(value, what)
            if (value == nil) then
                error("bad " .. what);
            end
            return value;
        end
        Enum.CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 };
        Enum.CompressionLevel = { Default = 0, OptimizeForSpeed = 1, OptimizeForSize = 2 };
        _G.C_EncodingUtil = {
            SerializeCBOR = function(value)
                return LibSerialize:Serialize(value);
            end,
            DeserializeCBOR = function(text)
                local ok, value = LibSerialize:Deserialize(text);
                return Must(ok and value or nil, "cbor");
            end,
            CompressString = function(text, method)
                assert(method == Enum.CompressionMethod.Deflate, "method");
                return LibDeflate:CompressDeflate(text);
            end,
            DecompressString = function(text, method)
                assert(method == Enum.CompressionMethod.Deflate, "method");
                return Must(LibDeflate:DecompressDeflate(text), "deflate");
            end,
            EncodeBase64 = function(text)
                return LibDeflate:EncodeForPrint(text);
            end,
            DecodeBase64 = function(text)
                return Must(LibDeflate:DecodeForPrint(text), "base64");
            end,
        };
    end

    --- Built once and read by both checks below.
    local function SamplePayload()
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 재생", index = 3 } };
        StatefulProfile({
            { type = Constants.SPELL, value = 774, key = "SHIFT-F", conditions = { combat = true } },
            { type = Constants.MACRO, value = "내매크로", key = "SHIFT-F" },
            { type = Constants.SETSWITCH_TOGGLE, value = "$state3", key = "G" },
        });
        return DebindStorage.BuildExportPayload();
    end

    --- Is what came back what went out? Every value checked here exists to stop a local reference
    --- from resolving wrongly, so if this falls the format has stopped doing its whole job.
    local function CheckSurvived(payload)
        check(payload.v == DebindStorage.PAYLOAD_VERSION, "페이로드 판");
        -- The actions' version rides apart from `v`. Without it the reader refuses the payload.
        check(payload.dbver == Constants.DB_VERSION, "dbver " .. tostring(payload.dbver));
        check(CountActions(payload) == 3, "액션 수 " .. CountActions(payload));
        local shiftF = GroupFor(payload, "SHIFT-F");
        check(#shiftF == 2, "SHIFT-F 그룹 크기 " .. #shiftF);
        local macro = shiftF[1].type == Constants.MACRO and shiftF[1] or shiftF[2];
        check(macro.value == "내매크로", "매크로 이름 " .. tostring(macro.value));
        check(OneOn(payload, "G").value == "$state3", "상태 이름");
        check(Definitions(payload)["$state3"].resetValue == false, "매니페스트");
    end

    test("봉투 모양", function()
        local str = DebindStorage.EncodeExportPayload(DebindStorage.BuildExportPayload());
        check(type(str) == "string", "문자열이 아니다: " .. tostring(str));
        check(str:sub(1, 5) == "DEB2:", "봉투 머리 " .. str:sub(1, 8));
        check(not str:find("%s"), "공백이 섞이면 채팅으로 못 나른다");
    end);

    test("문자열로 나갔다 그대로 돌아온다", function()
        SamplePayload();
        local str = DebindStorage.EncodeExportPayload(DebindStorage.BuildExportPayload());
        local payload, err = DebindStorage.DecodeExportString(str);
        check(payload, "디코드 실패: " .. tostring(err));
        CheckSurvived(payload);
    end);

    -- **`DEB1:` is read for as long as the libraries ship** (`reshaping-stored-layers.md` 1-2). It
    -- carries v2, so what comes out has been through the v2 step too.
    test("DEB1 문자열도 읽혀서 v3로 올라온다", function()
        local LibSerialize, LibDeflate = LibStub("LibSerialize"), LibStub("LibDeflate");
        local str = "DEB1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(
            LibSerialize:Serialize({
                v = 2, dbver = 7, class = CLASS,
                shared = { GENERAL = { { type = Constants.SPELL, value = 1, key = "F", seq = 1 } } },
            }), { level = 9 }));

        local payload, err = DebindStorage.DecodeExportString(str);
        check(payload, "디코드 실패: " .. tostring(err));
        check(payload.v == DebindStorage.PAYLOAD_VERSION, "판 " .. tostring(payload.v));
        check(General(payload) and General(payload)[1].value == 1, "일반 레이어가 안 옮겨졌다");
    end);

    ---------------------------------------------------------------------------
    -- Who a character cell is
    ---------------------------------------------------------------------------

    --- A profile with a character layer and a character override, made into an entry.
    local function EntryWithCharacter()
        _G.DebindStorageVars = nil;
        ResetProfile({
            general = { { type = Constants.SETSWITCH_TOGGLE, value = "$state3", key = "G" } },
            char = { [2] = { { type = Constants.SPELL, value = 1, key = "F" } } },
            switches = { ["$state3"] = { mode = Constants.SWITCH_MODES.MANUAL } },
            charOverrides = { [0] = { ["$state3"] = { mode = Constants.SWITCH_MODES.MANUAL } } },
        });
        return DebindStorage.CreateEntry();
    end

    test("문자열은 guid와 신원을 그대로 싣는다", function()
        local str = DebindStorage.ExportEntry(EntryWithCharacter(), nil);
        local payload = DebindStorage.DecodeExportString(str);
        check(LayerAt(payload, GUID, CLASS, 2), "guid 칸이 없다");
        check(payload.characters[GUID].name == "Tester", "신원이 없다");
    end);

    ---------------------------------------------------------------------------
    -- What an entry holds
    --
    -- The row holds when and how it reached the list, and nothing about whose it is: that is the
    -- payload's `characters` and cell keys.
    ---------------------------------------------------------------------------

    --- 페이로드 최상단에 설 수 있는 이름 전부. 닫힌 목록이라 새 필드가 붙으면 여기가 먼저
    --- 빨개진다.
    local PAYLOAD_KEYS = {
        v = true, dbver = true, layers = true, switches = true, characters = true,
        created = true, gameType = true, options = true,
    };

    local function ResetStore()
        _G.DebindStorageVars = nil;
    end

    --- 행 최상단에 설 수 있는 이름 전부. 누구의 칸인지는 페이로드의 `characters`가 들고, 행이 그것을
    --- 따로 들면 답이 둘이 된다.
    local ENTRY_KEYS = { id = true, received = true, receivedFrom = true, payload = true };

    local function CheckEntryKeys(entry, what)
        for name in pairs(entry) do
            check(ENTRY_KEYS[name], what .. "이 모르는 필드를 들었다: " .. tostring(name));
        end
    end

    test("프로필에서 만든 행은 행 바깥에 누구 것인지를 안 든다", function()
        ResetStore();
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });

        local entry = DebindStorage.CreateEntry();
        CheckEntryKeys(entry, "캐릭터에서 만든 행");
        check(CountActions(entry.payload) == 1, "액션이 안 담겼다");
        CheckEntryKeys(DebindStorage.CreateAccountEntry(), "계정에서 만든 행");
    end);

    -- Whose data it is, ours or another addon's, is the payload's `fromAddon`; the row says only
    -- whether it was read straight off a profile or pasted in as a string.
    test("행은 프로필에서 읽었는지 문자열로 받았는지를 든다", function()
        ResetStore();
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });

        check(DebindStorage.CreateEntry().receivedFrom == "profile", "캐릭터에서 만든 행");
        check(DebindStorage.CreateAccountEntry().receivedFrom == "profile", "계정에서 만든 행");
        local str = DebindStorage.EncodeExportPayload(DebindStorage.BuildExportPayload());
        check(DebindStorage.ImportEntry(str).receivedFrom == "string", "붙여넣은 행");
    end);

    ---------------------------------------------------------------------------
    -- An entry made from the whole account (`CreateAccountEntry`)
    --
    -- Every cell the account file holds, not the eleven this character reaches.
    ---------------------------------------------------------------------------

    local ALT = "Player-1-ALTGUID";
    local SWITCHED = { mode = Constants.SWITCH_MODES.MANUAL };

    --- This character's profile, plus a priest's account cell, a priest alt with a layer and an
    --- override, and a character whose override rows still wait for its class (`"*"`).
    local function AccountProfile()
        ResetStore();
        ResetProfile({
            general = { { type = Constants.SETSWITCH_TOGGLE, value = "$state1", key = "G" } },
            char = { [0] = { { type = Constants.SPELL, value = 1, key = "F" } } },
            switches = { ["$state1"] = { mode = Constants.SWITCH_MODES.MANUAL },
                         ["$state2"] = { mode = Constants.SWITCH_MODES.MANUAL } },
        });
        local db = DebindPrivate.db.global;
        db.layers.account.PRIEST = { [2] = { { type = Constants.SPELL, value = 2, key = "P" } } };
        db.layers[ALT] = { PRIEST = { [1] = {
            { type = Constants.SPELL, value = 3, key = "A" },
            { type = Constants.SPELL, value = 4, key = "B", arrivalID = 7 },
        } } };
        db.characters[ALT] = { name = "Alt", realm = "TestRealm", class = "PRIEST", lastSeen = 5 };
        db.switches.account.PRIEST = { [2] = { ["$state1"] = SWITCHED, ["$state2"] = SWITCHED } };
        db.switches[ALT] = { PRIEST = { [1] = { ["$state1"] = SWITCHED } } };
        db.switches["Player-1-WAITING"] = { ["*"] = { [0] = { ["$state1"] = SWITCHED } } };
    end

    test("계정에서 만든 것은 다른 직업의 계정 칸과 다른 캐릭터의 칸을 든다", function()
        AccountProfile();
        local payload = DebindStorage.CreateAccountEntry().payload;
        check(General(payload)[1].value == "$state1", "일반 칸이 없다");
        check(LayerAt(payload, "account", "PRIEST", 2)[1].value == 2, "다른 직업의 계정 칸이 없다");
        check(LayerAt(payload, GUID, CLASS, 0)[1].value == 1, "이 캐릭터의 칸이 없다");
        local alt = LayerAt(payload, ALT, "PRIEST", 1);
        check(alt and #alt == 1 and alt[1].value == 3, "다른 캐릭터의 칸이 틀렸다");
        check(payload.characters[ALT].name == "Alt", "다른 캐릭터의 신원이 없다");
        check(payload.characters[ALT].lastSeen == nil, "이 설치의 기록이 실렸다");
        check(payload.characters[GUID].name == "Tester", "이 캐릭터의 신원이 없다");
    end);

    test("계정에서 만든 것은 어느 칸의 오버라이드든 참조된 스위치만 싣는다", function()
        AccountProfile();
        local switches = DebindStorage.CreateAccountEntry().payload.switches;
        check(switches.account.PRIEST[2]["$state1"], "다른 직업의 오버라이드가 없다");
        check(switches[ALT].PRIEST[1]["$state1"], "다른 캐릭터의 오버라이드가 없다");
        check(switches.account.PRIEST[2]["$state2"] == nil, "아무도 안 부르는 스위치가 실렸다");
        check(switches.account.GENERAL[0]["$state2"] == nil, "아무도 안 부르는 정의가 실렸다");
    end);

    test("계정에서 만든 것은 직업을 기다리는 칸을 안 싣는다", function()
        AccountProfile();
        local switches = DebindStorage.CreateAccountEntry().payload.switches;
        check(switches["Player-1-WAITING"] == nil, "직업 모르는 칸이 실렸다");
    end);

    test("계정에서 만든 것은 아직 안 붙은 이 캐릭터의 칸과 신원도 든다", function()
        AccountProfile();
        local db = DebindPrivate.db.global;
        db.layers[GUID] = nil;
        db.characters[GUID] = nil;
        local payload = DebindStorage.CreateAccountEntry().payload;
        check(LayerAt(payload, GUID, CLASS, 0), "붙기 전의 칸이 빠졌다");
        check(payload.characters[GUID] and payload.characters[GUID].name == "Tester",
            "붙기 전의 신원이 빠졌다");
    end);

    ---------------------------------------------------------------------------
    -- Options
    --
    -- An entry made from the whole account is a backup, and most options change what an action
    -- does; one made on a character is what gets handed to somebody else, who keeps their own.
    ---------------------------------------------------------------------------

    --- 이 캐릭터의 프로필에 기본값이 아닌 옵션 몇 개를 세운다.
    local function OptionsProfile()
        ResetStore();
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });
        local options = DebindPrivate.Options;
        options.selfCast = false;
        options.hoverCastMode = "mouseover";
        options.excludePlayer = { party = true };
        options.frameBlacklist.addons.Grid2 = false;
        return options;
    end

    test("계정에서 만든 것은 옵션을 싣는다", function()
        OptionsProfile();
        local options = DebindStorage.CreateAccountEntry().payload.options;
        check(options, "옵션이 안 실렸다");
        check(options.selfCast == false, "selfCast가 안 실렸다");
        check(options.hoverCastMode == "mouseover", "hoverCastMode가 안 실렸다");
        check(options.excludePlayer and options.excludePlayer.party == true, "excludePlayer가 안 실렸다");
        check(options.frameBlacklist and options.frameBlacklist.addons.Grid2 == false,
            "frameBlacklist가 안 실렸다");
    end);

    test("실린 옵션은 프로필의 표와 떨어진 사본이다", function()
        local mine = OptionsProfile();
        local options = DebindStorage.CreateAccountEntry().payload.options;
        options.excludePlayer.party = nil;
        options.frameBlacklist.addons.Grid2 = nil;
        check(mine.excludePlayer.party == true, "페이로드를 고치니 프로필의 excludePlayer가 바뀌었다");
        check(mine.frameBlacklist.addons.Grid2 == false, "페이로드를 고치니 프로필의 frameBlacklist가 바뀌었다");
    end);

    test("캐릭터에서 만든 것은 옵션을 안 싣는다", function()
        OptionsProfile();
        check(DebindStorage.CreateEntry().payload.options == nil, "캐릭터에서 만든 것에 옵션이 실렸다");
    end);

    test("모르는 옵션은 안 싣는다", function()
        OptionsProfile().leftover = true;
        check(DebindStorage.CreateAccountEntry().payload.options.leftover == nil, "모르는 옵션이 실렸다");
    end);

    test("계정 항목을 골라 내보내도 옵션이 따라간다", function()
        OptionsProfile();
        local payload = DebindStorage.CreateAccountEntry().payload;
        local selection = { [General(payload)[1]] = true };
        local out = DebindStorage.FilterPayload(payload, selection);
        check(out.options and out.options.selfCast == false, "고른 사본에서 옵션이 빠졌다");
    end);

    test("들어올 때 모르는 옵션과 타입이 틀린 옵션은 걷힌다", function()
        OptionsProfile();
        local payload = DebindStorage.BuildExportPayload();
        payload.options = { focusCast = false, selfCast = "no", leftover = true, excludePlayer = 1 };
        local entry = DebindStorage.ImportEntry(DebindStorage.EncodeExportPayload(payload));
        check(entry, "받아들여지지 않았다");
        local options = entry.payload.options;
        check(options and options.focusCast == false, "맞는 옵션까지 걷혔다");
        check(options.selfCast == nil, "타입이 틀린 옵션이 남았다");
        check(options.leftover == nil, "모르는 옵션이 남았다");
        check(options.excludePlayer == nil, "표여야 할 옵션이 숫자로 남았다");
    end);

    test("들어올 때 표가 아닌 options는 통째로 걷힌다", function()
        OptionsProfile();
        local payload = DebindStorage.BuildExportPayload();
        payload.options = "all of them";
        local entry = DebindStorage.ImportEntry(DebindStorage.EncodeExportPayload(payload));
        check(entry, "options 하나 때문에 거절됐다");
        check(entry.payload.options == nil, "표가 아닌 options가 남았다");
    end);

    test("만든 행의 페이로드는 아는 필드만 든다", function()
        ResetStore();
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });

        local payload = DebindStorage.CreateEntry().payload;
        for name in pairs(payload) do
            check(PAYLOAD_KEYS[name],
                "페이로드가 모르는 필드를 들었다: " .. tostring(name));
        end
    end);

    test("붙여넣은 행도 행 바깥에 누구 것인지를 안 든다", function()
        ResetStore();
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });

        local str = DebindStorage.EncodeExportPayload(DebindStorage.BuildExportPayload());
        local entry = DebindStorage.ImportEntry(str, "받은 것");
        check(entry, "받아들여지지 않았다");
        CheckEntryKeys(entry, "붙여넣은 행");
    end);

    ---------------------------------------------------------------------------
    -- 고른 것만 나간다
    --
    -- 선택은 안 남는다. 한 엔트리를 매번 다르게 쓰는 답이라, 문자열을 만드는 그 순간에만
    -- 뜻이 있다 (12절 "체크박스와 삭제는 다른 일을 한다").
    ---------------------------------------------------------------------------

    test("고른 액션만 실린다", function()
        ResetStore();
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F" },
                { type = Constants.SPELL, value = 2, key = "G" },
            },
            char = { [0] = { { type = Constants.SPELL, value = 3, key = "H" } } },
        });

        local payload = DebindStorage.CreateEntry().payload;
        local all = AllActions(payload);
        check(#all == 3, "만들기가 셋을 안 담았다: " .. #all);

        local selection = {};
        for _, action in ipairs(all) do
            if (action.value ~= 2) then
                selection[action] = true;
            end
        end

        local out = DebindStorage.FilterPayload(payload, selection);
        check(CountActions(out) == 2, "실린 수 " .. CountActions(out));
        check(#GroupFor(out, "G") == 0, "안 고른 것이 실렸다");
        check(OneOn(out, "F").value == 1, "일반 레이어 것이 빠졌다");
        check(OneOn(out, "H").value == 3, "캐릭터 레이어 것이 빠졌다");
        -- 주소는 경로 그 자체다. 골라낸 뒤에도 같은 자리에 있어야 받는 쪽이 같은 곳에 놓는다.
        check(LayerAt(out, GUID, CLASS, 0), "캐릭터 자리가 안 섰다");
        check(General(out), "일반 자리가 안 섰다");
        check(out.characters and out.characters[GUID], "캐릭터 칸의 신원이 안 따라왔다");
        check(out.v == payload.v and out.dbver == payload.dbver, "판 필드가 안 따라왔다");
    end);

    ---------------------------------------------------------------------------
    -- What a payload says about itself (`META_FIELDS`)
    ---------------------------------------------------------------------------

    test("만든 페이로드는 만든 시각과 게임 타입을 든다", function()
        ResetStore();
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });

        local before = time();
        for _, payload in ipairs({ DebindStorage.BuildExportPayload(), DebindStorage.BuildAccountPayload() }) do
            check(type(payload.created) == "number" and payload.created >= before
                and payload.created <= time(), "시각 " .. tostring(payload.created));
            check(payload.gameType == "standard", "게임 타입 " .. tostring(payload.gameType));
        end
    end);

    --- A made payload with a name and a description, as the reader would have given it.
    local function NamedEntry()
        ResetStore();
        ResetProfile({
            general = { { type = Constants.SPELL, value = 1, key = "F" } },
            char = { [0] = { { type = Constants.SPELL, value = 3, key = "H" } } },
        });
        local entry = DebindStorage.CreateEntry();
        entry.payload.name = "이름";
        entry.payload.description = "설명";
        return entry;
    end

    local function CheckMeta(out, from, what)
        for _, field in ipairs({ "created", "gameType", "name", "description" }) do
            check(out[field] ~= nil and out[field] == from[field],
                what .. "에서 " .. field .. "가 빠졌다: " .. tostring(out[field]));
        end
    end

    test("골라내도, 문자열을 돌아도 제 것을 들고 간다", function()
        local entry = NamedEntry();
        local payload = entry.payload;
        CheckMeta(DebindStorage.FilterPayload(payload, { [OneOn(payload, "F")] = true }), payload, "골라내기");
        CheckMeta(DebindStorage.DecodeExportString(
            DebindStorage.ExportEntry(entry, { [OneOn(payload, "H")] = true })),
            payload, "문자열");
    end);

    -- **The field goes and the string stays**: none of these says anything about the actions.
    test("타입이 틀린 것은 그 필드만 버리고 받는다", function()
        for _, bad in ipairs({
            { name = 5 }, { description = {} }, { gameType = true }, { fromAddon = 1 },
            { created = "어제" }, { created = 0 / 0 }, { created = 1 / 0 }, { created = -1 / 0 },
        }) do
            local field, value = next(bad);
            local payload = { v = DebindStorage.PAYLOAD_VERSION, dbver = Constants.DB_VERSION,
                layers = { account = { GENERAL = { [0] = {
                    { type = Constants.SPELL, value = 1, key = "F", seq = 1 } } } } } };
            payload[field] = value;
            local out, reason = DebindStorage.BringPayloadForward(payload);
            check(out, field .. " 때문에 거절: " .. tostring(reason));
            check(out[field] == nil, field .. "가 남았다: " .. tostring(out[field]));
        end

        local good = { v = DebindStorage.PAYLOAD_VERSION, dbver = Constants.DB_VERSION, layers = {},
            name = "n", description = "d", gameType = "camelot", created = 5, fromAddon = "clique" };
        local out = DebindStorage.BringPayloadForward(good);
        check(out.name == "n" and out.description == "d" and out.gameType == "camelot"
            and out.created == 5 and out.fromAddon == "clique", "멀쩡한 것까지 버렸다");
    end);

    -- An addon this version has no conversion for has no shape to read, so its name says nothing the
    -- payload can be handled by; left on, it would grey the share button and be added as ours.
    test("모르는 애드온 이름은 버리고 받는다", function()
        local out = DebindStorage.BringPayloadForward({ v = DebindStorage.PAYLOAD_VERSION,
            dbver = Constants.DB_VERSION, layers = {}, fromAddon = "bindpad" });
        check(out and out.fromAddon == nil, "fromAddon " .. tostring(out and out.fromAddon));
    end);

    test("다른 애드온의 페이로드인지는 한 곳이 답한다", function()
        check(DebindStorage.IsForeignPayload({ fromAddon = DebindStorage.FROM_ADDON_CLIQUE }), "Clique");
        check(not DebindStorage.IsForeignPayload({}), "우리 것");
    end);

    -- 4.1 wrote the Clique mark as `source`, and a 4.1 string or a 4.1 drawer row still carries it.
    test("v2의 source는 fromAddon으로 올라간다", function()
        local out = DebindStorage.BringPayloadForward({ v = 2, dbver = Constants.DB_VERSION,
            shared = { GENERAL = {} }, source = "clique" });
        check(out, "올라가지 않았다");
        check(out.fromAddon == "clique", "fromAddon " .. tostring(out.fromAddon));
        check(out.source == nil, "source가 남았다");
    end);

    -- A Clique payload has not been through the reader's own add yet: what it holds is a
    -- conversion nobody has checked, and handing it on would pass that along unchecked.
    test("다른 애드온의 페이로드는 문자열로 못 나간다", function()
        ResetStore();
        local entry = DebindStorage.StorePayload(DebindStorage.PayloadFromCliqueBindings({
            { key = "F", type = "spell", spell = "Rejuvenation", sets = { default = true } },
        }, Constants.GAME_TYPE));
        check(entry, "Clique 행이 안 만들어졌다");
        local str, reason = DebindStorage.ExportEntry(entry);
        check(str == nil and reason == "FOREIGN_PAYLOAD", "나갔다: " .. tostring(reason));
    end);

    -- **A received payload's spells are put on their first rank where it arrives**
    -- (`keeping-a-pinned-rank-apart-from-the-spell.md` §5): a string an older version made would
    -- otherwise bring every rank's id back in. A pin and an id the table does not know stay.
    test("a payload's spells arrive on their first rank", function()
        local spells = DebindPrivate.CamelotSpells;
        DebindPrivate.CamelotSpells = { [686] = { 1 }, [705] = 686 };
        local payload = { v = DebindStorage.PAYLOAD_VERSION, dbver = Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = {
                { type = Constants.SPELL, value = 705, key = "F", seq = 1 },
                { type = Constants.SPELL, value = 686, key = "G", seq = 1, pinnedSpell = 705 },
                { type = Constants.SPELL, value = 424242, key = "H", seq = 1 },
            } } } } };
        local ok, out = pcall(DebindStorage.BringPayloadForward, payload);
        DebindPrivate.CamelotSpells = spells;
        check(ok and out, tostring(out));
        local actions = out.layers.account.GENERAL[0];
        check(actions[1].value == 686, "F: " .. tostring(actions[1].value));
        check(actions[2].value == 686 and actions[2].pinnedSpell == 705,
            "G: " .. tostring(actions[2].value) .. " " .. tostring(actions[2].pinnedSpell));
        check(actions[3].value == 424242, "H: " .. tostring(actions[3].value));
    end);

    test("캐릭터 칸이 다 빠지면 신원도 빠진다", function()
        ResetStore();
        ResetProfile({
            general = { { type = Constants.SPELL, value = 1, key = "F" } },
            char = { [0] = { { type = Constants.SPELL, value = 3, key = "H" } } },
        });

        local payload = DebindStorage.CreateEntry().payload;
        local out = DebindStorage.FilterPayload(payload, { [OneOn(payload, "F")] = true });
        check(out.layers[GUID] == nil, "빈 캐릭터 칸이 섰다");
        check(out.characters == nil, "칸이 없는 신원이 남았다");
    end);

    test("안 고르면 페이로드가 그대로 나간다", function()
        ResetStore();
        ResetProfile({ general = { { type = Constants.SPELL, value = 1, key = "F" } } });

        local payload = DebindStorage.CreateEntry().payload;
        check(DebindStorage.FilterPayload(payload, nil) == payload, "같은 표가 아니다");
    end);

    test("골라낸 뒤 매니페스트가 참조된 것만 남는다", function()
        ResetStore();
        StatefulProfile({
            { type = Constants.SPELL, value = 1, key = "F" },
            { type = Constants.SETSWITCH_TOGGLE, value = "$state3", key = "G" },
        });
        LayerActions(1)[1].conditions = { ["$state1"] = true };

        local payload = DebindStorage.CreateEntry().payload;
        check(Definitions(payload)["$state1"] and Definitions(payload)["$state3"], "둘 다 안 실렸다");

        local selection = {};
        selection[OneOn(payload, "G")] = true;

        local states = Definitions(DebindStorage.FilterPayload(payload, selection));
        check(states["$state3"], "고른 것이 쓰는 상태가 빠졌다");
        check(states["$state1"] == nil, "안 고른 것이 쓰던 상태가 남았다");
    end);

    test("골라낼 때 정의는 페이로드 것을 쓴다", function()
        ResetStore();
        StatefulProfile({ { type = Constants.SETSWITCH_TOGGLE, value = "$state3", key = "G" } });

        local payload = DebindStorage.CreateEntry().payload;
        -- 남이 준 문자열이면 정의가 내 것과 다르다. 여기서 프로필을 다시 물으면 그 순간
        -- **남의 정의가 내 것으로 바뀐 채** 나간다.
        Definitions(payload)["$state3"].resetValue = true;

        local selection = {};
        selection[OneOn(payload, "G")] = true;

        local states = Definitions(DebindStorage.FilterPayload(payload, selection));
        check(states["$state3"].resetValue == true,
            "프로필 정의로 바뀌었다: " .. tostring(states["$state3"].resetValue));
    end);

    test("골라낼 때 오버라이드 행도 참조된 것만 남는다", function()
        ResetStore();
        ResetProfile({
            general = {
                { type = Constants.SETSWITCH_TOGGLE, value = "$state1", key = "F" },
                { type = Constants.SETSWITCH_TOGGLE, value = "$state3", key = "G" },
            },
            switches = {
                ["$state1"] = { mode = Constants.SWITCH_MODES.MANUAL },
                ["$state3"] = { mode = Constants.SWITCH_MODES.MANUAL },
            },
            classOverrides = { [2] = {
                ["$state1"] = { mode = Constants.SWITCH_MODES.MANUAL },
                ["$state3"] = { mode = Constants.SWITCH_MODES.MANUAL },
            } },
        });

        local payload = DebindStorage.CreateEntry().payload;
        local out = DebindStorage.FilterPayload(payload, { [OneOn(payload, "G")] = true });
        local cell = out.switches.account[CLASS][2];
        check(cell["$state3"], "고른 것이 쓰는 행이 빠졌다");
        check(cell["$state1"] == nil, "안 고른 것이 쓰던 행이 남았다");
    end);

    ---------------------------------------------------------------------------
    -- The shape itself
    --
    -- **저장 구조 그대로**가 이 포맷의 결론이고, 그리는 코드를 번역 없이 재사용하려는 것이
    -- 그 이유다 (`building-export-import.md`의 세 번째 ★ 절). 아래 넷이 그 결론이
    -- 실제로 선을 타고 나가는지를 본다.
    ---------------------------------------------------------------------------

    test("최상위가 저장 주소 그대로다", function()
        ResetProfile({
            general = { { type = Constants.SPELL, value = 1, key = "F" } },
            class = { [2] = { { type = Constants.SPELL, value = 2, key = "G" } } },
            char = { [0] = { { type = Constants.SPELL, value = 3, key = "H" } } },
        });

        local payload = DebindStorage.BuildExportPayload();
        check(payload.groups == nil, "그룹 층이 아직 있다");
        check(General(payload) and #General(payload) == 1, "일반이 저장 경로에 없다");
        check(LayerAt(payload, "account", CLASS, 2)[1].value == 2, "직업/특성2 경로");
        check(LayerAt(payload, GUID, CLASS, 0)[1].value == 3, "캐릭터 경로");
        check(General(payload)[1].layer == nil, "레이어 서술이 남았다");
    end);

    test("key가 액션에 실려 그룹을 나른다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 1, key = "F", conditions = { combat = true } },
                { type = Constants.SPELL, value = 2, key = "F" },
            },
        });

        local actions = General(DebindStorage.BuildExportPayload());
        check(#actions == 2, "액션 수 " .. #actions);
        check(actions[1].key == "F" and actions[2].key == "F", "키가 액션에 없다");
    end);

    test("seq가 선에 실린다", function()
        ResetProfile({
            general = {
                { type = Constants.SPELL, value = 10, key = "F", seq = 1 },
                { type = Constants.SPELL, value = 20, key = "F", seq = 2 },
            },
        });

        for _, action in ipairs(General(DebindStorage.BuildExportPayload())) do
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
            { "DEB2:!!!!!!", "BAD_ENCODING" },
        };
        for _, case in ipairs(cases) do
            local payload, reason = DebindStorage.DecodeExportString(case[1]);
            check(payload == nil, "받아들이면 안 된다: " .. tostring(case[1]));
            check(reason == case[2],
                tostring(case[1]) .. " -> " .. tostring(reason) .. " (기대 " .. case[2] .. ")");
        end
    end);

    -- **An unknown payload version goes two ways, and what can be done about each is opposite.**
    -- While they were one, the reason was one and its sentence was "made by a newer version,
    -- update" - the first time `PAYLOAD_VERSION` went up, every entry already in the drawer would
    -- fail with that sentence, for a reader who had just updated.
    test("옛 판과 새 판을 갈라서 답한다", function()
        local function DecodeWithVersion(v)
            local _, reason = DebindStorage.DecodeExportString(
                DebindStorage.EncodeExportPayload({ v = v, class = CLASS }));
            return reason;
        end

        check(DecodeWithVersion(DebindStorage.PAYLOAD_VERSION + 1) == "PAYLOAD_TOO_NEW",
            "더 새 것");
        -- v1은 사다리가 받는다. 거절이 아니다.
        check(DecodeWithVersion(1) == nil, "v1을 거절했다");
        -- 사다리에 단계가 없는 판은 여전히 거절이다. 추측으로 읽으면 조건이 조용히
        -- 편을 바꾼다.
        check(DecodeWithVersion(0) == "PAYLOAD_TOO_OLD", "단계 없는 옛 판");
    end);

    -- **v1 매니페스트도 같은 단계가 받는다.** 3.2가 이 표를 실어 보냈으므로 v1 문자열이
    -- 남의 노트에 옛 모양으로 앉아 있다. 아직 매니페스트를 읽는 쪽은 없지만 단계는 한 번
    -- 쓰면 얼어붙어서, 읽는 쪽이 생기는 날 붙일 자리가 여기 말고는 없다.
    test("v1 매니페스트의 정의도 새 이름으로 올라온다", function()
        local payload = DebindStorage.BringPayloadForward({
            v = 1, class = CLASS,
            states = {
                ["$state1"] = { mode = 0, initialValue = true },
                ["$state2"] = { mode = 3, expr = "[combat]" },
                ["$state3"] = { mode = 0, initialValue = false },
            },
        });
        check(payload, "v1이 거절당했다");

        local states = Definitions(payload);
        check(states["$state1"].mode == Constants.SWITCH_MODES.MANUAL, "수동 모드");
        check(states["$state2"].mode == Constants.SWITCH_MODES.EXPR,
            "계산식 모드가 " .. tostring(states["$state2"].mode) .. "로 남았다");
        check(states["$state1"].initialValue == nil, "옛 필드가 남았다");
        check(states["$state1"].resetValue == true, "true가 안 옮겨졌다");
        -- `false`와 없는 것은 다른 답이다. 뭉개면 "로그인 때 꺼짐"이 "기억한 값"이 된다.
        check(states["$state3"].resetValue == false,
            "false가 " .. tostring(states["$state3"].resetValue) .. "가 됐다");
        check(states["$state2"].expr == "[combat]", "나머지가 안 따라왔다");
    end);

    ---------------------------------------------------------------------------
    -- v2 to v3
    --
    -- v2 carried no identity, so its character layer arrives under `"1"`, keyed by the class
    -- `payload.class` named (`reshaping-stored-layers.md` 1-1).
    ---------------------------------------------------------------------------

    local function V2()
        return {
            v = 2, dbver = 7, class = "MAGE",
            shared = {
                GENERAL = { { type = Constants.SPELL, value = 1, key = "F", seq = 1 } },
                classes = { MAGE = { [2] = { { type = Constants.SPELL, value = 2, key = "G", seq = 1 } } } },
            },
            char = { [0] = { { type = Constants.SPELL, value = 3, key = "H", seq = 1 } } },
            states = { ["$burst"] = { mode = Constants.SWITCH_MODES.MANUAL, resetValue = true } },
        };
    end

    test("v2의 주소가 v3의 칸으로 간다", function()
        local payload, reason = DebindStorage.BringPayloadForward(V2());
        check(payload, "거절당했다: " .. tostring(reason));
        check(payload.v == 3, "판 " .. tostring(payload.v));
        check(General(payload)[1].value == 1, "일반");
        check(LayerAt(payload, "account", "MAGE", 2)[1].value == 2, "직업");
        check(LayerAt(payload, "1", "MAGE", 0)[1].value == 3, "캐릭터가 보낸 쪽 직업의 칸으로 안 갔다");
        check(Definitions(payload)["$burst"].resetValue == true, "정의");
    end);

    test("v2의 이름은 v3에 안 남는다", function()
        local payload = DebindStorage.BringPayloadForward(V2());
        for _, name in ipairs({ "shared", "char", "states", "class" }) do
            check(payload[name] == nil, name .. "가 남았다");
        end
        check(payload.characters == nil, "v2에 없던 신원이 생겼다");
    end);

    -- Every string since 3.2 carries `class` (9b57dc4), so one without it was edited by hand, and a
    -- hand-edited file is not read for what it meant (`reshaping-stored-layers.md` 1절).
    test("class 없는 v2의 캐릭터 레이어는 버린다", function()
        local old = V2();
        old.class = nil;
        local payload = DebindStorage.BringPayloadForward(old);
        check(payload, "나머지까지 거절했다");
        check(payload.layers["1"] == nil, "직업 모를 캐릭터 칸이 섰다");
        check(General(payload)[1].value == 1, "나머지가 빠졌다");
    end);

    -- A refused payload is left as it came. The drawer raises every entry in place on open, so one
    -- refused after its shape moved would be stored in a shape no version wrote.
    test("거절되는 v2는 모양이 안 바뀐다", function()
        for _, dbver in ipairs({ 99, 0 / 0, 4 }) do
            local old = V2();
            old.dbver = dbver;
            local payload = DebindStorage.BringPayloadForward(old);
            check(payload == nil, "받아들였다: " .. tostring(dbver));
            check(old.v == 2 and old.shared and old.char and old.class, "모양이 바뀌었다: " .. tostring(dbver));
            check(old.layers == nil, "v3 칸이 섰다: " .. tostring(dbver));
        end
    end);

    test("문자열이 아닌 class도 없는 것과 같다", function()
        local old = V2();
        old.class = {};
        local payload = DebindStorage.BringPayloadForward(old);
        check(payload and payload.layers["1"] == nil, "표를 직업 키로 세웠다");
    end);

    ---------------------------------------------------------------------------
    -- 액션 사다리는 프로필의 것 하나뿐이다
    --
    -- 같은 변환이 두 벌 서 있었다. 조건 중첩이 `MigrateLayer` 안에 한 번, 페이로드 쪽에
    -- 손으로 한 번(`NestPayloadConditions`). `unifying-action-migration.md`가
    -- 없애려던 것이 그 갈라짐이다.
    ---------------------------------------------------------------------------

    -- **이 케이스만 결과가 아니라 경로를 본다.** 결과만 보는 검사는 두 벌이 우연히 같은 답을
    -- 내는 동안 아무 말도 안 하고, 갈렸다는 사실 자체가 여기서 막으려는 것이다.
    --
    -- 액션은 `dbver` 5 모양이다 - 조건이 평면이고 SETSTATE가 비트팩이라, 그 판 단계의 두
    -- 갈래를 한 액션이 같이 지난다.
    test("페이로드의 액션은 프로필의 사다리를 그대로 탄다", function()
        local seen = {};
        local real = DebindPrivate.MigrateLayer;
        DebindPrivate.MigrateLayer = function(layerTbl, dbver)
            seen[#seen + 1] = dbver;
            return real(layerTbl, dbver);
        end;

        local ok, err = pcall(function()
            local payload = DebindStorage.BringPayloadForward({
                v = 1, class = CLASS,
                shared = { GENERAL = {
                    { type = "setstate", key = "F", seq = 1, value = 0x400 + 3,
                      combat = true },
                } },
            });
            check(payload, "v1이 거절당했다");

            local action = General(payload)[1];
            check(action.conditions and action.conditions.combat == true,
                "조건이 안 내려갔다");
            check(action.combat == nil, "최상단에 조건이 남았다");
            check(action.type == Constants.SETSWITCH_TOGGLE,
                "타입이 안 갈렸다: " .. tostring(action.type));
            check(action.value == "$state3", "이름 " .. tostring(action.value));
            check(payload.dbver == Constants.DB_VERSION,
                "올린 뒤에도 옛 dbver가 남았다: " .. tostring(payload.dbver));
        end);

        DebindPrivate.MigrateLayer = real;
        if (not ok) then
            error(err, 0);
        end

        check(#seen > 0, "프로필 사다리를 안 불렀다 - 같은 변환이 두 벌 서 있다");
        for _, dbver in ipairs(seen) do
            check(dbver == 5, "v1을 5로 안 넘겼다: " .. tostring(dbver));
        end
    end);

    return T;
end
