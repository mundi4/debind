-- **호버 슬롯을 누가 채우고 누가 비우는가.** 와우 클라이언트 불필요.
--
-- 두 가지를 본다.
--
-- 하나는 커서가 멈춰 있는 동안 유닛 프레임이 가리키는 유닛이 바뀌는 경우다 (공대 프레임
-- 정렬이 그렇게 만든다). enter/leave는 커서가 안 움직이므로 안 뜨고, 그것을 알아채는 것은
-- 0.2초 상태 폴링뿐이다 (`UpdateBindings.lua`의 `_onattributechanged`). 그 폴링이 리빌드를
-- 부를지 말지가 앞의 두 테스트다. **밖에서 보이는 결과는 어느 쪽이나 같다**: 모든 키를 이미
-- 걸려 있던 값으로 다시 정하는 리빌드는 바인딩을 안 바꾼다. 그래서 물어볼 수 있는 것은
-- 돌았느냐뿐이고, `interp:rebuildCount()`가 그 답이다.
--
-- 다른 하나는 등록이 풀린 프레임이다. 래퍼를 안 떼므로 그런 프레임에서도 우리 본문이 계속
-- 돌고, 거기 들어갔을 때 무엇을 하느냐가 해제의 실체다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

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

    local GUID = "Player-1-HOVERSPEC";
    local interp;

    --- **첫 리빌드 전에 등록한다.** 인터프리터는 그때까지 기록된 것 위에 세워지고 그 뒤로는
    --- 리빌드마다 먹인다. 두 리빌드 사이에 끼워 넣은 등록은 어느 창에도 안 들어간다
    --- (`eval_spec.lua`가 같은 이유로 같은 자리에 둔다).
    local unitFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(unitFrame, "group");

    --- 등록을 풀 프레임 둘. 아래 두 테스트가 하나씩 쓴다.
    local spare = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(spare, "group");
    local dropped = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(dropped, "group");

    --- **등록이 됐는지부터 본다.** `RegisterFrame`은 조용히 거절하고 그 거절을 기억한다.
    --- 안 보면 이 아래는 애드온이 안 보고 있는 프레임을 몰면서 빈 슬롯을 읽고 그것을 보고한다.
    if (not (DebindPrivate.ccframes[unitFrame] and DebindPrivate.ccframes[spare]
            and DebindPrivate.ccframes[dropped])) then
        T.failures[#T.failures + 1] = "setup: RegisterFrame이 테스트 프레임을 안 받았다";
        return T;
    end

    local seq = 0;
    local function action(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.seq = seq;
        return t;
    end

    local function Bind(actions)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();

        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "리빌드가 거절됐다");

        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world);
        else
            interp:replay(frames.since(mark));
        end
        interp:resetState();
        return interp;
    end

    local function twoParty()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.units = {
            party1 = { id = "p1", reaction = "help", inParty = true },
            party2 = { id = "p2", reaction = "help", inParty = true },
        };
    end

    --- 커서를 프레임에 올리고 폴링을 한 번 돌려 상태를 가라앉힌다. 그 뒤의 리빌드만 세면
    --- 되도록.
    local function settleOn(unit)
        unitFrame:SetAttribute("unit", unit);
        interp:hoverEnter(unitFrame);
        interp:pollStates();
        return interp:rebuildCount();
    end

    --- 등록을 풀고, 그 해제를 제한 환경에도 먹인다. `DeinitFrame`은 `SecureHandlerExecute`로
    --- 나가므로 replay 전에는 인터프리터의 `ccframes`에 행이 그대로 있다.
    local function unregister(frame)
        local mark = frames.mark();
        DebindPrivate.UnregisterFrame(frame);
        local entries = frames.since(mark);
        interp:replay(entries);
        return entries;
    end

    ---------------------------------------------------------------------------
    -- 폴링이 리빌드를 부르는 조건
    ---------------------------------------------------------------------------

    --- **읽는 것이 없으면 리빌드도 없다.**
    ---
    --- 호버가 다시 걸 일이 되는 조건은 둘이고 폴링은 둘 다 물어야 한다. 호버 유닛을 읽는
    --- 바인딩이 있는가 (`SetUnit`이 `UnitStates`를 보고 답한다), 그리고 `frameTypes` 레코드를
    --- 다시 정해야 하는가 (`RebindOnHoverFrame`). `setup_onenter`는 처음부터 그 둘을 `or`로
    --- 묶어 물었는데 폴링만 `DirtyFlags.unitframe`을 무조건 세웠고, `DirtyFlags`에 뭐가 하나만
    --- 있어도 상태 구동 키가 전부 훑인다.
    test("호버 유닛이 바뀌어도 그것을 읽는 것이 없으면 폴링이 리빌드를 안 부른다", function()
        twoParty();
        local i = Bind({ action({ value = 585, key = "F1", combat = true }) });

        local before = settleOn("party1");
        unitFrame:SetAttribute("unit", "party2");
        i:pollStates();

        check(i:rebuildCount() == before,
            ("폴링이 리빌드를 %d번 불렀다. 이 프로필에는 호버를 읽는 것이 없다")
                :format(i:rebuildCount() - before));
    end);

    --- 반대쪽. 이게 없으면 위 테스트는 폴링이 아무것도 안 하는 상태에서도 통과한다.
    test("호버를 읽는 바인딩이 있으면 같은 변화가 리빌드를 부른다", function()
        twoParty();
        local i = Bind({
            action({ value = 585, key = "F1", conditions = { units = { hover = {} } } }),
        });

        local before = settleOn("party1");
        unitFrame:SetAttribute("unit", "party2");
        i:pollStates();

        check(i:rebuildCount() > before,
            "호버 조건이 걸린 프로필인데 폴링이 리빌드를 안 불렀다");
    end);

    ---------------------------------------------------------------------------
    -- 등록을 놓은 프레임
    ---------------------------------------------------------------------------

    --- **등록을 풀 때 래퍼를 떼지 않는다.**
    ---
    --- `SecureHandlerUnwrapScript`이 떼는 것은 맨 위 래퍼인데 (`SecureHandlers.lua`의
    --- `RemoveWrapper`가 `frame:GetScript`으로 지금 걸린 것을 잡는다), 그것이 우리 것이라는
    --- 보장이 없다. 남이 나중에 같은 스크립트를 감쌌으면 우리가 부르는 그 호출은 남의 것을
    --- 떼고 우리 것은 남긴다. 우리가 감싼 `OnClick`은 진작 안 뗐고 (`FrameRegistry.lua`의
    --- `_wrapped`), `OnEnter`/`OnLeave`만 안 그랬다.
    test("등록을 풀어도 OnEnter/OnLeave 래퍼는 안 뗀다", function()
        twoParty();
        Bind({ action({ value = 585, key = "F1", conditions = { units = { hover = {} } } }) });

        local entries = unregister(spare);

        local unwrapped;
        for i = 1, #entries do
            if (entries[i].kind == "UnwrapScript") then
                unwrapped = tostring(entries[i].name);
            end
        end
        check(unwrapped == nil,
            ("해제가 %s 래퍼를 뗐다. 그 자리에 남의 것이 있으면 남의 것이 떨어진다")
                :format(tostring(unwrapped)));
        check(DebindPrivate.ccframes[spare] == nil, "해제가 ccframes 행을 안 지웠다");
    end);

    --- **그래서 해제는 본문이 한다.** 위가 남겨둔 래퍼는 등록이 풀린 프레임에서도 계속 돈다.
    --- 거기 들어갔을 때 그냥 물러나면 안 된다. 마우스 포커스는 한 번에 하나이므로 **추적 안
    --- 하는 프레임 안에 커서가 있다는 것 자체가 우리가 마지막으로 적어둔 프레임 안에는 없다는
    --- 증거이고**, 그래서 `setup_onleave`로 넘긴다. 그것이 `OnLeave` 유실의 청소이기도 하다.
    ---
    --- 고치기 전에는 `ccframes[self]`를 가드 없이 깠으므로 이 자리가 nil 인덱싱으로 터졌다.
    test("추적을 놓은 프레임에 들어가면 호버 슬롯이 빈다", function()
        twoParty();
        local i = Bind({
            action({ value = 585, key = "F1", conditions = { units = { hover = {} } } }),
        });

        unitFrame:SetAttribute("unit", "party1");
        i:hoverEnter(unitFrame);
        check(i.env.UnitAliasMap.hover == "party1",
            ("전제가 깨졌다. 진입 후 hover=%s"):format(tostring(i.env.UnitAliasMap.hover)));

        unregister(dropped);
        check(i.env.UnitAliasMap.hover == "party1",
            "전제가 깨졌다. 다른 프레임 해제가 호버 슬롯을 비웠다");

        dropped:SetAttribute("unit", "party2");
        i:hoverEnter(dropped);

        check(i.env.States.unitframe == nil,
            "추적 안 하는 프레임에 들어갔는데 옛 프레임이 호버 슬롯에 남아 있다");
        check(i.env.UnitAliasMap.hover == nil,
            ("추적 안 하는 프레임에 들어갔는데 hover=%s"):format(
                tostring(i.env.UnitAliasMap.hover)));
    end);

    return T;
end
