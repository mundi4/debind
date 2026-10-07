-- How an issue code is drawn, and what it does to its action (`Constants.BINDING_ISSUE_OUTCOMES`).
-- No client needed.
--
-- **Every code is drawn alike** (owner, 2026-10-07): one mark, in orange, saying the action is
-- skipped some of the time or all of it. A code drawn otherwise says something about its key that
-- no code means any more, and `npm run check` cannot see a colour.

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

    --- Every issue code. `BINDING_ISSUE_OUTCOMES` and `BINDING_ISSUE_CATEGORIES` are filtered out by
    --- not being strings, though their names share the prefix.
    local function ForEachIssueCode(fn)
        local seen = 0;
        for name, code in pairs(Constants) do
            if (type(name) == "string" and name:match("^BINDING_ISSUE_")
                    and type(code) == "string") then
                seen = seen + 1;
                fn(name, code);
            end
        end
        check(seen > 0, "found no issue code; did the prefix change?");
    end

    ---------------------------------------------------------------------------
    -- Colour
    ---------------------------------------------------------------------------

    test("every code is orange, an unknown one too, and no issue has no colour", function()
        ForEachIssueCode(function(name, code)
            check(GetIssueColor(code) == _G.ORANGE_FONT_COLOR, name .. " is not orange");
        end);
        check(GetIssueColor("NO_SUCH_ISSUE_CODE") == _G.ORANGE_FONT_COLOR, "an unknown code is not orange");
        -- No problem, nothing to paint. Callers part the two with `if (color)`.
        check(GetIssueColor(nil) == nil, "a colour came out with no issue");
    end);

    ---------------------------------------------------------------------------
    -- Outcome (`Constants.BINDING_ISSUE_OUTCOMES`)
    ---------------------------------------------------------------------------

    -- A code added without a row falls to leaving the action out, which is safe, and nobody was
    -- asked whether that was meant.
    test("every code has an outcome written down", function()
        ForEachIssueCode(function(name, code)
            check(Constants.BINDING_ISSUE_OUTCOMES and Constants.BINDING_ISSUE_OUTCOMES[code] ~= nil,
                name .. " has no outcome");
        end);
    end);

    return T;
end
