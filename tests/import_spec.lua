-- Turning a received payload back into actions. `DebindShare/Import.lua`.
--
-- **This is the half of the round trip that can be wrong without anyone noticing.** The export side
-- is checked against the format; here the output is an action that goes straight into someone's
-- profile, and a field read back wrongly produces an action that looks fine in a list and does
-- something else when pressed.
--
-- Two of those are the whole reason the format is shaped the way it is:
--
--   * a `SETSTATE` value is `mode | index`, and the wire carries a **name**. Rebuild it against the
--     wrong index and the key sets some other state - silently, because an index always resolves.
--   * a `MACRO` carries a name, and a name is the one broken reference red text cannot see. The
--     snapshot is what turns "your macro of the same name, silently" into a fallback.
--
-- Everything built here also has to arrive quarantined. An action that landed without `imported`
-- is bound the moment it lands, which is the one thing this whole path promises not to do.

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
    -- The macro store, stubbed. Same shape as the real API, which is what makes
    -- the three-way match actually run.
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

    local function Payload(groups)
        return { v = 1, class = CLASS, groups = groups };
    end

    local GENERAL = { scope = "general" };

    --- The layer a group's actions lived in, written onto each of them.
    ---
    --- **The wire carries `layer` on the action, not on the group** (`Export.lua`): a group is a
    --- key, and a key crosses layers. Most cases below are not about that, so they hand one
    --- descriptor to this and it goes on every action - the same table the sender shares between
    --- them. The case that *is* about the crossing writes the descriptors itself.
    local function InLayer(descriptor, actions)
        for i = 1, #actions do
            actions[i].layer = descriptor;
        end
        return actions;
    end

    --- Plans one group and hands back the single action in it.
    local function PlanOne(group, batchID)
        local placements = DebindShare.PlanImport(Payload({ group }), batchID or 1);
        check(#placements == 1, "액션 수 " .. #placements);
        return placements[1].action, placements[1];
    end

    ResetProfile();

    ---------------------------------------------------------------------------
    -- Quarantine and placement
    ---------------------------------------------------------------------------

    test("들어오는 것은 전부 배지를 달고 온다", function()
        local placements = DebindShare.PlanImport(Payload({
            { id = 4, key = "F", actions = InLayer(GENERAL, {
                { type = Constants.SPELL, value = 1 },
                { type = Constants.SPELL, value = 2 } }) },
        }), 9);

        check(#placements == 2, "액션 수");
        local groupID = placements[1].action.importGroup;
        check(groupID ~= nil, "그룹 번호가 없다");
        for _, placement in ipairs(placements) do
            check(placement.action.imported == 9,
                "배지가 없다 - 이 액션은 들어가는 순간 키에 걸린다");
            -- **Not the payload's `id`.** One group's members share a number; which number it is
            -- belongs to the receiving profile, not to the sender (see the test below).
            check(placement.action.importGroup == groupID, "한 그룹인데 번호가 갈렸다");
        end
    end);

    -- **The number the reader sees has to be unique in their profile, not in the batch.** The
    -- payload's `id` is only unique inside its own string, so two strings waiting at once both
    -- carry a group 1 - and the overview would head two different sets with the same words.
    --
    -- Numbers are taken the way `GetNextSeq` takes them: the highest one in the profile plus one,
    -- with nothing stored. Gaps are fine, and reuse after everything is accepted is fine too -
    -- nothing refers to an old number.
    test("그룹 번호는 프로필 안에서 안 겹친다", function()
        ResetProfile();

        local first = DebindShare.PlanImport(Payload({
            { id = 1, actions = InLayer(GENERAL, { { type = Constants.SPELL, value = 1 } }) },
            { id = 2, actions = InLayer(GENERAL, { { type = Constants.SPELL, value = 2 } }) },
        }), 1);
        DebindPrivate.PlaceImportedActions(first);

        -- A second string, whose own group ids start over at 1.
        local second = DebindShare.PlanImport(Payload({
            { id = 1, actions = InLayer(GENERAL, { { type = Constants.SPELL, value = 3 } }) },
        }), 2);

        local taken = {};
        for _, placement in ipairs(first) do
            taken[placement.action.importGroup] = true;
        end
        check(not taken[second[1].action.importGroup],
            "두 번째 배치가 첫 배치의 그룹 번호를 다시 썼다: " .. tostring(second[1].action.importGroup));
    end);

    -- **The reused number would be one this session cannot see.** `LayerArray` is the view of the
    -- eleven layers this character has; another class's layers are stored all the same and are not
    -- in it. Counting the view would reissue a number that is alive over there, and the two would
    -- meet - both headed `키를 모름 #3` - the day the reader logs that class.
    test("안 보이는 레이어의 그룹 번호도 세어 넣는다", function()
        ResetProfile();

        local mage = DebindShare.PlanImport(Payload({
            { id = 1, actions = InLayer({ scope = "class", class = "MAGE", spec = 2 },
                { { type = Constants.SPELL, value = 1 } }) },
        }), 1);
        DebindPrivate.PlaceImportedActions(mage);

        -- The premise: it really did land somewhere the layer view does not reach.
        local seen = 0;
        for layerID = 1, 11 do
            local layer = DebindPrivate.GetProfileLayer(layerID);
            if (layer) then
                for _, action in layer:Enumerate() do
                    if (action.importGroup) then
                        seen = seen + 1;
                    end
                end
            end
        end
        check(seen == 0, "전제가 틀렸다 - 이 캐릭터의 레이어에서 " .. seen .. "개가 보인다");

        local next2 = DebindShare.PlanImport(Payload({
            { id = 1, actions = InLayer(GENERAL, { { type = Constants.SPELL, value = 2 } }) },
        }), 2);
        check(next2[1].action.importGroup ~= mage[1].action.importGroup,
            "안 보이는 번호를 재사용했다: " .. tostring(next2[1].action.importGroup));
    end);

    -- The key lives on the group, because one group is one key and that is what has to stay
    -- together. Reading it off the action would find nothing at all.
    test("키는 그룹에서 온다", function()
        local action = PlanOne({ id = 1, key = "SHIFT-G", actions = InLayer(GENERAL,
            { { type = Constants.SPELL, value = 774 } }) });
        check(action.key == "SHIFT-G", "키 " .. tostring(action.key));
    end);

    test("키 없이 온 그룹은 키 없이 들어간다", function()
        local action = PlanOne({ id = 1, actions = InLayer(GENERAL,
            { { type = Constants.SPELL, value = 774 } }) });
        check(action.key == nil, "없던 키가 생겼다");
    end);

    ---------------------------------------------------------------------------
    -- The order inside a group
    ---------------------------------------------------------------------------

    -- **Which of a key's actions goes first is design, not decoration**, and a string sent without
    -- keys carries nothing else that says so. `seq` cannot travel under its own name -- the
    -- receiving layer has already handed out numbers of its own -- so the wire says `order` and the
    -- action carries `importOrder` until the group is given a key.
    test("그룹 안의 순서가 보존된다", function()
        local placements = DebindShare.PlanImport(Payload({
            { id = 1, actions = InLayer(GENERAL, {
                { type = Constants.SPELL, value = 11, order = 1 },
                { type = Constants.SPELL, value = 22, order = 2 },
                { type = Constants.SPELL, value = 33, order = 3 } }) },
        }), 1);

        check(#placements == 3, "액션 수 " .. #placements);
        for i, placement in ipairs(placements) do
            check(placement.action.importOrder == i,
                i .. "번째 액션의 importOrder가 " .. tostring(placement.action.importOrder));
        end
    end);

    -- `BuildAction` copies the wire table with `pairs` and skips only what it names, so a field
    -- left unnamed rides straight into the profile. `order` and `layer` are the format's words, not
    -- the profile's; leaving them on would put a shape in the layer that only `CleanUpDB` would
    -- later notice - and `layer` is worse than a stray field, because it is one table the sender
    -- shares between actions.
    test("선의 order와 layer는 액션에 안 남는다", function()
        local action = PlanOne({ id = 1, actions = InLayer(GENERAL,
            { { type = Constants.SPELL, value = 774, order = 1 } }) });
        check(action.order == nil, "order가 액션에 남았다: " .. tostring(action.order));
        check(action.layer == nil, "layer가 액션에 남았다");
    end);

    -- **The receiving end of "leave the keys out".** Quarantine says nothing changes until the
    -- reader accepts; this says their keys are not touched even then. Wanting somebody's actions
    -- without their keybinds is ordinary, and until now it could only be had by asking the sender
    -- to tick the box.
    --
    -- **The grouping has to survive it.** Dropping the key while keeping the set is the whole point
    -- - a key split across conditional actions still has to arrive as one thing to give a key to.
    test("키를 빼고 가져오면 키만 없고 그룹은 남는다", function()
        local placements = DebindShare.PlanImport(Payload({
            { id = 1, key = "F", actions = InLayer(GENERAL, {
                { type = Constants.SPELL, value = 1, order = 1 },
                { type = Constants.SPELL, value = 2, order = 2 } }) },
        }), 1, { stripKeys = true });

        check(#placements == 2, "액션 수 " .. #placements);
        local group = placements[1].action.importGroup;
        check(group ~= nil, "그룹이 사라졌다 - 키를 뺐다고 한 벌이 흩어지면 안 된다");
        for i, placement in ipairs(placements) do
            check(placement.action.key == nil,
                "키가 남았다: " .. tostring(placement.action.key));
            check(placement.action.importGroup == group, "한 그룹인데 번호가 갈렸다");
            check(placement.action.importOrder == i, "순서가 사라졌다");
        end
    end);

    -- **A sender exports whole layers, so what they built and never bound goes out too.** Given a
    -- group number, one of those arrives on the far side headed as a set whose key was withheld,
    -- which says it was part of the design and asks what key it deserves. It was not, and the
    -- reader ends up working out whether they are supposed to use something the sender does not.
    --
    -- Only the export can tell the two apart: with keys stripped, a one-action key and an action
    -- that never had one are the same table on the wire.
    test("키가 없던 액션은 그룹 없이 들어온다", function()
        local action = PlanOne({ actions = InLayer(GENERAL,
            { { type = Constants.SPELL, value = 774 } }) });
        check(action.importGroup == nil,
            "묶인 적 없는 액션에 그룹이 붙었다: " .. tostring(action.importGroup));
        check(action.imported ~= nil, "배지는 그대로 있어야 한다");
    end);

    ---------------------------------------------------------------------------
    -- Where each action lands
    ---------------------------------------------------------------------------

    -- **한 키는 레이어를 넘어도 한 벌이다.** The sender groups by key and writes the layer on each
    -- action (`Export.lua`), so one group routinely carries two destinations. Splitting it here
    -- would undo the one thing a keyless string still says: with the keys stripped, the reader
    -- would be handed two headings for what was one key and would give them two keys - and then
    -- both fire.
    test("한 키가 레이어 여럿에 걸쳐도 그룹 하나로 들어온다", function()
        ResetProfile();

        local placements = DebindShare.PlanImport(Payload({
            { id = 1, key = "F", actions = {
                { type = Constants.SPELL, value = 1, order = 1,
                  layer = { scope = "general" } },
                { type = Constants.SPELL, value = 2, order = 2,
                  layer = { scope = "class", class = CLASS, spec = 0 } },
            } },
        }), 1);

        check(#placements == 2, "액션 수 " .. #placements);
        check(placements[1].action.importGroup ~= nil, "그룹 번호가 없다");
        check(placements[1].action.importGroup == placements[2].action.importGroup,
            "레이어가 갈렸다고 그룹까지 갈렸다");

        check(placements[1].scope == "general",
            "1번이 일반이 아니다: " .. tostring(placements[1].scope));
        check(placements[2].scope == "class" and placements[2].class == CLASS
            and placements[2].spec == 0, "2번이 직업 공용 자리가 아니다");
    end);

    -- **A layer is a coordinate, not something to translate.** Both profiles use the same one, so
    -- another class's layer keeps its class *and* its spec: a mage's spec 2 is a mage's spec 2 on
    -- every account. `workbench_spec` measures the addressing in detail; here it just has to be
    -- what the placement actually uses.
    test("목적지는 보낸 쪽 좌표 그대로다", function()
        local _, general = PlanOne({ id = 1, actions = InLayer(GENERAL,
            { { type = Constants.SPELL, value = 1 } }) });
        check(general.scope == "general", "일반이 아니다: " .. tostring(general.scope));

        local _, foreign = PlanOne({ id = 2, actions = InLayer(
            { scope = "class", class = "MAGE", spec = 2 },
            { { type = Constants.SPELL, value = 1 } }) });
        check(foreign.scope == "class" and foreign.class == "MAGE" and foreign.spec == 2,
            "남의 직업 좌표를 내 것으로 바꿨다: " .. tostring(foreign.class)
                .. "/" .. tostring(foreign.spec));
    end);

    -- A scope invented by a newer schema. Counted rather than dropped in silence: the window says
    -- how many did not land.
    test("모르는 레이어는 세어서 빠진다", function()
        local placements, skipped = DebindShare.PlanImport(Payload({
            { id = 1, actions = InLayer({ scope = "raid" },
                { { type = Constants.SPELL, value = 1 } }) },
            { id = 2, actions = InLayer(GENERAL, { { type = Constants.SPELL, value = 2 } }) },
        }), 1);
        check(#placements == 1, "빠뜨릴 것을 안 빠뜨렸다");
        check(skipped == 1, "안 센다 - 조용히 사라진다");
    end);

    -- **A line the reader unticked is not a skip.** Both leave the actions out, but one of them is
    -- the answer they gave and the other is this version having nowhere to put it. Counting the
    -- first would put "%d came from a layer this version does not know" on screen for a layer they
    -- themselves declined.
    test("안 고른 줄은 빠지되 세지 않는다", function()
        local placements, skipped = DebindShare.PlanImport(Payload({
            { id = 1, actions = InLayer(GENERAL, { { type = Constants.SPELL, value = 1 } }) },
            { id = 2, actions = InLayer({ scope = "class", class = CLASS, spec = 0 },
                { { type = Constants.SPELL, value = 2 } }) },
        }), 1, { lines = { ["shared.general"] = true } });

        check(#placements == 1, "고른 줄만 들어와야 한다: " .. #placements);
        check(placements[1].scope == "general", "엉뚱한 줄이 들어왔다");
        check(skipped == 0, "안 고른 것을 못 놓은 것으로 세었다: " .. skipped);
    end);

    ---------------------------------------------------------------------------
    -- SETSTATE: name axis back to the bitpack
    ---------------------------------------------------------------------------

    test("상태 이름이 비트팩으로 돌아온다", function()
        local action = PlanOne({ id = 1, key = "F", actions = InLayer(GENERAL,
            { { type = Constants.SETSTATE,
                setstate = { mode = "toggle", state = "$state3" } } }) });

        local mode, index = DebindPrivate.GetSetCustomStateModeAndIndex(action.value);
        check(mode == "toggle", "모드 " .. tostring(mode));
        check(index == 3, "상태 번호 " .. tostring(index));
        check(action.setstate == nil, "포맷 필드가 액션에 남았다");
    end);

    test("세 모드가 다 돌아온다", function()
        for _, mode in ipairs({ "on", "off", "toggle" }) do
            local action = PlanOne({ id = 1, key = "F", actions = InLayer(GENERAL,
                { { type = Constants.SETSTATE,
                    setstate = { mode = mode, state = "$state1" } } }) });
            check(DebindPrivate.GetSetCustomStateModeAndIndex(action.value) == mode,
                "모드가 안 돌아옴: " .. mode);
        end
    end);

    -- **A name this version does not know must not become a number.** Any number resolves, and it
    -- would resolve to some other state - the key would quietly set the wrong one.
    test("모르는 상태 이름은 값이 안 생긴다", function()
        local action = PlanOne({ id = 1, key = "F", actions = InLayer(GENERAL,
            { { type = Constants.SETSTATE,
                setstate = { mode = "toggle", state = "$nosuchstate" } } }) });
        check(action.value == nil, "엉뚱한 상태를 가리키는 값이 생겼다: " .. tostring(action.value));
        check(action.type == Constants.SETSTATE, "타입은 그대로여야 한다");
    end);

    ---------------------------------------------------------------------------
    -- MACRO: the reference comes back only on a three-way match
    ---------------------------------------------------------------------------

    local SNAPSHOT = { name = "내매크로", body = "/cast 재생", icon = 9, scope = "account" };

    local function MacroGroup()
        return { id = 1, key = "F", actions = InLayer(GENERAL,
            { { type = Constants.MACRO, value = "내매크로", macro = SNAPSHOT } }) };
    end

    test("이름·스코프·내용이 다 맞으면 참조가 살아 돌아온다", function()
        ResetProfile();
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 재생", index = 3 } };

        local action = PlanOne(MacroGroup());
        check(action.type == Constants.MACRO, "MACROTEXT로 떨어졌다");
        check(action.value == "내매크로", "이름 " .. tostring(action.value));
    end);

    -- **The case the snapshot exists for.** A macro of the same name with different contents is
    -- somebody else's macro, and firing it would be silent and wrong.
    test("이름은 같은데 내용이 다르면 본문으로 떨어진다", function()
        ResetProfile();
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 다른것", index = 3 } };

        local action = PlanOne(MacroGroup());
        check(action.type == Constants.MACROTEXT, "남의 매크로를 그대로 가리킨다");
        check(action.value == "/cast 재생", "본문 " .. tostring(action.value));
        check(action.name == "내매크로", "이름을 안 들고 왔다");
    end);

    test("같은 이름이 아예 없으면 본문으로 떨어진다", function()
        ResetProfile();
        local action = PlanOne(MacroGroup());
        check(action.type == Constants.MACROTEXT, "없는 매크로를 가리킨다");
        check(action.value == "/cast 재생", "본문");
    end);

    -- Scope is the third leg. An account macro and a character macro of the same name and body are
    -- still two macros, and the sender meant one of them.
    test("스코프가 다르면 본문으로 떨어진다", function()
        ResetProfile();
        local accountLimit = DebindPrivate.GetMacroSlotLimits();
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 재생",
            index = accountLimit + 1 } };

        local action = PlanOne(MacroGroup());
        check(action.type == Constants.MACROTEXT, "스코프를 안 본다");
    end);

    -- Dangling when it was sent: no snapshot travelled, so there is nothing to fall back to and the
    -- action stays what it was. Red text is what says so on this side
    -- (`BINDING_ISSUE_MISSING_MACRO`).
    test("스냅샷 없이 온 매크로는 그대로 둔다", function()
        ResetProfile();
        local action = PlanOne({ id = 1, key = "F", actions = InLayer(GENERAL,
            { { type = Constants.MACRO, value = "없는것" } }) });
        check(action.type == Constants.MACRO, "타입이 바뀌었다");
        check(action.value == "없는것", "이름이 바뀌었다");
    end);

    ---------------------------------------------------------------------------
    -- Placing them
    ---------------------------------------------------------------------------

    test("놓으면 그 레이어에 서고 순서 번호를 받는다", function()
        ResetProfile();
        local placements = DebindShare.PlanImport(Payload({
            { id = 1, key = "F", actions = InLayer(GENERAL,
                { { type = Constants.SPELL, value = 774 } }) },
        }), 5);

        DebindPrivate.PlaceImportedActions(placements);

        local layer = DebindPrivate.GetProfileLayer(1);
        check(layer:GetNumActions() == 1, "레이어에 안 들어감");
        local action = layer:GetAction(1);
        check(action.imported == 5, "배지가 없다");
        -- **The sender's number stays home.** It would collide with the ones this layer already
        -- handed out, so the receiving layer gives its own (`Export.lua` leaves `seq` behind).
        check(action.seq ~= nil, "순서 번호를 안 받았다");
    end);

    -- **A class this account has never played still has a place.** The address is the store's, not
    -- the eleven layers this character happens to see, so it goes in and waits there - invisible in
    -- this session and reaching no key, which is what quarantine already promises.
    test("이 세션에 없는 직업 레이어도 저장에는 들어간다", function()
        ResetProfile();
        DebindPrivate.PlaceImportedActions({
            { scope = "class", class = "MAGE", spec = 2,
              action = { type = Constants.SPELL, value = 1, key = "F", imported = 3 } },
        });

        local stored = _G.DebindVars.shared.classes.MAGE;
        check(stored and stored[2] and #stored[2] == 1,
            "마법사 특성2 자리에 안 들어갔다");
        check(stored[2][1].seq ~= nil, "순서 번호를 안 받았다");
    end);

    test("자리가 없는 주소를 가리키면 아무것도 안 놓는다", function()
        ResetProfile();
        -- A scope nothing answers to. `PlaceImportedActions` skips rather than erroring: what it is
        -- handed came off the wire.
        DebindPrivate.PlaceImportedActions({
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
        -- Layer 4 is the class layer of spec 2, and the shim's player is spec 1. A batch lands
        -- there routinely: an action is placed by the scope it was sent with, not by the
        -- specialization the reader happens to be in.
        DebindPrivate.PlaceImportedActions({
            { scope = "general",
              action = { type = Constants.SPELL, value = 774, key = "F", imported = 3 } },
            { scope = "class", class = CLASS, spec = 2,
              action = { type = Constants.SPELL, value = 774, key = "G", imported = 3 } },
        });

        -- The premise: the layer that walk is not allowed to use really does leave one out.
        local live = 0;
        for _, layer in DebindPrivate.EnumerateProfileLayers() do
            for _, action in layer:Enumerate() do
                if (action.imported) then
                    live = live + 1;
                end
            end
        end
        check(live == 1, "전제가 틀렸다 - 활성 레이어 훑기가 " .. live .. "개를 봤다");

        check(#DebindPrivate.CollectImportedActions() == 2,
            "오프스펙 레이어의 배지를 놓쳤다");
    end);

    test("배지가 없는 액션은 안 따라온다", function()
        ResetProfile();
        DebindPrivate.PlaceImportedActions({
            { scope = "general",
              action = { type = Constants.SPELL, value = 774, key = "F", imported = 3 } },
        });
        -- The reader's own, placed the ordinary way. Approving must not reach it.
        DebindPrivate.GetProfileLayer(1):Insert({ type = Constants.SPELL, value = 585, key = "H" });

        local badged = DebindPrivate.CollectImportedActions();
        check(#badged == 1, "배지 없는 것까지 세었다: " .. #badged);
        check(badged[1].value == 774, "엉뚱한 액션이 나왔다");
    end);

    return T;
end
