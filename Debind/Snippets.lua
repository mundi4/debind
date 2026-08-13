local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

-- `string.format`, not the `format` global. The same one in the game, but this file is also run
-- by `tools/` under a shim that has no WoW globals -- and until a probe with a live form appeared
-- in a baked body, no call site here was ever reached from the tools to say so.
local format = string.format;

--- Marks which lines *begin* in code, as opposed to beginning inside something that started on
--- an earlier line -- a long string or a long comment.
---
--- `StripSnippetComments` needs exactly this and nothing more. Deciding line by line, it cannot
--- otherwise tell a comment from a line of long-string content that happens to open with `--`,
--- and emptying the latter corrupts the body silently. Scanning for `[[` in the raw text is not
--- a substitute: `-- [[` is an ordinary comment by Lua's rule, since a long bracket only opens
--- one when it follows `--` immediately, and a scan without context reads it as a string that
--- never closes.
---
--- Short strings are tracked too, so a `"--"` inside one cannot be mistaken for a comment.
--- An unterminated one gives up at the newline rather than swallowing the rest of the body.
local function codeLineStarts(str)
	local starts = { [1] = true };
	local line = 1;
	local i, n = 1, #str;

	local function crossNewline(isCode)
		line = line + 1;
		starts[line] = isCode;
	end

	--- Skips a long bracket from its opener, marking every line inside it as not code.
	--- An unclosed one runs to the end, which is what the game would see too.
	local function skipLongBracket(from, eqs)
		local close = "]" .. eqs .. "]";
		local ce = str:find(close, from, true);
		local stop = ce and (ce + #close) or (n + 1);

		for k = from, stop - 1 do
			if (str:sub(k, k) == "\n") then crossNewline(false); end
		end

		return stop;
	end

	while (i <= n) do
		local c = str:sub(i, i);

		if (c == "\n") then
			crossNewline(true);
			i = i + 1;

		elseif (c == "-" and str:sub(i + 1, i + 1) == "-") then
			local eqs = str:match("^%[(=*)%[", i + 2);
			if (eqs) then
				i = skipLongBracket(i + 2, eqs);
			else
				-- To end of line. The newline itself is left for the next round so the line
				-- after a comment is still marked as starting in code.
				i = str:find("\n", i, true) or (n + 1);
			end

		elseif (c == "[") then
			local eqs = str:match("^%[(=*)%[", i);
			i = eqs and skipLongBracket(i, eqs) or (i + 1);

		elseif (c == '"' or c == "'") then
			i = i + 1;
			while (i <= n) do
				local d = str:sub(i, i);
				if (d == "\\") then
					i = i + 2;
				elseif (d == c) then
					i = i + 1;
					break;
				elseif (d == "\n") then
					break;
				else
					i = i + 1;
				end
			end

		else
			i = i + 1;
		end
	end

	return starts;
end

--- Drops comment text from a snippet body. **Line-leading comments only** -- a trailing
--- `x = a -- why` would need to know whether the `--` is inside a string literal, and getting
--- that wrong corrupts a body silently. Every comment in these bodies already starts its line.
---
--- The line itself stays, emptied. Dropping it would shift every line after it, and the line
--- numbers a snippet reports on error are the only handle there is for locating a fault inside
--- one. Only the text goes.
---
--- Stripping runs **before** substitution, which is what keeps two hazards from existing at
--- all: a comment mentioning a token would otherwise be substituted, and a replacement longer
--- than one line would otherwise spill out of the comment it landed in and become code.
---
--- Exposed rather than local because `tools/check-snippet-golden.js` calls this exact function
--- through fengari. That tool locks what the game receives, so a second copy of this rule in
--- JavaScript would be a copy that can drift -- and it would drift silently, since the tool
--- would then be guarding something other than what gets baked.
function DebindPrivate.StripSnippetComments(str)
	local starts = codeLineStarts(str);
	local out = {};
	local pos, len, no = 1, #str, 1;

	while (pos <= len) do
		local nl = str:find("\n", pos, true);
		local line = str:sub(pos, nl and nl - 1 or len);
		local rest = starts[no] and line:match("^[ \t]*%-%-(.*)$");

		if (rest) then
			-- A long comment opening the line would have its `--[[` emptied while the body it
			-- opened stays, leaving that text and a stray `]]` behind as code. Only the opener
			-- is on this line, so there is nothing to check further in; refuse it outright.
			assert(not rest:match("^%[=*%["),
				"long-bracket comment starting a snippet line - write it as plain `--` lines");
			out[#out + 1] = "";
		else
			out[#out + 1] = line;
		end

		no = no + 1;
		if (not nl) then break; end
		pos = nl + 1;
	end

	return table.concat(out, "\n");
end

--- Snippet bodies are strings, so anything the restricted environment cannot reach has to be
--- folded in before the body is handed to `SetAttribute`. This is where that folding lives.
---
--- It sits here rather than in `SecureBindings.lua` because `UpdateBindings.lua` generates
--- snippet text too, and both have to fold the same way from the same table.
---
--- **반드시 값 하나만 돌려준다.** `gsub`은 (문자열, 치환횟수)를 주는데, 그걸 그대로 흘리면
--- 마지막 인자 자리에서 남는 값이 다음 매개변수로 들어간다. `SetAttribute(name, body)`는
--- 남는 인자를 무시해서 표가 안 났지만, `SecureHandlerWrapScript(f, script, header, preBody,
--- postBody)`에서는 치환 횟수가 postBody가 되어 "Invalid post-handler body"로 터진다.
--- 그리고 그 오류는 **파일의 나머지를 통째로 중단시킨다** - 뒤따르는 속성들이 전부 정의되지
--- 않은 채로 게임이 계속 돌아서, 증상이 엉뚱한 곳(FrameRegistry의 OnEnter 래핑)에서 난다.
--- What each `PROBE.<name>(...)` becomes in a shipped build.
---
--- The point of writing them as probes at all is that they are **the plain call and nothing
--- else** once baked. A body carrying `PROBE.UnitExists(unit)` produces the same bytes as one
--- that always said `UnitExists(unit)`; `tools/snippet-golden.txt` is what holds that to it.
---
--- A name mapping to `false` disappears entirely, which is how a probe that only exists to report
--- something outward costs a real user nothing at all -- not a check that fails, not a table
--- lookup that misses, no line.
DebindPrivate.SNIPPET_PROBES_LIVE = {
	UnitExists = "UnitExists(%s)",
	PlayerCanAssist = "PlayerCanAssist(%s)",
	PlayerCanAttack = "PlayerCanAttack(%s)",
	PlayerIsChanneling = "PlayerIsChanneling(%s)",
	SecureCmdOptionParse = "SecureCmdOptionParse(%s)",

	-- Reporting only. Nothing is computed from it, so there is nothing to keep.
	Winner = false,

	-- Injection only. The click path measures its own axes now, and a test that wants to say
	-- "you are in combat" has to reach the value between the measurement and the comparison --
	-- writing into `States` does not hold, because the click measures again rather than reading
	-- it. Absent here, so a real user's snippet has no table to miss and no branch to fail.
	MockState = false,
};

--- Replaces the `PROBE.<name>(args)` tokens.
---
--- Arguments are taken as far as the first `)`, which is all these ever need and keeps the
--- substitution a regular one. A nested call would simply not match, and the leftover token is
--- caught below rather than compiled into a snippet that fails somewhere else.
local function applyProbes(str, table_)
	local result = str:gsub("PROBE%.([_A-Za-z0-9]+)%(([^()]*)%)", function(name, args)
		local form = table_[name];
		assert(form ~= nil, "unknown probe: " .. name);
		if (form == false) then
			return "";
		end
		return format(form, args);
	end);

	assert(not result:find("PROBE%.", 1, false),
		"a PROBE token survived substitution - nested parentheses in its arguments?");

	return result;
end

-- Exposed for `tools/check-snippet-golden.js`, which bakes every body with the live table to see
-- that a probe changes nothing. A second copy of this rule in JavaScript could drift, and a
-- drifted one would be guarding something other than what gets baked.
DebindPrivate.applyProbesForTools = applyProbes;

-- Raw bodies kept alongside the thing that installs them, so a body can be baked again later.
--
-- Bodies are baked while this addon loads, which is before anything that might want a probe
-- turned on has loaded at all -- a dependency loads after what it depends on, and there is no
-- ordering that puts it first. So the choice cannot be made once at bake time; the bodies have to
-- remain re-bakeable.
--
-- That is also the strongest form of the switch. Turning probes off is not "read an empty table"
-- but a rebuild with the live table, which produces the bytes a real user runs -- the same test
-- can be run against code that has no probes in it at all.
local rebakeable = {};

--- Bakes each body and hands them all to `install`, keeping them so it can be done again.
---
--- Takes several because `SecureHandlerWrapScript` has two -- a pre and a post -- and both are
--- snippets. `install` receives the baked texts in order. Everything a rebake needs is captured
--- in that closure, so the registry does not need to know what kind of destination it is: an
--- attribute, a wrapped script, or something that does not exist yet.
function DebindPrivate.InstallSnippet(install, ...)
	local bodies = { ... };
	rebakeable[#rebakeable + 1] = { install = install, bodies = bodies };

	local baked = {};
	for i = 1, #bodies do
		baked[i] = DebindPrivate.BakeSnippet(bodies[i]);
	end
	install(unpack(baked));
end

--- Bakes every registered body again with whatever table is current.
---
--- Out of combat only, which costs nothing: the environment this exists to drive is one where the
--- client is never actually in combat.
function DebindPrivate.RebakeSnippets()
	if (InCombatLockdown()) then
		return false, "in combat";
	end

	for i = 1, #rebakeable do
		local entry = rebakeable[i];
		local baked = {};
		for j = 1, #entry.bodies do
			baked[j] = DebindPrivate.BakeSnippet(entry.bodies[j]);
		end
		entry.install(unpack(baked));
	end

	return true;
end

function DebindPrivate.BakeSnippet(str)
	local probes = (DebindPrivate.SnippetProbes and DebindPrivate.SnippetProbes.expand)
		or DebindPrivate.SNIPPET_PROBES_LIVE;

	local result = applyProbes(DebindPrivate.StripSnippetComments(str), probes)
		:gsub("CONSTANTS%.([_A-Za-z0-9]+)", function(m)
		local value = Constants[m];
		assert(value ~= nil, m);
		if (type(value) == "string") then
			return format("%q", value);
		else
			return tostring(value);
		end
	end);
	return result;
end
