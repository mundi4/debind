-- `ParseHelpText`: a help page body cut into the blocks the help window lays out. No client needed.

return function(DebindPrivate)
    local ParseHelpText = DebindPrivate.ParseHelpText;

    local T = { passed = 0, failures = {} };

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local function show(value)
        if (type(value) ~= "table") then
            return type(value) == "string" and string.format("%q", value) or tostring(value);
        end
        local keys = {};
        for k in pairs(value) do
            keys[#keys + 1] = k;
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b); end);
        local parts = {};
        for _, k in ipairs(keys) do
            parts[#parts + 1] = tostring(k) .. "=" .. show(value[k]);
        end
        return "{" .. table.concat(parts, ", ") .. "}";
    end

    local function same(want, got)
        if (show(want) ~= show(got)) then
            error("\n  want " .. show(want) .. "\n  got  " .. show(got), 2);
        end
    end

    test("a body with no line breaks is one paragraph, word for word", function()
        local body = "First.|n|n|cnHIGHLIGHT_FONT_COLOR:Second.|r Third.";
        same({ { kind = "paragraph", text = body } }, ParseHelpText(body));
    end)

    test("lines run together into one paragraph until a blank line", function()
        same({
            { kind = "paragraph", text = "One line and the next." },
            { kind = "paragraph", text = "Another." },
        }, ParseHelpText("One line\nand the next.\n\nAnother."));
    end)

    test("a heading is one line and ends whatever came before it", function()
        same({
            { kind = "paragraph", text = "Before." },
            { kind = "heading", text = "Title" },
            { kind = "paragraph", text = "After." },
        }, ParseHelpText("Before.\n# Title\nAfter."));
    end)

    test("numbered and bulleted items keep their marker, and a following line joins the item", function()
        same({
            { kind = "paragraph", text = "Intro." },
            { kind = "item", marker = "1.", level = 0, text = "First item goes on." },
            { kind = "item", marker = "2.", level = 0, text = "Second." },
            { kind = "item", marker = "-", level = 0, text = "Bullet." },
        }, ParseHelpText("Intro.\n1. First item\ngoes on.\n2. Second.\n- Bullet."));
    end)

    test("two spaces of indent put an item one level deeper", function()
        same({
            { kind = "item", marker = "-", level = 0, text = "Outer." },
            { kind = "item", marker = "-", level = 1, text = "Inner." },
            { kind = "item", marker = "1.", level = 2, text = "Innermost." },
        }, ParseHelpText("- Outer.\n  - Inner.\n    1. Innermost."));
    end)

    test("a note ends the block before it, and a following line joins the note", function()
        same({
            { kind = "paragraph", text = "Before." },
            { kind = "note", text = "An aside that goes on." },
            { kind = "paragraph", text = "After." },
        }, ParseHelpText("Before.\n> An aside\nthat goes on.\n\nAfter."));
    end)

    test("a bare angle bracket with no space is not a note", function()
        same({ { kind = "paragraph", text = ">Not a note." } }, ParseHelpText(">Not a note."));
    end)

    test("a number in running text is not an item", function()
        same({ { kind = "paragraph", text = "It takes 1.5 seconds. 2.Not an item either." } },
            ParseHelpText("It takes 1.5 seconds.\n2.Not an item either."));
    end)

    test("blank lines at either end and CRLF leave no empty block", function()
        same({
            { kind = "heading", text = "Title" },
            { kind = "paragraph", text = "Body." },
        }, ParseHelpText("\r\n\r\n# Title\r\n\r\n\r\nBody.\r\n  \r\n"));
    end)

    test("escape sequences inside a line reach the block untouched", function()
        local line = "Press |A:NPE_LeftClick:16:16|a, see |Hdebind:help:ordering|h[the order]|h.";
        same({ { kind = "item", marker = "-", level = 0, text = line } }, ParseHelpText("- " .. line));
    end)

    return T;
end
