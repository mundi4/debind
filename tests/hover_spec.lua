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

    --- **Nothing reads it, so nothing is rebuilt.**
    ---
    --- Two things make a hover change worth re-deciding a key over, and the poll has to ask both:
    --- is there a binding that reads the hovered unit (`SetUnit` answers that off `UnitStates`),
    --- and is there a `frameTypes` record to decide again (`RebindOnHoverFrame`). `setup_onenter`
    --- asked the two as one `or` from the start; only the poll set `DirtyFlags.unitframe`
    --- unconditionally, and one entry in `DirtyFlags` walks every state-driven key.
    ---
    --- **This profile no longer emits the hover block at all** (2026-08-22). Nothing names hover,
    --- so `_unitsSeen.hover` is false and the poll never looks at the frame. What this test holds
    --- is one outcome with two layers behind it now; the inner layer -- a profile that names hover
    --- but has nothing to re-decide -- is what the macro text tests below stand on.
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

    --- The other side. Without it the test above also passes on a poll that does nothing at all.
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

    --- **A `@hover` switch expression needs the poll without carrying a single condition.**
    ---
    --- The `@hover` in it is substituted with `UnitAliasMap["hover"]`, and while the cursor sits
    --- still the only thing that keeps that alias current is the poll hover block. There is no key
    --- to re-decide: `UnitStates` holds no hover row and `RebindOnHoverFrame` is false, so
    --- `SetUnit` answers false. The block still has to go out.
    ---
    --- **That this is a switch expression and not a button body is the whole test.** A body on a
    --- button is held back to the click (item 2), and the click reads the unit off the frame
    --- again -- it never looks at this alias. What is left for the poll to keep current in
    --- `MacroTextsMap` is the expressions.
    test("@hover 스위치 계산식은 폴링이 별칭을 따라가 준다", function()
        twoParty();
        local i = Bind({
            action({ value = 585, key = "F1", conditions = { ["$state1"] = true } }),
        }, {
            ["$state1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[@hover]" },
        });

        settleOn("party1");
        check(i.env.SwitchExpressions["$state1"] == "[@party1]",
            ("전제가 깨졌다 - 첫 계산식이 %q다")
                :format(tostring(i.env.SwitchExpressions["$state1"])));

        unitFrame:SetAttribute("unit", "party2");
        i:pollStates();

        check(i.env.SwitchExpressions["$state1"] == "[@party2]",
            ("커서가 멈춘 채 프레임의 유닛이 바뀌었는데 계산식이 %q에 머물렀다")
                :format(tostring(i.env.SwitchExpressions["$state1"])));
    end);

    ---------------------------------------------------------------------------
    -- Holding a button body back to the click (item 2)
    ---------------------------------------------------------------------------

    if (not skipClickTests) then

    --- **A body that goes on a button is baked by nobody when a state moves.**
    ---
    --- It is not in `MacroTextsMap` but in `DeferredMacroTexts`, so it drops out of the list
    --- `SetUnit` walks while the cursor sweeps frames. It is baked by the click that picks that
    --- button instead.
    test("@hover 버튼 본문은 폴링이 아니라 클릭이 굽는다", function()
        twoParty();
        local i = Bind({
            action({ type = Constants.MACROTEXT, key = "F1", value = "/cast [@hover] Renew" }),
        });

        check(i.env.MacroTextsMap.hover == nil,
            "버튼 본문이 여전히 hover의 의존자로 남아 있다");

        settleOn("party1");
        local text = macrotextOn("F1");
        check(text == "/cast [@hover] Renew",
            ("폴링이 본문을 구웠다 (%q). 이건 클릭까지 미룬 것이다"):format(tostring(text)));

        i:evalKey("F1");

        text = macrotextOn("F1");
        check(text == "/cast [@party1]Renew",
            ("클릭이 본문을 안 구웠거나 잘못 구웠다 (%q)"):format(tostring(text)));
    end);

    --- **What the click bakes is the unit it judged, not the cache.**
    ---
    --- The wrapper reads the unit off the frame again to judge the conditions, and aims at what
    --- it read. Take only the body from `UnitAliasMap["hover"]` and **the unit that was judged
    --- and the unit the body aims at come apart** -- on a spell whose effect forks on friend or
    --- foe, that is not "nothing goes out" but "something else does".
    ---
    --- Not running the poll is how this test asks. The alias then stays on party1 while the frame
    --- already points at party2, so which of the two the body read is visible in the answer.
    test("클릭이 구운 본문은 그 클릭이 판정한 유닛을 겨눈다", function()
        twoParty();
        local i = Bind({
            action({ type = Constants.MACROTEXT, key = "F1", value = "/cast [@hover] Renew" }),
        });

        settleOn("party1");
        unitFrame:SetAttribute("unit", "party2");
        check(i.env.UnitAliasMap.hover == "party1",
            "전제가 깨졌다 - 별칭이 벌써 따라갔다. 폴링이 돈 것이다");

        i:evalKey("F1");

        local text = macrotextOn("F1");
        check(text == "/cast [@party2]Renew",
            ("본문이 캐시된 별칭을 읽었다 (%q). 클릭은 party2를 판정했다"):format(tostring(text)));
    end);

    end

    --- **A @custom1 action names no unit anywhere.**
    ---
    --- Which slot to fill is `value`, and where the unit comes from is baked by `DescribeBinding`
    --- as the literal `"hover"` on `UnitWatch`. So neither this action's conditions nor its target
    --- says hover, and the only way `_unitsSeen` hears about it from the record is
    --- `record.readsHoverUnit`. Miss it and the poll emits no hover block for this profile -- and
    --- when the frame's unit changes under a still cursor, the old unit lands in custom1.
    test("@custom1 지정 액션만 있어도 폴링이 호버 유닛을 따라간다", function()
        twoParty();
        local i = Bind({ action({ type = Constants.SETCUSTOM, value = 1, key = "F1" }) });

        settleOn("party1");
        check(i.driverHandle:RunAttribute("GetHoveredUnit") == "party1",
            "전제가 깨졌다 - enter가 호버 슬롯을 안 채웠다");

        unitFrame:SetAttribute("unit", "party2");
        i:pollStates();

        local hovered = i.driverHandle:RunAttribute("GetHoveredUnit");
        check(hovered == "party2",
            ("커서가 멈춘 채 프레임의 유닛이 바뀌었는데 호버 슬롯이 %s다")
                :format(hovered and ("%q"):format(hovered) or "비었다"));
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

    ---------------------------------------------------------------------------
    -- How much a wake measures
    ---------------------------------------------------------------------------

    --- A profile that measures one of each kind: the hover row, so a crossing wakes the pass at
    --- all; a base axis, which has an event of its own; and another unit's row, which has none.
    local function BindOneOfEach()
        twoParty();
        shim.world.units.target = { id = "t", reaction = "harm" };
        Bind({
            action({ key = "F1", unit = "hover",
                conditions = { units = { hover = { reaction = Constants.REACTION_HELP } } } }),
            action({ key = "F2", conditions = { combat = true } }),
            action({ key = "F3", conditions = { units = { target = { reaction = Constants.REACTION_HARM } } } }),
        });
        unitFrame:SetAttribute("unit", "party1");
        interp:hoverEnter(unitFrame);
        interp:pollStates();
        return interp;
    end

    --- Moves the cursor to the other frame, which is a `"unitframe"` wake and nothing else.
    local function crossTo(unit)
        unitFrame:SetAttribute("unit", unit);
        interp:hoverEnter(unitFrame);
    end

    -- **A crossing does not re-measure an axis that can announce itself.** `combat` has
    -- `PLAYER_REGEN_DISABLED` on the manager, and an event puts the manager's timer to 0, so the
    -- pass that picks it up is already coming. Spending the client calls on every frame boundary
    -- the cursor crosses buys the same answer sooner by less than the frame the event costs.
    --
    -- **The second half is what makes the first mean anything.** Without it a gate that was simply
    -- never opening would pass.
    test("a hover crossing leaves the axes that have an event to the poll", function()
        local i = BindOneOfEach();
        check(i.env.States.combat == false, "전제가 깨졌다. 시작부터 combat이 참이다");

        i.state.combat = true;
        crossTo("party2");
        check(i.env.States.combat == false,
            "a hover crossing re-measured combat, which has an event of its own");

        i:pollStates();
        check(i.env.States.combat == true, "the poll did not pick combat up either");
    end);

    -- **A unit row is the other kind and a crossing does take it.** Nothing fires when a target
    -- stops existing, so the only way anyone finds out is a pass that asks -- and a wake we were
    -- handed for free is one of those.
    test("a hover crossing still measures the rows nothing announces", function()
        local i = BindOneOfEach();
        check(i.env.UnitStates.target.exists == true,
            "전제가 깨졌다. 대상이 처음부터 없다");

        shim.world.units.target = nil;
        crossTo("party2");
        check(i.env.UnitStates.target.exists == false,
            "a hover crossing skipped the unit rows, which nothing else would have caught");
    end);

    -- **A rebuild's own pass measures everything, and it is not the value that says so.** It wakes
    -- with a number rather than the poll's `true`, and it wakes onto a `States` the prologue has
    -- just wiped, so the term that opens the gate for it is `DirtyFlags.forceAll`. Drop that term
    -- and every base axis stays nil until the next poll, with the first 0.2s of every rebuild
    -- deciding keys on nothing.
    test("a rebuild's own pass measures every axis", function()
        BindOneOfEach();
        interp.state.combat = true;

        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "리빌드가 거절됐다");
        interp:replay(frames.since(mark));

        check(interp.env.States.combat == true,
            "the rebuild's pass left combat at " .. tostring(interp.env.States.combat));
    end);

    ---------------------------------------------------------------------------
    -- Which keys a pass walks
    ---------------------------------------------------------------------------

    -- **A key on two axes that both went dirty in one pass is decided once.** The pass reaches it
    -- through each flag's list, and the generation number is what makes the second arrival free.
    --
    -- **It cannot be asked in a value**, which is the whole reason `WorkCount` is here: deciding a
    -- key twice lands on the same answer, because `bindings.bound` turns the second one into a
    -- no-op. A case that read the key back would pass with the guard taken out.
    test("a key on two dirty axes is decided once", function()
        twoParty();
        Bind({
            action({ key = "F1", value = 585, conditions = { combat = true, stealth = true } }),
        });

        -- **Settled to a known world first.** `Bind` resets the interpreter's state but not
        -- `States`, which the rebuild filled from whatever the case before this one left. An axis
        -- that was already true does not go dirty when this case sets it true, and then the pass
        -- has one flag in hand rather than two and proves nothing.
        interp.state.combat = false;
        interp.state.stealth = false;
        interp:pollStates();
        check(interp.env.States.combat == false and interp.env.States.stealth == false,
            "전제가 깨졌다. 시작부터 축이 서 있다");

        -- Both at once, so the pass has two flags in hand and one key filed under each.
        interp.state.combat = true;
        interp.state.stealth = true;
        interp:pollStates();

        check(interp.env.DirtyKeys.combat and #interp.env.DirtyKeys.combat == 1,
            "전제가 깨졌다. combat 목록에 이 키가 없다");
        check(interp.env.DirtyKeys.stealth and #interp.env.DirtyKeys.stealth == 1,
            "전제가 깨졌다. stealth 목록에 이 키가 없다");

        -- **`rawget`, because the environment raises on a name it does not carry.** In the shipped
        -- shape it does not carry this one, and that absence is the other half of the case: a
        -- counter that only a test reads has no business in a real user's snippet.
        local walked = rawget(interp.env, "WorkCount");
        if (ctx and ctx.shipped) then
            check(walked == nil, "the DEBUG-only walk counter is in the shipped snippet");
            return;
        end

        check(walked == 1, "one key on two dirty axes was walked " .. tostring(walked) .. " times");
    end);

    --- Rebuilds the profile that is already loaded with the throttle set to `value`, and puts the
    --- option back so nothing after this reads it.
    local function RebuildWithThrottle(value)
        DebindPrivate.Options.stateDriverUpdateThrottle = value;
        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "리빌드가 거절됐다");
        interp:replay(frames.since(mark));
        DebindPrivate.Options.stateDriverUpdateThrottle = nil;
    end

    -- **At zero the beat is every frame, so a wake of ours is always second to it.** There is
    -- nothing left for the pass to do and the handler turns round before it puts the attribute
    -- back. Asked of the unit row, because that is the half a crossing does measure otherwise --
    -- a base axis would read the same whether the pass was dropped or merely gated.
    --
    -- **The last half is what keeps this from passing on a dead profile.** A crossing that changed
    -- nothing and a beat that measures nothing look alike from one read.
    test("a crossing turns straight round while the beat comes every frame", function()
        local i = BindOneOfEach();
        RebuildWithThrottle(0);

        local before = i:rebuildCount();
        shim.world.units.target = nil;
        crossTo("party2");

        check(i:rebuildCount() == before,
            "a crossing ran the pass while the beat was already coming every frame");
        check(i.env.UnitStates.target.exists == true,
            "the pass ran far enough to measure a unit row");

        i:pollStates();
        check(i.env.UnitStates.target.exists == false,
            "the beat did not measure it either, so the check above proves nothing");
    end);

    -- The other side of the same switch: at the throttle the reader gets by default, a crossing is
    -- the only thing that carries the change until the next tick, and it does.
    test("a crossing still carries the change at the ordinary throttle", function()
        local i = BindOneOfEach();
        RebuildWithThrottle(Constants.STATE_DRIVER_UPDATETIME_DEFAULT);

        shim.world.units.target = nil;
        crossTo("party2");
        check(i.env.UnitStates.target.exists == false,
            "a crossing was dropped at a throttle that is not zero");
    end);

    return T;
end
