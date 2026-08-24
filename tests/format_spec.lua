-- What the client's `format` does that plain Lua's does not: **argument selection**, `%N$`.
--
-- It is a Lua 4.0 feature that 5.0 dropped and WoW kept, so `string.format` in a stock interpreter
-- raises `invalid conversion '%1$' to 'format'` on a string the game formats fine. The shim aliased
-- `format` straight to `string.format` for as long as it existed, which means **every spec that
-- reached one of these strings would have died on the format call rather than on what it measured.**
-- There are 122 of them across `Debind/`, `DebindStorage/` and `DebindDev/`, and the locale files
-- are three of the six that carry them.
--
-- The rule the game follows, from its own documentation
-- (`https://wowpedia.fandom.com/wiki/API_format`):
--
--     format("%2$d, %1$d, %d", 1, 2) == "2, 1, 2"
--
-- That one line pins the part nothing else pins. **A positional specifier moves the implicit
-- counter**: the trailing plain `%d` answers 2, not 1. Every other reading of "positional and plain
-- mixed in one string" gets that example wrong, and this repo depends on the answer being this one
-- (`UpdateBindings.lua`, the `SetSwitch` line that restores a switch's stored value).
return function()
    local T = { passed = 0, failures = {} };

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local function eq(got, want)
        if (got ~= want) then
            error(("got %q, want %q"):format(tostring(got), tostring(want)), 2);
        end
    end

    -- The documented example. This is the anchor: it comes from the client, not from us.
    test("argument selection, and a plain spec after one", function()
        eq(format("%2$d, %1$d, %d", 1, 2), "2, 1, 2");
    end);

    test("a skipped argument", function()
        -- `Misc.lua` builds a macro body this way. The unit is argument 2 and the string that
        -- wants no unit reaches past it, so **the specifiers are not a permutation of the
        -- arguments** and an implementation that walks them in order cannot serve this.
        eq(format("%1$s %3$s", "/cast", "target", "Rejuvenation"), "/cast Rejuvenation");
    end);

    test("positional and plain in one string", function()
        -- The shape in `UpdateBindings.lua`: the state name is named, the value follows it.
        eq(format([[SetSwitch(%1$q, %s)]], "$state1", "true"), [[SetSwitch("$state1", true)]]);
    end);

    test("one argument read twice", function()
        eq(format("States[%1$q]=v;Dirty[%1$q]=true", "combat"),
            [[States["combat"]=v;Dirty["combat"]=true]]);
    end);

    test("a conversion the stand-in does not cover raises", function()
        -- `%s`, `%d` and `%q` are every conversion this repo pairs with a positional specifier
        -- (85, 18 and 19 of them). The stand-in covers those and **raises on anything else
        -- rather than guessing** -- a width or a float silently formatted the wrong way would
        -- be a wrong answer coming out of the harness, which is worse than no answer.
        local ok = pcall(format, "%1$5.2f", 1.0);
        if (ok) then
            error("expected a raise", 2);
        end
    end);

    test("a literal percent consumes no argument", function()
        eq(format("100%% %1$s", "done"), "100% done");
    end);

    test("the method form takes the same path", function()
        -- The client's own strings arrive as globals and are formatted this way
        -- (`FULL_PLAYER_NAME:format(...)` in `Misc.lua`), and a localized one carries `%N$`
        -- where the English one does not. Aliasing only the `format` global would leave this
        -- call site on stock Lua.
        eq(("%2$s-%1$s"):format("realm", "name"), "name-realm");
    end);

    test("a string with no argument selection is untouched", function()
        eq(format("%s/%d %q", "a", 7, [[x"y]]), [[a/7 "x\"y"]]);
        eq(format("%5.2f|%-3d|", 1.239, 4), " 1.24|4  |");
    end);

    -- **The one conversion the two interpreters answer differently.** fengari gives `0.5` for a
    -- bare `%f` where C -- and so the client's 5.1 -- gives `0.500000`. `Flyout.lua` bakes a
    -- threshold into a snippet body with a bare `%f`, so without this the same rebuild builds two
    -- different snippets depending on who ran it, and the emission golden could only ever hold for
    -- one of them.
    test("a bare %f gets C's six places", function()
        eq(format("%f", 0.5), "0.500000");
        eq(format("[%f]", 1), "[1.000000]");
    end);

    -- What must **not** move with it. A precision that was written down already answers the same
    -- both ways, and an `f` that is not a conversion at all is just a letter.
    test("only the bare one moves", function()
        eq(format("%.2f", 0.5), "0.50");
        eq(format("%5.1f", 0.5), "  0.5");
        eq(format("%10f", 0.5), "  0.500000");
        eq(format("100%%f"), "100%f");
        eq(format("%s off", "50%"), "50% off");
    end);

    return T;
end
