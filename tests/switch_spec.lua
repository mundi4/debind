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

    local function InitWith(db)
        _G.DebounceVars = nil;
        _G.DebounceVarsPerChar = nil;
        _G.DebindVars = db;
        DebindPrivate.InitDB();
        return _G.DebindVars;
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

    -- 반대쪽. 시작값이 정해져 있으면 기억할 것이 없고, 남겨두면 그 값이 영영 안 쓰이는 채로
    -- 저장에 남는다.
    test("시작값이 정해진 스위치는 기억을 안 남긴다", function()
        InitWith(Profile());
        DebindPrivate.Switches["$state1"].resetValue = false;
        DebindPrivate.SetSwitchValue("$state1", true);
        check(DebindPrivate.Switches["$state1"].value == true, "값이 안 켜졌다");
        check(DebindPrivate.db.char.switches["$state1"] == nil, "안 쓰일 기억을 남겼다");
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
            check(reason == "SWITCH_RENAME_ERROR_INVALID", "이유가 " .. tostring(reason));
        end
        check(db.switches["$state1"] ~= nil, "거절해놓고 정의를 옮겼다");
        check(General(db)[1].conditions["$state1"] == true, "거절해놓고 조건을 옮겼다");
    end);

    test("이미 있는 이름은 거절한다", function()
        local db = InitWith(Profile());
        local ok, reason = DebindPrivate.RenameSwitch("$state1", "$state2");
        check(not ok, "두 스위치가 한 이름을 갖게 뒀다");
        check(reason == "SWITCH_RENAME_ERROR_TAKEN", "이유가 " .. tostring(reason));
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
    -- 메뉴가 내놓는 이름
    ---------------------------------------------------------------------------

    -- **개명은 붙박이 이름을 하나 비운다.** 상한이 없으면 둘을 개명한 사람에게 다섯 개를 더
    -- 만들 자리가 생긴다. 개수 제한을 푸는 것은 3c이고 여기가 아니다.
    test("메뉴가 내놓는 이름은 다섯을 안 넘는다", function()
        InitWith(Profile());
        DebindPrivate.RenameSwitch("$state1", "$burst");
        local offered = DebindPrivate.GetOfferedSwitchNames();
        check(#offered == Constants.MAX_NUM_SWITCHES,
            "내놓은 것이 " .. #offered .. "개다");
        check(offered[1] == "$burst", "만든 것이 먼저 서지 않는다: " .. tostring(offered[1]));
        local seen = {};
        for _, name in ipairs(offered) do
            check(not seen[name], name .. "이 두 번 나온다");
            seen[name] = true;
        end
        check(seen["$state2"], "이미 있는 스위치가 빠졌다");
    end);

    -- 만드는 자리는 붙박이 이름 위에만 선다. 그것이 3c까지 개수를 다섯으로 붙들어 두는 곳이다.
    test("붙박이가 아닌 이름은 만들어지지 않는다", function()
        InitWith(Profile());
        check(DebindPrivate.GetOrCreateSwitchDefinition("$newname") == nil,
            "아무 이름으로나 만들어진다 - 개수 제한이 없어졌다");
        check(DebindPrivate.GetOrCreateSwitchDefinition("$state3") ~= nil,
            "비어 있는 붙박이 이름을 못 만든다");
    end);

    return T;
end
