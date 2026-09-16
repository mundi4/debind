local _, DebindPrivate = ...;

--- **The tooltip an action gets, wherever it is drawn.**
---
--- Five lists hover over rows that hold an action, and every one of them puts up the same block:
--- what it is, which key it is on, what it is waiting on, what narrows it. That is a long block, and
--- one copy of it is the only way the answer stays the same when the reader looks at the same action
--- from two of those lists (`sharing-one-action-tooltip.md`, which built it).
---
--- **It takes the tooltip frame as an argument and knows nothing else about the screen.** No window,
--- no column, no list. What it needs to say is a function of the action and the key map, and the
--- lists that were reaching into `DebindUI.lua` for it were reaching through the overview window to
--- get at something the overview does not own (`breaking-up-debindui.md`, "창보다 위로 올릴 것").
local Constants              = DebindPrivate.Constants;
local LLL                    = DebindPrivate.L;
local DebindUI               = DebindPrivate.DebindUI;

local GetBindingIssue        = DebindPrivate.GetBindingIssue;
local IsUnreachableAction    = DebindPrivate.IsUnreachableAction;
local GetSpellNameAndIconID  = DebindPrivate.GetSpellNameAndIconID;

local DISABLED_FONT_COLOR    = _G.DISABLED_FONT_COLOR;
local INACTIVE_COLOR         = _G.INACTIVE_COLOR;

local IMPORTED_FONT_COLOR    = DebindUI.IMPORTED_FONT_COLOR;
local UNIT_INFO              = DebindUI.UNIT_INFO;
local NameAndIconForAction   = DebindUI.NameAndIconForAction;

local UNIT_FRAME_REACTIONS = {
	"HELP",
	"HARM",
	"OTHER",
};

--- `Constants.UNITGROUP_*`의 비트 차례 그대로.
local UNIT_GROUPS          = {
	"NONE",
	"PARTY",
	"RAID",
};

--- **`Constants.ROLE_*`의 비트 차례 그대로.** `FlagNames`가 목록의 순서를 1비트, 2비트로
--- 읽으므로, 상수 쪽 차례가 바뀌면 여기도 같이 바뀌어야 한다.
local UNIT_ROLES           = {
	"TANK",
	"HEALER",
	"DAMAGER",
	"NONE",
};

local UNIT_FRAME_TYPES     = {
	"PLAYER",
	"PET",
	"GROUP",
	"TARGET",
	"BOSS",
	"ARENA",
	"UNKNOWN",
};

local GetActionBarTypeLabel;
do
	local _bonusbarLabels;
	function GetActionBarTypeLabel(index)
		if (_bonusbarLabels == nil) then
			_bonusbarLabels = {
				[0] = LLL["DEFAULT"],
				[5] = GetFlyoutInfo(229),
			};
			if (Constants.PLAYER_CLASS == "DRUID") then
				_bonusbarLabels[1] = GetSpellNameAndIconID(768);
				_bonusbarLabels[3] = GetSpellNameAndIconID(5487);
				_bonusbarLabels[4] = GetSpellNameAndIconID(24858);
			elseif (Constants.PLAYER_CLASS == "ROGUE") then
				_bonusbarLabels[1] = GetSpellNameAndIconID(1784);
			end
			for i = 0, Constants.MAX_BONUSBAR_OFFSET do
				local text = _bonusbarLabels[i];
				_bonusbarLabels[i] = format("[bonusbar:%d]", i);
				if (text) then
					_bonusbarLabels[i] = format("%s (%s)", _bonusbarLabels[i], text);
				end
			end
		end
		return _bonusbarLabels[index];
	end
end

