-- **가리킨 사람의 역할 조건.** 와우 클라이언트 불필요.
--
-- 무엇이 여기서 답해지는가: 리빌드가 역할 헤더를 켜기로 정하는가, 방출된 스니펫이 그 축을
-- 들고 나가는가, 역할만 다른 두 바인딩이 서로를 지우지 않는가, 아무 역할도 안 고른 것이
-- 이슈가 되는가. 전부 값에 대한 물음이라 게임이 필요 없다.
--
-- 헤더가 실제로 채워져서 `UnitRoles`에 행이 생기는지는 여기서 못 본다. 그것은
-- `/debtest`가 본다 (`devdocs/adding-a-role-condition.md` §7).

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;

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

    local GUID = "Player-1-TESTGUID";
    local CLASS = Constants.PLAYER_CLASS;

    local function Profile(actions)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
    end

    local function PlanFor(actions)
        Profile(actions);
        return DebindPrivate.BuildBindingPlan(DebindPrivate.CollectBindingContext());
    end

    local seq = 0;
    local function spell(t)
        seq = seq + 1;
        t.type = Constants.SPELL;
        t.value = t.value or 585;
        t.seq = seq;
        return t;
    end

    --- Hover 조건에 역할을 걸어둔 액션 하나.
    local function roleAction(mask, extra)
        local conditions = { units = { hover = { role = mask } } };
        for k, v in pairs(extra or {}) do
            conditions[k] = v;
        end
        return spell({ key = "CTRL-SHIFT-F9", conditions = conditions });
    end

    local function unitEntry(plan, alias)
        for i = 1, #plan.units do
            if (plan.units[i].alias == alias) then
                return plan.units[i];
            end
        end
    end

    ---------------------------------------------------------------------------
    -- 리빌드의 결정
    ---------------------------------------------------------------------------

    --- 역할 맵을 채우는 것은 세 헤더뿐이고, `damager`는 별칭이 아니라 `plan.units`에 없다.
    --- 그래서 리빌드가 그것을 켜기로 했다는 사실이 `plan.roleMap` 말고는 어디에도 안 적힌다.
    test("a role condition turns the role map on and widens the role headers", function()
        local plan = PlanFor({ roleAction(Constants.ROLE_TANK) });

        check(plan.roleMap == true, "roleMap: " .. tostring(plan.roleMap));
        for _, alias in ipairs({ "tank", "healer" }) do
            local entry = unitEntry(plan, alias);
            check(entry and entry.watch == true, alias .. " is not watched");
            check(entry.slots == Constants.MAX_ROLE_SLOTS,
                alias .. " slots: " .. tostring(entry.slots));
        end
    end);

    --- **안 쓰면 넓히지도 켜지도 않는다.** `@tank`를 쓰는 것과 역할을 묻는 것은 다른 요구다:
    --- 앞의 것은 탱커가 하나인지만 알면 되므로 두 칸이면 끝이다.
    test("naming @tank does not widen its header", function()
        local plan = PlanFor({ spell({ key = "CTRL-SHIFT-F9", unit = "tank" }) });

        check(plan.roleMap == false, "roleMap: " .. tostring(plan.roleMap));
        local entry = unitEntry(plan, "tank");
        check(entry and entry.watch == true, "tank is not watched");
        check(entry.slots == nil, "tank slots: " .. tostring(entry.slots));
    end);

    test("no role condition leaves the map off", function()
        local plan = PlanFor({ spell({ key = "CTRL-SHIFT-F9" }) });
        check(plan.roleMap == false, "roleMap: " .. tostring(plan.roleMap));
        check(unitEntry(plan, "tank").watch == false, "tank was watched");
    end);

    ---------------------------------------------------------------------------
    -- 방출
    ---------------------------------------------------------------------------

    --- 조건 쪽은 켠 이름의 집합이고 상태 쪽은 값 하나다. 반응 축과 같은 모양이라야
    --- 비교가 `cond.role[role]` 한 번으로 끝난다.
    test("the emitted record carries the chosen roles as a set", function()
        local plan = PlanFor({
            roleAction(Constants.ROLE_TANK + Constants.ROLE_HEALER),
        });
        local snippet = plan.bindingsMapSnippet;

        check(snippet:find("u.role=newtable()", 1, true), "no role table was emitted");
        check(snippet:find("u.role.tank=true", 1, true), "tank is missing");
        check(snippet:find("u.role.healer=true", 1, true), "healer is missing");
        check(not snippet:find("u.role.damager=true", 1, true), "damager should not be in");
        check(not snippet:find("u.role.unknown=true", 1, true), "unknown should not be in");
    end);

    --- **hover가 아닌 유닛에는 안 나간다.** 재는 쪽은 `unit == "hover"`에서만 축을 세우므로,
    --- 방출만 유닛을 안 가리면 `UnitStates.target.role`이 영영 nil이고 `cond.role[nil]`이
    --- 되어 **그 키가 조용히 죽는다.** 솔버 쪽(`BuildUnitStates`)은 hover만 읽어서 그 조건을
    --- 무시하므로, 막지 않으면 솔버와 런타임이 갈린다.
    ---
    --- 메뉴로는 못 만드는 모양이지만 손으로 고친 프로필과 옛 문자열이 이리로 온다.
    test("a role on a unit other than hover is not emitted", function()
        local plan = PlanFor({
            spell({
                key = "CTRL-SHIFT-F9",
                conditions = { units = { target = { role = Constants.ROLE_TANK } } },
            }),
        });
        check(not (plan.bindingsMapSnippet or ""):find("u.role", 1, true),
            "a role went out for target");
    end);

    --- **역할은 유닛 행이 아니라 호버 슬롯에 얹힌다.** 가리킨 프레임에 대해서만 답이 나오는
    --- 축이라, 유닛을 재는 자리에 두면 프레임 이야기가 유닛 측정에 섞이고 비트마다 프레임을
    --- 다시 읽게 된다. 슬롯을 채우는 자리는 프레임을 이미 손에 들고 있다.
    ---
    --- **게이트가 거기 있어야 한다.** 맵의 키가 그룹 유닛 토큰이라, 플레이어 프레임의 `player`는
    --- 파티에서는 맵에 있고 공대에서는 없다. 프레임 종류로 자르지 않으면 같은 프레임이 그룹
    --- 형태에 따라 다른 답을 낸다.
    --- **폴링은 역할을 안 잰다.** 역할이 바뀌는 사건은 `SetRoleUnits`가 도는 순간 하나뿐이라,
    --- 비트마다 다시 재면 아무것도 안 바뀐 값을 계속 재는 것이 된다.
    test("the hover poll does not measure the role", function()
        local plan = PlanFor({
            roleAction(Constants.ROLE_TANK, { combat = true }),
        });
        check(not (plan.attrChangedSnippet or ""):find("UnitRoles", 1, true),
            "the poll reads the role map");
    end);

    --- **표가 서기 전에 헤더를 켜면 첫 패스가 그냥 돌아간다.** `SetRoleUnits`는 표가 있을 때만
    --- 채우고, 헤더를 켜는 것이 곧 배치를 돌리는 것이라 순서가 뒤집히면 다음 로스터 변화까지
    --- 맵이 비어 있다.
    test("the map is stood up before a header is widened", function()
        local frames = require("wow_frames");
        Profile({ roleAction(Constants.ROLE_TANK) });

        local mark = frames.mark();
        DebindPrivate.UpdateBindings();

        local stoodUp, widened;
        local entries = frames.since(mark);
        for i = 1, #entries do
            local e = entries[i];
            if (not stoodUp and e.kind == "Execute" and e.body
                    and e.body:find("UnitRoles = newtable()", 1, true)) then
                stoodUp = i;
            elseif (not widened and e.kind == "SetAttribute" and e.name == "unitsPerColumn"
                    and e.body == Constants.MAX_ROLE_SLOTS) then
                widened = i;
            end
        end

        check(stoodUp, "the map was never stood up");
        check(widened, "no header was widened");
        check(stoodUp < widened, "the header was widened first");
    end);

    --- 유닛 행에는 안 나간다. 남아 있으면 같은 값을 두 곳에서 재게 되고, 둘이 갈리는 날
    --- 어느 쪽이 틀렸는지 알 수 없다.
    test("no unit row measures a role", function()
        local plan = PlanFor({
            roleAction(Constants.ROLE_TANK, { combat = true }),
        });
        check(not (plan.unitRowsSnippet or ""):find("u.role", 1, true),
            "a unit row still measures the role");
    end);

    ---------------------------------------------------------------------------
    -- 솔버
    ---------------------------------------------------------------------------

    --- 역할은 컬럼이 하나 늘어나는 것이지 유닛 축이 넓어지는 것이 아니다
    --- (`Constants.lua`의 `UNITSTATE_NONE` 위 문단). 두 바인딩이 그 축에서만 갈리면
    --- 서로를 못 덮는다.
    test("two bindings that differ only by role both survive", function()
        Profile({
            roleAction(Constants.ROLE_TANK),
            roleAction(Constants.ROLE_HEALER),
        });
        DebindPrivate.BuildKeyMap();

        local records = DebindPrivate.KeyMap and DebindPrivate.KeyMap["CTRL-SHIFT-F9"];
        check(records and #records == 2, "records: " .. tostring(records and #records));
    end);

    --- 같은 역할을 두 번 걸면 아래쪽은 절대 못 나간다. 위의 테스트가 통과하는 이유가
    --- "역할 컬럼이 있어서"이지 "솔버가 이 키를 통째로 포기해서"가 아님을 여기가 잡는다.
    test("the same role twice still deletes the lower one", function()
        Profile({
            roleAction(Constants.ROLE_TANK),
            roleAction(Constants.ROLE_TANK),
        });
        DebindPrivate.BuildKeyMap();

        local records = DebindPrivate.KeyMap and DebindPrivate.KeyMap["CTRL-SHIFT-F9"];
        check(records and #records == 1, "records: " .. tostring(records and #records));
    end);

    ---------------------------------------------------------------------------
    -- 이슈
    ---------------------------------------------------------------------------

    --- 확인란을 전부 끈 상태. 저장은 0을 그대로 적고(`DropDownMenus.lua`), 그 조건은
    --- 어떤 역할로도 안 맞는다.
    test("choosing no role at all is reported rather than silently never firing", function()
        local action = roleAction(0);
        Profile({ action });
        check(DebindPrivate.GetBindingIssue(action) == Constants.BINDING_ISSUE_CONDITIONS_NEVER,
            "issue: " .. tostring(DebindPrivate.GetBindingIssue(action)));
        check(DebindPrivate.GetBindingIssue(action, "hover") ~= nil,
            "the hover group was not marked");
    end);

    --- **전부 켠 것은 조건이 아니다.** 메뉴가 그때 nil을 쓰지만, 손으로 고친 프로필이나
    --- 옛 문자열이 전체 마스크로 올 수 있고 그것을 조건으로 읽으면 상자가 둘로 갈린다.
    test("every role checked constrains nothing", function()
        local action = roleAction(Constants.ROLE_ALL);
        Profile({ action });
        local binding = DebindPrivate.GetBindingInfoForAction(action);
        check(binding.unitRole == Constants.ROLE_ALL,
            "unitRole: " .. tostring(binding.unitRole));
        check(DebindPrivate.GetBindingIssue(action) == nil,
            "issue: " .. tostring(DebindPrivate.GetBindingIssue(action)));
    end);

    --- 역할 헤더 셋은 `showSolo = false`라 혼자일 때 아무도 안 올라간다. 그러니 "혼자일 때만"과
    --- "탱커일 때만"은 같이 설 수 없다. **두 조건이 다른 메뉴에 있어서** 각자로는 멀쩡해 보이는
    --- 것이 이 검사가 있는 이유고, 역할 별칭(`@tank`)에 대한 같은 검사가 이미 옆에 있다.
    test("a real role asked for while solo is reported", function()
        local action = roleAction(Constants.ROLE_TANK, { groups = Constants.GROUP_NONE });
        Profile({ action });
        check(DebindPrivate.GetBindingIssue(action) == Constants.BINDING_ISSUE_CONDITIONS_NEVER,
            "issue: " .. tostring(DebindPrivate.GetBindingIssue(action)));
    end);

    --- **`unknown`이 마스크에 남아 있으면 성립한다.** 혼자일 때 모두가 역할 미상이므로,
    --- 그 조합은 참이 되는 순간이 실제로 있다. 위 검사가 그것까지 잡으면 멀쩡한 바인딩이 죽는다.
    test("unknown while solo is not a contradiction", function()
        local action = roleAction(Constants.ROLE_TANK + Constants.ROLE_UNKNOWN,
            { groups = Constants.GROUP_NONE });
        Profile({ action });
        check(DebindPrivate.GetBindingIssue(action) == nil,
            "issue: " .. tostring(DebindPrivate.GetBindingIssue(action)));
    end);

    --- 파티나 공대가 허용돼 있으면 모순이 아니다.
    test("a real role with a group allowed is fine", function()
        local action = roleAction(Constants.ROLE_TANK,
            { groups = Constants.GROUP_NONE + Constants.GROUP_PARTY });
        Profile({ action });
        check(DebindPrivate.GetBindingIssue(action) == nil,
            "issue: " .. tostring(DebindPrivate.GetBindingIssue(action)));
    end);

    ---------------------------------------------------------------------------
    -- 툴팁
    ---------------------------------------------------------------------------

    --- **`FlagNames`는 접두사 하나로 두 표를 찾는다**: 비트는 `Constants[접두사 .. 이름]`,
    --- 낱말은 `LLL[접두사 .. 이름]`. 둘 중 하나만 있으면 `band`가 nil을 받고 툴팁을 그리다가
    --- 터진다. 상수를 `UNITROLE_*`로 두고 로케일을 `ROLE_*`로 뒀다가 게임에서 그렇게 났다
    --- (2026-08-28). 검사 어느 것도 그 짝을 안 본다.
    test("the tooltip names the chosen roles", function()
        local action = roleAction(Constants.ROLE_TANK + Constants.ROLE_HEALER);
        Profile({ action });

        local shim = require("wow_shim");
        local tooltip = shim.newTooltip();
        DebindPrivate.AddActionToTooltip(tooltip, action, { suppressInactive = true });
        local text = tooltip:text();

        check(text:find(DebindPrivate.L["ROLE_TANK"], 1, true), "tank is not named");
        check(text:find(DebindPrivate.L["ROLE_HEALER"], 1, true), "healer is not named");
        check(not text:find(DebindPrivate.L["ROLE_DAMAGER"], 1, true), "damager should not be named");
    end);

    return T;
end
