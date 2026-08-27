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
local IsIssueMinor           = DebindPrivate.IsIssueMinor;
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

	local function addValueLine(tooltip, value, error, wrap, leftOffset)
		if (error) then
			GameTooltip_AddErrorLine(tooltip, value, wrap or false, leftOffset or LEFT_OFFSET);
		else
			GameTooltip_AddNormalLine(tooltip, value, wrap or false, leftOffset or LEFT_OFFSET);
		end
		if (type(error) == "string") then
			GameTooltip_AddErrorLine(tooltip, "(" .. LLL["BINDING_ERROR_" .. error] .. ")", wrap or false, leftOffset or LEFT_OFFSET);
		end
	end

	local function addValueLines(tooltip, lines, error, wrap, leftOffset)
		local fn = error and GameTooltip_AddErrorLine or GameTooltip_AddNormalLine;
		for i = 1, #lines do
			fn(tooltip, lines[i], wrap or false, leftOffset or LEFT_OFFSET);
		end
		if (type(error) == "string") then
			GameTooltip_AddErrorLine(tooltip, "(" .. LLL["BINDING_ERROR_" .. error] .. ")", wrap or false, leftOffset or LEFT_OFFSET);
		end
	end

	--- The names a mask has switched on, comma-joined onto one line.
	---
	--- **The full mask and the empty one get a word instead of a list.** Naming every reaction is
	--- longer than "all" and says less, and an empty mask is not a list of nothing: it is the one
	--- state nothing can satisfy, so it gets a word a reader can catch.
	---
	--- One `prefix` addresses both tables -- the flag is `Constants[prefix .. name]` and the word
	--- is `LLL[prefix .. name]` -- which holds because the two are keyed alike by construction.
	local function FlagNames(mask, names, prefix, all)
		if (mask == all) then
			return LLL["ALL"];
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
	---                     **unreachable is dropped and nothing else is.** That verdict comes out
	---                     of the key map built for the specialization in play, and is not true
	---                     over there. Key validity has no specialization in it and stays.
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

		local suppressedCategory = opts.offWorld and "unreachable" or nil;

		--- The only issue lookup this tooltip makes.
		---
		--- **Another specialization's order drops one thing: unreachable.** That verdict comes out
		--- of the key map built for the specialization in play, so it is not true over there. The
		--- row is already computed that way (`CollectActionsForKey`) while the tooltip asked again
		--- from scratch, which left **no warning on the row and its own tooltip calling the
		--- binding unreachable in red**. One set of data must not say two things on one screen.
		---
		--- **조건 이름을 그대로 넘기는 호출자가 있어서 갈래인지 먼저 본다.** 조건 열여덟 중
		--- 검사가 있는 것은 절반이고, 없는 이름으로 물으면 언제나 nil이라 답은 같다. 다른 것은
		--- DEBUG에서 그 물음이 걸린다는 것뿐이다.
		local function GetIssue(category)
			if (category ~= nil and not Constants.BINDING_ISSUE_CATEGORIES[category]) then
				return nil;
			end
			return GetBindingIssue(action, category, suppressedCategory);
		end

		local isInactive = not suppressInactive and DebindPrivate.IsInactiveAction(action);
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
				-- **A minor problem is stated here, not shouted.** The key itself is a valid one and
				-- the sentence under it describes a neighbour, so neither half goes red.
				-- `addValueLine`'s error argument colours both at once, which is why the sentence is
				-- put up separately instead of being handed to it.
				if (error and IsIssueMinor(error)) then
					addValueLine(tooltip, keyText);
					addValueLine(tooltip, DISABLED_FONT_COLOR:WrapTextInColorCode(
						"(" .. LLL["BINDING_ERROR_" .. error] .. ")"));
				else
					addValueLine(tooltip, keyText, error);
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

		if (action.unit ~= nil) then
			addLabelLine(tooltip, LLL["TARGET_UNIT"]);
			local error = hasIssues and GetIssue("unit");
			local unitStr = UNIT_INFO[action.unit] and UNIT_INFO[action.unit].name or LLL[action.unit];
			addValueLine(tooltip, unitStr, error);
		end

		-- 호버 조건은 `units["hover"]`다(`Profile.lua`의 `dbver <= 4`). 아래 유닛
		-- 묶음이 이 키를 건너뛰는 것도 그래서다 - 같은 조건을 두 번 그리게 된다.
		-- 저장에는 끈 값이 남아 있다. 여기는 **걸린 조건**을 그리는 자리라 그걸 접고 본다.
		local hoverCondition = DebindPrivate.UnitConditionForBinding(
			conditions.units and conditions.units.hover);
		if (hoverCondition ~= nil) then
			addLabelLine(tooltip, LLL["CONDITION_HOVER"]);
			local error = hasIssues and GetIssue("hover");
			if (hoverCondition) then
				local reactions = hoverCondition.reaction or Constants.REACTION_ALL;
				local frameTypes = conditions.frameTypes or Constants.FRAMETYPE_ALL;

				addValueLine(tooltip, LabelledValue("CONDITION_REACTIONS",
					FlagNames(reactions, UNIT_FRAME_REACTIONS, "REACTION_", Constants.REACTION_ALL)),
					hasIssues and GetIssue("reactions") and true or false, true);

				addValueLine(tooltip, LabelledValue("CONDITION_FRAMETYPES",
					FlagNames(frameTypes, UNIT_FRAME_TYPES, "FRAMETYPE_", Constants.FRAMETYPE_ALL)),
					hasIssues and GetIssue("frameTypes") and true or false, true);

				if (hoverCondition.dead ~= nil) then
					addValueLine(tooltip, LabelledValue("CONDITION_LIFE",
						hoverCondition.dead and LLL["LIFE_DEAD"] or LLL["LIFE_ALIVE"]),
						error and true or false, true);
				end

				if (action.ignoreHoverUnit) then
					addValueLine(tooltip, LLL["IGNORE_HOVER_UNIT"]);
				end
			else
				addValueLine(tooltip, LLL["CONDITION_HOVER_NO"], error);
			end
			if (error) then
				addErrorLine(tooltip, LLL["BINDING_ERROR_" .. error]);
			end
		end

		if (conditions.units) then
			local first = true;
			for checkedUnit, stored in pairs(conditions.units) do
				-- 끈 조건은 저장에 남아 있어도 여기 안 나온다. `"hover"`는 위 호버 묶음이 그렸다.
				local value = DebindPrivate.UnitConditionForBinding(stored);
				if (value ~= nil and checkedUnit ~= "hover"
						and (checkedUnit ~= "@" or (action.unit and action.unit ~= "none"))) then
					if (first) then
						addLabelLine(tooltip, LLL["CONDITION_UNITS"]);
						first = false;
					end

					local error = hasIssues and GetIssue("units");
					local unitStr;
					if (checkedUnit == "@") then
						unitStr = format(LLL["SELECTED_TARGET_UNIT"], UNIT_INFO[action.unit].name);
					else
						unitStr = UNIT_INFO[checkedUnit].name;
					end
					-- Storage keeps one field per axis (`Profile.lua`'s `dbver <= 4` step). One
					-- line says whether the unit has to be there, and each constrained axis adds
					-- a line below it in the shape the hover block already uses. A new axis is
					-- one more branch here.
					if (value == false) then
						addValueLine(tooltip, unitStr .. " - " .. LLL["CONDITION_UNIT_DOES_NOT_EXIST"], error);
					else
						addValueLine(tooltip, unitStr .. " - " .. LLL["CONDITION_UNIT_EXISTS"], error);

						local reaction = type(value) == "table" and value.reaction or nil;
						if (reaction ~= nil and reaction ~= Constants.REACTION_ALL) then
							addValueLine(tooltip, LabelledValue("CONDITION_REACTIONS",
								FlagNames(reaction, UNIT_FRAME_REACTIONS, "REACTION_", Constants.REACTION_ALL)),
								error, true);
						end

						if (type(value) == "table" and value.dead ~= nil) then
							addValueLine(tooltip, LabelledValue("CONDITION_LIFE",
								value.dead and LLL["LIFE_DEAD"] or LLL["LIFE_ALIVE"]), error, true);
						end
					end
				end
			end
		end

		if (conditions.groups ~= nil) then
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

		addBooleanCondition("combat");
		addBooleanCondition("stealth");
		addBooleanCondition("mounted");
		addBooleanCondition("skyriding");
		addBooleanCondition("flyable");
		addBooleanCondition("advflyable");
		addBooleanCondition("indoors");

		-- **Not `addBooleanCondition`**, because only one of the two answers is ever drawn: the
		-- menu toggles `known` between true and nil rather than inverting it, so there is no
		-- "does not know it" row to write and `CONDITION_KNOWN_NO` does not exist.
		if (conditions.known) then
			local error = hasIssues and GetIssue("known");
			addLabelLine(tooltip, LLL["CONDITION_KNOWN"]);
			addValueLine(tooltip, LLL["CONDITION_KNOWN_YES"], error);
		end

		if (conditions.forms ~= nil) then
			addLabelLine(tooltip, LLL["CONDITION_SHAPESHIFT"]);
			if (conditions.forms == 0) then
				addValueLine(tooltip, LLL["BINDING_ERROR_FORMS_NONE_SELECTED"], true);
			else
				wipe(_lines);
				local error = hasIssues and GetIssue("forms");
				for i = 0, 10 do
					local flag = 2 ^ i;
					if (bit.band(conditions.forms, flag) ~= 0) then
						if (i == 0) then
							tinsert(_lines, format("[form:%d] (%s)", i, LLL["NO_SHAPESHIFT"]));
						else
							local _, _, _, spellID = GetShapeshiftFormInfo(i);
							local spellName = spellID and GetSpellNameAndIconID(spellID);
							if (spellName) then
								tinsert(_lines, format("[form:%d] (%s)", i, spellName));
							else
								tinsert(_lines, format("[form:%d]", i));
							end
						end
					end
				end
				addValueLines(tooltip, _lines, error);
			end
		end

		if (conditions.bonusbars ~= nil) then
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
		addBooleanCondition("pet");
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
