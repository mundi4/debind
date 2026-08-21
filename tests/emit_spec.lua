-- The emission golden: everything one rebuild hands to the secure side, held against a recorded
-- file (`devdocs/legacy/going-headless-outside-the-ui.md` §6).
--
-- **This is a net, not a specification.** It says nothing about whether what came out is right; it
-- says that splitting a 578-line function did not change a byte of it. That is the only thing
-- guarding `UpdateBindings.lua` while the rest of the addon is allowed to be red, so when the
-- emission is meant to move the answer is `--update-golden` and reading the diff.
--
-- **What it locks is also the hot code.** What `UpdateAttrChangedHandler` builds *is* the body of
-- the state watch loop, so a rebuild of the emitters that leaves the emitted string untouched
-- costs the hot path nothing by definition (§3-5).
--
-- Nothing here interprets a snippet. The strings are recorded and compared as strings, which is
-- why the golden can exist long before there is anything that could run one (§5).

return function(DebindPrivate, _, ctx)
    local frames = require("wow_frames");
    local shim = require("wow_shim");

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

    ---------------------------------------------------------------------------
    -- Rendering what the recorder caught
    ---------------------------------------------------------------------------

    --- One recorded value as a line of the golden.
    ---
    --- **A frame is rendered by its name and never by its address.** `*attribute-frame-` carries a
    --- frame, and `tostring(frame)` is a different string on every run -- the golden would never
    --- hold still and the difference would look like a change in the addon.
    local function renderValue(value)
        local kind = type(value);
        if (kind == "table") then
            return "<frame " .. tostring(frames.label(value)) .. ">";
        elseif (kind == "string") then
            return string.format("%q", value);
        end
        return tostring(value);
    end

    --- Body lines get their own prefixed lines so a blank line inside a snippet is visible in the
    --- diff, and so a body can never be mistaken for the header of the next entry.
    local function appendBody(out, body)
        for line in (body .. "\n"):gmatch("([^\n]*)\n") do
            out[#out + 1] = "  | " .. line;
        end
    end

    local function render(entries)
        local out = {};
        for i = 1, #entries do
            local e = entries[i];
            local head = e.kind .. " " .. tostring(e.target);
            if (e.kind == "Execute") then
                out[#out + 1] = head;
                appendBody(out, e.body or "");
            elseif (e.kind == "SetAttribute" or e.kind == "WrapScript"
                    or e.kind == "WrapScriptPost") then
                local value = e.kind == "SetAttribute" and e.body or e.body;
                if (type(value) == "string" and value:find("\n", 1, true)) then
                    out[#out + 1] = head .. " " .. tostring(e.name) .. " =";
                    appendBody(out, value);
                else
                    out[#out + 1] = head .. " " .. tostring(e.name)
                        .. " = " .. renderValue(value);
                end
            else
                if (e.name ~= nil) then
                    head = head .. " " .. tostring(e.name);
                end
                if (e.body ~= nil) then
                    head = head .. " " .. renderValue(e.body);
                end
                out[#out + 1] = head;
            end
        end
        out[#out + 1] = "";
        return table.concat(out, "\n");
    end

    ---------------------------------------------------------------------------
    -- The run
    ---------------------------------------------------------------------------

    local fixture = assert(loadfile(ctx.root .. "/emit_fixture.lua"))()(DebindPrivate, shim);

    --- **A golden per shape.** The shipped shape emits different bytes, and not only where a
    --- `if (DEBUG)` writes a comment line into a record list: the driver frame is created
    --- **unnamed** there (`Debind.lua`, `DEBUG and "DebindBindingDriver" or nil`), so every line
    --- that names a frame reads differently too. Holding both against one file would mean one of
    --- the two shapes could never be recorded, and the one that lost is the one users run.
    local goldenPath = ctx.root
        .. (ctx.shipped and "/emit-shipped-golden.txt" or "/emit-golden.txt");

    local produced;

    test("a rebuild runs headless end to end", function()
        fixture.install();
        DebindPrivate.BuildKeyMap();

        local mark = frames.mark();
        local built = DebindPrivate.UpdateBindings();
        local entries = frames.since(mark);

        check(built == true, "UpdateBindings declined to build");
        check(#entries > 0, "the rebuild handed nothing to the secure side");
        produced = render(entries);
    end);

    -- **The count is asserted apart from the bytes.** A fixture edit that quietly stops reaching a
    -- branch shows up here as a smaller number, where in the golden diff it would be one more
    -- block among many.
    test("the fixture drives every key it defines", function()
        local keys = 0;
        for _ in pairs(DebindPrivate.KeyMap) do keys = keys + 1; end
        check(keys == 37, "keys in KeyMap: " .. keys);
    end);

    test("what the rebuild emitted has not moved", function()
        check(produced, "nothing was produced to compare");

        if (ctx.updateGolden) then
            ctx.writeFile(goldenPath, produced);
            return;
        end

        local golden = ctx.readFile(goldenPath);
        check(golden, "no golden at " .. goldenPath .. " -- run with --update-golden");

        -- **Carriage returns come off, and that is not laziness.** The file is a recording of
        -- bytes, but git rewrites line endings on checkout wherever `core.autocrlf` is on --
        -- so the golden matched only in the working tree that generated it, and any fresh
        -- checkout on Windows went red on line 1 showing two lines that look identical.
        -- `.gitattributes` keeps git out of the file from here on; this is what carries a copy
        -- that was already converted.
        golden = golden:gsub("\r\n", "\n");

        if (golden == produced) then
            return;
        end

        -- **Report the first line that differs, not the whole file.** The golden runs to a few
        -- hundred lines and a failure that prints all of it buries the one line that moved.
        local g, p = {}, {};
        for line in (golden .. "\n"):gmatch("([^\n]*)\n") do g[#g + 1] = line; end
        for line in (produced .. "\n"):gmatch("([^\n]*)\n") do p[#p + 1] = line; end
        for i = 1, math.max(#g, #p) do
            if (g[i] ~= p[i]) then
                error(string.format("line %d\n  golden: %s\n  now:    %s",
                    i, tostring(g[i]), tostring(p[i])), 0);
            end
        end
        error("the two differ but no line does -- trailing bytes?", 0);
    end);

    return T;
end
