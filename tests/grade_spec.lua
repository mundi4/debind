-- How an issue is drawn, and what it does to its action (`Constants.BINDING_ISSUE_OUTCOMES`).
-- No WoW client needed.
--
-- **One grade** (owner, 2026-10-07; `giving-keys-back-when-no-action-runs.md` 1-1). Every issue
-- means the same thing to the key, that the action is sometimes or always skipped, so every issue
-- is drawn in one colour. `npm run check` cannot see a colour, so the value that picks it is caught
-- here.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local GetIssueColor = DebindPrivate.GetIssueColor;

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

    --- Every issue code. A table under the same prefix is skipped, its value not being a string.
    local function ForEachIssueCode(fn)
        local seen = 0;
        for name, code in pairs(Constants) do
            if (type(name) == "string" and name:match("^BINDING_ISSUE_")
                    and type(code) == "string") then
                seen = seen + 1;
                fn(name, code);
            end
        end
        check(seen > 0, "no issue code found - did the prefix change?");
    end

    ---------------------------------------------------------------------------
    -- Colour
    ---------------------------------------------------------------------------

    test("every issue code is drawn in orange", function()
        ForEachIssueCode(function(name, code)
            check(GetIssueColor(code) == _G.ORANGE_FONT_COLOR, name .. " is not orange");
        end);
    end);

    -- A code with no row anywhere is still an issue, and no issue has no colour: a caller writes
    -- `if (color)`.
    test("an unknown code is orange, and nil has no colour", function()
        check(GetIssueColor("NO_SUCH_ISSUE_CODE") == _G.ORANGE_FONT_COLOR, "an unknown code is not orange");
        check(GetIssueColor(nil) == nil, "no issue has a colour");
    end);

    ---------------------------------------------------------------------------
    -- Outcome (`Constants.BINDING_ISSUE_OUTCOMES`)
    ---------------------------------------------------------------------------

    -- A code added without a row falls to leaving the action out, which is safe, and nobody was asked
    -- whether that was meant.
    test("every code has an outcome written down", function()
        ForEachIssueCode(function(name, code)
            check(Constants.BINDING_ISSUE_OUTCOMES and Constants.BINDING_ISSUE_OUTCOMES[code] ~= nil,
                name .. " has no outcome");
        end);
    end);

    return T;
end
