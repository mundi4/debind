-- Turning a received payload back into actions. `DebindStorage/Import.lua`.
--
-- **This is the half of the round trip that can be wrong without anyone noticing.** The export side
-- is checked against the format; here the output is an action that goes straight into someone's
-- profile, and a field read back wrongly produces an action that looks fine in a list and does
-- something else when pressed.
--
-- Two of those are the whole reason the format is shaped the way it is:
--
--   * a `SETSTATE` value is a switch **name**, on the wire and in the profile alike (§9-1 of
--     `devdocs/redesigning-custom-states.md`). What still has to be rebuilt is v1's `setstate`
--     subtable, and that happens at the door rather than here.
--   * a `MACRO` carries a **name**, and only a name. A slot index would resolve on any install and
--     point at some other macro; the body no longer travels at all, so nothing can arrive carrying
--     a stranger's macro text (`devdocs/building-export-import.md`, 2026-08-18).
--
-- Everything built here also has to arrive quarantined. An action that landed without `imported`
-- is bound the moment it lands, which is the one thing this whole path promises not to do.

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

    ---------------------------------------------------------------------------
    -- The macro store, stubbed. Same shape as the real API: `GetMacroInfo` answers to a name or to
    -- a slot index, which is what lets a bare number be shown resolving to the wrong macro.
    ---------------------------------------------------------------------------

    local MACROS = {};

    _G.GetMacroInfo = function(nameOrIndex)
        local macro = MACROS[nameOrIndex];
        if (not macro) then
            return nil;
        end
        return macro.name, macro.icon, macro.body;
    end

    local function ResetProfile()
        MACROS = {};
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = {}, classes = { [CLASS] = {} } },
            characters = { [GUID] = { layers = {} } },
            migrated = {},
        };
        DebindPrivate.InitDB();
    end

    --- A payload holding one general layer. **The path is the address** -- there is no descriptor
    --- to write, so a test that is not about addressing says nothing about it at all.
    local function General(actions)
        return { v = 1, class = CLASS, shared = { GENERAL = actions } };
    end

    --- Plans a payload holding exactly one action and hands it back.
    local function PlanOne(payload)
        local placements = DebindStorage.PlanArrival(payload);
        check(#placements == 1, "액션 수 " .. #placements);
        return placements[1].action, placements[1];
    end

    ResetProfile();

    ---------------------------------------------------------------------------
    -- Quarantine and keys
    ---------------------------------------------------------------------------

    test("들어오는 것은 전부 배지를 달고 온다", function()
        local placements = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 1, key = "F", seq = 1 },
            { type = Constants.SPELL, value = 2, key = "F", seq = 2 },
        }));

        check(#placements == 2, "액션 수");
        for _, placement in ipairs(placements) do
            check(placement.action.arrivalID ~= nil,
                "배지가 없다 - 이 액션은 들어가는 순간 키에 걸린다");
        end
    end);

    -- **The key it was sent on is the key it lands on.** What keeps it off the reader's keyboard is
    -- the badge, and what keeps it out of the reader's own set on that key is that a group is
    -- `(key, arrivalID)` -- so the two sit on one key under two headings and neither is merged into
    -- the other (`devdocs/building-export-import.md` 12절).
    test("실키를 달고 오면 그 키에 앉고 배지가 붙는다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SPELL, value = 774, key = "SHIFT-G", seq = 1 } }));
        check(action.key == "SHIFT-G", "보낸 키가 안 남았다: " .. tostring(action.key));
        check(type(action.arrivalID) == "number",
            "배지가 arrival 번호가 아니다: " .. tostring(action.arrivalID));
    end);

    -- **No way in skips the badge** (2026-08-23, 소유자). There was one: the accept-on-arrival verb
    -- asked the plan to leave it off, and the actions went live on the sender's keys with nothing
    -- asked -- where the reader already used one of those keys, a merge they never chose. That verb
    -- lands badged like everything else now and runs the approval afterwards, which is the path that
    -- asks. The old option name is fed in here on purpose: an option nothing reads has to be inert
    -- rather than quietly still working.
    test("배지를 빼달라는 옵션은 없다", function()
        ResetProfile();
        local placements = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 774, key = "SHIFT-G", seq = 1 },
        }), { keepKeys = true });
        check(#placements == 1, "하나가 아니다");
        check(placements[1].action.key == "SHIFT-G",
            "실키가 안 남았다: " .. tostring(placements[1].action.key));
        check(type(placements[1].action.arrivalID) == "number",
            "배지가 안 붙었다: " .. tostring(placements[1].action.arrivalID));
    end);

    -- **A number in `key` is not a key any more.** It used to mean "a group whose key the sender had
    -- not decided", and the whitelist no longer lets one through (`ACTION_FIELDS`) - so it is
    -- dropped like any field of the wrong type and what lands is a keyless action, which the
    -- profile has always allowed and draws greyed.
    test("숫자 키는 아예 안 들어온다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SPELL, value = 774, key = 7, seq = 1 } }));
        check(action.key == nil, "숫자가 키로 앉았다: " .. tostring(action.key));
        -- 키가 없으면 번호도 없다.
        check(action.seq == nil, "키 없는 액션이 번호를 들었다: " .. tostring(action.seq));
    end);

    -- The grouping is what the badge has to keep whole: one call is one arrival, so every action of
    -- it carries the same number and a set spanning four layers stays one set.
    test("한 번의 arrival은 번호 하나다", function()
        ResetProfile();
        local placements = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 1, key = "G", seq = 1 },
            { type = Constants.SPELL, value = 2, key = "G", seq = 2 },
            { type = Constants.SPELL, value = 3, key = "H", seq = 1 },
        }));

        local first = placements[1].action.arrivalID;
        check(type(first) == "number", "번호가 아니다: " .. tostring(first));
        for _, placement in ipairs(placements) do
            check(placement.action.arrivalID == first,
                "한 arrival 안에서 번호가 갈렸다: " .. tostring(placement.action.arrivalID));
        end
    end);

    test("키 없이 온 것은 키 없이 들어가고 배지는 붙는다", function()
        ResetProfile();
        local action = PlanOne(General({ { type = Constants.SPELL, value = 774 } }));
        check(action.key == nil, "없던 키가 생겼다");
        check(type(action.arrivalID) == "number",
            "배지가 arrival 번호가 아니다: " .. tostring(action.arrivalID));
    end);

    ---------------------------------------------------------------------------
    -- Arrival numbers
    ---------------------------------------------------------------------------

    -- **두 arrival이 같은 번호를 받으면 서로 남남인 두 벌이 한 머리글 아래로 합쳐진다.** 그리고
    -- 그건 화면에 나오기 전까지 조용하다. 카운터는 스토어에 저장되고 올라가기만 한다.
    test("다음 arrival은 다른 번호를 받는다", function()
        ResetProfile();

        local first = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 1, key = "F", seq = 1 } }));
        DebindPrivate.PlaceArrivedActions(first);

        local second = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 2, key = "F", seq = 1 } }));

        check(first[1].action.arrivalID ~= second[1].action.arrivalID,
            "두 arrival이 같은 번호를 받았다: " .. tostring(second[1].action.arrivalID));
    end);

    -- **같은 페이로드를 두 번 가져와도 그룹이 안 섞인다.** 키가 같으니 키만으로는 한 덩어리로
    -- 보이는데, 번호가 그 둘을 갈라 세운다.
    test("같은 키로 두 번 들어와도 그룹이 갈린다", function()
        ResetProfile();

        local first = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 1, key = "F", seq = 1 } }));
        DebindPrivate.PlaceArrivedActions(first);
        local second = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 2, key = "F", seq = 1 } }));
        DebindPrivate.PlaceArrivedActions(second);

        local one = DebindPrivate.CollectKeyGroupActions("F", first[1].action.arrivalID);
        local two = DebindPrivate.CollectKeyGroupActions("F", second[1].action.arrivalID);
        check(#one == 1 and one[1].value == 1, "첫 arrival이 " .. #one .. "개");
        check(#two == 1 and two[1].value == 2, "둘째 arrival이 " .. #two .. "개");
        check(#DebindPrivate.CollectKeyGroupActions("F") == 0, "내 것으로 세어졌다");
    end);

    -- **안 보이는 레이어에 앉은 것도 같은 카운터를 쓴다.** `LayerArray`는 이 캐릭터의 뷰라 다른
    -- 직업의 레이어가 통째로 빠지는데, 번호는 그 뷰가 아니라 스토어의 카운터에서 나온다.
    test("다른 직업 레이어에 놓아도 번호는 이어진다", function()
        ResetProfile();

        local mage = DebindStorage.PlanArrival({
            v = 1, class = CLASS,
            shared = { classes = { MAGE = { [2] = {
                { type = Constants.SPELL, value = 1, key = "F", seq = 1 } } } } },
        });
        DebindPrivate.PlaceArrivedActions(mage);

        -- The premise: it really did land somewhere the layer view does not reach.
        local seen = 0;
        for layerID = 1, 11 do
            local layer = DebindPrivate.GetProfileLayer(layerID);
            if (layer) then
                seen = seen + layer:GetNumActions();
            end
        end
        check(seen == 0, "전제가 틀렸다 - 이 캐릭터의 레이어에서 " .. seen .. "개가 보인다");

        local next2 = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 2, key = "F", seq = 1 } }));
        check(next2[1].action.arrivalID ~= mage[1].action.arrivalID,
            "안 보이는 arrival의 번호를 재사용했다: " .. tostring(next2[1].action.arrivalID));
    end);


    ---------------------------------------------------------------------------
    -- The order inside a group
    ---------------------------------------------------------------------------

    -- **Which of a key's actions goes first is design, not decoration.** It travels as `seq` under
    -- its own name: the number means nothing in the layer that receives it, and what makes that
    -- harmless is that `PlaceArrivedActions` overwrites every one of them on the way in.
    test("실려온 seq가 액션에 남는다", function()
        ResetProfile();
        local placements = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 11, key = "F", seq = 1 },
            { type = Constants.SPELL, value = 22, key = "F", seq = 2 },
            { type = Constants.SPELL, value = 33, key = "F", seq = 3 },
        }));

        check(#placements == 3, "액션 수 " .. #placements);
        for i, placement in ipairs(placements) do
            check(placement.action.seq == i,
                i .. "번째 액션의 seq가 " .. tostring(placement.action.seq));
        end
    end);

    -- **No key, no number** is an invariant of the profile (`ClearActionKey`), and a hand-made
    -- string is exactly the input that would walk one past it.
    test("키 없이 온 액션의 seq는 버린다", function()
        ResetProfile();
        local action = PlanOne(General({ { type = Constants.SPELL, value = 1, seq = 4 } }));
        check(action.seq == nil, "키 없는 액션이 번호를 들고 들어왔다: " .. tostring(action.seq));
    end);

    -- **Both ends read one whitelist now** (`ACTION_FIELDS`). It used to be a blacklist here, so a
    -- wire field nobody had named rode straight into the profile - which is what forced the ranking
    -- to travel under a name other than `seq` in the first place.
    test("명단에 없는 선의 필드는 액션에 안 남는다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SPELL, value = 774, key = "F", seq = 1,
              somethingANewerSchemaAdded = true } }));
        check(action.somethingANewerSchemaAdded == nil,
            "모르는 선 필드가 프로필까지 들어왔다");
        check(action.value == 774 and action.key == "F", "명단에 있는 것은 들어와야 한다");
    end);

    --- **스위치 이름은 무엇이든 도착한다. 여기 정의가 없어도 그렇다.**
    ---
    --- `$state1`~`$state5` 밖의 이름을 실은 문자열은 통째로 거절이었다(`c6f0b17`). 근거는
    --- 이름이 아니라 **솔버**였다 - 그 이름에 컬럼이 안 생겨서 조건이 안 보였고, 상자가 조건
    --- 공간 전체가 되어 그 액션이 같은 키의 아래 바인딩을 전부 덮었다. 컬럼이 이름마다
    --- 생기고 나면(`Solver.lua`) 그 근거가 없어지고, 거절만 남으면 정반대로 틀린다.
    ---
    --- 남는 것은 이 포맷의 원래 규칙이다: **망가진 것도 보내고 받는 쪽이 빨간 것을 보고
    --- 지운다.** 정의가 없는 이름은 안 배운 주문과 같은 자리 - 평범한데 이 컴퓨터에서 안
    --- 풀리는 것 - 이고, 그 조건이 걸린 바인딩은 안 나간다.
    test("이 판에 정의가 없는 스위치 조건도 문자열을 거절하지 않는다", function()
        local payload = General({ { type = Constants.SPELL, value = 1, key = "F", seq = 1,
            conditions = { ["$burst"] = true } } });
        check(DebindStorage.PayloadIsImpossible(payload) == false,
            "만들 수 있는 문자열을 거절했다");
    end);

    test("아는 커스텀 상태 조건은 거절 사유가 아니다", function()
        local payload = General({ { type = Constants.SPELL, value = 1, key = "F", seq = 1,
            conditions = { ["$state3"] = true } } });
        check(DebindStorage.PayloadIsImpossible(payload) == false, "멀쩡한 문자열을 거절했다");
    end);

    -- 거절하지 않는 것과 **조건을 들고 도착하는 것**은 다른 답이다. 조건만 조용히 떨어지면
    -- 액션이 넓어져서 도착하고, 그게 위 주석이 말하는 "아래 바인딩을 덮는" 바로 그 모양이다.
    test("정의 없는 스위치 조건이 프로필까지 들어온다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SPELL, value = 1, key = "F", seq = 1,
                conditions = { ["$burst"] = false } } }));
        check(action.conditions ~= nil and action.conditions["$burst"] == false,
            "임의 이름 조건이 도중에 사라졌다");
    end);

    test("$상태 조건은 명단에 없어도 통과한다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SPELL, value = 1, key = "F", seq = 1,
                conditions = { ["$state3"] = true } } }));
        check(action.conditions["$state3"] == true, "$상태 조건이 걸러졌다");
    end);

    ---------------------------------------------------------------------------
    -- Hand-made strings
    --
    -- **A pasted string is untrusted input and none of this may error.** The schema check turns
    -- away anything from a version we do not know, so what is left is a string somebody built by
    -- hand - which is exactly what that rule exists for. An error here goes off inside
    -- `CommitEntry`, after part of an entry has already been placed.
    ---------------------------------------------------------------------------

    test("액션 자리에 액션이 아닌 것이 있어도 안 터진다", function()
        ResetProfile();
        local placements = DebindStorage.PlanArrival(General({
            5,
            { type = Constants.SPELL, value = 1, key = "F", seq = 1 },
            "쓰레기",
        }));
        check(#placements == 1, "액션 수 " .. #placements);
        check(placements[1].action.value == 1, "엉뚱한 것이 들어왔다");
    end);

    test("setstate가 테이블이 아니어도 안 터진다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SETSTATE, key = "F", seq = 1, setstate = 5 } }));
        check(action.type == Constants.SETSTATE, "타입이 바뀌었다");
        check(action.setstate == nil, "포맷 필드가 액션에 남았다");
    end);

    -- **명단은 이름을 거르지 타입을 안 거른다.** 아래 넷은 전부 계산에 쓰인다 - `seq`는 도착
    -- 번호에 더해지고(`PlaceArrivedActions`), `priority`는 `table.sort` 안에서 비교되고,
    -- `units`는 `pairs`로 훑고, `forms`는 `band`를 지난다. 어느 쪽이든 터지는 자리가
    -- 커밋 도중이라, 앞의 액션은 이미 들어간 채로 멈춘다.
    test("타입이 어긋난 선 필드는 안 들어온다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SPELL, value = 774, key = "F", seq = {},
              priority = {}, units = "쓰레기", forms = "쓰레기" } }));
        check(action.seq == nil, "seq " .. tostring(action.seq));
        check(action.priority == nil, "priority " .. tostring(action.priority));
        check(action.units == nil, "units " .. tostring(action.units));
        check(action.forms == nil, "forms " .. tostring(action.forms));
        check(action.value == 774 and action.key == "F", "멀쩡한 필드까지 걸렀다");
    end);

    -- **타입 선언이 틀리면 실패가 조용하다.** 멀쩡한 필드가 임포트에서 걸러지고, 받는 쪽은
    -- 조건 하나가 빠진 액션을 얻는다 - 즉 **더 자주 발동한다.** 위의 두 테스트는 "틀린 값이 안
    -- 들어온다"만 보므로 그 반대 방향을 못 본다.
    --
    -- **값은 명단에서 뽑지 않는다.** 처음엔 선언된 타입으로 표본을 만들었는데, 그러면 선언을
    -- 바꿔도 표본이 같이 바뀌어서 무엇을 먹여도 통과했다. 아래 값은 전부 **애드온이 실제로 그
    -- 필드에 쓰는 것**이고 출처가 옆에 적혀 있다. 그래서 선언 하나를 틀리게 하면 빨개진다.
    --
    -- 명단에 있는데 여기 없으면 그것도 실패다. 필드가 늘면 이 표도 같이 늘어야 한다.
    --- 조건 표 **안쪽**의 실제 값. 바깥 명단과 안쪽 명단이 따로 있으므로 표본도 둘이다.
    local REAL_CONDITIONS = {
        -- `DropDownMenus.lua`의 `setActionValue`가 조건에 쓰는 것: 예/아니오/안 물음 = true/false/nil.
        known = true,
        combat = true,
        stealth = true,
        specialbar = true,
        extrabar = true,
        pet = true,
        petbattle = true,
        -- 비트 마스크. `Misc.lua`가 `== 0`으로 비교한다.
        forms = 6,
        groups = 3,
        frameTypes = 1,
        bonusbars = 2,
        units = { target = {} },
        ["$state1"] = true,
        ["$state2"] = true,
        ["$state3"] = true,
        ["$state4"] = true,
        ["$state5"] = true,
    };

    local REAL_VALUES = {
        -- `setActionValue`의 체크박스 갈래. 둘 다 조건이 아니라 액션 최상단이다.
        keepInBindingContext = true,
        ignoreHoverUnit = true,
        -- `Constants.SPELL`은 문자열이다("spell").
        type = Constants.SPELL,
        value = 774,
        key = "F",
        seq = 1,
        priority = 2,
        name = "이름",
        icon = 132219,
        unit = "target",
        conditions = REAL_CONDITIONS,
    };

    test("애드온이 실제로 쓰는 값이 명단의 타입을 통과한다", function()
        ResetProfile();

        local sent = {};
        for field in pairs(DebindStorage.ACTION_FIELDS) do
            check(REAL_VALUES[field] ~= nil,
                field .. "이 명단에 늘었는데 이 표에는 없다");
            sent[field] = REAL_VALUES[field];
        end

        for field in pairs(DebindStorage.CONDITION_TYPES) do
            check(REAL_CONDITIONS[field] ~= nil,
                field .. "이 조건 명단에 늘었는데 이 표에는 없다");
        end

        local action = PlanOne(General({ sent }));
        for field, want in pairs(REAL_CONDITIONS) do
            local got = action.conditions and action.conditions[field];
            if (type(want) == "table") then
                check(type(got) == "table", field .. "이 테이블로 안 왔다: " .. tostring(got));
            else
                check(got == want, field .. "이 " .. tostring(want) .. " 대신 " .. tostring(got));
            end
        end

        for field, want in pairs(REAL_VALUES) do
            local got = action[field];
            if (type(want) == "table") then
                check(type(got) == "table", field .. "이 테이블로 안 왔다: " .. tostring(got));
            else
                check(got == want, field .. "이 " .. tostring(want) .. " 대신 " .. tostring(got));
            end
        end
    end);

    -- **SavedVariables까지 가는 쪽.** 배치 루프가 도중에 터지면 앞의 것은 이미 `Insert`된 뒤이고
    -- 뒤따르는 재번호 매기기가 아예 안 돌아, 살아남은 액션이 내부 도착 밴드(`ARRIVAL_SEQ`)를
    -- 그대로 들고 저장된다. `CleanUpDB`는 nil과 중복만 고치지 그 범위는 안 걷어낸다.
    test("망가진 seq가 있어도 배치가 반쯤 끝나지 않는다", function()
        ResetProfile();
        local placements = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 10, key = "F", seq = 1 },
            { type = Constants.SPELL, value = 20, key = "F", seq = {} },
            { type = Constants.SPELL, value = 30, key = "F", seq = 3 },
        }));
        local key = placements[1].action.key;
        local arrivalID = placements[1].action.arrivalID;
        DebindPrivate.PlaceArrivedActions(placements);

        local placed = 0;
        for _, row in ipairs(DebindPrivate.CollectActionsForKey(key, nil, arrivalID)) do
            placed = placed + 1;
            check(type(row.action.seq) == "number" and row.action.seq < 1000,
                "도착 밴드가 저장에 남았다: " .. tostring(row.action.seq));
        end
        check(placed == 3, "액션 수 " .. placed);
    end);

    ---------------------------------------------------------------------------
    -- Where each action lands
    ---------------------------------------------------------------------------

    -- **한 키는 레이어를 넘어도 한 묶음이다.** The key is on the action and the layer is the path it
    -- sits under, so one set routinely has two addresses. Splitting it would undo the one thing a
    -- keyless string still says: the reader would be handed two headings for what was one key and
    -- would give them two keys - and then both fire.
    test("한 키가 레이어 여럿에 걸쳐도 묶음 하나로 들어온다", function()
        ResetProfile();

        local placements = DebindStorage.PlanArrival({
            v = 1, class = CLASS,
            shared = {
                GENERAL = { { type = Constants.SPELL, value = 1, key = "F", seq = 1 } },
                classes = { [CLASS] = { [0] = {
                    { type = Constants.SPELL, value = 2, key = "F", seq = 1 } } } },
            },
        });

        check(#placements == 2, "액션 수 " .. #placements);
        local scopes, oneKey = {}, nil;
        for _, placement in ipairs(placements) do
            -- One key on the wire has to stay one key here, whatever it got renamed to. Two
            -- numbers would head the same set twice and give the reader two decisions to make
            -- about one thing.
            oneKey = oneKey or placement.action.key;
            check(placement.action.key == oneKey, "키가 갈렸다");
            scopes[placement.scope] = placement;
        end
        check(scopes.general, "일반 자리에 안 갔다");
        check(scopes.class and scopes.class.class == CLASS and scopes.class.spec == 0,
            "직업 공용 자리에 안 갔다");
    end);

    -- **A layer is a coordinate, not something to translate.** Both profiles use the same one, so
    -- another class's layer keeps its class *and* its spec: a mage's spec 2 is a mage's spec 2 on
    -- every account. `entry_spec` measures the addressing in detail; here it just has to be
    -- what the placement actually uses.
    test("목적지는 보낸 쪽 좌표 그대로다", function()
        ResetProfile();
        local _, general = PlanOne(General({ { type = Constants.SPELL, value = 1 } }));
        check(general.scope == "general", "일반이 아니다: " .. tostring(general.scope));

        local _, foreign = PlanOne({
            v = 1, class = CLASS,
            shared = { classes = { MAGE = { [2] = { { type = Constants.SPELL, value = 1 } } } } },
        });
        check(foreign.scope == "class" and foreign.class == "MAGE" and foreign.spec == 2,
            "남의 직업 좌표를 내 것으로 바꿨다: " .. tostring(foreign.class)
                .. "/" .. tostring(foreign.spec));
    end);

    -- A class name no client has. Counted rather than dropped in silence: the window says how many
    -- did not land.
    test("갈 데 없는 주소는 세어서 빠진다", function()
        ResetProfile();
        local placements, skipped = DebindStorage.PlanArrival({
            v = 1, class = CLASS,
            shared = {
                GENERAL = { { type = Constants.SPELL, value = 2 } },
                classes = { NOSUCHCLASS = { [0] = { { type = Constants.SPELL, value = 1 } } } },
            },
        });
        check(#placements == 1, "빠뜨릴 것을 안 빠뜨렸다");
        check(skipped == 1, "안 센다 - 조용히 사라진다");
    end);

    -- 직업 이름이 아니라 **특성 번호**가 자리를 없애는 쪽. 4특성 캐릭터의 캐릭터 레이어를
    -- 3특성 직업이 받으면 그 액션들은 갈 데가 없고, 그것은 읽는 사람이 뺀 것이 아니라 이 판이
    -- 놓을 데가 없는 것이라 세어야 한다.
    test("이 캐릭터에 없는 특성 번호도 세어서 뺀다", function()
        ResetProfile();
        local placements, skipped = DebindStorage.PlanArrival({
            v = 1, class = CLASS,
            shared = { GENERAL = { { type = Constants.SPELL, value = 3 } } },
            char = { [5] = { { type = Constants.SPELL, value = 1 },
                             { type = Constants.SPELL, value = 2 } } },
        });

        check(#placements == 1, "액션 수 " .. #placements);
        check(skipped == 2, "못 놓은 둘을 안 세었다: " .. skipped);
    end);

    -- **틱은 이제 액션에 붙는다.** 미리보기가 액션을 그리고 거기서 고르므로, 놓이는 것도 액션
    -- 단위로 갈린다 (`devdocs/building-export-import.md` 12절). 줄 필터와 같은 규칙이 그대로
    -- 선다: 안 고른 것은 빠지되 세지 않는다.
    test("안 고른 액션은 빠지되 세지 않는다", function()
        ResetProfile();
        local mine = { type = Constants.SPELL, value = 1, key = "F" };
        local theirs = { type = Constants.SPELL, value = 2, key = "G" };

        local placements, skipped = DebindStorage.PlanArrival(General({ mine, theirs }),
            { selection = { [mine] = true } });

        check(#placements == 1, "고른 것만 놓여야 한다: " .. #placements);
        check(placements[1].action.value == 1, "엉뚱한 액션이 놓였다");
        check(skipped == 0, "안 고른 것을 못 놓은 것으로 세었다: " .. skipped);
    end);

    -- **갈 데 없는 것을 세는 자리는 액션 틱에 안 걸린다.** 주소를 못 찾은 레이어는 액션을 도는
    -- 데까지 오지 않고 통째로 세어진다. 줄 필터에서는 그 순서가 실제로 뒤집힐 수 있어 검사가
    -- 하나 서 있는데(위), 여기서는 뒤집을 자리 자체가 없다.
    ---------------------------------------------------------------------------
    -- SETSTATE: v1's subtable, and the shape it lands in
    --
    -- **The rebuild left this file.** The profile stores a type and a name now (§9-1 of
    -- `devdocs/redesigning-custom-states.md`), so a current payload lands as it arrived and
    -- `BuildAction` has nothing to do with it. What v1 spelled as a `setstate` subtable is a
    -- version step like any other, and it stands one door earlier - `BringPayloadForward`.
    ---------------------------------------------------------------------------

    --- A payload run through the door both entrances go through.
    local function Forwarded(payload)
        local raised, reason = DebindStorage.BringPayloadForward(payload);
        check(raised, "관문이 거절했다: " .. tostring(reason));
        return raised;
    end

    --- The wire shape 3.2 wrote. `Constants.SETSTATE` is gone, so the old type is a literal here
    --- for the same reason the migration step holds one.
    local function V1Setstate(mode, state)
        return General({
            { type = "setstate", key = "F", seq = 1,
              setstate = { mode = mode, state = state } } });
    end

    test("v1의 서브테이블이 타입과 이름으로 도착한다", function()
        for _, case in ipairs({
            { mode = "on", type = Constants.SETSTATE_ON },
            { mode = "off", type = Constants.SETSTATE_OFF },
            { mode = "toggle", type = Constants.SETSTATE_TOGGLE },
        }) do
            ResetProfile();
            local action = PlanOne(Forwarded(V1Setstate(case.mode, "$state3")));
            check(action.type == case.type, case.mode .. " -> " .. tostring(action.type));
            check(action.value == "$state3", "이름 " .. tostring(action.value));
            check(action.setstate == nil, "포맷 필드가 액션에 남았다");
        end
    end);

    -- **이 문서 전체가 겨눈 자리다.** 같은 액션이 v1 서브테이블로 와도 지금 모양으로 와도 같은
    -- 것으로 도착해야 한다. 갈리면 액션 모양이 둘이라는 뜻이고, 그러면 마이그레이션도 두 벌이
    -- 된다 (`devdocs/legacy/unifying-action-migration.md`).
    test("v1 페이로드와 새 페이로드가 같은 액션으로 도착한다", function()
        ResetProfile();
        local fromV1 = PlanOne(Forwarded(V1Setstate("toggle", "$state3")));

        local current = General({
            { type = Constants.SETSTATE_TOGGLE, value = "$state3", key = "F", seq = 1 } });
        current.v = DebindStorage.EXPORT_SCHEMA_VERSION;
        current.dbver = Constants.DB_VERSION;

        ResetProfile();
        local fromCurrent = PlanOne(Forwarded(current));

        for _, field in ipairs({ "type", "value", "key", "seq", "imported" }) do
            check(fromV1[field] == fromCurrent[field],
                field .. ": " .. tostring(fromV1[field]) .. " vs " .. tostring(fromCurrent[field]));
        end
    end);

    -- **모르는 모드는 옛 타입인 채로 남는다.** 무엇을 하려던 액션인지 알 수 없으니 셋 중
    -- 아무거나 고르면 켜기가 끄기가 된다. 남은 `"setstate"`는 이 판이 모르는 타입이라
    -- `IsUsableAction`이 걸러내고, 문자열 전체가 거절된다 - 아래 그 자리에서 다시 본다.
    --
    -- **딸려온 `value`도 같이 죽는다.** v1은 `value`를 비우고 보냈으므로 그 자리에 숫자가
    -- 앉아 있는 문자열은 손으로 만든 것이고, 그 숫자는 어떤 것이든 어떤 스위치로 풀린다.
    test("모르는 모드는 안 갈리고, 그래서 못 쓰는 액션이 된다", function()
        local payload = Forwarded(V1Setstate("없는모드", "$state3"));
        local action = payload.shared.GENERAL[1];
        check(action.type == "setstate", "타입 " .. tostring(action.type));
        check(action.setstate == nil, "서브테이블이 남았다");
        check(DebindStorage.PayloadIsImpossible(payload), "문자열이 안 거절됐다");
    end);

    -- **정의가 없는 이름은 그대로 도착한다. 이것이 바뀐 자리다.**
    --
    -- 전에는 `SWITCH_INDICES`에 없는 이름이면 값이 안 만들어져서 문자열이 통째로 거절됐다.
    -- 그 거절은 이름을 번호로 되돌려야 해서 생긴 것이지 판단이 아니었고, 저장 표현이 이름이
    -- 된 지금은 되돌릴 것이 없다. 도착한 뒤의 답도 이미 있다 - 정의가 없는 스위치를 가리키는
    -- 것은 조건 쪽에서 이미 평범하게 받아들이는 모양이고(`ConditionAllowed`), 누르면 아무
    -- 일도 안 일어난다. 붙박이 다섯을 가리키면서 정의가 없는 액션은 이 리포에서 이미 만들 수
    -- 있다 - 카탈로그에서 고르는 것은 정의를 안 심는다(`GetOrCreateSwitchDefinition`).
    test("정의가 없는 이름도 그대로 도착한다", function()
        ResetProfile();
        local action = PlanOne(Forwarded(V1Setstate("toggle", "$nosuchswitch")));
        check(action.type == Constants.SETSTATE_TOGGLE, "타입 " .. tostring(action.type));
        check(action.value == "$nosuchswitch", "이름 " .. tostring(action.value));
    end);

    ---------------------------------------------------------------------------
    -- MACRO: a name and nothing else
    ---------------------------------------------------------------------------

    -- A name that resolves stands as a live reference. One that does not is what
    -- `BINDING_ISSUE_MISSING_MACRO` names, and naming it is the whole of this side's job.
    test("이름으로 온 MACRO는 그대로 참조로 선다", function()
        ResetProfile();
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 재생", index = 3 } };

        local action = PlanOne(General({
            { type = Constants.MACRO, value = "내매크로", key = "F", seq = 1 } }));
        check(action.type == Constants.MACRO, "타입 " .. tostring(action.type));
        check(action.value == "내매크로", "이름 " .. tostring(action.value));
    end);

    test("없는 이름으로 와도 그대로 둔다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.MACRO, value = "없는것", key = "F", seq = 1 } }));
        check(action.type == Constants.MACRO, "타입이 바뀌었다");
        check(action.value == "없는것", "이름이 바뀌었다");
    end);

    -- **Somebody else's macro body does not come in** (2026-08-18,
    -- `devdocs/building-export-import.md`). Our export no longer sends one, but a paste is input
    -- somebody else handed over and may hold anything. A string carrying the old shape leaves no
    -- body in the profile and does not turn the action into a `MACROTEXT`.
    test("본문 스냅샷을 달고 와도 본문은 안 앉는다", function()
        ResetProfile();
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 다른것", index = 3 } };

        local action = PlanOne(General({
            { type = Constants.MACRO, value = "내매크로", key = "F", seq = 1,
              macro = { name = "내매크로", body = "/cast 재생", icon = 9, scope = "account" } } }));
        check(action.type == Constants.MACRO, "MACROTEXT로 떨어졌다");
        check(action.value == "내매크로", "값 " .. tostring(action.value));
        check(action.macro == nil, "포맷 필드가 액션에 남았다");
    end);

    -- **`type = macro` means `value` is a name, at every moment.** A slot number is not a
    -- reference, it is a position in a name-ordered list, and one macro created or deleted ahead of
    -- it hands that position to a different macro. No sharing needed: it breaks the next day on the
    -- same account and the same character.
    --
    -- **Our export cannot emit that**, so a string holding one was edited after it was made, and
    -- the whole string goes. `ImportEntry` reads this and refuses; the rest of the entry is not
    -- warranted by a string somebody has been inside of.
    test("숫자를 든 MACRO 하나가 문자열 전체를 거절시킨다", function()
        check(DebindStorage.PayloadIsImpossible(General({
            { type = Constants.MACRO, value = 4, key = "F", seq = 1 },
            { type = Constants.SPELL, value = 774, key = "G", seq = 1 } })), "안 걸렸다");
    end);

    -- Everything the addon does make goes through untouched. A false positive here refuses a
    -- perfectly good string and the reader is told to ask for another one that will fail the same
    -- way, so this half matters as much as the half above.
    test("멀쩡한 것은 안 걸린다", function()
        check(not DebindStorage.PayloadIsImpossible(General({
            { type = Constants.SPELL, value = 774, key = "F", seq = 1 },
            { type = Constants.MACRO, value = "내매크로", key = "G", seq = 1 },
            { type = Constants.MACROTEXT, value = "/cast 재생", key = "H", seq = 1 },
            { type = Constants.COMMAND, value = "JUMP", key = "J", seq = 1 },
            { type = Constants.PETACTION, value = "PETATTACK", key = "K", seq = 1 },
            { type = Constants.WORLDMARKER, value = 3, key = "L", seq = 1 },
            { type = Constants.SETCUSTOM, value = 1, key = "M", seq = 1 },
            { type = Constants.TARGET, key = "N", seq = 1 },
            { type = Constants.UNUSED, key = "O", seq = 1 },
            { type = Constants.SETSTATE_TOGGLE, value = "$state3", key = "P", seq = 1 } })),
            "멀쩡한 것이 걸렸다");
    end);

    -- The UI reaches for `value` on these three without asking, so one arriving without it is not a
    -- broken reference to show in red, it is a row that raises while being drawn.
    test("값이 있어야 하는 타입이 값 없이 오면 걸린다", function()
        for _, type in ipairs({ Constants.SETCUSTOM, Constants.COMMAND, Constants.WORLDMARKER }) do
            check(DebindStorage.PayloadIsImpossible(General({
                { type = type, key = "F", seq = 1 } })), "안 걸렸다: " .. type);
        end
    end);

    -- A type from a Debind that does not exist yet. It cannot be drawn, bound, or repaired, and
    -- guessing at it is how a key ends up doing something nobody chose.
    test("모르는 타입도 걸린다", function()
        check(DebindStorage.PayloadIsImpossible(General({
            { type = "직업변경", value = 1, key = "F", seq = 1 } })), "안 걸렸다");
    end);

    -- **The old single type is one nothing knows any more**, so a payload still carrying it is
    -- turned away by the same rule that turns away a type from a Debind that does not exist. It
    -- is reachable two ways: a v1 string whose mode the adapter could not read (above), and a
    -- string somebody wrote by hand.
    test("옛 단일 타입 setstate는 모르는 타입으로 걸린다", function()
        check(DebindStorage.PayloadIsImpossible(General({
            { type = "setstate", value = "$state3", key = "F", seq = 1 } })), "안 걸렸다");
    end);

    -- The three that replaced it carry a name, and a number there is a reference to nothing: it
    -- reaches `SetAttribute` as the name of the attribute to set (`UpdateBindings.lua`).
    test("이름 대신 숫자를 든 SETSTATE도 걸린다", function()
        check(DebindStorage.PayloadIsImpossible(General({
            { type = Constants.SETSTATE_TOGGLE, value = 3, key = "F", seq = 1 } })), "안 걸렸다");
    end);

    -- **값이 아예 없는 것은 반대다.** 3c부터 선택 창이 대상 없는 켜기/끄기/전환을 하나 넣으므로
    -- (§6-C), 그 상태로 내보낸 문자열은 **이 애드온이 만들 수 있는 모양**이다. 여기서 걸면
    -- 반쯤 만든 줄 하나 때문에 문자열이 통째로 거절되는데, 받는 쪽 규칙은 그 반대다. 깨진
    -- 것도 보내고 읽는 사람이 빨간 줄을 보고 지운다.
    test("스위치를 안 고른 SETSTATE는 안 걸린다", function()
        check(not DebindStorage.PayloadIsImpossible(General({
            { type = Constants.SETSTATE_TOGGLE, key = "F", seq = 1 } })), "걸렸다");
    end);

    -- **`payload.class` is read as a class name and printed with `%s`.** A table there throws in
    -- WoW's Lua 5.1, out of the drawer row's tooltip, for an entry already written to disk. Our
    -- export only ever writes this character's class.
    test("모르는 class를 든 페이로드는 걸린다", function()
        for _, class in ipairs({ "없는직업", 5 }) do
            local payload = General({ { type = Constants.SPELL, value = 1, key = "F", seq = 1 } });
            payload.class = class;
            check(DebindStorage.PayloadIsImpossible(payload), "안 걸렸다: " .. tostring(class));
        end
    end);

    -- **NaN survives the round trip** and raises the moment it is used as a table index, which the
    -- count in `ImportEntry` does. Refused with everything else rather than guarded at each place a
    -- key is indexed by.
    test("NaN 키도 걸린다", function()
        local nan = tonumber("nan") or (0 / 0);
        check(nan ~= nan, "이 인터프리터에서 NaN이 안 만들어졌다");
        check(DebindStorage.PayloadIsImpossible(General({
            { type = Constants.SPELL, value = 1, key = nan, seq = 1 } })), "안 걸렸다");
    end);

    ---------------------------------------------------------------------------
    -- Placing them
    ---------------------------------------------------------------------------

    test("놓으면 그 레이어에 서고 순서 번호를 받는다", function()
        ResetProfile();
        local placements = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 774, key = "F", seq = 1 } }));

        DebindPrivate.PlaceArrivedActions(placements);

        local layer = DebindPrivate.GetProfileLayer(1);
        check(layer:GetNumActions() == 1, "레이어에 안 들어감");
        local action = layer:GetAction(1);
        check(action.key == "F", "보낸 키가 안 남았다: " .. tostring(action.key));
        check(type(action.arrivalID) == "number", "배지가 없다: " .. tostring(action.arrivalID));
        -- **The sender's number does not survive landing.** It is a place inside their layer; this
        -- one hands out its own, which is what makes carrying it on the wire harmless.
        check(action.seq == 1, "이 그룹의 번호가 아니다: " .. tostring(action.seq));
    end);

    -- **보낸 쪽 차례가 그대로 선다.** 도착 번호가 실려온 `seq`를 더하므로, 배치 안의 차례는
    -- 저장 배열 순서가 아니라 보낸 사람이 정한 것이 된다. 아래는 그 둘을 일부러 어긋나게
    -- 세운다 - 배열 순서대로 매기는 구현에서는 3 1 2가 나온다.
    test("한 그룹은 실려온 seq 차례로 번호를 받는다", function()
        ResetProfile();
        local placements = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 30, key = "F", seq = 3 },
            { type = Constants.SPELL, value = 10, key = "F", seq = 1 },
            { type = Constants.SPELL, value = 20, key = "F", seq = 2 },
        }));
        DebindPrivate.PlaceArrivedActions(placements);

        local layer = DebindPrivate.GetProfileLayer(1);
        for _, action in layer:Enumerate() do
            check(action.seq == action.value / 10,
                "값 " .. action.value .. "의 번호가 " .. tostring(action.seq));
        end
    end);

    -- **The reader own set on that key is left exactly as it was.** The arrival lands on the same
    -- key -- it was sent on F and F is where it goes -- and stays a separate group all the same,
    -- because a group is `(key, arrivalID)`. A merge is the one thing quarantine cannot take back:
    -- once the two are one set, no field anywhere says which member came from where.
    test("이미 쓰고 있는 키는 건드리지 않는다", function()
        ResetProfile();
        DebindPrivate.GetProfileLayer(1):Insert(
            { type = Constants.SPELL, value = 99, key = "F", seq = 1 });

        local placements = DebindStorage.PlanArrival(General({
            { type = Constants.SPELL, value = 10, key = "F", seq = 1 },
            { type = Constants.SPELL, value = 20, key = "F", seq = 2 },
        }));
        DebindPrivate.PlaceArrivedActions(placements);

        local mine = {};
        for _, row in ipairs(DebindPrivate.CollectActionsForKey("F")) do
            mine[#mine + 1] = row.action.value;
        end
        check(#mine == 1 and mine[1] == 99, "내 키에 섞였다: " .. table.concat(mine, " "));

        -- And the arrival is still one set, in the order it was sent.
        local arrived = {};
        for _, row in ipairs(DebindPrivate.CollectActionsForKey(
                "F", nil, placements[1].action.arrivalID)) do
            arrived[#arrived + 1] = row.action.value;
        end
        check(#arrived == 2 and arrived[1] == 10 and arrived[2] == 20,
            "묶음이 안 남았다: " .. table.concat(arrived, " "));
    end);

    -- **A class this account has never played still has a place.** The address is the store's, not
    -- the eleven layers this character happens to see, so it goes in and waits there - invisible in
    -- this session and reaching no key, which is what quarantine already promises.
    test("이 세션에 없는 직업 레이어도 저장에는 들어간다", function()
        ResetProfile();
        DebindPrivate.PlaceArrivedActions({
            { scope = "class", class = "MAGE", spec = 2,
              action = { type = Constants.SPELL, value = 1, key = "F", arrivalID = 3 } },
        });

        local stored = _G.DebindVars.shared.classes.MAGE;
        check(stored and stored[2] and #stored[2] == 1,
            "마법사 특성2 자리에 안 들어갔다");
        check(stored[2][1].seq ~= nil, "순서 번호를 안 받았다");
    end);

    test("자리가 없는 주소를 가리키면 아무것도 안 놓는다", function()
        ResetProfile();
        -- A scope nothing answers to. `PlaceArrivedActions` skips rather than erroring: what it is
        -- handed came off the wire.
        DebindPrivate.PlaceArrivedActions({
            { scope = "raid", action = { type = Constants.SPELL } },
        });
        check(DebindPrivate.GetProfileLayer(1):GetNumActions() == 0, "엉뚱한 데 들어갔다");
    end);

    ---------------------------------------------------------------------------
    -- Finding them again
    ---------------------------------------------------------------------------

    -- **What [Accept all] hands to the approver.** The count on that button and the set it
    -- clears both come from here, so the failure this guards is one number being smaller than the
    -- other - and the leftovers would sit badged in a layer that has no screen of its own until
    -- the reader happens to change specialization.
    test("배지 찾기는 지금 특성 밖의 레이어까지 훑는다", function()
        ResetProfile();
        -- Layer 4 is the class layer of spec 2, and the shim's player is spec 1. An entry lands
        -- there routinely: an action is placed by the scope it was sent with, not by the
        -- specialization the reader happens to be in.
        DebindPrivate.PlaceArrivedActions({
            { scope = "general",
              action = { type = Constants.SPELL, value = 774, key = "F", arrivalID = 3 } },
            { scope = "class", class = CLASS, spec = 2,
              action = { type = Constants.SPELL, value = 774, key = "G", arrivalID = 3 } },
        });

        -- The premise: the layer that walk is not allowed to use really does leave one out.
        local live = 0;
        for _, layer in DebindPrivate.EnumerateProfileLayers() do
            for _, action in layer:Enumerate() do
                if (action.arrivalID) then
                    live = live + 1;
                end
            end
        end
        check(live == 1, "전제가 틀렸다 - 활성 레이어 훑기가 " .. live .. "개를 봤다");

        check(#DebindPrivate.CollectArrivedActions() == 2,
            "오프스펙 레이어의 배지를 놓쳤다");
    end);

    test("배지가 없는 액션은 안 따라온다", function()
        ResetProfile();
        DebindPrivate.PlaceArrivedActions({
            { scope = "general",
              action = { type = Constants.SPELL, value = 774, key = "F", arrivalID = 3 } },
        });
        -- The reader's own, placed the ordinary way. Approving must not reach it.
        DebindPrivate.GetProfileLayer(1):Insert({ type = Constants.SPELL, value = 585, key = "H" });

        local badged = DebindPrivate.CollectArrivedActions();
        check(#badged == 1, "배지 없는 것까지 세었다: " .. #badged);
        check(badged[1].value == 774, "엉뚱한 액션이 나왔다");
    end);

    return T;
end
