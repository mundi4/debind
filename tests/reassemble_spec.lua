-- **Standing on top of another addon's wrappers.** WoW client not needed.
--
-- The client runs only the outermost `OnLeave` body -- `Wrapped_OnLeave` clears `_wrapentered`
-- before it descends -- so an addon that wraps a frame after us takes our leave away and our hover
-- slot outlives the cursor. What closes that is taking the top back: everything that came off goes
-- straight back on in the order it was in, ours goes on top of it, and only the leave body the
-- client can no longer reach is run by us.
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

    --- A second addon. **Two wrappers under one header are the shape a reassembly collapses**, so
    --- a case about several bodies on one script has to spread them across headers to be about
    --- several addons rather than about one addon's stale copy.
    local alsoTheirs = frames.newFrame("Frame", "ReassembleOtherHeader", nil,
        "SecureHandlerBaseTemplate");
    local thirdTheirs = frames.newFrame("Frame", "ReassembleThirdHeader", nil,
        "SecureHandlerBaseTemplate");

    --- One of their bodies, writing a letter into a global of their own. Reading the order back as
    --- a string is what makes "all of them, outermost first" and "only the first one" separate
    --- answers rather than two counts.
    ---
    --- **The letter also goes on the frame**, because a body running in another header's
    --- environment writes another header's global, and a case that spans two of them has no one
    --- environment to read the order out of.
    local function say(letter, extra)
        return "self:SetAttribute(\"debind_log\", (self:GetAttribute(\"debind_log\") or \"\") .. \""
            .. letter .. "\")\n"
            .. "their_log = their_log .. \"" .. letter .. "\"\n" .. (extra or "");
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
        rawset(interp:envFor(alsoTheirs), "their_log", "");
        rawset(interp:envFor(thirdTheirs), "their_log", "");
    end

    --- The order several bodies ran in, read off the frame they ran on. **The one reader that
    --- spans headers**, since a body writes the global of the environment it runs in and two
    --- addons have two of those.
    local function frameLog(frame)
        return (frame.__attributes and frame.__attributes["debind_log"]) or "";
    end

    local function resetFrameLog(frame)
        if (frame.__attributes) then
            frame.__attributes["debind_log"] = nil;
        end
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
    local clickFrame = newFrame();
    local growFrame = newFrame();
    local dropFrame = newFrame();
    local loopFrame = newFrame();

    for _, frame in ipairs({ leaveFrame, envFrame, orderFrame, refuseFrame, messageFrame,
            unwrapFrame, contestedFrame, clickFrame, growFrame, dropFrame, loopFrame }) do
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
                conditions = { units = { unitframe = {} } } }) },
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
    local function theyWrap(frame, script, pre, post, header)
        local mark = frames.mark();
        _G.SecureHandlerWrapScript(frame, script, header or theirs, pre, post);
        interp:replay(frames.since(mark));
    end

    local function theyUnwrap(frame, script)
        local mark = frames.mark();
        _G.SecureHandlerUnwrapScript(frame, script);
        interp:replay(frames.since(mark));
    end

    --- The tick our own re-topping waits for. **Replayed like any other pass**, because the
    --- reassembly it runs is what hands the restricted side its leave copy.
    local function nextTick()
        local mark = frames.mark();
        frames.drainTimers();
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
        return interp.env.UnitAliasMap.unitframe;
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
    --- outermost on both scripts again, and what they wrapped is still on the frame underneath.
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
        check(#chain == 2, ("%d wrappers left on OnEnter, not two"):format(#chain));
        check(chain[2].header == theirs, "theirs is not back under ours");

        --- And theirs still runs -- in **their** environment, which is what being a wrapper of
        --- their own buys them. A global they write is theirs; the driver's environment never
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

    --- **Enter is the chain's own work and leave is ours.** Every enter body is back where it was,
    --- so the client runs them outermost first the way it always did; of the leave bodies exactly
    --- one ever ran, because the client clears `_wrapentered` in the outermost and every one below
    --- reads it to decide whether to run at all. That one is the only body we run ourselves, and
    --- running the rest would be inventing behaviour that frame never had.
    test("enter runs all of them in order and only the outermost leave runs", function()
        local i = Bind();
        resetFrameLog(orderFrame);
        orderFrame:SetAttribute("unit", "party1");

        -- The last one wrapped is the outermost, so the client would have run B then A.
        theyWrap(orderFrame, "OnEnter", say("A"));
        theyWrap(orderFrame, "OnEnter", say("B"), nil, alsoTheirs);
        theyWrap(orderFrame, "OnLeave", say("y"));
        theyWrap(orderFrame, "OnLeave", say("z"), nil, alsoTheirs);

        i:hoverEnter(orderFrame);
        check(frameLog(orderFrame) == "BA",
            ("their enter bodies ran as %s, not BA"):format(frameLog(orderFrame)));

        i:hoverLeave(orderFrame);
        check(frameLog(orderFrame) == "BAz",
            ("their leave bodies ran as %s -- only the outermost ever did"):format(
                frameLog(orderFrame)));
        check(hovered() == nil, "our own leave did not run underneath theirs");
    end);

    --- **`false` from one of them stops everything below it and nothing above it**, which is what
    --- the client does with a chain: `Wrapped_OnEnter` returns without descending. We are above all
    --- of them, so the one thing a refusal down there cannot take is our own body.
    ---
    --- The one that refused gets no post body either -- the client returns before reaching it --
    --- while the ones above it are owed theirs and get them on the way out.
    test("a false from one of them stops the ones below it and not us", function()
        local i = Bind();
        resetFrameLog(refuseFrame);
        refuseFrame:SetAttribute("unit", "party1");

        theyWrap(refuseFrame, "OnEnter", say("A"));
        theyWrap(refuseFrame, "OnEnter", say("B", "return false\n"), say("b"), alsoTheirs);
        theyWrap(refuseFrame, "OnEnter", say("C", "return nil, \"m\"\n"), say("c"), thirdTheirs);

        i:hoverEnter(refuseFrame);
        check(frameLog(refuseFrame) == "CBc",
            ("their bodies ran as %s, not CBc"):format(frameLog(refuseFrame)));
        check(hovered() == "party1",
            ("a refusal below us took our own enter with it: the slot holds %s"):format(
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

    --- **An unwrap says nothing about who asked**, so it is passed on rather than read.
    --- `SecureHandlerUnwrapScript(frame, script)` carries no header; when the top comes off a frame
    --- of ours all that is known is that the top was ours and that the wrapper the call meant to
    --- take is still there. Taking their outermost as well is what that call would have done had we
    --- never been on the frame, which is the only answer the arguments allow.
    test("their unwrap is passed on to the wrapper it meant to take", function()
        local i = Bind();
        resetFrameLog(unwrapFrame);
        unwrapFrame:SetAttribute("unit", "party1");

        theyWrap(unwrapFrame, "OnEnter", say("A"));
        theyWrap(unwrapFrame, "OnEnter", say("B"), nil, alsoTheirs);

        theyUnwrap(unwrapFrame, "OnEnter");
        nextTick();

        check(topHeader(unwrapFrame, "OnEnter") == DRIVER,
            "after their unwrap the outermost wrapper is "
                .. topHeader(unwrapFrame, "OnEnter"));

        i:hoverEnter(unwrapFrame);
        check(frameLog(unwrapFrame) == "A",
            ("their bodies ran as %s -- B is the one their call was taking"):format(
                frameLog(unwrapFrame)));
        check(hovered() == "party1",
            ("our own enter stopped working too: the slot holds %s"):format(tostring(hovered())));
    end);

    --- **An unwrap nobody follows with a wrap stops their body**, which is what an addon taking a
    --- frame back asks for: Clique's `UnregisterFrame` unwraps both motion scripts and never wraps
    --- again. The leave half also has to clear the copy we hold, or the body would go on running
    --- out of our own wrapper.
    test("an unwrap with no wrap after it stops their bodies", function()
        local i = Bind();
        resetFrameLog(dropFrame);
        dropFrame:SetAttribute("unit", "party1");

        theyWrap(dropFrame, "OnEnter", say("A"));
        theyWrap(dropFrame, "OnLeave", say("L"));

        theyUnwrap(dropFrame, "OnEnter");
        theyUnwrap(dropFrame, "OnLeave");
        nextTick();

        check(#frames.wrapperChain(dropFrame, "OnEnter") == 1,
            ("%d wrappers left on OnEnter, not just ours"):format(
                #frames.wrapperChain(dropFrame, "OnEnter")));

        i:hoverEnter(dropFrame);
        i:hoverLeave(dropFrame);
        check(frameLog(dropFrame) == "",
            ("they took the frame back and %s still ran"):format(frameLog(dropFrame)));
        check(hovered() == nil, "our own leave stopped working too");
    end);

    --- **An engine that unwraps until the chain is empty must be able to reach empty.** Going back
    --- on top inside the hook would hand it ours on every pass and the loop would never end.
    test("an engine unwrapping until the chain is empty gets there", function()
        local i = Bind();
        resetFrameLog(loopFrame);

        theyWrap(loopFrame, "OnEnter", say("A"));

        local passes = 0;
        while (#frames.wrapperChain(loopFrame, "OnEnter") > 0) do
            passes = passes + 1;
            check(passes <= 10, "the chain never emptied: we kept putting ours back");
            theyUnwrap(loopFrame, "OnEnter");
        end

        nextTick();
        check(topHeader(loopFrame, "OnEnter") == DRIVER,
            "we did not come back after the loop ended: the top is "
                .. topHeader(loopFrame, "OnEnter"));
        check(#frames.wrapperChain(loopFrame, "OnEnter") == 1,
            "we came back onto a chain that is not just ours");

        loopFrame:SetAttribute("unit", "party1");
        i:hoverEnter(loopFrame);
        check(hovered() == "party1", "our own enter did not come back");
    end);

    --- **An engine replacing its own wrapper must not leave the old one behind.** Changing what a
    --- wrapper runs means unwrapping and wrapping again, because a body is fixed when it is
    --- wrapped; Clique's `ApplyAttributes` does it on every combat transition and every binding
    --- change. With us on top the unwrap half takes ours instead of theirs, so what they meant to
    --- replace is still on the frame -- and putting it back would add one link per pass.
    test("an engine replacing its own wrapper does not lengthen the chain", function()
        local i = Bind();
        resetLog();
        growFrame:SetAttribute("unit", "party1");

        theyWrap(growFrame, "OnEnter", say("A"));

        -- One of their replacement passes: the unwrap takes ours, the wrap brings the new body.
        for _ = 1, 3 do
            theyUnwrap(growFrame, "OnEnter");
            theyWrap(growFrame, "OnEnter", say("B"));
        end

        local chain = frames.wrapperChain(growFrame, "OnEnter");
        check(#chain == 2, ("the chain is %d long after three passes, not two"):format(#chain));

        i:hoverEnter(growFrame);
        check(theirLog() == "B",
            ("their bodies ran as %s -- a replaced one is still on the frame"):format(
                tostring(theirLog())));
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

        check(DebindPrivate.ccframes[contestedFrame] == false,
            "we kept fighting for a frame another engine keeps taking back");

        --- **And the frame still works for them**, which is the whole reason for standing down
        --- rather than for anything else. Ours is the side that gives up.
        i:hoverEnter(contestedFrame);
        check(theirLog() ~= "", "we stood down and took their body with us");
    end);

    ---------------------------------------------------------------------------
    -- What a replayed body is given
    ---------------------------------------------------------------------------

    -- **A click pre body is compiled with `self, button, down`**, which is why our own body in
    -- `SecureBindings.lua` reads `button` with nothing declaring it. Leaving theirs in the chain is
    -- what keeps those names theirs; running it any other way would hand it `self, ...` and put
    -- every name it uses one place out.
    --
    -- **Nothing raises when that is wrong.** A pre body is where a pack refuses a click or renames
    -- the button; reading a nil global there means the branch never runs, and their click casting
    -- stops on every frame we hold with no error anywhere.
    test("their click pre body is given the button the client compiled it with", function()
        local i = Bind();
        resetLog();

        theyWrap(clickFrame, "OnClick", [[
            if (button == "RightButton") then their_log = their_log .. "R" end
            if (down == false) then their_log = their_log .. "u" end
        ]]);

        i:runWrapped(clickFrame, "OnClick", "RightButton", false);
        check(theirLog() == "Ru", "their body read: " .. theirLog());

        -- The other button reaches them too, so what is measured above is the value and not
        -- merely that something ran.
        resetLog();
        i:runWrapped(clickFrame, "OnClick", "LeftButton", false);
        check(theirLog() == "u", "their body saw the wrong button: " .. theirLog());
    end);

    return T;
end
