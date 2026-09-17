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

    --- The plainest accessor. A target is a table with `values`, written straight through; writes and
    --- commits are counted. A ctx with no `targets` is its own single target.
    local function Accessor()
        local store = { writes = 0, commits = 0 };
        return {
            store = store,
            Targets = function(ctx)
                return ctx.targets or { ctx };
            end,
            Get = function(target, key)
                return target.values[key];
            end,
            Set = function(target, key, value)
                store.writes = store.writes + 1;
                target.values[key] = value;
            end,
            Commit = function()
                store.commits = store.commits + 1;
                return "refreshed";
            end,
        };
    end

    local function Ctx(values)
        return { values = values or {} };
    end

    --- Several targets under one ctx, each starting from its own values.
    local function Many(...)
        local targets = {};
        for i, values in ipairs({ ... }) do
            targets[i] = { values = values };
        end
        return { targets = targets };
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
    -- MakeHandlers over several targets
    --------------------------------------------------------------------------

    test("a radio reads as picked only when every target holds the value", function()
        local h = MenuKit.MakeHandlers(Accessor());
        check(not h.equals({ ctx = Many({ combat = true }, { combat = false }), key = "combat", value = true }),
            "one target holding another value leaves the radio off");
        check(h.equals({ ctx = Many({ combat = true }, { combat = true }), key = "combat", value = true }),
            "every target holding it lights the radio");
    end);

    test("a radio write reaches every target that differs and commits once", function()
        local accessor = Accessor();
        local h = MenuKit.MakeHandlers(accessor);
        local ctx = Many({ combat = true }, { combat = false }, {});

        check(h.set({ ctx = ctx, key = "combat", value = true }) == "refreshed", "the commit's answer comes back");
        for i, target in ipairs(ctx.targets) do
            check(target.values.combat == true, "target " .. i .. " did not take the value");
        end
        check(accessor.store.writes == 2, "the one already holding it is written anyway: " .. accessor.store.writes);
        check(accessor.store.commits == 1, "commits: " .. accessor.store.commits);
    end);

    --- **Flipping each target from its own value leaves a mixed set mixed.** The press has to decide
    --- one outcome from what is drawn, and a box that is not on for everyone is drawn off.
    test("a toggle box on a mixed set turns everything on, then everything off", function()
        local h = MenuKit.MakeHandlers(Accessor());
        local ctx = Many({ keep = true }, {}, { keep = false });
        local data = { ctx = ctx, key = "keep", value = MenuKit.TOGGLE };

        check(not h.equals(data), "a mixed set draws the box off");
        h.set(data);
        for i, target in ipairs(ctx.targets) do
            check(target.values.keep == true, "first press, target " .. i .. ": " .. tostring(target.values.keep));
        end
        check(h.equals(data), "everything on draws the box on");

        h.set(data);
        for i, target in ipairs(ctx.targets) do
            check(target.values.keep == false, "second press, target " .. i .. ": " .. tostring(target.values.keep));
        end
    end);

    test("a bit box on a mixed set moves that bit everywhere and leaves each target's other bits", function()
        local h = MenuKit.MakeHandlers(Accessor());
        local ctx = Many({ forms = 1 + 4 }, { forms = 2 }, {});
        local data = { ctx = ctx, key = "forms", value = 4 };

        check(not h.hasBit(data), "a bit only some targets hold draws off");
        h.toggleBit(data);
        check(ctx.targets[1].values.forms == 5, "first: " .. tostring(ctx.targets[1].values.forms));
        check(ctx.targets[2].values.forms == 6, "second: " .. tostring(ctx.targets[2].values.forms));
        check(ctx.targets[3].values.forms == 4, "third: " .. tostring(ctx.targets[3].values.forms));

        h.toggleBit(data);
        check(ctx.targets[1].values.forms == 1, "first, off: " .. tostring(ctx.targets[1].values.forms));
        check(ctx.targets[2].values.forms == 2, "second, off: " .. tostring(ctx.targets[2].values.forms));
        check(ctx.targets[3].values.forms == 0, "third, off: " .. tostring(ctx.targets[3].values.forms));
    end);

    --- The bit rule reads an unset value as the default mask, so turning a default bit off on a target
    --- that stored nothing has to start from that mask and not from zero.
    test("a bit box starts an unset target from the default mask", function()
        local h = MenuKit.MakeHandlers(Accessor());
        local ctx = Many({}, { frameTypes = 7 });
        local data = { ctx = ctx, key = "frameTypes", value = 2, defaultValue = 7 };

        check(h.hasBit(data), "both read the bit as on");
        h.toggleBit(data);
        check(ctx.targets[1].values.frameTypes == 5, "unset: " .. tostring(ctx.targets[1].values.frameTypes));
        check(ctx.targets[2].values.frameTypes == 5, "set: " .. tostring(ctx.targets[2].values.frameTypes));
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

    test("the clearing checkbox on a mixed set stores everywhere, then clears everywhere", function()
        local registry = MenuKit.NewRegistry({
            accessor = Accessor(),
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

        local ctx = Many({ known = true }, {});
        registry:Build(parent, "KNOWN", ctx);
        local box = parent.calls.checkboxes[1];

        check(not box.isSelected(box.data), "a mixed set draws the box off");
        box.setSelected(box.data);
        check(ctx.targets[1].values.known == true and ctx.targets[2].values.known == true,
            "the first press stores the value on both");
        box.setSelected(box.data);
        check(ctx.targets[1].values.known == nil and ctx.targets[2].values.known == nil,
            "the second press clears both");
    end);

    --- The row's label and the sentence in its tooltip are one statement, so the grade that paints
    --- one paints the other. A WARNING's label went orange while its sentence stayed red.
    test("an issue's sentence in a row's tooltip takes the grade's colour", function()
        local WARNING_COLOR = { GetRGB = function() return 1, 0.5, 0.25; end };
        local registry = MenuKit.NewRegistry({
            accessor = Accessor(),
            resolveIssue = function(issue) return "sentence for " .. issue, WARNING_COLOR; end,
        });
        registry:Define("WARNED", {
            label = "WARNED",
            skipTitle = true,
            issue = function() return "CODE"; end,
        });

        local row = { initializers = {} };
        function row:AddInitializer(fn) self.initializers[#self.initializers + 1] = fn; end
        registry:Build({ CreateButton = function() return row; end }, "WARNED", Ctx());

        local tooltipFn;
        local element = { SetTooltip = function(_, fn) tooltipFn = fn; end };
        local frame = { fontString = {
            GetText = function() return "WARNED"; end,
            SetTextToFit = function() end,
            SetTextColor = function() end,
        } };
        for _, fn in ipairs(row.initializers) do
            fn(frame, element);
        end
        check(tooltipFn ~= nil, "no tooltip was set");

        local tooltip = require("wow_shim").newTooltip();
        tooltipFn(tooltip);
        local line;
        for _, l in ipairs(tooltip.lines) do
            if (l.text == "sentence for CODE") then line = l; end
        end
        check(line ~= nil, "the sentence is not in the tooltip");
        check(line.kind == "colored" and line.color == WARNING_COLOR,
            "the sentence came out as " .. tostring(line.kind));
    end);

    --- **A leaf and not a submenu**, the same as `CreateBlockedMenuItem`: a list nobody can open has
    --- no reason to stand, and an arrow on it promises a step that is not there.
    test("a node that says it is blocked draws one locked row and nothing under it", function()
        local registry = Registry({});
        local built = false;
        registry:Define("BLOCKED", {
            label = "BLOCKED",
            skipTitle = true,
            blocked = function(ctx)
                return ctx.values.reason;
            end,
            build = function()
                built = true;
            end,
        });

        local enabled, tooltip;
        local parent = FakeDescription();
        parent.SetEnabled = function(_, value) enabled = value; end;
        parent.SetTooltip = function(_, fn) tooltip = fn; end;

        check(registry:Build(parent, "BLOCKED", Ctx({ reason = "only one" })) ~= nil, "the row stands");
        check(parent.calls.buttons == 1, "one row");
        check(enabled == false, "the row is locked");
        check(tooltip ~= nil, "the row carries its reason");
        check(not built, "nothing is built under a blocked row");

        enabled, tooltip = nil, nil;
        registry:Build(parent, "BLOCKED", Ctx());
        check(enabled == nil, "no reason, no lock");
        check(built, "no reason, the node builds as usual");
    end);

    --------------------------------------------------------------------------
    -- MarkNew
    --------------------------------------------------------------------------

    --- 행 하나. 커널이 부르는 것만 받아 적는다.
    local Row;
    function Row(text)
        local row = { text = text, initializers = {}, children = {} };

        function row:AddInitializer(fn)
            self.initializers[#self.initializers + 1] = fn;
        end

        function row:CreateButton(label)
            local child = Row(label);
            self.children[#self.children + 1] = child;
            return child;
        end

        function row:CreateTitle(label)
            local child = Row(label);
            self.children[#self.children + 1] = child;
            return child;
        end

        function row:AddQueuedDescription(description)
            table.insert(self.children, 1, description);
        end

        function row:HasElements()
            return #self.children > 0;
        end

        function row:SetTooltip() end

        return row;
    end

    local function NewFeatureRegistry(tags)
        local registry = MenuKit.NewRegistry({
            accessor = Accessor(),
            newFeatures = tags,
            resolveIssue = function(issue) return issue, nil; end,
        });
        registry:Define("OUTER", { label = "밖", children = { "INNER" } });
        registry:Define("INNER", {
            label = "안",
            build = function(kit)
                registry:MarkNew("NEW_THING", kit.description);
            end,
        });
        return registry;
    end

    --- 이 행이 화면에 낼 글자. **`text` 필드가 아니다** - 행이 실제로 그리는 것은 초기화
    --- 함수들이 남기는 것이라(`MarkRowNew`), 그것들을 차례로 태워 봐야 답이 나온다. 템플릿이
    --- 자기 초기화 함수에서 놓고 가는 글자가 그 시작이다.
    local function drawn(description)
        local text = description.text;
        local frame = {
            fontString = {
                GetText = function() return text; end,
                SetTextToFit = function(_, value) text = value; end,
                SetTextColor = function() end,
            },
        };
        for _, fn in ipairs(description.initializers) do
            fn(frame, description);
        end
        return text;
    end

    local function hasDot(text)
        return text:find("|A:", 1, true) ~= nil;
    end

    --- 태그가 가리킨 줄과, 그 줄에 닿기까지 열어야 하는 줄.
    local function BuildMarked(tags)
        local root = Row();
        NewFeatureRegistry(tags):Build(root, "OUTER", Ctx());
        local outer = root.children[1];
        return outer.children[2], outer;
    end

    --- 점을 끄는 것은 목록에서 태그를 빼는 것 하나다. 릴리스가 하는 일이 그것이다.
    test("only the tags in the list get a dot", function()
        check(hasDot(drawn(BuildMarked({ "NEW_THING" }))), "목록에 있는 태그는 점이 붙는다");
        check(not hasDot(drawn(BuildMarked({ "SOMETHING_ELSE" }))), "목록에 없으면 손대지 않는다");
        check(not hasDot(drawn(BuildMarked(nil))), "목록을 안 주면 아무것도 안 붙는다");
    end);

    test("the mark carries the original label with it", function()
        check(drawn(BuildMarked({ "NEW_THING" })):find("안", 1, true) == 1,
            "원래 글자가 앞에 그대로 남는다");
    end);

    --- 새것이 하위 메뉴 안에 있으면, 그 안까지 열어 본 사람만 점을 보게 된다.
    test("every row that has to be opened to reach it is marked too", function()
        local inner, outer = BuildMarked({ "NEW_THING" });

        check(hasDot(drawn(inner)), "태그가 가리킨 줄에 붙는다");
        check(hasDot(drawn(outer)), "여는 줄에도 붙는다");

        -- 하위 메뉴의 첫 줄은 그 줄 자신의 이름을 다시 적은 제목이다(`skipTitle`).
        check(hasDot(drawn(inner.children[1])), "태그가 가리킨 줄이 여는 제목에도 붙는다");
        check(not hasDot(drawn(outer.children[1])), "지나온 줄의 제목에는 안 붙는다");
    end);

    --- 제목이 그 메뉴의 머리일 때만 표시가 간다. 중간에 낀 제목은 그 아래 묶음의 이름이라
    --- 위에서 붙은 표시와 상관이 없다.
    local function BuildTitledRow(first)
        local registry = MenuKit.NewRegistry({
            accessor = Accessor(),
            newFeatures = { "NEW_THING" },
            resolveIssue = function(issue) return issue, nil; end,
        });
        registry:Define("PLAIN", {
            label = "밖",
            skipTitle = true,
            build = function(kit)
                if (not first) then
                    kit.description:CreateButton("먼저 선 줄");
                end
                kit:Title("제목");
                registry:MarkNew("NEW_THING", kit.description);
            end,
        });

        local root = Row();
        registry:Build(root, "PLAIN", Ctx());
        return root.children[1];
    end

    test("the title a family puts at the top of the menu is marked with it", function()
        local row = BuildTitledRow(true);
        check(hasDot(drawn(row)), "표시한 줄에는 붙는다");
        check(hasDot(drawn(row.children[1])), "그 메뉴의 첫 줄인 제목에 붙는다");
    end);

    test("a title further down the menu is left alone", function()
        local row = BuildTitledRow(false);
        check(hasDot(drawn(row)), "표시한 줄에는 붙는다");
        check(not hasDot(drawn(row.children[2])), "첫 줄이 아닌 제목에는 안 붙는다");
    end);

    --------------------------------------------------------------------------
    -- Mixed selections
    --------------------------------------------------------------------------

    --- **Every choice an appender draws goes past the family's hook**, so a family counting how many
    --- of its targets hold a value does not have to find each row the kit made on its behalf.
    test("every choice an appender draws is handed to the family's decorator", function()
        local seen = {};
        local registry = MenuKit.NewRegistry({
            accessor = Accessor(),
            resolveIssue = function(issue) return issue, nil; end,
            decorateChoice = function(description, ctx, isSelected, data)
                seen[#seen + 1] = { ctx = ctx, key = data.key, isSelected = isSelected };
            end,
        });
        registry:Define("ALL", {
            label = "ALL",
            skipTitle = true,
            build = function(kit)
                kit:DisableYesNo("X", "combat");
                kit:Checkboxes("forms", { { text = "a", value = 1 } });
                kit:ClearingCheckbox("k", "known", true);
            end,
        });

        local parent = FakeDescription();
        parent.CreateRadio = function(self, text, isSelected, setSelected, data)
            return self;
        end;
        local ctx = Ctx();
        registry:Build(parent, "ALL", ctx);

        check(#seen == 5, "choices decorated: " .. #seen);
        for i = 1, #seen do
            check(seen[i].ctx == ctx, "choice " .. i .. " was handed another ctx");
            check(type(seen[i].isSelected) == "function", "choice " .. i .. " came without its reading");
        end
    end);

    test("a node row carries the family's mixed count after its label", function()
        local registry = MenuKit.NewRegistry({
            accessor = Accessor(),
            resolveIssue = function(issue) return issue, nil; end,
            mixedCount = function(node, ctx)
                return ctx.values.mixed;
            end,
        });
        registry:Define("GROUP", { label = "밖", skipTitle = true });

        local root = Row();
        registry:Build(root, "GROUP", Ctx({ mixed = 2 }));
        check(drawn(root.children[1]) == "밖 " .. format(DebindPrivate.L["MENU_MIXED_COUNT"], 2),
            "drawn: " .. tostring(drawn(root.children[1])));

        root = Row();
        registry:Build(root, "GROUP", Ctx());
        check(drawn(root.children[1]) == "밖", "no count, no suffix: " .. tostring(drawn(root.children[1])));
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
