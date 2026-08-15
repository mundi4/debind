-- 키 그룹의 순서 번호를 다시 매기는 것. `devdocs/renumbering-a-key-group.md`가 명세다.
--
-- **재는 것은 밴드를 넘은 액션이 어디에 서는가다.** `CompareActionOrder`의 `seq` 앞 다섯 층
-- (중요도·hover·조건·레이어·전문화)이 같은 액션들을 그 문서가 "밴드"라고 부른다. 조건을 켜면
-- 액션은 다른 밴드로 가는데, 들고 가는 번호가 그 밴드와 무관한 이력이면 **맨 앞에도 중간에도
-- 맨 뒤에도** 떨어졌다 - 같은 조작인데 결과가 셋이고, 무엇이 그걸 정하는지 화면에 안 나온다.
--
-- 재부여가 그 전제를 세운다. 번호가 "그룹 안에서 지금 보이는 자리"이면 밴드들이 번호 구간을
-- 순서대로 나눠 가지므로, 넘어온 번호는 목적지 구간의 바깥일 수밖에 없고 착지는 **왔던 쪽에
-- 면한 끝** 하나로 정해진다.

return function(DebindPrivate)
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

    -- keygroup_spec과 같은 전제: 드루이드(4특성), 활성 특성 1.
    check(CLASS == "DRUID", "드루이드 전제: " .. tostring(CLASS));

    local function ResetProfile(layout)
        layout = layout or {};
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = layout.general or {}, classes = { [CLASS] = layout.class or {} } },
            characters = { [GUID] = { layers = layout.char or {} } },
            migrated = {},
        };
        DebindPrivate.InitDB();
    end

    --- 조건이 걸린 액션. `combat`은 밴드의 `조건` 층만 건드린다 - hover는 그 위의 독립된
    --- 층이라 섞으면 무엇이 밴드를 갈랐는지가 흐려진다.
    local function Cond(value, key, seq)
        return { type = Constants.SPELL, value = value, key = key, seq = seq, combat = true };
    end

    local function Plain(value, key, seq)
        return { type = Constants.SPELL, value = value, key = key, seq = seq };
    end

    --- 발동 순서 한 줄. 실패했을 때 차례가 눈에 보인다.
    local function Order(key)
        local out = {};
        for i, row in ipairs(DebindPrivate.CollectActionsForKey(key)) do
            out[i] = tostring(row.action.value);
        end
        return table.concat(out, " ");
    end

    --- 그룹의 번호를 차례대로. `1 2 3 ...`이 아니면 재부여가 안 돌았거나 자리 순으로 안 돌았다.
    local function Seqs(key)
        local out = {};
        for i, row in ipairs(DebindPrivate.CollectActionsForKey(key)) do
            out[i] = tostring(row.action.seq);
        end
        return table.concat(out, " ");
    end

    local function Find(key, value)
        for _, row in ipairs(DebindPrivate.CollectActionsForKey(key)) do
            if (row.action.value == value) then
                return row.action;
            end
        end
    end

    --- 게임에서 조건 하나를 켜고 끄는 것. **값을 쓰고 그 키 그룹을 재부여하는 것이 전부**이고,
    --- 그 둘이 `DropDownMenus.lua`의 `onActionValueChanged`가 하는 일이다.
    local function Edit(action, field, value)
        action[field] = value;
        DebindPrivate.RenumberKeyGroupForAction(action);
    end

    --- 한 키에 밴드 둘, **번호를 일부러 어긋나게 심은** 그룹.
    ---
    --- 조건밴드가 10·20·30을 들고 무조건밴드가 2·25·99를 든다. 무조건 쪽 하나가 조건을 켜면
    --- 그 번호는 10~30 구간의 앞에도, 안에도, 뒤에도 떨어질 수 있다 - 셋을 다 낼 수 있게
    --- 고른 값이다. 번호가 화면 차례와 나란했으면 이 파일은 아무것도 못 잰다.
    ---
    --- **저장 배열의 차례도 화면 차례와 다르게 둔다.** 재부여가 배열 순으로 매기면 이 어긋남이
    --- 그대로 순서가 되는데, 매겨야 하는 것은 보이는 차례다.
    local function TwoBands()
        ResetProfile({
            general = {
                Plain(23, "F", 99),
                Cond(11, "F", 10),
                Plain(22, "F", 25),
                Cond(13, "F", 30),
                Plain(21, "F", 2),
                Cond(12, "F", 20),
            },
        });
        check(Order("F") == "11 12 13 21 22 23", "심어놓은 차례: " .. Order("F"));
    end

    --- 어긋난 번호 위로 **편집 한 번을 미리 지나보낸다.**
    ---
    --- 재부여는 유도로 서는 불변식이다 - 편집 전에 번호가 화면 차례와 나란했으면 편집 뒤에도
    --- 나란하다. 옛 저장 파일에서 온 어긋난 번호는 그 유도의 바깥이고, 그것을 안으로 들이는
    --- 것이 그 그룹에 닿는 첫 편집이다. 아래 토글들은 전부 **그 다음** 편집이다.
    ---
    --- 미리 지나가는 이 편집은 밴드를 안 바꾼다(이미 조건이 있는 액션에 조건 하나 더). 그래서
    --- 자리는 안 움직이고 번호만 정리되는데, 바로 아래 첫 테스트가 그것을 따로 세운다.
    local function Settle()
        Edit(Find("F", 12), "stealth", true);
    end

    ---------------------------------------------------------------------------
    -- 밴드가 안 바뀌면 아무것도 안 움직인다
    ---------------------------------------------------------------------------

    -- 조건을 다듬는 것이 편집의 대부분인데 그때마다 자리를 잃으면 안 된다. `isConditional`은
    -- 파생값이라 이미 조건이 있는 액션에 조건을 하나 더 켜도 밴드는 그대로다.
    test("밴드가 안 바뀌는 편집은 자리를 안 바꾼다", function()
        TwoBands();

        Edit(Find("F", 12), "stealth", true);

        check(Order("F") == "11 12 13 21 22 23", "자리가 움직였다: " .. Order("F"));
    end);

    -- 재부여가 매기는 것은 **보이는 차례**다. 저장 배열의 차례로 매기면 위 테스트는 통과하면서
    -- (한 번은 화면이 안 움직이므로) 다음 편집부터 순서가 갈린다.
    test("재부여는 보이는 차례로 1..n을 매긴다", function()
        TwoBands();

        Edit(Find("F", 12), "stealth", true);

        check(Seqs("F") == "1 2 3 4 5 6", "번호: " .. Seqs("F"));
    end);

    ---------------------------------------------------------------------------
    -- 밴드를 넘으면 왔던 쪽에 면한 끝
    ---------------------------------------------------------------------------

    --- 조건을 켠 액션이 조건밴드의 **맨 뒤**에 서는지. 조건밴드는 앞쪽 밴드라, 뒤쪽에서
    --- 넘어온 번호는 그 구간 전부보다 크고 그래서 맨 뒤다.
    local function ExpectBackOfConditionalBand(value, expected)
        TwoBands();
        Settle();

        Edit(Find("F", value), "combat", true);

        check(Order("F") == expected, "차례: " .. Order("F"));
    end

    -- **셋 다 같은 자리로 간다.** 재부여가 없을 때 이 셋이 정확히 맨 앞·중간·맨 뒤였다:
    -- 21은 2번을 들고 있어서 조건밴드(10~30) 전체보다 앞, 22는 25번이라 20과 30 사이,
    -- 23은 99번이라 뒤. 같은 조작 하나에 결과가 셋이었고, 무엇이 그걸 정하는지는 화면
    -- 어디에도 안 나왔다.
    test("조건을 켜면 조건밴드의 맨 뒤 - 맨 앞으로 떨어지던 것", function()
        ExpectBackOfConditionalBand(21, "11 12 13 21 22 23");
    end);

    test("조건을 켜면 조건밴드의 맨 뒤 - 중간으로 떨어지던 것", function()
        ExpectBackOfConditionalBand(22, "11 12 13 22 21 23");
    end);

    test("조건을 켜면 조건밴드의 맨 뒤 - 맨 뒤로 떨어지던 것", function()
        ExpectBackOfConditionalBand(23, "11 12 13 23 21 22");
    end);

    -- 반대 방향. 무조건밴드는 뒤쪽 밴드라, 앞에서 넘어온 번호는 그 구간 전부보다 작고
    -- 그래서 **맨 앞**이다. 나갈 때 "가까운 앞", 들어올 때 "가까운 뒤"라 껐다 켜면 제자리로
    -- 안 돌아오는데, 그건 재부여를 하는 이상 피할 수 없는 대가다(문서의 "복구 불가는 구조적").
    test("조건을 끄면 무조건밴드의 맨 앞", function()
        TwoBands();
        Settle();

        Edit(Find("F", 11), "combat", nil);

        check(Order("F") == "12 13 11 21 22 23", "차례: " .. Order("F"));
    end);

    ---------------------------------------------------------------------------
    -- 재부여가 닿는 범위
    ---------------------------------------------------------------------------

    -- 번호가 읽히는 범위가 (레이어, 키) 하나라 재부여도 거기서 멈춘다. 같은 레이어의 다른
    -- 키까지 훑으면 사용자가 그 키에서 정해둔 자리가 남의 편집에 딸려 바뀐다.
    test("같은 레이어의 다른 키는 안 건드린다", function()
        ResetProfile({
            general = {
                Cond(11, "F", 10),
                Plain(21, "F", 2),
                Plain(31, "G", 7),
                Plain(32, "G", 9),
            },
        });

        Edit(Find("F", 21), "combat", true);

        check(Seqs("G") == "7 9", "G의 번호가 바뀌었다: " .. Seqs("G"));
    end);

    -- **겹친 번호를 들고 그룹에 들어와도 자리가 흔들리면 안 된다.** 번호가 그룹마다 1부터라
    -- 한 레이어 안에서 겹치는 것이 정상이고, 키를 뗀 액션은 그 번호를 든 채로 남는다
    -- (`CleanUpDB`가 이제 그것을 안 가른다). 그것이 같은 번호를 쓰는 키에 걸리면 동률이 하나
    -- 생긴다.
    test("겹친 번호를 들고 들어오면 쌍둥이 바로 뒤에 선다", function()
        ResetProfile({
            general = {
                Plain(11, "F", 1),
                Plain(12, "F", 2),
                -- 키를 뗀 채 1번을 들고 있던 액션. 이제 F에 걸린다.
                Plain(13, nil, 1),
            },
        });

        local rejoining = DebindPrivate.GetProfileLayer(1):GetAction(3);
        rejoining.key = "F";
        DebindPrivate.RenumberKeyGroupForAction(rejoining);

        check(Order("F") == "11 13 12", "차례: " .. Order("F"));
        check(Seqs("F") == "1 2 3", "번호: " .. Seqs("F"));
    end);

    -- **매기는 답이 `sort`의 속사정에 걸리면 안 된다.** 동률이 여럿이면 `table.sort`는 equals를
    -- 통째로 흩어놓는다 - 위의 셋짜리로는 안 드러나고 여덟 개쯤에서 드러난다. 재부여의 답은
    -- 곧바로 저장되므로 한 번 흩어지면 그 차례가 남고, 다시 매길 때 또 달라진다.
    --
    -- 여기까지 오는 것은 손으로 고친 저장 파일이다. **번호는 로드한 뒤에 심는다** - `InitDB`가
    -- 끝에 `CleanUpDB`를 부르고 그 그물이 한 그룹 안의 겹침을 먼저 갈라버린다.
    test("동률이 여럿이어도 배열 자리가 차례를 정한다", function()
        ResetProfile({
            general = {
                Plain(1, "F", 1), Plain(2, "F", 2), Plain(3, "F", 3), Plain(4, "F", 4),
                Plain(5, "F", 5), Plain(6, "F", 6), Plain(7, "F", 7), Plain(8, "F", 8),
            },
        });

        local layer = DebindPrivate.GetProfileLayer(1);
        for i = 1, 8 do
            layer:GetAction(i).seq = (i % 2 == 1) and 2 or 1;
        end

        layer:RenumberKeyGroup("F");

        -- 1번을 든 것들이 배열 순으로 먼저, 그다음 2번을 든 것들이 배열 순으로.
        check(Order("F") == "2 4 6 8 1 3 5 7", "차례: " .. Order("F"));
    end);

    -- 레이어마다 1부터 다시 센다. `seq`는 레이어 안에서만 뜻이 있고(비교자가 layerRank로 먼저
    -- 가른다) 레이어끼리 겹치는 번호는 만날 일이 없다.
    --
    -- **밴드는 레이어보다 넓다.** `조건` 층이 `레이어` 층보다 위라 조건밴드가 레이어를 가로지른다
    -- (51·11이 붙고 61·21이 붙는다). 그래도 한 레이어로 걸러낸 차례는 전체 차례에서의 상대 순서
    -- 그대로라, 재부여가 레이어 안에서만 돌아도 매기는 값은 화면 차례다.
    test("레이어를 가로지르는 키는 레이어마다 1부터", function()
        ResetProfile({
            general = { Cond(11, "F", 40), Plain(21, "F", 50) },
            class = { [0] = { Cond(51, "F", 60), Plain(61, "F", 70) } },
        });

        Edit(Find("F", 11), "stealth", true);
        Edit(Find("F", 51), "stealth", true);

        -- 조건밴드(51·11)가 먼저고 그 안에서 직업/공용이 일반보다 위다.
        check(Order("F") == "51 11 61 21", "차례: " .. Order("F"));
        check(Seqs("F") == "1 1 2 2", "번호: " .. Seqs("F"));
    end);

    return T;
end