local AddActionToTooltip, HideActionTooltip;
do
	local _lines = {};
	--- 스위치 조건 줄을 이름순으로 세우는 자리. `_lines`와 나누는 이유는 그쪽이
	--- `addValueLines` 안에서 비워지며 돌기 때문이다.
	local _switchNames = {};
	local LEFT_OFFSET = 10;
	-- **One step in, for a line that belongs to the line above it.** Two things use it. The reason a
	-- value is red, which is red itself because the sentence is about a fault and gold would read as
	-- a second value, so the step is the only thing left to tell the setting from the explanation.
	-- And the axes one unit condition narrows, which would otherwise stand level with the units
	-- themselves and stop saying whose they are.
	--
	-- The reason used to be bracketed instead, which put one sentence in two shapes: a reason that
	-- belongs to a whole block goes up under the label with no bracket.
	local INDENT_STEP = 10;

	--- Stands in for a caller that passes nothing, so the reads below need no guard. Never
	--- written to: the entry point only reads fields off it.
	local EMPTY_OPTS = {};
	--- 조건이 하나도 없는 액션을 위한 빈 표. `EMPTY_OPTS`를 같이 쓰지 않는 것은 그 이름이
	--- 옵션을 말하기 때문이다 - 둘 다 빈 표라는 것은 우연이다.
	local EMPTY_CONDITIONS = {};

	--- Drawing order for the group condition, which is also `Constants.GROUP_*`'s bit order.
	--- Built once: it used to be a table literal inside the loop's `ipairs`, so a hover allocated
	--- one and threw it away.
	local GROUP_TYPES = { "NONE", "PARTY", "RAID" };

	local function addErrorLine(tooltip, message, wrap, leftOffset)
		GameTooltip_AddErrorLine(tooltip, message, wrap or false, leftOffset or LEFT_OFFSET);
	end

	local function addLabelLine(tooltip, label, hasError)
		GameTooltip_AddBlankLineToTooltip(tooltip);
		if (hasError) then
			GameTooltip_AddErrorLine(tooltip, format(LLL["LINE_TOOLTIP_CONDITION_LABEL"], label));
		else
			GameTooltip_AddHighlightLine(tooltip, format(LLL["LINE_TOOLTIP_CONDITION_LABEL"], label));
		end
	end

	--- The sentence a code prints, in the colour its grade asks for.
	---
	--- **The grade paints, never the code** (`Misc.lua`'s `GetIssueColor`). This drew every sentence
	--- red, which is the colour that says the key is dead, and the one WARNING says the opposite:
	--- the key works and one thing it was told to do is missing. The row mark, the group heading and
	--- the order flag were already asking the grade, so the tooltip was the one surface saying
	--- something else about the same state.
	local function addIssueLine(tooltip, code, wrap, leftOffset)
		GameTooltip_AddColoredLine(tooltip, LLL["BINDING_ERROR_" .. code],
			DebindPrivate.GetIssueColor(code), wrap or false, leftOffset or LEFT_OFFSET);
	end

	--- **Red on the value only where the value is the whole of the problem.** `error` as `true`
	--- says exactly that -- nothing is selected, and there is no separate sentence to print, so the
	--- value has to carry the colour itself. A code instead means the sentence goes up underneath,
	--- and then the value is a setting the reader chose with nothing wrong in it.
	local function addValueLine(tooltip, value, error, wrap, leftOffset)
		if (error == true) then
			GameTooltip_AddErrorLine(tooltip, value, wrap or false, leftOffset or LEFT_OFFSET);
		else
			GameTooltip_AddNormalLine(tooltip, value, wrap or false, leftOffset or LEFT_OFFSET);
		end
		if (type(error) == "string") then
			addIssueLine(tooltip, error, wrap, (leftOffset or LEFT_OFFSET) + INDENT_STEP);
		end
	end

	local function addValueLines(tooltip, lines, error, wrap, leftOffset)
		local fn = error == true and GameTooltip_AddErrorLine or GameTooltip_AddNormalLine;
		for i = 1, #lines do
			fn(tooltip, lines[i], wrap or false, leftOffset or LEFT_OFFSET);
		end
		if (type(error) == "string") then
			addIssueLine(tooltip, error, wrap, (leftOffset or LEFT_OFFSET) + INDENT_STEP);
		end
	end

	--- The names a mask has switched on, comma-joined onto one line.
	---
	--- **The empty mask gets a word instead of a list.** It is not a list of nothing: it is the one
	--- state nothing can satisfy, so it gets a word a reader can catch.
	---
	--- One `prefix` addresses both tables -- the flag is `Constants[prefix .. name]` and the word
	--- is `LLL[prefix .. name]` -- which holds because the two are keyed alike by construction.
	local function FlagNames(mask, names, prefix, all)
		-- **Nil for the full mask, so the caller drops the line.** All of them on filters nothing
		-- out, which is the same condition as the axis being unset: `FillBinding` folds the one
		-- into the other before a binding is built (`Misc.lua`), and `frameTypes` is not written
		-- as an attribute either (`UpdateBindings.lua`). A line for it says a condition is at work
		-- where none is.
		if (mask == all) then
			return nil;
		elseif (mask == 0) then
			return LLL["NOT_SELECTED"];
		end

		local s = "";
		for i = 1, #names do
			local flag = Constants[prefix .. names[i]];
			if (bit.band(mask, flag) == flag) then
				if (s ~= "") then
					s = s .. ", ";
				end
				s = s .. LLL[prefix .. names[i]];
			end
		end
		return s;
	end

	--- A value line that names the axis it is narrowing, in white, ahead of the value.
	---
	--- These sit **under** a condition's own label line, one per narrowed axis, so each needs to
	--- say which axis it is. The label line's shape (`LINE_TOOLTIP_CONDITION_LABEL`) is not reused:
	--- that one opens a block and this one is inside it.
	local function LabelledValue(labelKey, value)
		return format("|cnWHITE_FONT_COLOR:%s:|r %s", LLL[labelKey], value);
	end

	--- The two axes only a unit frame can answer, each on its own labelled line under the unit's.
	---
	--- **Not joined onto the unit's line like the others.** Both are lists of names long enough that
	--- a joined line wraps somewhere arbitrary.
	local function AddUnitFrameAxes(tooltip, value)
		if (type(value) ~= "table") then
			return;
		end
		if (value.frameTypes ~= nil) then
			local names = FlagNames(value.frameTypes, UNIT_FRAME_TYPES, "FRAMETYPE_",
				Constants.FRAMETYPE_ALL);
			if (names) then
				addValueLine(tooltip, LabelledValue("CONDITION_FRAMETYPES", names), nil, true);
			end
		end
		if (value.role ~= nil) then
			local names = FlagNames(value.role, UNIT_ROLES, "ROLE_", Constants.ROLE_ALL);
			if (names) then
				addValueLine(tooltip, LabelledValue("CONDITION_ROLE", names), nil, true);
			end
		end
	end

	--- What one unit condition narrows, joined onto the unit's own line: "Focus - Enemy, Alive".
	--- Nil where it narrows nothing, and the caller writes "when the unit exists" instead.
	---
	--- **No label on either part, and no line of its own.** Anything after the unit's name is a
	--- restriction on that unit and nothing else can be there, so the position says what a label
	--- would; on separate lines they stood level with the units themselves and stopped saying whose
	--- they were. The two axes above are the exception, and say why.
	---
	--- **The existence is not written where an axis is.** An axis can only be read off a unit that
	--- is there, so a reaction or a life state already carries it.
	local function UnitConditionSummary(value)
		if (type(value) ~= "table") then
			return nil;
		end
		local s;
		if (value.reaction ~= nil and value.reaction ~= Constants.REACTION_ALL) then
			s = FlagNames(value.reaction, UNIT_FRAME_REACTIONS, "REACTION_", Constants.REACTION_ALL);
		end
		if (value.dead ~= nil) then
			local life = value.dead and LLL["LIFE_DEAD"] or LLL["LIFE_ALIVE"];
			s = s and (s .. ", " .. life) or life;
		end
		if (value.group ~= nil and value.group ~= Constants.UNITGROUP_ALL) then
			local groups = FlagNames(value.group, UNIT_GROUPS, "UNITGROUP_", Constants.UNITGROUP_ALL);
			if (groups) then
				s = s and (s .. ", " .. groups) or groups;
			end
		end
		return s;
	end

	--- Everything one action has to say, written into a tooltip somebody else owns.
	---
	--- **Where it goes is the caller's**, which is why neither an owner nor an anchor is asked for:
	--- the four lists that draw an action anchor differently and one of them will want to add lines
	--- of its own underneath. So a caller sets the owner, calls this, and shows the tooltip, the
	--- shape every `GameTooltip_Add…` in the client is used in.
	---
	--- The minimum width is the exception, and it is here because it belongs to **this content**:
	--- the condition lines are unreadable narrower. `HideActionTooltip` puts it back, and a caller
	--- that hides the tooltip without it leaves every later tooltip in the session that wide.
	---
	--- `opts`:
	---
	---   offWorld          this action is not from the world the live key map was built for, so
	---                     **it is not called unreachable.** That verdict comes out of the key map
	---                     built for the specialization in play, and is not true over there.
	---                     Nothing else is dropped: what is wrong with the action itself has no
	---                     specialization in it and stays.
	---   suppressInactive  "inactive means nothing in this list". The order list's other
	---                     specialization view is that case: everything is active over there, so
	---                     greying a row would be a lie. Independent of `offWorld` -- that list
	---                     sets this always and still marks a live row unreachable.
	---   instructionKeys   locale keys to put at the bottom in place of the default two.
	---   layerLabel        adds a scope line. **Only a list that mixes layers passes it**: the
	---                     order list, whose rows say nothing else about where an action lives,
	---                     and the export list, which does head its groups but scrolls a long one
	---                     out of sight. The layer tab's list does not, because it draws one layer
	---                     and the window title names it.
	function AddActionToTooltip(tooltip, action, opts)
		---@diagnostic disable-next-line: redundant-parameter
		tooltip:SetMinimumWidth(140, true);

		opts = opts or EMPTY_OPTS;
		local suppressInactive = opts.suppressInactive;
		local instructionKeys = opts.instructionKeys;
		local layerLabel = opts.layerLabel;

		--- **Answered here on the same terms the row was answered on** (`Profile.lua`'s `MakeRow`).
		--- It comes out of the key map built for the specialization in play, so it is not true of a
		--- row read from another one. The tooltip used to ask from scratch, which left **no mark on
		--- the row and its own tooltip calling the binding unreachable**. One set of data must not
		--- say two things on one screen.
		local unreachable = not opts.offWorld and IsUnreachableAction(action);

		--- The only issue lookup this tooltip makes.
		---
		--- **조건 이름을 그대로 넘기는 호출자가 있어서 갈래인지 먼저 본다.** 조건 열여덟 중
		--- 검사가 있는 것은 절반이고, 없는 이름으로 물으면 언제나 nil이라 답은 같다. 다른 것은
		--- DEBUG에서 그 물음이 걸린다는 것뿐이다.
		--- `unit` narrows the answer to one unit token, which is what keeps a contradiction on one
		--- unit off the lines of the units beside it.
		local function GetIssue(category, unit)
			if (category ~= nil and not Constants.BINDING_ISSUE_CATEGORIES[category]) then
				return nil;
			end
			return GetBindingIssue(action, category, nil, unit);
		end

		-- **The three tests the row's name uses** (`LayerDisplay.lua`'s `IsActionLive`), and not
		-- `IsInactiveAction`. That one also drops an action whose specialization condition is false
		-- right now, which greyed the key for a condition the reader set like any other one. A
		-- condition belongs to the line that carries it. `offWorld` is the layer half of that test,
		-- already answered by the caller, and a keyless action never reaches this value.
		local isInactive = not suppressInactive
			and (action.arrivalID ~= nil or opts.offWorld == true);
		local hasIssues = GetIssue() ~= nil;
		-- 조건은 액션 최상단이 아니라 이 표 안이다(`Constants.CONDITION_FIELDS`). 표가 없으면
		-- 그릴 조건이 하나도 없다는 뜻이라, 아래 갈래들이 전부 저절로 비켜간다.
		local conditions = action.conditions or EMPTY_CONDITIONS;

		--- A condition that is only on or off, drawn whole.
		---
		--- **The field name is the body of all three locale keys** -- `combat` gives
		--- `CONDITION_COMBAT` and `CONDITION_COMBAT_YES`/`_NO` -- so another one of these is a call
		--- and three strings rather than another copy of the block.
		---
		--- `hasIssues` gates the per-category lookup and is not an optimisation to drop: with
		--- nothing wrong on the action, asking about each condition would rebuild the binding once
		--- per row, since `GetBindingInfoForAction` rewrites it on every call.
		local function addBooleanCondition(field)
			-- **`conditions`에서 읽는다.** 이름을 변수로 받는 자리라, 조건을 최상단에서 내릴 때
			-- 필드 이름으로 훑는 grep에 안 걸렸다. 액션에서 읽으면 언제나 nil이고 이 여섯 줄이
			-- 툴팁에서 통째로 사라진다.
			if (conditions[field] == nil) then
				return;
			end
			local key = "CONDITION_" .. strupper(field);
			local error = hasIssues and GetIssue(field);
			addLabelLine(tooltip, LLL[key]);
			addValueLine(tooltip, conditions[field] == true and LLL[key .. "_YES"] or LLL[key .. "_NO"], error);
		end

		-- **The title does not carry the list's colours.** Those exist so an eye running down forty
		-- rows can sort them without reading; a tooltip is one thing the reader already chose to
		-- read, so there is nothing for the colour to sort. Two of the three also say the wrong
		-- thing here: a blue title is item rarity in this game's visual grammar, and a grey one
		-- repeats what the `KEY` line below already says in words. What the colours carry is said
		-- in lines instead - the badge just under the key, problems on the lines they belong to.
		GameTooltip_SetTitle(tooltip, (NameAndIconForAction(action)));

		do
			addLabelLine(tooltip, LLL["KEY"]);

			if (action.key) then
				local keyText = DebindPrivate.GetKeyDisplayText(action.key);
				local error;
				if (isInactive) then
					keyText = INACTIVE_COLOR:WrapTextInColorCode(keyText);
				else
					error = hasIssues and GetIssue("key") or nil;
				end
				addValueLine(tooltip, keyText, error);
				-- **Stated here, not shouted, and under the key rather than on it.** The key itself
				-- is a valid one and the sentence describes a neighbour on it, so neither half goes
				-- red. `addValueLine`'s error argument colours both at once, which is why this is
				-- put up as a line of its own instead of being handed to it.
				--
				-- **A second line beside whatever the key already said**, since the two are
				-- separate axes: an action can be covered by a neighbour and be carrying a fault of
				-- its own at the same time, and saying only one of them loses the other.
				if (unreachable) then
					addValueLine(tooltip, DISABLED_FONT_COLOR:WrapTextInColorCode(
						"(" .. LLL["BINDING_ERROR_UNREACHABLE"] .. ")"));
				end
			else
				-- 행의 단축키 칸과 같은 말을 쓴다. 한때 여기만 따로 번역된 키를
				-- 들고 있어서, 로케일에 따라 같은 창 안에서 두 낱말이 될 수 있었다.
				addValueLine(tooltip, INACTIVE_COLOR:WrapTextInColorCode(LLL["OVERVIEW_NO_KEY"]));
			end

			-- **Under the key, because it is the key this qualifies.** The line above says which
			-- key it has; this one says that key does nothing yet. Anywhere else in the tooltip
			-- the two would be a statement and a contradiction with other lines in between.
			--
			-- Same blue as the name in the list and the dot on the icon, so the three read as one
			-- mark rather than three. It is the only thing in this tooltip that says so, now that
			-- the title has stopped carrying the colour.
			if (action.arrivalID) then
				addValueLine(tooltip, IMPORTED_FONT_COLOR:WrapTextInColorCode(LLL["LINE_TOOLTIP_IMPORTED"]), nil, true);
			end
		end

		-- **What this character casts, first.** The three spec-resolved types are the only actions
		-- whose value is not on the row, so the tooltip is where the spell is named -- and where a
		-- specialization with nothing to cast is told so, since the key still takes the press.
		if (Constants.SPEC_RESOLVED_TYPES[action.type]) then
			addLabelLine(tooltip, LLL["LINE_TOOLTIP_SPEC_SPELL"]);
			local spellID = DebindPrivate.SpecSpells.SpellForType(action.type);
			local name = spellID and DebindPrivate.GetSpellNameAndIconID(spellID);
			if (name) then
				addValueLine(tooltip, name);
			else
				addValueLine(tooltip, DISABLED_FONT_COLOR:WrapTextInColorCode(LLL["LINE_TOOLTIP_SPEC_SPELL_NONE"]));
			end
		end

		if (action.unit ~= nil) then
			addLabelLine(tooltip, LLL["TARGET_UNIT"]);
			-- **Asked about `"@"` because the target is what that resolves to with no key held.** A
			-- contradiction on that unit is one picking another target can clear, and asking without
			-- it would report contradictions on units the reader named somewhere else.
			local error = hasIssues and GetIssue("unit", "@");
			local unitStr = UNIT_INFO[action.unit] and UNIT_INFO[action.unit].name or LLL[action.unit];
			addValueLine(tooltip, unitStr, error);
		end

		-- **Shown with a target set as well.** The box was read here under `action.unit == nil`, on
		-- the grounds that `FillBinding` only fills the unit where none is set. It refuses the
		-- account-wide twin too (`Misc.lua`'s `TwinUnitFor`), and that one stands on an action that
		-- has a target, so the line was missing exactly where the box was the only thing stopping it.
		if (action.ignoreHoverUnit) then
			addLabelLine(tooltip, LLL["IGNORE_HOVER_UNIT"]);
			addValueLine(tooltip, LLL["LINE_TOOLTIP_IGNORE_HOVER_UNIT"]);
		end

		if (conditions.units) then
			local first = true;

			-- **`"@"` first, as the `Units` menu lists it.**
			local resolved = DebindPrivate.UnitConditionForBinding(conditions.units["@"]);
			if (resolved ~= nil) then
				addLabelLine(tooltip, LLL["CONDITION_UNITS"]);
				first = false;
				local error = hasIssues and GetIssue("units", "@");
				if (resolved == false) then
					addValueLine(tooltip, LLL["RESOLVED_TARGET"] .. " - " .. LLL["CONDITION_UNIT_DOES_NOT_EXIST"], error);
				else
					addValueLine(tooltip, LLL["RESOLVED_TARGET"] .. " - "
						.. (UnitConditionSummary(resolved) or LLL["CONDITION_UNIT_EXISTS"]), error);
					AddUnitFrameAxes(tooltip, resolved);
				end
			end

			for checkedUnit, stored in pairs(conditions.units) do
				-- 끈 조건은 저장에 남아 있어도 여기 안 나온다.
				local value = DebindPrivate.UnitConditionForBinding(stored);
				-- **옛 철자를 새 이름으로 바꿔서 그린다.** 이 순회는 원본 액션의 표를 도는데,
				-- 사다리가 아직 안 닿은 프로필은 가리킨 개체창의 유닛이 `hover`다. 그대로 두면
				-- `UNIT_INFO`에 그 이름이 없어서 아래 줄이 nil을 인덱싱하다 터지고, 건너뛰면
				-- 걸어둔 조건이 화면에서 통째로 사라진다. 새 이름이 이미 있으면 그쪽이 이긴다 -
				-- `StoredUnitFrameCondition`이 같은 순서로 읽는다.
				if (checkedUnit == "hover" and conditions.units.unitframe == nil) then
					checkedUnit = "unitframe";
				end
				-- `"@"` is drawn just before this loop. `"player"` is skipped: its own menu sits
				-- beside `Group` and asks about the reader rather than about a unit they picked, so
				-- its line goes beside that one too. Skipped whole rather than only where life is
				-- set, so a hand-edited axis there is drawn once rather than in both places.
				if (value ~= nil and checkedUnit ~= "hover"
						and checkedUnit ~= "@" and checkedUnit ~= "player") then
					if (first) then
						addLabelLine(tooltip, LLL["CONDITION_UNITS"]);
						first = false;
					end

					-- **Asked of this unit, not of the block.** One `GetIssue("units")` for the whole
					-- loop put one unit's contradiction on every line under the heading, so a unit
					-- that had nothing to do with it read as broken and the sentence repeated once
					-- per row. The fourth argument is what narrows the answer to one unit; the unit
					-- submenus have always asked that way (`Misc.lua`).
					local error = hasIssues and GetIssue("units", checkedUnit);
					local unitStr = UNIT_INFO[checkedUnit].name;
					-- Storage keeps one field per axis (`Profile.lua`'s `dbver <= 4` step). One
					-- line says whether the unit has to be there, and each constrained axis adds
					-- a line below it in the shape the unit frame block already uses. A new axis is
					-- one more branch here.
					if (value == false) then
						addValueLine(tooltip, unitStr .. " - " .. LLL["CONDITION_UNIT_DOES_NOT_EXIST"], error);
					else
						local summary = UnitConditionSummary(value);
						addValueLine(tooltip, unitStr .. " - "
							.. (summary or LLL["CONDITION_UNIT_EXISTS"]), error);
						AddUnitFrameAxes(tooltip, value);
					end
				end
			end
		end

		-- 읽는 이 자신에 대한 조건. **`Units` 묶음이 아니라 `Group` 옆이다** - 편집하는 자리가
		-- 거기고, 화면 둘이 다른 자리를 가리키면 고칠 곳을 찾는 사람이 헤맨다.
		--
		-- **A full mask is not drawn at all, label and values both.** Every one of them on rules
		-- nothing out, which is the state the axis is in when it was never set, and the emitter
		-- drops it against `allValue` (`UpdateBindings.lua`). Drawing it would name a condition
		-- that holds nothing back.
		if (conditions.groups ~= nil and conditions.groups ~= Constants.GROUP_ALL) then
			addLabelLine(tooltip, LLL["CONDITION_GROUP"]);

			if (conditions.groups == 0) then
				addValueLine(tooltip, LLL["BINDING_ERROR_GROUPS_NONE_SELECTED"], true);
			else
				wipe(_lines);
				for i = 1, #GROUP_TYPES do
					local flag = Constants["GROUP_" .. GROUP_TYPES[i]];
					if (bit.band(conditions.groups, flag) == flag) then
						tinsert(_lines, LLL["GROUP_" .. GROUP_TYPES[i]]);
					end
				end
				local error = hasIssues and GetIssue("groups");
				addValueLines(tooltip, _lines, error);
			end
		end

		-- 읽는 이 자신의 생사. 저장은 `units.player`인데 **`Units` 묶음이 아니라 여기다.**
		--
		-- 이유 둘이 같은 방향을 가리킨다. 고치는 자리가 조건 메뉴의 `Group` 바로 아래라
		-- 읽는 줄도 그 옆이어야 하고, **라벨에 주어가 없어서 이웃이 주어를 준다** - 이름으로
		-- 고른 유닛들 사이에 두면 그 유닛들의 생사로 읽힌다. 메뉴 쪽 순서와 한 벌이므로
		-- 한쪽을 옮기면 다른 쪽도 옮긴다.
		--
		-- 이 유닛에는 존재 조건이 설 자리가 없다. 자기 자신은 늘 있으므로 `false`가 왔다면
		-- 손으로 고친 프로필이고, `UnitConditionSummary`가 그 경우 nil을 내므로 줄이 안 나간다.
		local selfCondition = DebindPrivate.UnitConditionForBinding(
			conditions.units and conditions.units.player);
		if (selfCondition) then
			local summary = UnitConditionSummary(selfCondition);
			if (summary) then
				addLabelLine(tooltip, LLL["CONDITION_LIFE"]);
				addValueLine(tooltip, summary,
					hasIssues and GetIssue("units", "player") and true or false);
			end
		end

		if (conditions.specs ~= nil) then
			addLabelLine(tooltip, LLL["CONDITION_SPECS"]);

			if (next(conditions.specs) == nil) then
				addValueLine(tooltip, LLL["BINDING_ERROR_SPECS_NONE_SELECTED"], true);
			else
				addValueLine(tooltip, DebindPrivate.DescribeSpecCondition(conditions.specs),
					hasIssues and GetIssue("specs"));
				-- **Under the names, not on them.** The names are what the reader chose and
				-- none of them is wrong; what this adds is that none is the one being played.
				-- Held back where the layer is another specialization's, for the reason
				-- `unreachable` is: the reader opened that world on purpose and the answer here
				-- is about the one they are standing in.
				if (not opts.offWorld and not DebindPrivate.SpecConditionHolds(action)) then
					addValueLine(tooltip, DISABLED_FONT_COLOR:WrapTextInColorCode(
						"(" .. LLL["LINE_TOOLTIP_SPEC_INACTIVE"] .. ")"));
				end
			end
		end

		addBooleanCondition("combat");
		addBooleanCondition("stealth");
		addBooleanCondition("mounted");
		addBooleanCondition("skyriding");
		addBooleanCondition("flyable");
		addBooleanCondition("advflyable");
		addBooleanCondition("flying");
		addBooleanCondition("indoors");

		-- **Not `addBooleanCondition`**, because only one of the two answers is ever drawn: the
		-- menu picks which spell is asked about rather than inverting the question, so there is no
		-- "does not know it" row to write and `CONDITION_KNOWN_NO` does not exist.
		--
		-- The value names the spell (`devdocs/making-known-a-spell-name.md`); `true` is the three
		-- types whose spell the specialization picks, and there the action itself is the answer.
		if (conditions.known) then
			local error = hasIssues and GetIssue("known");
			addLabelLine(tooltip, LLL["CONDITION_KNOWN"]);
			if (conditions.known == true) then
				addValueLine(tooltip, LLL["CONDITION_KNOWN_YES"], error);
			else
				addValueLine(tooltip, format(LLL["CONDITION_KNOWN_VALUE"], conditions.known), error);
			end
		end

		if (conditions.forms ~= nil and conditions.forms ~= Constants.FORM_ALL) then
			addLabelLine(tooltip, LLL["CONDITION_SHAPESHIFT"]);
			if (conditions.forms == 0) then
				addValueLine(tooltip, LLL["BINDING_ERROR_FORMS_NONE_SELECTED"], true);
			else
				-- **Numbers on one line, the way the specializations above are drawn.** A name
				-- each would be eleven rows of a word the label already said, and most of them
				-- have no name on this class anyway. The menu is where the names live.
				local s = "";
				for i = 0, 10 do
					if (bit.band(conditions.forms, 2 ^ i) ~= 0) then
						if (s ~= "") then
							s = s .. ", ";
						end
						s = s .. i;
					end
				end
				addValueLine(tooltip, s, hasIssues and GetIssue("forms"));
			end
		end

		if (conditions.bonusbars ~= nil and conditions.bonusbars ~= Constants.BONUSBAR_ALL) then
			addLabelLine(tooltip, LLL["CONDITION_BONUSBAR"]);
			if (conditions.bonusbars == 0) then
				addValueLine(tooltip, LLL["BINDING_ERROR_BONUSBARS_NONE_SELECTED"], true);
			else
				wipe(_lines);
				local error = hasIssues and GetIssue("bonusbars");
				for i = 0, Constants.MAX_BONUSBAR_OFFSET do
					local flag = 2 ^ i;
					if (bit.band(conditions.bonusbars, flag) ~= 0) then
						local label = GetActionBarTypeLabel(i);
						if (label) then
							tinsert(_lines, label);
						end
					end
				end
				addValueLines(tooltip, _lines, error);
			end
		end

		addBooleanCondition("specialbar");
		addBooleanCondition("extrabar");
		addBooleanCondition("petbattle");

		-- **조건 표에 있는 이름을 그린다.** 다섯 번호를 돌던 자리라 그 밖의 이름이 걸린 액션은
		-- 툴팁에 조건이 아예 없는 것처럼 보였다 - 안 나가는 이유가 화면 어디에도 없다는 뜻이다.
		--
		-- `pairs`는 순서를 안 주고 툴팁 줄 순서는 볼 때마다 달라지면 안 되므로 이름순으로
		-- 세운다. 배열은 파일 위쪽 조건 줄들이 쓰는 `_lines`와 다른 것을 쓴다 - 저쪽은
		-- `addValueLines`가 자기 것을 비우며 돈다.
		wipe(_switchNames);
		for name in pairs(conditions) do
			if (Constants.IsSwitchName(name)) then
				tinsert(_switchNames, name);
			end
		end
		sort(_switchNames);
		for i = 1, #_switchNames do
			local state = _switchNames[i];
			addLabelLine(tooltip, state);
			addValueLine(tooltip, conditions[state] == true and LLL["CONDITION_CUSTOM_STATE_YES"] or LLL["CONDITION_CUSTOM_STATE_NO"]);
		end

		-- 매크로 본문의 `[$이름]`은 위 조건 칸들과 달리 그릴 자리가 없다 - 저장에는 본문
		-- 문자열 하나로만 있다. 그래서 이슈 코드만으로는 **어느 이름이 틀렸는지**를 못 말하고,
		-- 그걸 말하는 것이 이 마커의 존재 이유라 여기서만 이름을 붙여 적는다.
		if (hasIssues) then
			local undefinedState = DebindPrivate.GetUndefinedSwitch(action);
			if (undefinedState) then
				GameTooltip_AddBlankLineToTooltip(tooltip);
				addErrorLine(tooltip, format(LLL["BINDING_ERROR_UNDEFINED_STATE"], undefinedState), true);
			end

			-- Named here for the same reason. The macro name is the action's `value`, so no
			-- condition row above draws it, and the name on the row is the one
			-- `NameAndIconForAction` hands back **unchanged** next to a question-mark icon -- it
			-- cannot say on its own why the row went red.
			local missingMacro = DebindPrivate.GetMissingMacroName(action);
			if (missingMacro) then
				GameTooltip_AddBlankLineToTooltip(tooltip);
				addErrorLine(tooltip, format(LLL["BINDING_ERROR_MISSING_MACRO"], missingMacro), true);
			end
		end

		if (action.priority and action.priority ~= Constants.DEFAULT_IMPORTANCE) then
			addLabelLine(tooltip, LLL["IMPORTANCE"]);
			addValueLine(tooltip, LLL["IMPORTANCE" .. action.priority]);
		end

		-- 중요도 바로 밑에 둔다. 둘 다 순서를 정하는 값이고, 조건들과는 성질이 다르다.
		if (layerLabel) then
			addLabelLine(tooltip, LLL["SCOPE"]);
			addValueLine(tooltip, layerLabel);
		end

		if (instructionKeys) then
			if (#instructionKeys > 0) then
				GameTooltip_AddBlankLineToTooltip(tooltip);
				for _, instructionKey in ipairs(instructionKeys) do
					GameTooltip_AddInstructionLine(tooltip, LLL[instructionKey]);
				end
			end
		else
			GameTooltip_AddBlankLineToTooltip(tooltip);
			GameTooltip_AddInstructionLine(tooltip, LLL["LINE_TOOLTIP_INSTRUCTION_MESSAGE1"]);
			GameTooltip_AddInstructionLine(tooltip, LLL["LINE_TOOLTIP_INSTRUCTION_MESSAGE2"]);
		end
	end

	--- The other half of `AddActionToTooltip`: puts the minimum width back and hides.
	---
	--- **A bare `Hide()` is not enough**, which is the one place the split is not clean. The
	--- content sets a minimum width because it needs one, and a minimum width outlives the
	--- tooltip that asked for it -- so every tooltip in the session afterwards, ours or the
	--- game's, comes out that wide. The client pairs the two the same way, in the achievement
	--- category rows.
	function HideActionTooltip(tooltip)
		---@diagnostic disable-next-line: redundant-parameter
		tooltip:SetMinimumWidth(0, false);
		tooltip:Hide();
	end

	DebindPrivate.AddActionToTooltip = AddActionToTooltip;
	DebindPrivate.HideActionTooltip = HideActionTooltip;
end

--- **The issue mark's tooltip**, on a row and on a group heading.
---
--- Here for the same reason the block above is: it takes the tooltip as an argument and knows
--- nothing else about the screen. In `DebindUI.lua` it was out of reach of every headless spec,
--- which is the rule §11 of `going-headless-outside-the-ui.md` decides by -- whether the function
--- needs a frame, not whether the file is UI.
do
	--- How deep a problem's sentence sits under the name of the group that can fix it. The step the
	--- block above indents a condition's own lines by.
	local ISSUE_INDENT = 10;

	--- **The order the problems are read in.** What raised them is the order the checks happen to
	--- be written in (`GetBindingIssue`), which decided nothing while only the worst one was ever
	--- shown and decides the reading order now that they are all listed.
	---
	--- Two rules make it. The action's own faults come first, because a key that points at nothing
	--- is not a condition on anything. Then the condition groups, **in the order the right-click
	--- menu draws them** (`DropDownMenus.lua`'s `conditionNodes`, and each group's own children
	--- under it) -- the reader who goes to fix one opens that menu next, and finds the groups in
	--- the order the tooltip just named them.
	---
	--- A label missing here sorts last rather than breaking the list. **It also means a group added
	--- to the menu and not to this table reads in the wrong place**, which is the cost of the order
	--- being written down twice; there is nowhere both files can see it, because this one is read
	--- with no frames at all.
	local ISSUE_ORDER = {};
	for i, label in ipairs({
		"TYPE_MACRO", "KEY",
		"CONDITION_UNITS", "CONDITION_GROUP", "CONDITION_SPEC",
		"CONDITION_SHAPESHIFT", "CONDITION_BONUSBAR", "CONDITION_SPECIALBAR",
		"CONDITION_SKYRIDING", "CONDITION_PETBATTLE", "CONDITION_CUSTOM_STATES",
	}) do
		ISSUE_ORDER[label] = i;
	end

	--- **A sort that keeps ties where they were.** `table.sort` is not stable, and two problems in
	--- one group would otherwise swap places between two draws of the same tooltip.
	local function ByGroupOrder(issues)
		local at = {};
		for i = 1, #issues do
			at[issues[i]] = i;
		end
		local LAST = #issues + 100;
		table.sort(issues, function(a, b)
			local rankA = ISSUE_ORDER[a.label] or LAST;
			local rankB = ISSUE_ORDER[b.label] or LAST;
			if (rankA ~= rankB) then
				return rankA < rankB;
			end
			return at[a] < at[b];
		end);
	end

	--- The sentence an issue code prints, in its grade's colour. The wording fallback is the menu's
	--- (`resolveIssue` in ActionMenuModel.lua), and the colour is the grade's (`GetIssueColor`).
	---
	--- **Two of the sentences name something** -- the switch and the macro that were not found --
	--- and the name comes with the code (`GetBindingIssues`). Without it the reader was handed a
	--- raw `%s` where the name should have been.
	local function AddIssueLine(tooltip, code, arg, leftOffset)
		local text = rawget(LLL, code) or rawget(LLL, "BINDING_ERROR_" .. code) or code;
		if (arg ~= nil) then
			text = format(text, arg);
		end
		GameTooltip_AddColoredLine(tooltip, text, DebindPrivate.GetIssueColor(code), true, leftOffset or 0);
	end

	--- One grade's problems, written under the name of the group each one is fixed in. `done`
	--- carries across the two calls, so no line stands under both grades.
	---
	--- **Names are written in the order they first appear and every sentence under a name is
	--- gathered there.** Walking the list as it comes puts the same name up twice whenever one axis
	--- is caught by two branches, which is the ordinary case rather than a rare one.
	---
	--- `titled` is the grade the tooltip's title already names, so that grade writes no heading of
	--- its own -- the other one does, or the reader cannot tell the two apart once both are up.
	local function AddIssueGroup(tooltip, issues, warning, done, titled)
		local headed = warning == titled;
		for i = 1, #issues do
			local issue = issues[i];
			if (not done[i] and DebindPrivate.IsIssueWarning(issue.code) == warning) then
				if (not headed) then
					headed = true;
					GameTooltip_AddBlankLineToTooltip(tooltip);
					GameTooltip_AddHighlightLine(tooltip,
						warning and LLL["ORDER_FLAG_ISSUE_WARNING"] or LLL["ORDER_FLAG_ISSUE"]);
					GameTooltip_AddNormalLine(tooltip,
						warning and LLL["MARK_TOOLTIP_ISSUE_DESC_WARNING"]
							or LLL["MARK_TOOLTIP_ISSUE_DESC"], true);
				end
				GameTooltip_AddBlankLineToTooltip(tooltip);
				if (issue.label) then
					GameTooltip_AddHighlightLine(tooltip,
						format(LLL["LINE_TOOLTIP_CONDITION_LABEL"], LLL[issue.label]));
				end
				for j = i, #issues do
					local other = issues[j];
					if (not done[j] and other.label == issue.label
							and DebindPrivate.IsIssueWarning(other.code) == warning) then
						done[j] = true;
						AddIssueLine(tooltip, other.code, other.arg,
							issue.label and ISSUE_INDENT or 0);
					end
				end
			end
		end
	end

	--- The row's issue mark: every problem on this row, under the name of the group that can fix it.
	---
	--- **The title is the grade, in the same words the order flag uses** (`ORDER_FLAG_ISSUE*`), and
	--- the line under it says what that grade costs. A list that only paints the two grades says
	--- nothing to a reader who cannot part red from orange.
	---
	--- **The list is built here rather than on the row.** Only a hover needs it, and a row that is
	--- rebuilt on every profile change would pay for it every time.
	function DebindPrivate.AddIssueMarkToTooltip(tooltip, action)
		local issues = DebindPrivate.GetBindingIssues(action);
		ByGroupOrder(issues);

		-- The title speaks for the worst grade in the list, which is the grade the mark itself is
		-- drawn in (`SetKind`). Anything milder writes its own heading further down.
		local warningIsWorst = true;
		for i = 1, #issues do
			if (not DebindPrivate.IsIssueWarning(issues[i].code)) then
				warningIsWorst = false;
				break;
			end
		end

		GameTooltip_SetTitle(tooltip,
			warningIsWorst and LLL["ORDER_FLAG_ISSUE_WARNING"] or LLL["ORDER_FLAG_ISSUE"]);
		GameTooltip_AddNormalLine(tooltip,
			warningIsWorst and LLL["MARK_TOOLTIP_ISSUE_DESC_WARNING"]
				or LLL["MARK_TOOLTIP_ISSUE_DESC"], true);

		local done = {};
		AddIssueGroup(tooltip, issues, false, done, warningIsWorst);
		AddIssueGroup(tooltip, issues, true, done, warningIsWorst);
	end

	--- The name a sentence with a `%s` in it prints, asked of the action that raised the code.
	--- The row-mark tooltip gets this handed to it by `GetBindingIssues`; a group heading has only
	--- the rows, so it asks the same two functions the branches ask.
	local ISSUE_NAMES = {
		[Constants.BINDING_ISSUE_MISSING_MACRO] = function(action)
			return DebindPrivate.GetMissingMacroName(action);
		end,
		[Constants.BINDING_ISSUE_UNDEFINED_STATE] = function(action)
			return DebindPrivate.GetUndefinedSwitch(action);
		end,
	};

	--- The group heading's issue mark: every problem in the group, one line per sentence, so a
	--- folded group still says what is wrong further down.
	---
	--- **A code that names something counts as one sentence per name.** Two rows missing two
	--- different macros are two problems, and folding them on the code alone would print one of
	--- the names and drop the other.
	function DebindPrivate.AddGroupIssuesToTooltip(tooltip, rows)
		local seen = {};
		for i = 1, #rows do
			local row = rows[i];
			local issue = row.issue;
			if (issue and not DebindPrivate.IsInactiveAction(row.action)) then
				local named = ISSUE_NAMES[issue];
				local arg = named and named(row.action);
				local key = issue .. "\0" .. tostring(arg);
				if (not seen[key]) then
					seen[key] = true;
					AddIssueLine(tooltip, issue, arg);
				end
			end
		end
	end
end
