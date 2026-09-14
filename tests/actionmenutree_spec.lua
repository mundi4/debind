-- The whole action menu, built the way the game builds it, and read row by row
-- (`devdocs/editing-many-actions-at-once.md`).
--
-- **What is swept is two rules every row has to keep, not one case per group.** Written out per
-- group, the next group added is a group nobody wrote a case for.
--
-- 1. Asked about one action, **each run of radios has exactly one lit.** A radio reading that also
--    answers true for the state its neighbour owns draws two ticks.
-- 2. Over a selection, **the number after a label is how many actions hold that row**, asked one
--    action at a time with the row's own reading, and there is no number where they all agree.
--
-- What the game still owns is the client's menu calling these readings and drawing what they
-- return; everything they return is decided here.

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
    local DebindUI = DebindPrivate.DebindUI;
    local LLL = DebindPrivate.L;
    local CLASS = Constants.PLAYER_CLASS;
    local GUID = "Player-1-TESTGUID";

    local function ResetProfile(actions)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [CLASS] = {} } },
            characters = { [GUID] = { layers = {} } },
            migrated = {},
        };
        DebindPrivate.InitDB();
        return actions;
    end

    local function Spell(value, fields)
        local action = { type = Constants.SPELL, value = value, key = "F" };
        for k, v in pairs(fields or {}) do
            if (Constants.IsConditionField(k)) then
                action.conditions = action.conditions or {};
                action.conditions[k] = v;
            else
                action[k] = v;
            end
        end
        return action;
    end

    --- A description that keeps what it was told to draw.
    local function Element(kind, text, isSelected, setSelected, data)
        local element = {
            kind = kind, text = text, isSelected = isSelected, setSelected = setSelected, data = data,
            children = {}, initializers = {},
        };
        local function Add(child)
            element.children[#element.children + 1] = child;
            return child;
        end
        function element:AddInitializer(fn) self.initializers[#self.initializers + 1] = fn; end
        function element:SetEnabled(enabled) self.enabled = enabled; end
        function element:SetTooltip() end
        function element:SetTag() end
        function element:HasElements() return #self.children > 0; end
        function element:AddQueuedDescription(child) table.insert(self.children, 1, child); end
        function element:CreateTitle(label) return Add(Element("title", label)); end
        function element:CreateButton(label, fn, args) return Add(Element("button", label, nil, fn, args)); end
        function element:CreateRadio(label, sel, set, args) return Add(Element("radio", label, sel, set, args)); end
        function element:CreateCheckbox(label, sel, set, args) return Add(Element("checkbox", label, sel, set, args)); end
        function element:CreateDivider() return Add(Element("divider")); end
        return element;
    end

    --- The label a row draws once every initializer on it has run, with the new-feature dot taken off.
    local function Drawn(element)
        local text = element.text;
        local frame = {
            fontString = {
                GetText = function() return text; end,
                SetTextToFit = function(_, value) text = value; end,
                SetTextColor = function() end,
            },
        };
        for _, fn in ipairs(element.initializers or {}) do
            fn(frame, element);
        end
        return (text:gsub(" ?|A:[^|]*|a", ""));
    end

    --- The menu over `actions`, and the ctx its rows read.
    local function Build(actions)
        local root = Element("root");
        local ctx = { actions = actions };
        DebindUI.SetupActionDropdownMenu(nil, root, ctx);
        return root, ctx;
    end

    --- Asks `fn` with the menu narrowed to one action, the same narrowing the counts use.
    local function AskedAbout(ctx, action, fn)
        local actions = ctx.actions;
        ctx.actions = { action };
        local ok, result = pcall(fn);
        ctx.actions = actions;
        if (not ok) then
            error(result, 0);
        end
        return result;
    end

    local function EachChoice(root, visit)
        local function Walk(element, path)
            for _, child in ipairs(element.children or {}) do
                local here = path .. " > " .. tostring(child.text);
                if (child.kind == "radio" or child.kind == "checkbox") then
                    visit(child, here);
                end
                Walk(child, here);
            end
        end
        Walk(root, "");
    end

    --- Every run of two or more radios standing next to each other under one row.
    local function RadioRuns(root)
        local runs = {};
        local function Walk(element, path)
            local run;
            local function Close()
                if (run and #run >= 2) then
                    runs[#runs + 1] = { path = path, radios = run };
                end
                run = nil;
            end
            for _, child in ipairs(element.children or {}) do
                if (child.kind == "radio") then
                    run = run or {};
                    run[#run + 1] = child;
                else
                    Close();
                end
                Walk(child, path .. " > " .. tostring(child.text));
            end
            Close();
        end
        Walk(root, "");
        return runs;
    end

    local function CheckOneLitPerRun(root, ctx)
        for _, run in ipairs(RadioRuns(root)) do
            for index, action in ipairs(ctx.actions) do
                local lit = {};
                for _, radio in ipairs(run.radios) do
                    if (AskedAbout(ctx, action, function() return radio.isSelected(radio.data); end)) then
                        lit[#lit + 1] = radio.text;
                    end
                end
                check(#lit == 1, format("%s, action %d: %d lit (%s)", run.path, index, #lit,
                    table.concat(lit, ", ")));
            end
        end
    end

    local function CheckCounts(root, ctx)
        local total = #ctx.actions;
        EachChoice(root, function(choice, path)
            local held = 0;
            for _, action in ipairs(ctx.actions) do
                if (AskedAbout(ctx, action, function() return choice.isSelected(choice.data); end)) then
                    held = held + 1;
                end
            end
            local expected = choice.text;
            if (held > 0 and held < total) then
                expected = choice.text .. " " .. format(LLL["MENU_MIXED_COUNT"], held);
            end
            check(Drawn(choice) == expected, format("%s: drew %q, %d of %d hold it", path, Drawn(choice), held, total));
        end);
    end

    local function Fixtures()
        local catalog = DebindPrivate.ClassSpecCatalog();
        local firstSpec = catalog[1].specs[1].id;
        return ResetProfile({
            Spell(1),
            Spell(2, { units = { hover = { exists = true, reaction = Constants.REACTION_HELP } } }),
            Spell(3, { units = { hover = { exists = false } } }),
            Spell(4, { units = { target = { exists = true, dead = true } } }),
            Spell(5, { combat = true, stealth = false }),
            Spell(6, { specs = { [firstSpec] = true } }),
            Spell(7, { forms = 1 + 4, keepInBindingContext = true, unit = "focus" }),
            Spell(8, { units = { player = { exists = true, dead = false } } }),
        });
    end

    -- The destination lists of move and copy read the window's tabs as the menu is built. No tab is
    -- what the window has before it is drawn, and neither rule below is about destinations.
    local layerPanel = rawget(_G, "DebindLayerPanel");
    _G.DebindLayerPanel = { Tabs = {}, SideTabs = {} };

    test("one action at a time: every run of radios has exactly one lit", function()
        local actions = Fixtures();
        for _, action in ipairs(actions) do
            local root, ctx = Build({ action });
            CheckOneLitPerRun(root, ctx);
        end
    end);

    test("a selection: every run of radios has exactly one lit for each action in it", function()
        local actions = Fixtures();
        local root, ctx = Build(actions);
        CheckOneLitPerRun(root, ctx);
    end);

    test("a selection: every choice's number is how many actions hold it, and absent where they agree", function()
        local actions = Fixtures();
        for _, picked in ipairs({
            actions,
            { actions[1], actions[3] },
            { actions[2], actions[3] },
            { actions[4], actions[8] },
            { actions[5], actions[5] },
        }) do
            local root, ctx = Build(picked);
            CheckCounts(root, ctx);
        end
    end);

    _G.DebindLayerPanel = layerPanel;

    return T;
end
