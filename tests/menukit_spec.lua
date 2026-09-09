-- **메뉴 커널의 값 처리와 이슈 올림.** 와우 클라이언트 불필요.
--
-- 무엇이 여기서 답해지는가: 접근자 한 쌍으로 만든 네 콜백이 라디오·확인란·비트에 맞게
-- 답하고 쓰는가, 그리고 하위 묶음의 이슈가 손으로 적은 목록 없이 상위로 올라오는가.
-- 둘 다 값에 대한 물음이라 화면이 필요 없다.
--
-- `Registry:Build`는 **부르는 것만** 본다. 설명자 대역에 무엇이 그려지라고 불렸는지까지가
-- 여기 닿는 끝이고, 색이 실제로 칠해지는지와 툴팁 줄이 어떻게 서는지는 화면에서만 보인다
-- (`devdocs/legacy/putting-the-menus-on-a-kit.md`).

return function(DebindPrivate)
    local MenuKit = DebindPrivate.MenuKit;

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

    --- 가장 단순한 접근자. 표 하나에 그대로 읽고 쓰고, 쓴 횟수를 센다.
    local function Accessor()
        local store = { writes = 0 };
        return {
            store = store,
            Get = function(ctx, key)
                return ctx.values[key];
            end,
            Set = function(ctx, key, value)
                store.writes = store.writes + 1;
                ctx.values[key] = value;
                return "refreshed";
            end,
        };
    end

    local function Ctx(values)
        return { values = values or {} };
    end

    --------------------------------------------------------------------------
    -- MakeHandlers
    --------------------------------------------------------------------------

    test("radio equals reads through the accessor", function()
        local h = MenuKit.MakeHandlers(Accessor());
        local ctx = Ctx({ combat = true });
        check(h.equals({ ctx = ctx, key = "combat", value = true }), "고른 값이 켜져 보여야 한다");
        check(not h.equals({ ctx = ctx, key = "combat", value = false }), "다른 값은 꺼져 보여야 한다");
        check(h.equals({ ctx = Ctx(), key = "combat", value = nil }),
            "값이 없으면 [사용 안 함] 줄이 켜져 보여야 한다");
    end);

    test("picking the value it already has writes nothing", function()
        local accessor = Accessor();
        local h = MenuKit.MakeHandlers(accessor);
        local ctx = Ctx({ combat = true });

        check(h.set({ ctx = ctx, key = "combat", value = true }) == nil,
            "안 바뀌었으면 메뉴에 아무것도 안 돌려준다");
        check(accessor.store.writes == 0, "안 바뀌었으면 쓰기가 없어야 한다");

        check(h.set({ ctx = ctx, key = "combat", value = false }) == "refreshed",
            "바뀌었으면 Set이 낸 것을 그대로 돌려준다");
        check(accessor.store.writes == 1, "바뀐 것만 한 번 쓴다");
    end);

    test("clearing a key that was never set writes nothing", function()
        local accessor = Accessor();
        local h = MenuKit.MakeHandlers(accessor);
        h.set({ ctx = Ctx(), key = "combat", value = nil });
        check(accessor.store.writes == 0, "없던 것을 지우면서 표를 만들지 않는다");
    end);

    --- **끈 확인란은 `false`를 쓴다.** 지우는 것과 끄는 것은 다르고, 이 자리로 오는 필드는
    --- 전부 조건 표 밖에 살아서 지워질 일도 없다.
    test("a toggle box writes false rather than clearing", function()
        local h = MenuKit.MakeHandlers(Accessor());
        local ctx = Ctx();

        h.set({ ctx = ctx, key = "keepInBindingContext", value = MenuKit.TOGGLE });
        check(ctx.values.keepInBindingContext == true, "안 켜져 있던 것은 켜진다");
        check(h.equals({ ctx = ctx, key = "keepInBindingContext", value = MenuKit.TOGGLE }),
            "켜진 뒤에는 확인란도 켜져 보인다");

        h.set({ ctx = ctx, key = "keepInBindingContext", value = MenuKit.TOGGLE });
        check(ctx.values.keepInBindingContext == false, "끄면 false가 남지 nil이 되지 않는다");
        check(not h.equals({ ctx = ctx, key = "keepInBindingContext", value = MenuKit.TOGGLE }),
            "false는 꺼진 것으로 보인다");
    end);

    test("bit boxes read the default mask while nothing is stored", function()
        local h = MenuKit.MakeHandlers(Accessor());
        local ctx = Ctx();
        local data = { ctx = ctx, key = "frameTypes", value = 2, defaultValue = 7 };

        check(h.hasBit(data), "아무것도 안 정했으면 기본 마스크로 읽는다");
        check(not h.hasBit({ ctx = ctx, key = "frameTypes", value = 8, defaultValue = 7 }),
            "기본 마스크 밖의 비트는 꺼져 있다");

        h.toggleBit(data);
        check(ctx.values.frameTypes == 5, "켜져 있던 비트를 끄면 기본에서 그것만 빠진다");
        check(not h.hasBit(data), "끈 비트는 꺼져 보인다");

        h.toggleBit(data);
        check(ctx.values.frameTypes == 7, "다시 켜면 되돌아온다");
    end);

    test("a bit box with nothing stored and no default reads zero", function()
        local h = MenuKit.MakeHandlers(Accessor());
        check(not h.hasBit({ ctx = Ctx(), key = "forms", value = 1 }),
            "기본값이 없으면 아무 비트도 안 켜져 있다");
    end);

    --------------------------------------------------------------------------
    -- IssueOf
    --------------------------------------------------------------------------

    --- 이슈는 커널에게 불투명한 값이다. 여기서는 키 이름을 그대로 이슈로 쓴다.
    local function Registry(broken)
        local registry = MenuKit.NewRegistry({
            accessor = Accessor(),
            issueForKey = function(_, key)
                return broken[key];
            end,
            isActiveForKey = function(ctx, key)
                return ctx.values[key] ~= nil;
            end,
            resolveIssue = function(issue)
                return issue, nil;
            end,
        });
        registry:Define("BARS", { label = "BARS", children = { "BONUS", "SPECIAL" } });
        registry:Define("BONUS", { label = "BONUS", key = "bonusbars" });
        registry:Define("SPECIAL", { label = "SPECIAL", key = "specialbar" });
        return registry;
    end

    test("a parent with no value of its own reports its child's issue", function()
        local registry = Registry({ specialbar = "SPECIALBAR_NEVER_HOLDS" });
        check(registry:IssueOf(registry:Get("BARS"), Ctx()) == "SPECIALBAR_NEVER_HOLDS",
            "두 번째 자식의 문제가 여는 줄까지 올라와야 한다");
    end);

    test("nothing wrong anywhere is nothing wrong at the top", function()
        local registry = Registry({});
        check(registry:IssueOf(registry:Get("BARS"), Ctx()) == nil,
            "자식이 다 멀쩡하면 여는 줄도 멀쩡하다");
    end);

    test("the node's own issue comes before its children's", function()
        local registry = Registry({ bonusbars = "FROM_CHILD" });
        registry:Get("BARS").issue = function()
            return "FROM_SELF";
        end;
        check(registry:IssueOf(registry:Get("BARS"), Ctx()) == "FROM_SELF",
            "자기 문제가 있으면 그것을 먼저 낸다");
    end);

    test("children are read in the order they are named", function()
        local registry = Registry({ bonusbars = "FIRST", specialbar = "SECOND" });
        check(registry:IssueOf(registry:Get("BARS"), Ctx()) == "FIRST",
            "먼저 적힌 자식의 문제가 먼저다");
    end);

    --- **손목록이 없다는 것이 이 항목이다.** 자식 하나를 더 매달았을 뿐인데 그 문제가 위로
    --- 올라온다. 예전에는 여는 줄 옆에 갈래 이름을 적어야 올라왔고, 안 적으면 조용히 안
    --- 빨개졌다.
    test("a child added later brings its issue up with it", function()
        local registry = Registry({ extrabar = "EXTRABAR_BROKEN" });
        check(registry:IssueOf(registry:Get("BARS"), Ctx()) == nil,
            "아직 안 매달렸으면 안 올라온다");

        registry:Define("EXTRA", { label = "EXTRA", key = "extrabar" });
        local children = registry:Get("BARS").children;
        children[#children + 1] = "EXTRA";

        check(registry:IssueOf(registry:Get("BARS"), Ctx()) == "EXTRABAR_BROKEN",
            "매달자마자 목록을 안 고쳤는데도 올라온다");
    end);

    test("an issue two levels down still reaches the top", function()
        local registry = Registry({ bonusbars = "DEEP" });
        registry:Define("ALL", { label = "ALL", children = { "BARS" } });
        check(registry:IssueOf(registry:Get("ALL"), Ctx()) == "DEEP",
            "손자의 문제도 올라온다");
    end);

    --------------------------------------------------------------------------
    -- IsActive
    --------------------------------------------------------------------------

    test("a group is active when the value under its key is set", function()
        local registry = Registry({});
        check(not registry:IsActive(registry:Get("BONUS"), Ctx()), "값이 없으면 안 켜져 있다");
        check(registry:IsActive(registry:Get("BONUS"), Ctx({ bonusbars = 0 })),
            "0도 정한 값이라 켜져 있다");
    end);

    test("a group with no key and no isActive is never active", function()
        local registry = Registry({});
        check(not registry:IsActive(registry:Get("BARS"), Ctx({ bonusbars = 1 })),
            "여는 줄은 자기 판정을 안 주면 안 켜진다");
    end);

    --------------------------------------------------------------------------
    -- shown, and the clearing checkbox
    --------------------------------------------------------------------------

    --- 설명자 대역. **행이 그려지는지가 아니라 무엇이 그려지라고 불렸는지만 잰다** - 진짜
    --- 메뉴 행은 프레임이라 여기서 못 만든다. 커널이 부르는 것만 받아 적는다.
    local function FakeDescription()
        local calls = { buttons = 0, checkboxes = {} };
        local fake;
        fake = {
            calls = calls,
            CreateButton = function(self)
                calls.buttons = calls.buttons + 1;
                return fake;
            end,
            CreateCheckbox = function(self, text, isSelected, setSelected, data)
                calls.checkboxes[#calls.checkboxes + 1] = {
                    text = text, isSelected = isSelected, setSelected = setSelected, data = data,
                };
                return fake;
            end,
            AddInitializer = function() end,
            QueueTitle = function() end,
        };
        return fake;
    end

    test("a node that says it is not shown draws nothing", function()
        local registry = Registry({});
        registry:Define("HIDDEN", {
            label = "HIDDEN",
            -- 제목 줄은 `MenuUtil`을 거치는 그리기 쪽이라 여기서 못 지난다.
            skipTitle = true,
            shown = function(ctx)
                return ctx.values.allowed == true;
            end,
        });

        local parent = FakeDescription();
        check(registry:Build(parent, "HIDDEN", Ctx()) == nil, "안 보이면 설명자를 안 돌려준다");
        check(parent.calls.buttons == 0, "행 자체가 안 만들어져야 한다");

        check(registry:Build(parent, "HIDDEN", Ctx({ allowed = true })) ~= nil,
            "보이면 평소대로 선다");
        check(parent.calls.buttons == 1, "그때만 행이 하나 만들어진다");
    end);

    --- 끄면 키를 지우는 확인란. `MenuKit.TOGGLE`과 다른 점이 이것 하나다.
    test("the clearing checkbox removes the key instead of writing false", function()
        local accessor = Accessor();
        local registry = MenuKit.NewRegistry({
            accessor = accessor,
            resolveIssue = function(issue) return issue, nil; end,
        });
        local parent = FakeDescription();
        registry:Define("KNOWN", {
            label = "KNOWN",
            key = "known",
            skipTitle = true,
            build = function(kit)
                kit:ClearingCheckbox("known?", "known", true);
            end,
        });

        local ctx = Ctx();
        registry:Build(parent, "KNOWN", ctx);
        local box = parent.calls.checkboxes[1];
        check(box ~= nil, "확인란이 하나 만들어진다");

        check(not box.isSelected(box.data), "값이 없으면 꺼져 있다");
        box.setSelected(box.data);
        check(ctx.values.known == true, "켜면 값이 들어간다");
        check(box.isSelected(box.data), "켜진 뒤에는 켜져 보인다");

        box.setSelected(box.data);
        check(ctx.values.known == nil, "끄면 false가 아니라 아무것도 안 남는다");
    end);

    --------------------------------------------------------------------------
    -- MarkNew
    --------------------------------------------------------------------------

    --- 점을 끄는 것은 목록에서 태그를 빼는 것 하나다. 릴리스가 하는 일이 그것이다.
    test("only the tags in the list get a dot", function()
        local registry = MenuKit.NewRegistry({
            accessor = Accessor(),
            newFeatures = { "SMART_CAST" },
            resolveIssue = function(issue) return issue, nil; end,
        });

        local marked = registry:MarkNew("SMART_CAST", "스마트캐스트");
        check(marked ~= "스마트캐스트", "목록에 있는 태그는 글자가 달라진다");
        check(marked:find("스마트캐스트", 1, true) == 1, "원래 글자가 앞에 그대로 남는다");

        check(registry:MarkNew("ROLE", "역할") == "역할", "목록에 없으면 손대지 않는다");
    end);

    test("an empty list marks nothing", function()
        local registry = MenuKit.NewRegistry({
            accessor = Accessor(),
            resolveIssue = function(issue) return issue, nil; end,
        });
        check(registry:MarkNew("SMART_CAST", "스마트캐스트") == "스마트캐스트",
            "목록을 안 주면 아무것도 안 붙는다");
    end);

    --------------------------------------------------------------------------
    -- Define
    --------------------------------------------------------------------------

    test("the same name cannot be defined twice", function()
        local registry = Registry({});
        check(not pcall(function()
            registry:Define("BONUS", { label = "BONUS" });
        end), "이름이 겹치면 그 자리에서 터진다");
    end);

    test("building an undefined name raises rather than drawing nothing", function()
        local registry = Registry({});
        check(not pcall(function()
            registry:Get("NOPE");
        end), "없는 이름은 조용히 넘어가지 않는다");
    end);

    return T;
end
