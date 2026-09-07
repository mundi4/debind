-- **Standing on top of another addon's wrappers.** WoW client not needed.
--
-- The client runs only the outermost `OnLeave` body -- `Wrapped_OnLeave` clears `_wrapentered`
-- before it descends -- so an addon that wraps a frame after us takes our leave away and our hover
-- slot outlives the cursor. What closes that is taking the top back and replaying what we took,
-- and every rule of that replay is measured here.
--
-- `tests/wow_frames.lua` keeps the wrapper chain and `tests/restricted.lua` walks it, so a case
-- below drives the same order the client would.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

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

    local GUID = "Player-1-REASSEMBLE";

    ---------------------------------------------------------------------------
    -- The other addon
    ---------------------------------------------------------------------------

    --- Their header. Its bodies run in **its** managed environment, not the driver's, which is
    --- what `RunFor` on their handle is for and what the log below is read out of.
    local theirs = frames.newFrame("Frame", "ReassembleTheirHeader", nil,
        "SecureHandlerBaseTemplate");

    --- One of their bodies, writing a letter into a global of their own. Reading the order back as
    --- a string is what makes "all of them, outermost first" and "only the first one" separate
    --- answers rather than two counts.
    local function say(letter, extra)
        return "their_log = their_log .. \"" .. letter .. "\"\n" .. (extra or "");
    end

    local interp;

    local function theirLog()
        return rawget(interp:envFor(theirs), "their_log");
    end

    --- Their environment carries across cases the way it would across a session, so each case
    --- opens the log itself. It is a real global of theirs, which is also why the bodies can
    --- append to it without the environment raising on an unset name.
    local function resetLog()
        rawset(interp:envFor(theirs), "their_log", "");
    end

    --- The frames the cases below register. **All of them before the first rebuild**, because the
    --- interpreter is stood up on what has been recorded by then and fed each rebuild after.
    local function newFrame()
        local frame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
        DebindPrivate.RegisterFrame(frame, "group");
        return frame;
    end

    local leaveFrame = newFrame();
    local envFrame = newFrame();
    local orderFrame = newFrame();
    local refuseFrame = newFrame();
    local messageFrame = newFrame();
    local unwrapFrame = newFrame();
    local contestedFrame = newFrame();

    for _, frame in ipairs({ leaveFrame, envFrame, orderFrame, refuseFrame, messageFrame,
            unwrapFrame, contestedFrame }) do
        if (type(DebindPrivate.ccframes[frame]) ~= "table") then
            T.failures[#T.failures + 1] = "setup: RegisterFrame did not take a test frame";
            return T;
        end
    end

    local seq = 0;
    local function action(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.seq = seq;
        return t;
    end

    --- A profile with one binding that reads the hovered unit, so filling and emptying the hover
    --- slot is something a case can see.
    local function Bind()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.units = {
            party1 = { id = "p1", reaction = "help", inParty = true },
        };

        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = { action({ value = 585, key = "F1",
                conditions = { units = { hover = {} } } }) },
                classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();

        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild was refused");

        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world);
        else
            interp:replay(frames.since(mark));
        end
        interp:resetState();
        return interp;
    end

    --- Wraps one of their bodies onto a frame, and feeds the restricted side whatever the
    --- reassembly that follows handed it.
    local function theyWrap(frame, script, pre, post)
        local mark = frames.mark();
        _G.SecureHandlerWrapScript(frame, script, theirs, pre, post);
        interp:replay(frames.since(mark));
    end

    local function theyUnwrap(frame, script)
        local mark = frames.mark();
        _G.SecureHandlerUnwrapScript(frame, script);
        interp:replay(frames.since(mark));
    end

    --- Who is outermost on that script now, by name.
    local function topHeader(frame, script)
        local chain = frames.wrapperChain(frame, script);
        local entry = chain and chain[1];
        if (not entry) then
            return "<nothing>";
        end
        return entry.header:GetName() or "<unnamed>";
    end

    local DRIVER = DebindPrivate.BindingDriver:GetName() or "<unnamed>";

    local function hovered()
        return interp.env.UnitAliasMap.hover;
    end

    ---------------------------------------------------------------------------
    -- The top
    ---------------------------------------------------------------------------

    --- **This is the whole reason the track was reopened.** `Wrapped_OnLeave` runs the outermost
    --- pre body and nothing below it, so before this an addon wrapping after us took our leave and
    --- the hover slot stayed on a frame the cursor had left. Taking the top back is what answers
    --- it, and the cursor arriving and leaving is where that shows.
    test("an addon wrapping after us does not take our leave away", function()
        local i = Bind();
        resetLog();
        leaveFrame:SetAttribute("unit", "party1");

        theyWrap(leaveFrame, "OnEnter", say("E"));
        theyWrap(leaveFrame, "OnLeave", say("L"));

        i:hoverEnter(leaveFrame);
        check(hovered() == "party1",
            ("the premise is gone: after enter the slot holds %s"):format(tostring(hovered())));

        i:hoverLeave(leaveFrame);
        check(hovered() == nil,
            ("the cursor left and the slot still holds %s"):format(tostring(hovered())));
    end);

    --- The structural half of the same thing, and the one that says *how* it was answered: we are
    --- outermost on both scripts again, and what they wrapped is not on the frame at all any more.
    test("we are outermost again on every script they wrapped", function()
        local i = Bind();
        resetLog();
        theyWrap(envFrame, "OnEnter", say("E"));
        theyWrap(envFrame, "OnLeave", say("L"));

        check(topHeader(envFrame, "OnEnter") == DRIVER,
            "OnEnter's outermost wrapper is " .. topHeader(envFrame, "OnEnter"));
        check(topHeader(envFrame, "OnLeave") == DRIVER,
            "OnLeave's outermost wrapper is " .. topHeader(envFrame, "OnLeave"));

        local chain = frames.wrapperChain(envFrame, "OnEnter");
        check(#chain == 1, ("%d wrappers left on OnEnter, not one"):format(#chain));

        --- And what we took still runs -- in **their** environment, which is what `RunFor` on
        --- their own header buys. A global they write is theirs; the driver's environment never
        --- hears about it, and would raise on the read.
        envFrame:SetAttribute("unit", "party1");
        i:hoverEnter(envFrame);
        check(theirLog() == "E",
            ("their enter body left %s in their own environment"):format(tostring(theirLog())));
        check(rawget(i.env, "their_log") == nil,
            "their global landed in the driver's environment");
    end);

    ---------------------------------------------------------------------------
    -- What gets replayed, and in what order
    ---------------------------------------------------------------------------

    --- **Enter takes all of them, leave takes one.** Every enter pre body above us ran before we
    --- arrived, outermost first; of the leave bodies exactly one ever did, because the client
    --- clears `_wrapentered` in the outermost and every one below reads it to decide whether to
    --- run at all. Replaying the rest would be inventing behaviour that frame never had.
    test("enter replays all of them in order and leave replays only the outermost", function()
        local i = Bind();
        resetLog();
        orderFrame:SetAttribute("unit", "party1");

        -- The last one wrapped is the outermost, so the client would have run B then A.
        theyWrap(orderFrame, "OnEnter", say("A"));
        theyWrap(orderFrame, "OnEnter", say("B"));
        theyWrap(orderFrame, "OnLeave", say("y"));
        theyWrap(orderFrame, "OnLeave", say("z"));

        i:hoverEnter(orderFrame);
        check(theirLog() == "BA",
            ("their enter bodies ran as %s, not BA"):format(tostring(theirLog())));

        i:hoverLeave(orderFrame);
        check(theirLog() == "BAz",
            ("their leave bodies ran as %s -- only the outermost ever did"):format(
                tostring(theirLog())));
        check(hovered() == nil, "our own leave did not run underneath theirs");
    end);

    --- **`false` from one of them stops everything below it**, which is what the client does:
    --- `Wrapped_OnEnter` returns without descending, so neither the entries under it nor the
    --- frame's own handler run. Ours is one of the things under it.
    ---
    --- The one that refused gets no post body either -- the client returns before reaching it --
    --- while the ones above it are owed theirs and get them on the way out.
    test("a false from one of them stops the ones below it and stops us", function()
        local i = Bind();
        resetLog();
        refuseFrame:SetAttribute("unit", "party1");

        theyWrap(refuseFrame, "OnEnter", say("A"));
        theyWrap(refuseFrame, "OnEnter", say("B", "return false\n"), say("b"));
        theyWrap(refuseFrame, "OnEnter", say("C", "return nil, \"m\"\n"), say("c"));

        i:hoverEnter(refuseFrame);
        check(theirLog() == "CBc",
            ("their bodies ran as %s, not CBc"):format(tostring(theirLog())));
        check(hovered() == nil,
            ("they refused the enter and we filled the slot with %s anyway"):format(
                tostring(hovered())));
    end);

    --- **A post body runs on the value its own pre answered with.** The client keeps that value
    --- per wrapper and passes it back as `message`, and it is also the switch: a pre that answers
    --- nothing gets no post at all.
    test("a post body is handed the message its own pre answered with", function()
        local i = Bind();
        resetLog();
        messageFrame:SetAttribute("unit", "party1");

        theyWrap(messageFrame, "OnEnter",
            "their_log = \"pre\"\nreturn nil, \"carried\"\n",
            "their_log = their_log .. \":\" .. tostring(message)\n");

        i:hoverEnter(messageFrame);
        check(theirLog() == "pre:carried",
            ("their post body saw %s"):format(tostring(theirLog())));
    end);

    ---------------------------------------------------------------------------
    -- When they take a wrapper off
    ---------------------------------------------------------------------------

    --- **An unwrap says nothing about who asked.** `SecureHandlerUnwrapScript(frame, script)`
    --- carries no header, so when the top comes off a frame of ours all that is known is that the
    --- top was ours. We put ourselves back on whatever is left -- and where they had nothing else
    --- on the frame, what is left is nothing, so their bodies stop. That is what they asked for.
    test("their unwrap stops their bodies and leaves us on top", function()
        local i = Bind();
        resetLog();
        unwrapFrame:SetAttribute("unit", "party1");

        theyWrap(unwrapFrame, "OnEnter", say("A"));
        theyWrap(unwrapFrame, "OnEnter", say("B"));

        theyUnwrap(unwrapFrame, "OnEnter");

        check(topHeader(unwrapFrame, "OnEnter") == DRIVER,
            "after their unwrap the outermost wrapper is "
                .. topHeader(unwrapFrame, "OnEnter"));

        i:hoverEnter(unwrapFrame);
        check(theirLog() == "",
            ("they turned their wrapping off and %s still ran"):format(tostring(theirLog())));
        check(hovered() == "party1",
            ("our own enter stopped working too: the slot holds %s"):format(tostring(hovered())));
    end);

    ---------------------------------------------------------------------------
    -- An engine that takes the top back
    ---------------------------------------------------------------------------

    --- **Two engines that both re-wrap on being wrapped over never settle**, and they do not
    --- settle *on the call stack* -- each pass is a nested call, so what it costs is depth rather
    --- than time. So the frame is given up the moment the second pass arrives inside the first.
    ---
    --- The competitor here is written the way one would actually behave: it wraps again whenever
    --- it sees somebody else's header go on that frame.
    test("a frame another engine keeps taking back is given up", function()
        local i = Bind();
        resetLog();
        contestedFrame:SetAttribute("unit", "party1");

        local fighting = false;
        local mark = frames.mark();
        hooksecurefunc("SecureHandlerWrapScript", function(frame, script, header)
            if (frame ~= contestedFrame or script ~= "OnEnter" or header == theirs) then
                return;
            end
            if (fighting) then
                return;
            end
            fighting = true;
            _G.SecureHandlerWrapScript(frame, script, theirs, say("R"));
            fighting = false;
        end);

        _G.SecureHandlerWrapScript(contestedFrame, "OnEnter", theirs, say("R"));
        interp:replay(frames.since(mark));

        check(DebindPrivate.ccframes[contestedFrame] == nil,
            "we kept fighting for a frame another engine keeps taking back");

        --- **And the frame still works for them**, which is the whole reason for standing down
        --- rather than for anything else. Ours is the side that gives up.
        i:hoverEnter(contestedFrame);
        check(theirLog() ~= "", "we stood down and took their body with us");
    end);

    return T;
end
