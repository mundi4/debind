-- **Who fills the hover slot, who empties it, and who reads it.** No WoW client needed.
--
-- Three things are asked. A unit changing under a cursor that never moves, which only the poll
-- notices, and what the poll keeps current then. What the click bakes when the body on a button
-- names `@unitframe`. And a frame we stood down from: the wrapper stays on, so our bodies keep running
-- there, and what they do on arrival is what standing down amounts to.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

    local T = { passed = 0, failures = {} };

    --- The door to the click-time decision is `EvalClickTimeKey`, and it is **DEBUG only**
    --- (`eval_spec.lua` asserts it is absent from the shipped shape). A test that has to go
    --- through it cannot run in the shipped pass. The baking below it is the same bytes in both
    --- shapes, so what is given up here is the door and nothing else.
    local skipClickTests = ctx and ctx.shipped;

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

    --- 우리가 물러날 프레임 둘. 아래 두 테스트가 하나씩 쓴다.
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

    local function Bind(actions, switches)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = switches or {},
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
        return interp:rebuildCount();
    end

    --- 행을 잃게 만들고, 그 해제를 제한 환경에도 먹인다. `DeinitFrame`은 `SecureHandlerExecute`로
    --- 나가므로 replay 전에는 인터프리터의 `ccframes`에 행이 그대로 있다.
    ---
    --- **싸움이 유일한 길이다.** 밖에서 들어오는 해제는 이제 아무것도 안 하고
    --- (`taking-every-unit-frame-with-one-blacklist.md` §1-5), 행이 사라지는 자리는
    --- `StandDown` 하나만 남았다. 싸움의 정의가 **우리가 감싸는 그 순간에 그 위에 다시 감는
    --- 것**이라 여기서도 그렇게 만든다 - 우리 리어셈블리가 스택에 있는 동안 남의 래퍼를 얹으면
    --- 그 프레임에서 물러난다.
    local function standDown(frame)
        local theirs = frames.newFrame("Frame", nil, nil, "SecureHandlerBaseTemplate");
        local fighting = false;
        hooksecurefunc("SecureHandlerWrapScript", function(wrapped, script, header)
            if (wrapped == frame and script == "OnEnter" and fighting
                    and header == DebindPrivate.BindingDriver) then
                fighting = false;
                SecureHandlerWrapScript(frame, "OnEnter", theirs, "-- theirs, on top again");
            end
        end);

        local mark = frames.mark();
        fighting = true;
        SecureHandlerWrapScript(frame, "OnEnter", theirs, "-- theirs");
        fighting = false;

        local entries = frames.since(mark);
        interp:replay(entries);
        return entries;
    end

    ---------------------------------------------------------------------------
    -- What makes the poll emit the hover block
    ---------------------------------------------------------------------------

    --- The macro body on that key. Attributes do not enumerate, so it is recovered through the
    --- button name the record carries.
    local function macrotextOn(key)
        local records = interp:recordsFor(key);
        if (not records) then
            return nil, "이 키에는 클릭 시점 레코드가 없다";
        end
        for n = 1, #records do
            local button = records[n].clickbutton;
            local text = button
                and DebindPrivate.DefaultClickFrame:GetAttribute("*macrotext-" .. button);
            if (text) then
                return text;
            end
        end
        return nil, "레코드 중 매크로 본문을 가진 것이 없다";
    end

    ---------------------------------------------------------------------------
    -- Holding a button body back to the click (item 2)
    ---------------------------------------------------------------------------

    if (not skipClickTests) then

    --- **A body that goes on a button is baked by nobody until the click.**
    ---
    --- It sits in `DeferredMacroTexts`, so sweeping frames bakes nothing: the click that picks
    --- that button is what composes it.
    test("@unitframe 버튼 본문은 커서가 아니라 클릭이 굽는다", function()
        twoParty();
        local i = Bind({
            action({ type = Constants.MACROTEXT, key = "F1", value = "/cast [@unitframe] Renew" }),
        });

        settleOn("party1");
        local text = macrotextOn("F1");
        check(text == "/cast [@unitframe] Renew",
            ("폴링이 본문을 구웠다 (%q). 이건 클릭까지 미룬 것이다"):format(tostring(text)));

        i:evalKey("F1");

        text = macrotextOn("F1");
        check(text == "/cast [@party1]Renew",
            ("클릭이 본문을 안 구웠거나 잘못 구웠다 (%q)"):format(tostring(text)));
    end);

    --- **키보드 키에 걸린 호버 조건.** 마우스 버튼 쪽은 위아래로 여러 케이스가 들고 있는데,
    --- 키가 그 조건을 들고 프레임 위에서 눌렸을 때는 어느 케이스도 안 묻고 있었다.
    ---
    --- 두 갈래가 한 케이스 안에 있다. 프레임 위에서는 승자가 나와야 하고, 프레임을 벗어나면
    --- 그 키는 아무것도 안 내야 한다. 앞쪽만 물으면 조건을 아예 안 보는 구현도 통과한다.
    test("호버 조건이 붙은 키는 프레임 위에서만 승자를 낸다", function()
        twoParty();
        local i = Bind({
            action({ value = 585, key = "F1", unit = "unitframe",
                conditions = { units = { unitframe = { reaction = Constants.REACTION_ALL } } } }),
        });

        settleOn("party1");
        local won = i:evalKey("F1");
        check(won ~= nil, "프레임 위인데 키가 아무 승자도 못 냈다");

        interp:hoverLeave(unitFrame);
        check(i:evalKey("F1") == nil, "프레임을 벗어났는데 키가 여전히 승자를 낸다");
    end);

    --- **What the click bakes is the unit it judged, not the cache.**
    ---
    --- The wrapper reads the unit off the frame again to judge the conditions, and aims at what
    --- it read. Take only the body from `UnitAliasMap["unitframe"]` and **the unit that was judged
    --- and the unit the body aims at come apart** -- on a spell whose effect forks on friend or
    --- foe, that is not "nothing goes out" but "something else does".
    ---
    --- Not running the poll is how this test asks. The alias then stays on party1 while the frame
    --- already points at party2, so which of the two the body read is visible in the answer.
    test("클릭이 구운 본문은 그 클릭이 판정한 유닛을 겨눈다", function()
        twoParty();
        local i = Bind({
            action({ type = Constants.MACROTEXT, key = "F1", value = "/cast [@unitframe] Renew" }),
        });

        settleOn("party1");
        unitFrame:SetAttribute("unit", "party2");
        check(i.env.UnitAliasMap.unitframe == "party1",
            "전제가 깨졌다 - 별칭이 벌써 따라갔다. 폴링이 돈 것이다");

        i:evalKey("F1");

        local text = macrotextOn("F1");
        check(text == "/cast [@party2]Renew",
            ("본문이 캐시된 별칭을 읽었다 (%q). 클릭은 party2를 판정했다"):format(tostring(text)));
    end);

    end

    --- **A @custom1 action takes the hovered unit off the frame at the call** (`GetUnitFrameUnit`).
    --- The frame's unit changes under a still cursor and no beat runs in between, so a slot that
    --- read the unit enter left behind would fill custom1 with somebody who is no longer there.
    test("@custom1 지정 액션은 커서 밑 프레임의 지금 유닛을 받는다", function()
        twoParty();
        local i = Bind({ action({ type = Constants.SETCUSTOM, value = 1, key = "F1" }) });

        settleOn("party1");
        check(i.driverHandle:RunAttribute("GetUnitFrameUnit") == "party1",
            "전제가 깨졌다 - enter가 호버 슬롯을 안 채웠다");

        unitFrame:SetAttribute("unit", "party2");

        local hovered = i.driverHandle:RunAttribute("GetUnitFrameUnit");
        check(hovered == "party2",
            ("커서가 멈춘 채 프레임의 유닛이 바뀌었는데 호버 슬롯이 %s다")
                :format(hovered and ("%q"):format(hovered) or "비었다"));
    end);

    ---------------------------------------------------------------------------
    -- 우리가 물러난 프레임
    ---------------------------------------------------------------------------

    --- **프레임에서 물러날 때 래퍼를 떼지 않는다.**
    ---
    --- `SecureHandlerUnwrapScript`이 떼는 것은 맨 위 래퍼인데 (`SecureHandlers.lua`의
    --- `RemoveWrapper`가 `frame:GetScript`으로 지금 걸린 것을 잡는다), 그것이 우리 것이라는
    --- 보장이 없다. 남이 나중에 같은 스크립트를 감쌌으면 우리가 부르는 그 호출은 남의 것을
    --- 떼고 우리 것은 남긴다. 우리가 감싼 `OnClick`은 진작 안 뗐고 (`FrameRegistry.lua`의
    --- `_wrapped`), `OnEnter`/`OnLeave`만 안 그랬다.
    ---
    --- 물러나는 쪽이 부르는 unwrap은 리어셈블리 자신의 것이라 여기서 안 센다 - 세는 것은
    --- 행이 사라진 **뒤에** 떨어진 래퍼다.
    test("프레임에서 물러나도 OnEnter/OnLeave 래퍼는 안 뗀다", function()
        twoParty();
        Bind({ action({ value = 585, key = "F1", conditions = { units = { unitframe = {} } } }) });

        local entries = standDown(spare);
        check(DebindPrivate.ccframes[spare] == false, "싸움에서 물러났는데 ccframes 행이 남았다");

        local unwrappedAfter;
        local rowGone = false;
        for i = 1, #entries do
            local entry = entries[i];
            if (entry.kind == "Execute" and strfind(tostring(entry.body), "DeinitFrame", 1, true)) then
                rowGone = true;
            elseif (rowGone and entry.kind == "UnwrapScript") then
                unwrappedAfter = tostring(entry.name);
            end
        end
        check(rowGone, "전제가 깨졌다 - 물러나면서 DeinitFrame을 안 냈다");
        check(unwrappedAfter == nil,
            ("물러나면서 %s 래퍼를 뗐다. 그 자리에 남의 것이 있으면 남의 것이 떨어진다")
                :format(tostring(unwrappedAfter)));
    end);

    --- **그래서 청소는 본문이 한다.** 위가 남겨둔 래퍼는 우리가 물러난 프레임에서도 계속 돈다.
    --- 거기 들어갔을 때 그냥 물러나면 안 된다. 마우스 포커스는 한 번에 하나이므로 **추적 안
    --- 하는 프레임 안에 커서가 있다는 것 자체가 우리가 마지막으로 적어둔 프레임 안에는 없다는
    --- 증거이고**, 그래서 `setup_onleave`로 넘긴다. 그것이 `OnLeave` 유실의 청소이기도 하다.
    ---
    --- 고치기 전에는 `ccframes[self]`를 가드 없이 깠으므로 이 자리가 nil 인덱싱으로 터졌다.
    test("추적을 놓은 프레임에 들어가면 호버 슬롯이 빈다", function()
        twoParty();
        local i = Bind({
            action({ value = 585, key = "F1", conditions = { units = { unitframe = {} } } }),
        });

        unitFrame:SetAttribute("unit", "party1");
        i:hoverEnter(unitFrame);
        check(i.env.UnitAliasMap.unitframe == "party1",
            ("전제가 깨졌다. 진입 후 hover=%s"):format(tostring(i.env.UnitAliasMap.unitframe)));

        standDown(dropped);
        check(i.env.UnitAliasMap.unitframe == "party1",
            "전제가 깨졌다. 다른 프레임 해제가 호버 슬롯을 비웠다");

        dropped:SetAttribute("unit", "party2");
        i:hoverEnter(dropped);

        check(i.env.States.unitframe == nil,
            "추적 안 하는 프레임에 들어갔는데 옛 프레임이 호버 슬롯에 남아 있다");
        check(i.env.UnitAliasMap.unitframe == nil,
            ("추적 안 하는 프레임에 들어갔는데 hover=%s"):format(
                tostring(i.env.UnitAliasMap.unitframe)));
    end);

    ---------------------------------------------------------------------------
    -- The two ladders that turn a hovered unit into a reaction
    ---------------------------------------------------------------------------

    --- **One snippet answers this now**: `setup_onenter` in `SecureBindings.lua`, when the cursor
    --- arrives. The rebuild used to emit a second ladder for the poll, and the two parted once --
    --- the poll's last branch said `REACTION_NONE`, a bit outside `REACTION_ALL` (`Solver.lua`)
    --- that no mask a reader can build ever matches, so every hover binding carrying a reaction
    --- restriction was right the instant the cursor arrived and went dead on the first poll tick,
    --- on exactly the targets that fall to the last branch: friendly NPCs, corpses, totems.
    ---
    --- **The last branch is why every reaction is asked about here**, rather than only the two a
    --- reader usually names.
    local function reactionOnArrival(unit)
        Bind({
            action({ value = 585, key = "F1", unit = "unitframe",
                conditions = { units = { unitframe = { reaction = Constants.REACTION_ALL } } } }),
        });
        unitFrame:SetAttribute("unit", unit);
        interp:hoverEnter(unitFrame);
        return interp.env.States.unitframe and interp.env.States.unitframe.reaction;
    end

    local REACTIONS = {
        { name = "help", world = "help", expected = Constants.REACTION_HELP },
        { name = "harm", world = "harm", expected = Constants.REACTION_HARM },
        -- Neither helpable nor attackable: the branch the divergence killed.
        { name = "other", world = "neutral", expected = Constants.REACTION_OTHER },
    };

    test("arrival reads the unit's reaction, every branch of the ladder", function()
        for i = 1, #REACTIONS do
            local case = REACTIONS[i];
            shim.world.spells[585] = { name = "Renew" };
            shim.world.units = {
                party1 = { id = "p1", reaction = case.world, inParty = true },
            };

            local onArrival = reactionOnArrival("party1");
            check(onArrival == case.expected,
                ("arrival read %s for a %s unit, not %s"):format(
                    tostring(onArrival), case.name, tostring(case.expected)));
        end
    end);

    ---------------------------------------------------------------------------
    -- 등록되지 않은 개체창 위의 custom target
    ---------------------------------------------------------------------------

    --- **호버 슬롯은 넘겨받은 프레임만 채운다.** 그 밖의 개체창 위에서는 비어 있고, 그 자리에서
    --- `mouseover`로 떨어지는 것이 등록 없이 남는 유일한 길이다. `hover`를 다시 쓰기 전에 `none`을
    --- 거치는 것은 `_onattributechanged`가 값이 실제로 바뀔 때만 돌기 때문이다.
    local function customFromHover(units)
        Bind({ action({ value = 585, key = "F1", unit = "custom1" }) });
        shim.world.units = units;
        interp:clearHoverSlot();
        interp.unitWatchHandle:SetAttribute("custom1", "none");
        return interp:setCustomTarget("custom1", "unitframe");
    end

    test("호버 슬롯이 비어 있으면 mouseover가 서 있는 토큰으로 지정된다", function()
        local unit = customFromHover({
            player = { id = "me" },
            mouseover = { id = "me" },
        });
        check(unit == "player", "custom1: " .. tostring(unit));
    end);

    test("mouseover도 없으면 아무것도 지정되지 않는다", function()
        local unit = customFromHover({ player = { id = "me" } });
        check(unit == nil, "custom1: " .. tostring(unit));
    end);

    return T;
end
