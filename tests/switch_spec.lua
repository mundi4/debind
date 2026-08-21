-- Renaming and deleting a switch. No WoW client needed.
--
-- **A rename is not a rename, it is five rewrites.** The definition moving is the part that is
-- obvious and the part that is safe; a switch's name is written down in four other kinds of place,
-- and every one of them fails **silently** when it is missed:
--
--   * a condition key. The condition stops matching anything, and the action goes on being drawn
--     with a condition on it
--   * an on/off/toggle target. The key sets a name nothing defines
--   * a macro body. The clause bakes to `known:0` and that binding stops firing
--   * another switch's expression. The switch computed from it is false from then on
--
-- Plus the value each character remembers, which is keyed by name too. Nothing red appears for the
-- first, the last, or the values.
--
-- **The layers here are wider than the ones on screen on purpose.** A definition is account-wide,
-- so the walk has to reach another class and another character; a rename that only fixed the
-- current character would look right on the screen that ordered it.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local MODES = Constants.SWITCH_MODES;

    -- `LoadProfile` fires "OnProfileLoaded", and so does the notifier every edit below ends in.
    -- The bus is built in `Debind.lua`, which the runner does not load.
    DebindPrivate.callbacks = DebindPrivate.callbacks or { Fire = function() end };
    DebindPrivate.log = function() end;

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
            error(msg or "check failed", 2);
        end
    end

    local ALT = "Player-1234-0000BEEF";
    -- The shim's own character, and the one `InitWith` puts back. Overrides are filed under an
    -- absolute key, so a test that leaves somebody else logged in hands the next one a profile it
    -- reads under a different name (`GetSwitchLayerKey`).
    local ME = "Player-1-TESTGUID";

    --- A profile already at the current version, so nothing migrates and what is read back is what
    --- the rename wrote. Every reference kind is in here exactly once, and each one sits in a
    --- different layer so a walk that reaches only some of them cannot pass.
    local function Profile()
        return {
            dbver = Constants.DB_VERSION,
            shared = {
                GENERAL = {
                    { type = Constants.SPELL, value = 1, key = "F1", seq = 1,
                        conditions = { ["$state1"] = true } },
                    -- The `$state1` after the group is chat text. It is here because a rename that
                    -- reaches it has stopped being a rename of a reference and started being a
                    -- search and replace over what the user typed.
                    { type = Constants.MACROTEXT, key = "F2", seq = 1,
                        value = "/cast [$state1,no$state2] Foo\n/say $state1 is on" },
                    { type = Constants.SETSTATE_TOGGLE, value = "$state1", key = "F3", seq = 1 },
                },
                -- **This character's class, and the shim's character is a druid on spec 1.** Two
                -- layers, and the second one is the one that makes the three counts differ: an
                -- action in specialization 2 is stored, is this character's, and is not live.
                classes = {
                    DRUID = {
                        [0] = {
                            { type = Constants.SPELL, value = 2, key = "F4", seq = 1,
                                conditions = { ["$state1"] = false } },
                        },
                        [2] = {
                            { type = Constants.SPELL, value = 4, key = "F7", seq = 1,
                                conditions = { ["$state1"] = true } },
                        },
                    },
                },
            },
            characters = {
                [ALT] = {
                    layers = {
                        [0] = {
                            { type = Constants.SETSTATE_ON, value = "$state1", key = "F5",
                                seq = 1 },
                        },
                    },
                    switches = { ["$state1"] = true },
                },
            },
            migrated = {},
            switches = {
                ["$state1"] = { mode = MODES.MANUAL },
                -- One switch computed from another. This is the reference the design calls the
                -- easy one to forget, and the only one that is not inside an action at all.
                ["$state2"] = { mode = MODES.EXPR, expr = "[$state1] [combat]" },
            },
        };
    end

    --- Which specialization the world is in. The shim answers 1; a test that changes it is
    --- standing where the game's specialization change stands, and `InitWith` puts it back.
    local function SetSpec(spec)
        _G.C_SpecializationInfo.GetSpecialization = function() return spec; end
    end

    --- Loads a profile, **as somebody**. Both the character and the specialization are set here
    --- rather than left to each test, so a test that logs in as an alt or changes specialization
    --- cannot leak that into the next one: which override wins depends on both.
    local function InitWith(db, guid)
        _G.DebounceVars = nil;
        _G.DebounceVarsPerChar = nil;
        _G.UnitGUID = function() return guid or ME; end
        SetSpec(1);
        _G.DebindVars = db;
        DebindPrivate.InitDB();
        return _G.DebindVars;
    end

    --- The keys the two overridable scopes are filed under, for whoever is logged in now. Asked
    --- through the addon rather than spelled out, because what a test must not do is write down a
    --- second answer to "what is this layer called" and then agree with itself.
    local function CharKey(spec)
        return DebindPrivate.GetSwitchLayerKey(DebindPrivate.GetLayerID(spec, true));
    end

    local function ClassKey(spec)
        return DebindPrivate.GetSwitchLayerKey(DebindPrivate.GetLayerID(spec, false));
    end

    local function General(db)
        return db.shared.GENERAL;
    end

    ---------------------------------------------------------------------------
    -- Renaming
    ---------------------------------------------------------------------------

    test("이름을 바꾸면 정의가 새 이름으로만 열린다", function()
        local db = InitWith(Profile());
        check(DebindPrivate.RenameSwitch("$state1", "$burst"), "개명이 거절됐다");
        check(db.switches["$burst"] ~= nil, "정의가 새 이름 아래 없다");
        check(db.switches["$state1"] == nil, "옛 이름이 남았다 - 스위치가 둘로 보인다");
        check(DebindPrivate.ResolveSwitchDefinition("$burst") ~= nil,
            "살아 있는 표가 새 이름을 모른다");
    end);

    test("조건 키가 따라온다", function()
        local db = InitWith(Profile());
        DebindPrivate.RenameSwitch("$state1", "$burst");
        local action = General(db)[1];
        check(action.conditions["$burst"] == true,
            "조건이 안 따라왔다 - 그 조건은 이제 아무것도 안 맞춘다");
        check(action.conditions["$state1"] == nil, "옛 조건이 남았다");
    end);

    -- 화면에 없는 레이어. 여기가 안 따라오면 사제 화면에서 바꾼 이름이 드루이드 조건을
    -- 조용히 끊는다.
    test("다른 직업·다른 캐릭터의 레이어까지 따라온다", function()
        local db = InitWith(Profile());
        DebindPrivate.RenameSwitch("$state1", "$burst");
        local druid = db.shared.classes.DRUID[0][1];
        check(druid.conditions["$burst"] == false,
            "다른 직업 레이어의 조건이 안 따라왔다");
        check(druid.conditions["$state1"] == nil, "옛 조건이 남았다");
        -- 지금 안 도는 전문화의 레이어. 여기가 빠지면 전문화를 바꾼 날에야 끊긴 것이 보인다.
        check(db.shared.classes.DRUID[2][1].conditions["$burst"] == true,
            "지금 안 도는 전문화 레이어의 조건이 안 따라왔다");
        local alt = db.characters[ALT].layers[0][1];
        check(alt.value == "$burst", "다른 캐릭터의 켜기 액션이 안 따라왔다");
    end);

    -- **이 캐릭터의 항목은 계정 표에 아직 안 붙어 있을 수 있다.** 내용이 생겨야 붙이므로
    -- (`CleanUpDB`의 게으른 생성), 캐릭터 레이어에 방금 만든 액션은 `db.characters` 어디에도
    -- 없고 `db.char`에만 있다. 거기를 안 훑으면 **지금 화면에 보이는 바로 그 액션**이 개명에서
    -- 빠진다.
    test("아직 계정 표에 안 붙은 이 캐릭터의 레이어까지 따라온다", function()
        local db = InitWith(Profile());
        local charEntry = DebindPrivate.db.char;
        for _, entry in pairs(db.characters) do
            check(entry ~= charEntry, "전제가 깨졌다 - 항목이 이미 계정 표에 붙어 있다");
        end
        charEntry.layers[0] = {
            { type = Constants.SPELL, value = 3, key = "F6", seq = 1,
                conditions = { ["$state1"] = true } },
        };

        DebindPrivate.RenameSwitch("$state1", "$burst");

        local action = charEntry.layers[0][1];
        check(action.conditions["$burst"] == true,
            "안 붙은 항목의 조건이 안 따라왔다 - 지금 보고 있는 액션이 조용히 끊긴다");
        check(action.conditions["$state1"] == nil, "옛 조건이 남았다");
    end);

    test("켜기·끄기·전환의 대상이 따라온다", function()
        local db = InitWith(Profile());
        DebindPrivate.RenameSwitch("$state1", "$burst");
        check(General(db)[3].value == "$burst",
            "전환 액션이 옛 이름을 가리킨다 - 눌러도 아무 일이 없다");
    end);

    test("매크로 본문의 조건절만 따라온다", function()
        local db = InitWith(Profile());
        DebindPrivate.RenameSwitch("$state1", "$burst");
        local body = General(db)[2].value;
        check(body:find("[$burst,no$state2]", 1, true),
            "본문 조건이 안 따라왔다: " .. body);
        check(not body:find("[$state1", 1, true), "본문에 옛 이름이 남았다: " .. body);
        check(body:find("/say $state1 is on", 1, true),
            "조건절 밖의 글자까지 바꿨다 - 사용자가 친 문장이다: " .. body);
    end);

    test("다른 스위치의 계산식이 따라온다", function()
        local db = InitWith(Profile());
        DebindPrivate.RenameSwitch("$state1", "$burst");
        check(db.switches["$state2"].expr == "[$burst] [combat]",
            "계산식이 " .. tostring(db.switches["$state2"].expr) .. "로 남았다");
    end);

    -- 참조는 아니지만 이름으로 앉아 있는 다섯 번째 자리. 안 옮기면 "기억하기" 스위치가
    -- 개명 다음 로그인에 저 혼자 꺼진 채로 올라온다.
    test("캐릭터가 기억하는 값이 따라온다", function()
        local db = InitWith(Profile());
        DebindPrivate.db.char.switches["$state1"] = true;
        DebindPrivate.RenameSwitch("$state1", "$burst");
        check(db.characters[ALT].switches["$burst"] == true,
            "다른 캐릭터의 기억한 값이 안 따라왔다");
        check(db.characters[ALT].switches["$state1"] == nil, "옛 이름이 남았다");
        check(DebindPrivate.db.char.switches["$burst"] == true,
            "이 캐릭터의 기억한 값이 안 따라왔다");
    end);

    -- 켜둔 스위치의 이름을 바꾸는 것은 그 스위치를 끄는 일이 아니다. 표를 다시 지으면
    -- `resetValue`에서 값을 다시 계산해서, 지금 켜져 있는 것이 개명 부작용으로 꺼진다.
    test("켜져 있는 값은 개명에 안 흔들린다", function()
        InitWith(Profile());
        DebindPrivate.Switches["$state1"].value = true;
        DebindPrivate.RenameSwitch("$state1", "$burst");
        check(DebindPrivate.Switches["$burst"].value == true,
            "개명이 켜져 있던 스위치를 껐다");
    end);

    -- 위 케이스의 나머지 절반. 개명은 값을 안 건드리지만 **그 뒤에 오는 리빌드**가 건드릴 수
    -- 있다: 마지막으로 무엇을 걸었는지는 이름으로 기억되므로(`ApplySwitchResets`), 새 이름에
    -- 기억이 없으면 첫 리빌드가 그 답을 처음부터 다시 건다. 개명은 스위치를 누르는 방법이
    -- 아니다.
    test("개명 뒤의 리빌드도 켜져 있던 값을 안 끈다", function()
        InitWith(Profile());
        DebindPrivate.Switches["$state1"].resetValue = false;
        DebindPrivate.ApplySwitchResets();
        DebindPrivate.SetSwitchValue("$state1", true);

        DebindPrivate.RenameSwitch("$state1", "$burst");
        DebindPrivate.ApplySwitchResets();

        check(DebindPrivate.Switches["$burst"].value == true,
            "개명 다음 리빌드가 켜져 있던 스위치를 껐다");
    end);

    ---------------------------------------------------------------------------
    -- 값을 바꾸는 자리
    --
    -- **값과 기억은 한 번의 쓰기다.** "두던 대로"인 스위치가 기억하는 것은 캐릭터 쪽에
    -- 앉아 있어서, 정의에만 쓰면 이번 세션은 멀쩡하고 다음 로드에 조용히 되돌아간다.
    ---------------------------------------------------------------------------

    test("두던 대로인 스위치는 캐릭터가 값을 기억한다", function()
        InitWith(Profile());
        DebindPrivate.SetSwitchValue("$state1", true);
        check(DebindPrivate.Switches["$state1"].value == true, "값이 안 켜졌다");
        check(DebindPrivate.db.char.switches["$state1"] == true,
            "기억을 안 남겼다 - 다음 로드에 도로 꺼진다");
    end);

    ---------------------------------------------------------------------------
    -- 거절하는 자리
    --
    -- **거절은 아무것도 안 바꾸고 거절해야 한다.** 절반만 옮긴 개명은 이름 하나가 두 군데를
    -- 가리키는 상태라, 사용자가 볼 수 있는 어떤 화면도 그 상태를 설명하지 못한다.
    ---------------------------------------------------------------------------

    test("매크로에 못 쓰는 이름은 거절한다", function()
        local db = InitWith(Profile());
        for _, bad in ipairs({ "burst", "$", "$bur st", "$버스트", "$burst!", "" }) do
            local ok, reason = DebindPrivate.RenameSwitch("$state1", bad);
            check(not ok, "매크로에 칠 수 없는 이름 " .. bad .. "을 받았다");
            check(reason == "SWITCH_NAME_ERROR_INVALID", "이유가 " .. tostring(reason));
        end
        check(db.switches["$state1"] ~= nil, "거절해놓고 정의를 옮겼다");
        check(General(db)[1].conditions["$state1"] == true, "거절해놓고 조건을 옮겼다");
    end);

    test("이미 있는 이름은 거절한다", function()
        local db = InitWith(Profile());
        local ok, reason = DebindPrivate.RenameSwitch("$state1", "$state2");
        check(not ok, "두 스위치가 한 이름을 갖게 뒀다");
        check(reason == "SWITCH_NAME_ERROR_TAKEN", "이유가 " .. tostring(reason));
        check(db.switches["$state2"].mode == MODES.EXPR, "남의 정의를 덮어썼다");
        check(General(db)[3].value == "$state1", "거절해놓고 액션을 옮겼다");
    end);

    test("없는 스위치는 거절한다", function()
        InitWith(Profile());
        local ok, reason = DebindPrivate.RenameSwitch("$nosuch", "$burst");
        check(not ok, "없는 것을 개명했다");
        check(reason == "SWITCH_RENAME_ERROR_GONE", "이유가 " .. tostring(reason));
    end);

    ---------------------------------------------------------------------------
    -- 지우기
    --
    -- **참조는 그대로 둔다.** 정의가 없는 이름을 가리키는 액션은 빨개지고(`GetUndefinedSwitch`),
    -- 그 빨간 것이 사용자가 고치러 갈 자리의 목록이다. 여기서 참조까지 지우면 사용자가 잃은
    -- 것이 무엇이었는지 화면 어디에도 안 남는다.
    ---------------------------------------------------------------------------

    test("지워도 참조는 그 자리에 남는다", function()
        local db = InitWith(Profile());
        check(DebindPrivate.DeleteSwitch("$state1"), "지우기가 거절됐다");
        check(db.switches["$state1"] == nil, "정의가 안 지워졌다");
        check(General(db)[1].conditions["$state1"] == true, "조건까지 지웠다");
        check(General(db)[3].value == "$state1", "액션의 대상까지 지웠다");
    end);

    test("지운 스위치를 가리키는 액션은 빨개진다", function()
        InitWith(Profile());
        DebindPrivate.DeleteSwitch("$state1");
        check(DebindPrivate.GetBindingIssue({ type = Constants.SETSTATE_TOGGLE, value = "$state1",
                key = "F3" }) == Constants.BINDING_ISSUE_UNDEFINED_STATE,
            "지운 이름을 가리키는 액션이 멀쩡한 줄로 남는다");
    end);

    -- 값은 이 스위치의 것이라 같이 간다. 남겨두면 같은 이름을 다음에 쓰는 스위치가 남의 값을
    -- 물려받는다.
    test("지우면 기억한 값도 간다", function()
        local db = InitWith(Profile());
        DebindPrivate.db.char.switches["$state1"] = true;
        DebindPrivate.DeleteSwitch("$state1");
        check(db.characters[ALT].switches["$state1"] == nil, "다른 캐릭터의 값이 남았다");
        check(DebindPrivate.db.char.switches["$state1"] == nil, "이 캐릭터의 값이 남았다");
    end);

    ---------------------------------------------------------------------------
    -- 몇 개가 걸려 있나
    --
    -- 지울 때 묻는 문장이 드는 숫자다. 정의는 계정 것인데 목록은 지금 캐릭터가 닿는 레이어만
    -- 보여주므로, **그 한 줄이 그 비대칭을 덮는 유일한 자리다**.
    ---------------------------------------------------------------------------

    test("걸린 액션 수는 세 종류를 다 센다", function()
        InitWith(Profile());
        -- 조건 하나(GENERAL) + 본문 하나 + 전환 하나 + 드루이드 공용 조건 하나 + 드루이드
        -- 2특성 조건 하나 + 다른 캐릭터의 켜기 하나.
        local account = DebindPrivate.CountSwitchReferences("$state1");
        check(account == 6, "센 것이 " .. account .. "개다");
        check(DebindPrivate.CountSwitchReferences("$state2") == 1,
            "본문의 부정형(`no$state2`)을 안 셌다");
        check(DebindPrivate.CountSwitchReferences("$nosuch") == 0, "없는 이름이 세어졌다");
    end);

    -- **세 거리가 서로 다른 답이라는 것이 이 함수의 존재 이유다.** 하나로 합치면 세 캐릭터가
    -- 기대는 스위치와 만들어놓고 안 쓰는 스위치가 같은 숫자로 보인다.
    --
    -- 이 프로필에서 셋은 이렇게 갈린다: 다른 캐릭터의 켜기 액션은 **계정에만** 있고,
    -- 드루이드 2특성 조건은 **이 캐릭터 것이지만 지금 안 도는** 레이어에 있다.
    test("세 거리가 각각 다른 것을 센다", function()
        InitWith(Profile());
        local account, character, live = DebindPrivate.CountSwitchReferences("$state1");
        check(account == 6, "계정 전체가 " .. account .. "개다");
        check(character == 5,
            "현재 캐릭터가 " .. character .. "개다 - 다른 캐릭터 것까지 셌거나 덜 셌다");
        check(live == 4,
            "현재 활성이 " .. live .. "개다 - 지금 안 도는 2특성 레이어까지 셌다");
    end);

    ---------------------------------------------------------------------------
    -- 만들기
    --
    -- 3c 전까지는 **붙박이 다섯 이름 위에서만** 만들어졌고, 그것이 개수를 다섯으로 붙들어
    -- 두는 유일한 자리였다. 그 문이 없어졌으니 여기서 답해야 하는 것은 둘이다. 아무 이름이나
    -- 되는가, 그리고 **이름 규칙은 여전히 서는가**. 둘째가 빠지면 매크로 본문에 적을 수 없는
    -- 이름이 프로필에 앉는다(`ParseMacroText`가 그 토큰을 버리고 조건이 글자 그대로 나간다).
    ---------------------------------------------------------------------------

    test("붙박이 다섯 밖의 이름으로도 만들어진다", function()
        local db = InitWith(Profile());
        check(DebindPrivate.CreateSwitch("$newname"), "다섯 밖의 이름이 거절됐다");
        check(db.switches["$newname"] ~= nil, "정의가 안 앉았다");
        check(db.switches["$newname"].mode == MODES.MANUAL,
            "기본값이 안 들어갔다: " .. tostring(db.switches["$newname"].mode));
    end);

    -- 씨앗에 둘이 있고 여덟을 더 만든다. 상한이 다시 서면 여섯째에서 걸린다.
    test("다섯을 넘겨 만들어도 전부 남는다", function()
        local db = InitWith(Profile());
        for i = 1, 8 do
            check(DebindPrivate.CreateSwitch("$extra" .. i), i .. "번째에서 거절됐다");
        end
        local names = DebindPrivate.GetSwitchNames();
        check(#names == 10, "정의가 " .. #names .. "개다");
        for i = 1, 8 do
            check(db.switches["$extra" .. i] ~= nil, "$extra" .. i .. "이 안 남았다");
        end
    end);

    test("이름 규칙에 안 맞으면 거절한다", function()
        InitWith(Profile());
        local ok, reason = DebindPrivate.CreateSwitch("burst");
        check(not ok, "$ 없는 이름이 통과했다");
        check(reason == "SWITCH_NAME_ERROR_INVALID", "이유가 " .. tostring(reason));
        check(not DebindPrivate.CreateSwitch("$has space"), "빈칸이 든 이름이 통과했다");
        check(not DebindPrivate.CreateSwitch("$"), "$ 하나가 통과했다");
    end);

    test("이미 있는 이름은 거절한다", function()
        InitWith(Profile());
        local ok, reason = DebindPrivate.CreateSwitch("$state1");
        check(not ok, "이미 있는 이름이 통과했다");
        check(reason == "SWITCH_NAME_ERROR_TAKEN", "이유가 " .. tostring(reason));
    end);

    ---------------------------------------------------------------------------
    -- 아직 스위치를 안 고른 켜기/끄기/전환
    --
    -- 선택 창이 값 없이 하나 넣는다(§6-C). **그 액션은 KeyMap에서 빠져야 한다.** 안 빠지면
    -- `SetAttribute`가 nil 이름을 받아 속성을 지우고, 키는 조용히 아무 일도 안 한다.
    ---------------------------------------------------------------------------

    test("스위치를 안 고른 켜기/끄기/전환은 빨개진다", function()
        InitWith(Profile());
        local NONE = Constants.BINDING_ISSUE_SWITCH_NONE_SELECTED;
        for _, actionType in ipairs({ Constants.SETSTATE_ON, Constants.SETSTATE_OFF,
                Constants.SETSTATE_TOGGLE }) do
            local issue = DebindPrivate.GetBindingIssue({ type = actionType, key = "F1" });
            check(issue == NONE, actionType .. "이 " .. tostring(issue) .. "다");
        end
        -- 고르고 나면 사라진다. 이게 없으면 위는 "이 타입은 늘 빨갛다"와 구별이 안 된다.
        check(DebindPrivate.GetBindingIssue({ type = Constants.SETSTATE_TOGGLE,
            value = "$state1", key = "F1" }) == nil, "고른 뒤에도 빨갛다");
    end);

    -- 이름이 없는 것과 이름이 틀린 것은 다른 이야기를 한다. 한 코드로 접으면 사용자가 읽는
    -- 문장이 "안 골랐다"인데 실제로는 "고른 것이 없어졌다"가 된다.
    test("안 고른 것과 없는 것을 가르는 코드가 다르다", function()
        InitWith(Profile());
        check(DebindPrivate.GetBindingIssue({ type = Constants.SETSTATE_ON, value = "$typo",
                key = "F1" }) == Constants.BINDING_ISSUE_UNDEFINED_STATE,
            "없는 이름이 안 고른 것으로 보고된다");
    end);

    -- 본문을 지을 수 없는 액션에 [매크로로 바꾸기]를 세우면 눌러도 아무 일이 없다.
    test("스위치를 안 고르면 매크로로 못 바꾼다", function()
        InitWith(Profile());
        check(not DebindPrivate.CanConvertToMacroText({ type = Constants.SETSTATE_TOGGLE }),
            "이름이 없는데도 바꾸기를 내준다");
        check(DebindPrivate.CanConvertToMacroText({ type = Constants.SETSTATE_TOGGLE,
            value = "$state1" }), "이름이 있는데 바꾸기가 안 선다");
    end);

    ---------------------------------------------------------------------------
    -- 레이어 오버라이드
    --
    -- 정체성은 전역이고 동작은 레이어에서 덮인다(§4-6). 한 레이어가 하는 말은 넷 중 하나이고,
    -- **좁은 쪽부터 읽어 처음 나오는 답이 이긴다.** 뿌리 값은 정의 자신이라 언제나 있다.
    ---------------------------------------------------------------------------

    -- ⚠ **레이어 키는 절대값이어야 한다**(§4-7-3). 오버라이드는 계정 것인 정의에 붙는데
    -- `LAYER_INFOS`의 7~11은 "지금 로그인한 캐릭터"라, 번호로 적으면 다음 캐릭터가 남의
    -- 설정을 읽는다. 아래 두 케이스가 그 거울이다.
    test("레이어 키가 어느 캐릭터·어느 직업인지를 들고 있다", function()
        InitWith(Profile());
        check(CharKey(1) == ME .. ":1", "캐릭터 키가 " .. tostring(CharKey(1)) .. "다");
        check(CharKey(0) == ME .. ":0", "캐릭터 공용 키가 " .. tostring(CharKey(0)) .. "다");
        check(ClassKey(2) == "DRUID:2", "직업 키가 " .. tostring(ClassKey(2)) .. "다");
        check(ClassKey(0) == "DRUID:0", "직업 공용 키가 " .. tostring(ClassKey(0)) .. "다");
        -- 전역은 뿌리 값이라 오버라이드 자리가 없다. 있으면 지울 수 있는 뿌리가 된다.
        check(DebindPrivate.GetSwitchLayerKey(DebindPrivate.GetLayerID(nil, false)) == nil,
            "전역이 오버라이드 키를 갖는다");
    end);

    test("캐릭터 레이어의 오버라이드는 다른 캐릭터로 안 샌다", function()
        local db = InitWith(Profile());
        DebindPrivate.SetSwitchAnswer("$state1", CharKey(1), MODES.MANUAL, true);

        local mode, resetValue, _, layerKey = DebindPrivate.ResolveSwitchAnswer("$state1");
        check(resetValue == true and mode == MODES.MANUAL, "만든 캐릭터에서 안 이긴다");
        check(layerKey == ME .. ":1", "이긴 레이어가 " .. tostring(layerKey) .. "다");

        -- 다른 캐릭터로 들어온다. 같은 계정 표, 같은 정의, 같은 레이어 번호.
        InitWith(db, ALT);
        local altMode, altReset, _, altKey = DebindPrivate.ResolveSwitchAnswer("$state1");
        check(altKey == nil, "다른 캐릭터가 남의 오버라이드를 읽었다: " .. tostring(altKey));
        check(altReset == nil and altMode == MODES.MANUAL, "다른 캐릭터가 남의 답을 받았다");
    end);

    -- 직업 레이어는 반대다. 같은 직업이면 캐릭터가 달라도 같은 답이고, 그게 그 층의 뜻이다.
    test("직업 레이어의 오버라이드는 같은 직업의 다른 캐릭터도 읽는다", function()
        local db = InitWith(Profile());
        DebindPrivate.SetSwitchAnswer("$state1", ClassKey(0), MODES.MANUAL, false);

        InitWith(db, ALT);
        local _, resetValue, _, layerKey = DebindPrivate.ResolveSwitchAnswer("$state1");
        check(layerKey == "DRUID:0", "이긴 레이어가 " .. tostring(layerKey) .. "다");
        check(resetValue == false, "답이 안 따라왔다");
    end);

    test("좁은 레이어가 넓은 레이어를 이긴다", function()
        InitWith(Profile());
        DebindPrivate.SetSwitchAnswer("$state1", ClassKey(0), MODES.MANUAL, false);
        local _, _, _, key = DebindPrivate.ResolveSwitchAnswer("$state1");
        check(key == ClassKey(0), "직업 공용이 뿌리를 못 이겼다: " .. tostring(key));

        DebindPrivate.SetSwitchAnswer("$state1", ClassKey(1), MODES.MANUAL, true);
        _, _, _, key = DebindPrivate.ResolveSwitchAnswer("$state1");
        check(key == ClassKey(1), "직업 전문화가 직업 공용을 못 이겼다: " .. tostring(key));

        DebindPrivate.SetSwitchAnswer("$state1", CharKey(0), MODES.MANUAL, false);
        _, _, _, key = DebindPrivate.ResolveSwitchAnswer("$state1");
        check(key == CharKey(0), "캐릭터 공용이 직업을 못 이겼다: " .. tostring(key));

        DebindPrivate.SetSwitchAnswer("$state1", CharKey(1), MODES.EXPR);
        local mode; mode, _, _, key = DebindPrivate.ResolveSwitchAnswer("$state1");
        check(key == CharKey(1), "캐릭터 전문화가 못 이겼다: " .. tostring(key));
        check(mode == MODES.EXPR, "이긴 행의 모드가 안 나왔다");
    end);

    -- 한 행이 하는 말은 **넷 중 하나**다(§4-6). 필드마다 따로 물려받으면 "마지막 상태"를
    -- 말할 수가 없다 - `resetValue`가 없는 것과 "없음이 답인 것"이 같은 모양이라서다.
    test("이긴 행이 셋을 다 답한다", function()
        InitWith(Profile());
        DebindPrivate.SetSwitchAnswer("$state1", nil, MODES.MANUAL, true);
        DebindPrivate.SetSwitchAnswer("$state1", ClassKey(1), MODES.MANUAL, nil);

        local mode, resetValue = DebindPrivate.ResolveSwitchAnswer("$state1");
        check(mode == MODES.MANUAL, "모드가 " .. tostring(mode) .. "다");
        check(resetValue == nil,
            "이긴 행이 '마지막 상태'인데 뿌리의 시작값이 새어 나왔다: " .. tostring(resetValue));
    end);

    ---------------------------------------------------------------------------
    -- 전문화 전환에 다시 적용 (§4-8)
    --
    -- `resetValue`는 로그인 때만 거는 값이 아니다. "이 전문화에서는 항상 켜짐"인데 그 전문화로
    -- 들어왔을 때 꺼져 있으면 설정이 거짓말이 된다. 게임에서 이것을 부르는 자리는
    -- `UpdateBindings`이고, 전문화 전환이 재컴파일을 부른다.
    ---------------------------------------------------------------------------

    test("전문화를 바꾸면 그 전문화의 오버라이드가 걸린다", function()
        InitWith(Profile());
        DebindPrivate.SetSwitchAnswer("$state1", ClassKey(2), MODES.MANUAL, true);
        DebindPrivate.ApplySwitchResets();
        check(DebindPrivate.Switches["$state1"].value == false, "1특성에서 벌써 켜졌다");

        SetSpec(2);
        DebindPrivate.ApplySwitchResets();
        check(DebindPrivate.Switches["$state1"].value == true,
            "2특성으로 들어왔는데 '항상 켜짐'이 안 걸렸다");
    end);

    -- 다른 절반. 안 바뀌었으면 안 걸어야 한다 - 리빌드는 바인딩을 고칠 때마다 도는데,
    -- 그때마다 다시 걸면 사용자가 방금 끈 스위치가 도로 켜진다.
    test("답이 그대로면 다시 안 건다", function()
        InitWith(Profile());
        DebindPrivate.SetSwitchAnswer("$state1", nil, MODES.MANUAL, true);
        DebindPrivate.ApplySwitchResets();
        check(DebindPrivate.Switches["$state1"].value == true, "시작값이 안 걸렸다");

        DebindPrivate.SetSwitchValue("$state1", false);
        DebindPrivate.ApplySwitchResets();
        check(DebindPrivate.Switches["$state1"].value == false,
            "리빌드가 사용자가 끈 스위치를 도로 켰다");
    end);

    ---------------------------------------------------------------------------
    -- savedValue는 안 지운다 (§4-9)
    --
    -- 옛 규칙은 "강제된 것은 기억 안 함"이었다. 오버라이드가 들어오면 그 규칙이 **"강제된
    -- 전문화를 떠나면 기억이 날아간다"** 가 된다. 지우지 않으면 분기가 하나 줄고, 전역만
    -- 쓰는 프로필에서는 관측 차이가 0이다.
    ---------------------------------------------------------------------------

    test("시작값이 정해져 있어도 기억은 남는다", function()
        InitWith(Profile());
        DebindPrivate.Switches["$state1"].resetValue = false;
        DebindPrivate.SetSwitchValue("$state1", true);
        check(DebindPrivate.Switches["$state1"].value == true, "값이 안 켜졌다");
        check(DebindPrivate.db.char.switches["$state1"] == true,
            "기억을 안 남겼다 - 강제된 레이어를 떠나면 돌아갈 값이 없다");
    end);

    test("강제된 전문화를 벗어나면 원래 값이 돌아온다", function()
        InitWith(Profile());
        -- 뿌리는 "마지막 상태", 2특성만 "항상 꺼짐". 1특성에서 켜둔다.
        DebindPrivate.SetSwitchAnswer("$state1", ClassKey(2), MODES.MANUAL, false);
        DebindPrivate.SetSwitchValue("$state1", true);
        DebindPrivate.ApplySwitchResets();
        check(DebindPrivate.Switches["$state1"].value == true, "1특성에서 안 켜져 있다");

        SetSpec(2);
        DebindPrivate.ApplySwitchResets();
        check(DebindPrivate.Switches["$state1"].value == false, "2특성에서 안 꺼졌다");
        check(DebindPrivate.db.char.switches["$state1"] == true,
            "강제된 값이 기억을 덮었다 - 돌아갈 곳이 없어졌다");

        SetSpec(1);
        DebindPrivate.ApplySwitchResets();
        check(DebindPrivate.Switches["$state1"].value == true,
            "돌아왔는데 켜져 있지 않다");
    end);

    -- 리셋은 비보안 쪽에서 값을 쓰고 제한 환경으로 밀어넣는데, 그쪽이 그것을 그대로 되보고한다
    -- (`OnSwitchChanged`). 그 되보고를 기억으로 받으면 로그인 한 번에 기억이 날아간다.
    test("되돌아온 리셋은 기억이 되지 않는다", function()
        InitWith(Profile());
        DebindPrivate.SetSwitchValue("$state1", true);
        check(DebindPrivate.db.char.switches["$state1"] == true, "전제가 깨졌다");

        DebindPrivate.Switches["$state1"].resetValue = false;
        DebindPrivate.ApplySwitchResets();
        check(DebindPrivate.Switches["$state1"].value == false, "시작값이 안 걸렸다");

        -- 제한 환경이 방금 밀어넣은 값을 그대로 돌려준다.
        DebindPrivate.SetSwitchValue("$state1", false);
        check(DebindPrivate.db.char.switches["$state1"] == true,
            "리셋의 메아리가 기억을 덮었다");
    end);

    ---------------------------------------------------------------------------
    -- 오버라이드를 편집하는 자리
    ---------------------------------------------------------------------------

    test("전역 행은 제거할 수 없다", function()
        InitWith(Profile());
        DebindPrivate.SetSwitchAnswer("$state1", nil, MODES.MANUAL, true);
        check(not DebindPrivate.ClearSwitchOverride("$state1", nil), "뿌리 값을 지웠다");
        local _, resetValue = DebindPrivate.ResolveSwitchAnswer("$state1");
        check(resetValue == true, "뿌리 값이 흔들렸다");
    end);

    test("제거하면 넓은 쪽 답으로 돌아간다", function()
        InitWith(Profile());
        DebindPrivate.SetSwitchAnswer("$state1", nil, MODES.MANUAL, true);
        DebindPrivate.SetSwitchAnswer("$state1", CharKey(1), MODES.MANUAL, false);
        check(DebindPrivate.ClearSwitchOverride("$state1", CharKey(1)), "제거가 거절됐다");

        local _, resetValue, _, layerKey = DebindPrivate.ResolveSwitchAnswer("$state1");
        check(layerKey == nil and resetValue == true, "뿌리로 안 돌아갔다");
        check(DebindPrivate.Switches["$state1"].overrides == nil,
            "마지막 오버라이드를 뺐는데 빈 표가 남았다");
    end);

    -- 답을 고르는 것과 식을 적는 것은 두 동작이다. 넷을 훑어보고 돌아온 사용자가 적어둔
    -- 글자를 잃으면 안 된다.
    test("답을 바꿔도 그 행의 식은 남는다", function()
        InitWith(Profile());
        DebindPrivate.SetSwitchAnswer("$state1", CharKey(1), MODES.EXPR);
        DebindPrivate.SetSwitchExpression("$state1", CharKey(1), "[combat]");
        DebindPrivate.SetSwitchAnswer("$state1", CharKey(1), MODES.MANUAL, true);
        DebindPrivate.SetSwitchAnswer("$state1", CharKey(1), MODES.EXPR);

        local mode, _, expr = DebindPrivate.ResolveSwitchAnswer("$state1");
        check(mode == MODES.EXPR, "모드가 " .. tostring(mode) .. "다");
        check(expr == "[combat]", "식이 " .. tostring(expr) .. "로 남았다");
    end);

    -- 오버라이드가 정의 안에 사는 이유 하나(§4-7-1). 레이어 쪽에 뒀으면 개명이 훑을 자리가
    -- 하나 더 늘고, 탭 복사가 오버라이드를 데려가야 하는지를 물어야 했다.
    test("개명이 오버라이드를 데려간다", function()
        local db = InitWith(Profile());
        DebindPrivate.SetSwitchAnswer("$state1", CharKey(1), MODES.MANUAL, true);
        check(DebindPrivate.RenameSwitch("$state1", "$burst"), "개명이 거절됐다");

        local _, resetValue, _, layerKey = DebindPrivate.ResolveSwitchAnswer("$burst");
        check(layerKey == CharKey(1) and resetValue == true, "오버라이드가 안 따라왔다");
        check(db.switches["$burst"].overrides[CharKey(1)] ~= nil, "저장에 안 앉았다");
    end);

    -- **오버라이드에도 계산식이 산다.** 뿌리의 식만 훑으면 탭에서만 계산하는 스위치가
    -- 개명 뒤에 옛 이름을 부르게 되고, 그 이름은 `known:0`으로 구워져서 **그 탭에서만**
    -- 조용히 거짓이 된다. 스위치 목록도 액션 줄도 아무 말을 안 한다.
    test("개명이 오버라이드의 계산식까지 따라온다", function()
        local db = InitWith(Profile());
        local key = ClassKey(1);
        DebindPrivate.SetSwitchAnswer("$state2", key, MODES.EXPR);
        DebindPrivate.SetSwitchExpression("$state2", key, "[$state1] [stealth]");

        DebindPrivate.RenameSwitch("$state1", "$burst");

        check(db.switches["$state2"].overrides[key].expr == "[$burst] [stealth]",
            "오버라이드의 식이 " .. tostring(db.switches["$state2"].overrides[key].expr)
                .. "로 남았다");
    end);

    -- 지울 때 묻는 문장이 드는 두 번째 숫자. 정의는 계정 것인데 목록은 이 캐릭터가 닿는
    -- 레이어만 보여주므로, 안 보이는 오버라이드가 같이 사라지는 것을 말해줄 자리가 여기뿐이다.
    test("오버라이드 개수는 화면에 안 보이는 것까지 센다", function()
        InitWith(Profile());
        DebindPrivate.SetSwitchAnswer("$state1", CharKey(1), MODES.MANUAL, true);
        -- 사제의 레이어. 이 캐릭터는 어느 화면에서도 이 행을 볼 수 없다.
        DebindPrivate.SetSwitchAnswer("$state1", "PRIEST:2", MODES.MANUAL, false);
        check(DebindPrivate.CountSwitchOverrides("$state1") == 2,
            "센 것이 " .. DebindPrivate.CountSwitchOverrides("$state1") .. "개다");
        check(DebindPrivate.CountSwitchOverrides("$state2") == 0, "없는데 세어졌다");
        check(DebindPrivate.CountSwitchOverrides("$nosuch") == 0, "없는 이름이 세어졌다");
    end);

    ---------------------------------------------------------------------------
    -- 대소문자
    ---------------------------------------------------------------------------

    test("만들 때 이름이 소문자로 내려간다", function()
        local db = InitWith(Profile());
        check(DebindPrivate.CreateSwitch("$ZZZ"), "만들기가 거절됐다");
        check(db.switches["$zzz"] ~= nil, "소문자 이름으로 안 앉았다");
        check(db.switches["$ZZZ"] == nil, "친 대로 앉았다 - 대소문자만 다른 둘이 생긴다");
    end);

    test("대소문자만 다른 이름은 이미 있는 것으로 본다", function()
        InitWith(Profile());
        check(DebindPrivate.CreateSwitch("$zzz"), "만들기가 거절됐다");
        local ok, err = DebindPrivate.CreateSwitch("$ZZZ");
        check(not ok, "`$zzz`가 있는데 `$ZZZ`가 또 만들어졌다");
        check(err == "SWITCH_NAME_ERROR_TAKEN", "다른 이유로 거절됐다: " .. tostring(err));
    end);

    test("이름을 바꿀 때도 소문자로 내려간다", function()
        local db = InitWith(Profile());
        check(DebindPrivate.RenameSwitch("$state1", "$Burst"), "개명이 거절됐다");
        check(db.switches["$burst"] ~= nil, "소문자 이름으로 안 앉았다");
        check(db.switches["$Burst"] == nil, "친 대로 앉았다");
    end);

    test("대소문자만 바꾸는 개명은 아무 일도 아니다", function()
        local db = InitWith(Profile());
        check(DebindPrivate.RenameSwitch("$state1", "$STATE1"),
            "자기 자신으로 바꾸는 것이 '이미 있음'으로 거절됐다");
        check(db.switches["$state1"] ~= nil, "정의가 사라졌다");
    end);

    return T;
end
