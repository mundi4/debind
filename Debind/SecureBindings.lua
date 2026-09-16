--[[
FIXME 유닛 popup메뉴에 들어갔다가 나오면 hover값이 nil로 변경되지 않음
]]

local _, DebindPrivate = ...;
local BindingDriver      = DebindPrivate.BindingDriver;
local Constants          = DebindPrivate.Constants;
local BakeSnippet        = DebindPrivate.BakeSnippet;

function BindingDriver:print(...)
	DebindPrivate.log(...);
end

function BindingDriver:dump(name, ...)
	if (DebindPrivate.DEBUG) then
		DebindPrivate.dump(name, { ... });
	end
end

--- 보안 스니펫이 완성한 매크로 본문. `UpdateMacroTexts`가 부른다.
---
--- 속성은 한 번 쓰면 열거할 수가 없어서, **버튼에 무엇이 올라갔는지 확인할 길이 이 로그뿐이다.**
--- 짝이 되는 정적 쪽 로그는 `UpdateBindings.lua`의 `SetBindingAttributes`에 있다 - 둘을 같이
--- 봐야 "본문이 틀렸나"와 "본문이 아예 안 올라갔나"가 갈린다.
function BindingDriver:printMacroText(attr, text)
	DebindPrivate.log(format("[secure] %s = %s", tostring(attr), tostring(text)));
end

--- **The unit-condition test is written out at every site rather than shared.**
---
--- A snippet cannot declare a callable of its own. `BuildRestrictedClosure`
--- (`Blizzard_RestrictedAddOnEnvironment/RestrictedExecution.lua:58`) rejects the body on a plain
--- substring match -- its own comment calls that "overzealous but it keeps it simple" -- and the
--- whole snippet dies with it. When the one below dies, `ccframes` / `DirtyFlags` / `UnitStates`
--- are never created, and the first write to any of them fails somewhere else entirely. The error
--- you see then has nothing to do with the line that caused it.
---
--- The same check bans braces, and both look at the **raw text**. Which is the other half of why
--- snippet bodies carry no comments at all: an explanation inside one is shipped to that parser.
--- `tools/check-snippets.js` enforces both.
---
--- The shape each site writes out:
---
---     local s = UnitStates[u]
---     if (not s or c.exists ~= s.exists
---             or (c.reaction and not c.reaction[s.reaction])
---             or (c.dead ~= nil and c.dead ~= s.dead)) then  -- no match
---
--- One comparison per axis, never a mask intersection: there is no `bit` in there, and the
--- arithmetic idiom that replaces it costs the same two lookups **plus** three operations.
--- `c.exists` needs no nil guard (the emitter always writes it), and a condition that asked for
--- absence carries no other axis, so neither needs a wrapper. A nil row means the state has not
--- been computed yet and nothing matches -- reading it as "absent" would fire a binding on the
--- strength of a state nobody looked at.
SecureHandlerSetFrameRef(BindingDriver, "clickFrame", DebindPrivate.DefaultClickFrame);
SecureHandlerSetFrameRef(BindingDriver, "castFrame", DebindPrivate.CastFrame);
-- A protected frame, so its handle still answers `IsShown` in combat.
if (OverrideActionBar) then
	SecureHandlerSetFrameRef(BindingDriver, "overrideActionBar", OverrideActionBar);
end
SecureHandlerExecute(BindingDriver, [[

	debind_driver = self
	ccframes = newtable()

	-- 남의 래퍼에서 걷어와 우리가 대신 돌리는 본문들. `프레임 -> 스크립트 이름 -> 목록`이고
	-- 목록의 1번이 맨 바깥이었던 것이다. 각 항목은 `handle`(그쪽 헤더), `pre`, `post`,
	-- 그리고 이번 실행에서 pre가 낸 `message`를 든다.
	--
	-- **비어 있는 프레임은 행 자체가 없다.** enter/leave/click 세 핫패스가 전부 여기를
	-- 먼저 보므로, 걷어온 것이 없는 프레임에서 조회가 하나로 끝나야 한다. 그래서 목록이
	-- 비면 스크립트 칸을 지우고, 칸이 다 비면 프레임 행을 지운다.
	Overs = newtable()

	MacroMap = newtable()
	
	DefaultClickFrame = self:GetFrameRef("clickFrame")
	DefaultClickFrameName = DefaultClickFrame:GetName()
	CastFrame = self:GetFrameRef("castFrame")

	-- 자동 자가시전을 끄고 도는 쌍둥이 버튼. `진짜 버튼 이름 -> 쌍둥이 이름`이고 리빌드가
	-- 통째로 다시 쓴다(`UpdateBindingsMap`). 클릭 경로에서 조회 하나로 끝나야 해서 표다 -
	-- 이름을 결합하면 매 클릭 문자열이 생긴다.
	SelfCastWrappers = newtable()

	-- `button name -> where its slot is` for every action button action, rewritten whole by the
	-- rebuild (`UpdateBindingsMap`). `ACTION_SLOT_SNIPPET` reads it.
	ActionSlots = newtable()
	OverrideActionBar = self:GetFrameRef("overrideActionBar")
	
	SwitchExpressions = newtable()

	-- A computed switch's composed entry by name, and every computed switch in the order a press
	-- works them out (`BuildSwitchesSnippet`). `ClickSwitches` holds what one press worked out and
	-- `ClickSwitchesReady` says whether it has yet.
	SwitchEntries = newtable()
	ComputedSwitches = newtable()
	ClickSwitches = newtable()
	ClickSwitchesReady = false

	-- Every key that holds a key record: button name ("@" + key) -> that key's record list. The
	-- OnClick wrapper finds which key it is by the button name the press arrived under.
	ClickTimeKeys = newtable()

	-- 클릭캐스팅으로 도착한 클릭. `[버튼번호][수식어] -> 그 키의 레코드 배열`.
	--
	-- **이쪽은 이름을 못 받는다.** 유닛 프레임은 `type="click"`으로 우리에게 넘기는데
	-- `SECURE_ACTIONS.click`은 `delegate:Click(button)`이라 원래 마우스 버튼 이름만 온다
	-- (`/click`과 달리 버튼 이름을 못 싣는다 - 그게 매크로 안의 매크로를 부르던 옛 경로를
	-- 버린 이유다). 그래서 도착한 마우스 버튼과 지금 눌린 수식어로 키를 되찾는다.
	--
	-- 두 단계 표인 이유는 **클릭 순간에 문자열을 안 만들기 위해서다.** 키 문자열로 색인하면
	-- 매 클릭 결합이 생긴다.
	ClickCastKeys = newtable()

	-- 도착한 마우스 버튼 이름 -> 번호. 클릭 경로에서 쓰는 조회라 미리 만들어 둔다.
	MouseButtonNumbers = newtable()
	MouseButtonNumbers["LeftButton"] = 1
	MouseButtonNumbers["RightButton"] = 2
	MouseButtonNumbers["MiddleButton"] = 3
	MouseButtonNumbers["Button4"] = 4
	MouseButtonNumbers["Button5"] = 5

	-- 클릭 시전이 어느 엣지에 발동하는가. `ApplyOptions`가 매번 다시 쓴다. 여기 기본값은
	-- 그 전에 클릭이 도착해도 답이 있게 하려는 것이고, 블리자드 개체창의 기본값과 같다.
	ClickCastOnMouseDown = false

	-- Whether a press asks about the Self Cast Key and the Focus Cast Key. Every rebuild writes both
	-- (`UpdateBindingsMap`); before the first one there is no key to press.
	SelfCastKeyOn = false
	FocusCastKeyOn = false

	-- 실행 엣지가 down일 때 down의 선택을 up이 재사용하기 위한 자리. 버튼 이름 -> 이긴 레코드,
	-- 그리고 그때 확정한 대상. down이 항상 먼저 오므로 덮어쓰기로 자가 치유된다.
	HeldButtons = newtable()
	HeldUnits = newtable()

	-- 래퍼가 클릭 안에서 쓰는 메모. **클릭 경로에서는 newtable()을 부르지 않는다** -
	-- GC 스파이크는 평균 비용보다 아프게 나타난다. 그래서 미리 만들어 두고 재사용한다.
	-- 같은 유닛을 여러 레코드가 물을 때 C 호출이 반복되는 것을 막는다.
	ClickUnitExists = newtable()
	ClickUnitReaction = newtable()
	ClickUnitDead = newtable()
	ClickUnitGroup = newtable()

	MacroTextsMap = newtable()

	-- The macro bodies held back until a click. `button name -> what it takes to compose one`.
	--
	-- **This and `MacroTextsMap` do not overlap.** A body is in one or the other. What is here is
	-- rebuilt by nobody when a state moves, and by the click that picks that button. That is what
	-- takes a raid-frame sweep down: the list `SetUnit` walks no longer holds them.
	--
	-- Indexed by button name because at the moment of a click that is the only thing in hand --
	-- what the wrapper's winner carries is `clickbutton`, and that name is what `*macrotext-`
	-- ends in.
	DeferredMacroTexts = newtable()

	UnitAliasMap = newtable()

	-- 그룹 유닛 토큰 -> 역할 헤더의 별칭(`"tank"` / `"healer"` / `"damager"`), 곧 역할 이름
	-- 그대로다. 행이 없는 그룹원은 `"norole"`이고, 그것도 축 위의 값이다(`Constants.lua`).
	--
	-- **반응 축과 같은 모양이다**: 런타임은 값 하나를 들고 조건은 이름으로 켠 집합이라,
	-- 비교가 `cond.role[role]` 한 번이다.
	--
	-- **표가 없으면 `false`이고, 그것이 "답할 수 없다"는 뜻이다.** 이름은 늘 서 있고 값만 오간다. `"norole"`은 세 헤더가
	-- 다 보고도 아무도 데려가지 않았다는 답이라, 셋 중 하나라도 안 서 있으면 낼 수 없다. 탱커
	-- 헤더만 켜진 채로 답을 내면 딜러가 전부 `"norole"`이 되고, [탱커]와 [역할 없음]을 고른
	-- 사용자에게 딜러까지 걸린다. 그래서 표를 세우고 내리는 자리는 **셋을 켜기로 정하는 리빌드 하나**다.
	--
	-- 리빌드가 `ClearPreviousBindings`에서 안 건드린다. 로스터가 채우는 표라서, 켜져 있는 동안
	-- 리빌드가 지우면 헤더가 다음에 재배치될 때까지 전원이 미상으로 보인다.
	UnitRoles = false

	-- 각 역할 헤더가 마지막으로 `UnitRoles`에 써넣은 토큰들. 헤더가 다시 배치될 때 자기 몫만
	-- 지우고 다시 채우려고 든다. 평평한 표를 훑어 값으로 골라내는 것보다 정확하고, 읽는 쪽은
	-- 조회 하나로 남는다.
	RoleOwners = false

	UnitStates = newtable()
	States = newtable()
	DirtyFlags = newtable()

	-- Does Blizzard's beat already come every frame? `UpdateBindings` bakes this on every rebuild
	-- from the throttle the reader's slider asked for, and it is true only at zero and only while
	-- the beat is registered at all.
	--
	-- Where it is true, a wake of our own can never be earlier than the beat, so
	-- `_onattributechanged` turns straight round on one. Where it is false, our wakes are the only
	-- thing that carries a hover crossing or a switch before the next tick.
	PollEveryFrame = false

	OldStates = newtable()

	_macrotextsSeen = newtable()
	_isUpdatingMacrotests = false
	_switchesUpdating = newtable()

	-- 유닛 조건을 클릭 시점에 풀 때 필요한 분류. 화이트리스트 밖이라 스니펫이 스스로
	-- 알 수 없으므로 아래에서 실어 보낸다.
	--
	-- **값이 곧 `needsExists`이고, 멤버십 검사는 `~= nil`이다.** 별칭이 아니면 nil, 별칭이면
	-- false/true 중 하나 - 즉 `if (UnitAliasNeedsExists[u])`로 물으면 custom1/custom2 밖의
	-- 별칭이 통째로 빠지고 조용히 맨 유닛 토큰으로 떨어진다. 반드시 `~= nil`로 물을 것.
	UnitAliasNeedsExists = newtable()

]]);

do
	-- custom1/custom2만 두 겹이다. tank/healer/maintank/mainassist/hover는 UnitWatch가
	-- UnitAliasMap에 넣어준 것 자체가 존재 증거라는 규약이고, 옛 경로(UpdateBindings.lua의
	-- 유닛 상태 표현식)가 이미 그렇게 갈라져 있다. 여기서 통일하면 조건이 조용히 빡빡해진다.
	local needsExists = { custom1 = true, custom2 = true };
	local lines = {};
	for alias in pairs(Constants.SPECIAL_UNITS) do
		lines[#lines + 1] = format("UnitAliasNeedsExists[%q]=%s", alias,
			needsExists[alias] and "true" or "false");
	end
	SecureHandlerExecute(BindingDriver, table.concat(lines, "\n"));
end


--- 본문 로그. **빌드 시점에 가른다** - 릴리스에서는 문자열 자체가 비어서 스니펫에 그 줄이
--- 아예 없다. `printMacroText` 안쪽의 DEBUG 검사만으로는 늦다: 그건 이미 샌드박스를 넘어온
--- 뒤라, 실사용자도 전투 중 상태가 바뀔 때마다 의존 바인딩 수만큼 `CallMethod`를 치른다.
--- 아래 `UpdateBindings`가 같은 방식으로 갈린다.
local PRINT_MACROTEXT_SNIPPET = DebindPrivate.DEBUG and [[
	self:CallMethod("printMacroText", entry.attr or entry.state or "?", s)
]] or "";

--- Composes one macro body. The caller declares `entry`, `s`, `unitframeAlias`, `clickSwitches` and
--- `pressUnit` and hands them in; `clickSwitches` is what a press worked out, nil where no press is
--- running, and `pressUnit` is the unit the winner goes out at, nil where it aims at nothing.
---
--- **`@@` with no unit goes out as a lone `@`**, which the client ignores wherever it sits in the
--- group (`devdocs/implementing-focus-and-self-cast.md` §2-3). `@target` in its place would drop
--- the engine's automatic self-cast.
---
--- **Two places bake.** When a state moves (`UpdateMacroTexts`), and when a click arrives (the
--- `OnClick` wrapper below). So the composition is one copy spliced into both -- two copies and
--- the day comes when `arg.reverse` is fixed on one side only, and that body goes out inverted
--- with nothing to say so.
---
--- **`unitframeAlias` comes from the caller, and that is what keeps this one copy.** When a state
--- moves the hovered unit can only be `UnitAliasMap["unitframe"]`, but **at a click that value must
--- not be used**: the wrapper reads the unit off the frame again to judge the conditions and aims
--- at what it read, so taking only the body from the cache **splits the unit that was judged from
--- the unit the body aims at.** On a spell whose effect forks on friend or foe, that is not "the
--- action does not go out" but "a different one does".
---
--- Only the even slots are overwritten. The odd ones are the literals the parser left, and
--- `#entry.args` is the number of even slots (`ParseMacroText`).
local COMPOSE_MACROTEXT_SNIPPET = [==[
	for i = 1, #entry.args do
		local arg = entry.args[i]
		local value
		if (arg.unit) then
			-- **No ternary stand-in here.** `unitframeAlias` is nil while nothing is hovered, so
			-- `arg.unit == "unitframe" and unitframeAlias or UnitAliasMap[arg.unit]` falls through to the
			-- cache in exactly that case -- which is the thing the comment above exists to stop.
			if (arg.unit == "unitframe") then
				value = unitframeAlias
			else
				value = UnitAliasMap[arg.unit]
			end
			value = value or "raid41"
		elseif (arg.pressUnit) then
			value = pressUnit or ""
		elseif (arg.state) then
			value = clickSwitches and clickSwitches[arg.state]
			if (value == nil) then
				value = States[arg.state]
			end
			value = value and true or false
			if (arg.reverse) then
				value = not value
			end
			value = value and "" or "known:0"
		elseif (arg.fixed) then
			value = arg.fixed
		end
		entry.fragments[i * 2] = value
	end
	s = table.concat(entry.fragments)
]==];

--- Works every computed switch out for this press, once, into `ClickSwitches`. Spliced where a
--- press first needs a switch: a record that carries one, or a body on the winner's button.
---
--- **In `ComputedSwitches` order**, so a switch that reads another reads what this press just got.
--- The caller has `unitframeUnit` in hand, which is what `@hover` inside a switch aims at.
---
--- **A switch that moved is written and reported here.** The Switches tab reads what the report
--- writes, and a switch off the beat has nothing else to write it.
local COMPUTE_SWITCHES_SNIPPET = [==[
	if (not ClickSwitchesReady) then
		ClickSwitchesReady = true
		wipe(ClickSwitches)
		for n = 1, #ComputedSwitches do
			local name = ComputedSwitches[n]
			local s
			local entry = SwitchEntries[name]
			if (entry) then
				local unitframeAlias = unitframeUnit
				local clickSwitches = ClickSwitches
				local pressUnit
]==] .. COMPOSE_MACROTEXT_SNIPPET .. [==[
			else
				s = SwitchExpressions[name]
			end
			local answer = SecureCmdOptionParse(s or "") and true or false
			ClickSwitches[name] = answer
			if (States[name] ~= answer) then
				States[name] = answer
				debind_driver:CallMethod("OnSwitchChanged", name, answer)
			end
		end
	end
]==];

BindingDriver:SetAttribute("UpdateMacroTexts", [=[
	local key = ...
	for state, dependents in pairs(MacroTextsMap) do
		if (key == true or key == state or DirtyFlags[state]) then
			for i = 1, #dependents do
				local entry = dependents[i]
				local s
				local unitframeAlias = UnitAliasMap["unitframe"]
				local clickSwitches
				local pressUnit
]=] .. COMPOSE_MACROTEXT_SNIPPET .. [=[

				-- **Only a switch's expression is finished here.** A button's body is held back
				-- for the click in `DeferredMacroTexts` (`EmitMacroTextEntries` in
				-- `UpdateBindings.lua`), so what moves with a unit or a switch and is not a button
				-- is this, and the log belongs here.
]=] .. PRINT_MACROTEXT_SNIPPET .. [=[

				-- No "did the text change" guard around this. The pass already parsed the
				-- previous `SwitchExpressions[entry.state]` before reaching here, so the parse
				-- below is what the newly composed text needs; skipping it when the text is
				-- unchanged would save one call, and this only runs because something the
				-- text depends on went dirty, so unchanged is the rare case.
				-- It stood as `if (true or ... ~= s)`, which read as a guard and was not one.
				if (entry.state) then
					SwitchExpressions[entry.state] = s
					local newValue = SecureCmdOptionParse(s) and true or false
					if (States[entry.state] ~= newValue) then
						self:RunAttribute("SetSwitch", entry.state, newValue, true)
					end
				end
			end
		end
	end
]=]);

--- Bakes the winning record's macro body at the click. Spliced in **after the winner is settled
--- and before the button name goes back**, and after `RESOLVE_UNIT_SNIPPET`, whose `unit` is what
--- `@@` in the body becomes.
---
--- **No `RunAttribute` and no `RunFor`.** Splicing is what keeps the 2026-08-11 decision standing.
---
--- **It buys one allocation.** This wrapper's rule is that the click path builds no strings, and
--- here one `table.concat` does. That is this item's trade: rebuilding **every** `@hover` body
--- while the cursor sweeps a raid frame becomes **the one that won** per click. A click runs at
--- hand speed, ten a second at the outside; sweeping frames does not.
---
--- A button that is not in `DeferredMacroTexts` costs nothing here. A static body stands as
--- `StampBinding` wrote it, and a body that has to move with a state and is not here belongs to
--- `UpdateMacroTexts` above.
--- The same log on the click side. **`debind_driver`, not `self`** -- this wrapper's `self` is
--- the frame it wraps, and `printMacroText` is not on that one.
local PRINT_BAKED_MACROTEXT_SNIPPET = DebindPrivate.DEBUG and [[
		debind_driver:CallMethod("printMacroText", entry.attr, s)
]] or "";

local BAKE_WINNER_MACROTEXT_SNIPPET = [==[
	local entry = DeferredMacroTexts[winner.clickbutton]
	if (entry) then
]==] .. COMPUTE_SWITCHES_SNIPPET .. [==[
		local s
		local unitframeAlias = unitframeUnit
		local clickSwitches = ClickSwitches
		local pressUnit = unit
]==] .. COMPOSE_MACROTEXT_SNIPPET .. PRINT_BAKED_MACROTEXT_SNIPPET .. [==[
		DefaultClickFrame:SetAttribute(entry.attr, s)
	end
]==];

--- The slot an action button action fires, worked out at the press
--- (`devdocs/dropping-the-game-fallback.md` §4). Declares `slotButton`, the name to answer with
--- where the winner is one. Needs `winner`.
---
--- **A check the Blizzard binding makes on the press is made here too, and it cancels the click.**
--- `EXTRAACTIONBUTTON1` does nothing without `HasExtraActionBar()`, and `BONUSACTIONBUTTONn` nothing
--- without `PetHasActionBar()`, which the restricted environment does not have: a pet it cannot
--- control is not `pet`, so `UnitExists("pet")` answers the same. **The winner is already settled,
--- so nothing under it fires instead**; passing a press on is what the reader's own conditions do,
--- in `EVAL_SNIPPET` (2026-09-14, owner).
---
--- **The page is `ActionBarController_UpdateAll`'s order**, and a bonus bar only counts on page 1.
---
--- **A flyout slot goes to the bar button that shows it.** `SECURE_ACTIONS.action` opens a flyout
--- with `SpellFlyout:Toggle(self, ...)`, which calls `GetPopupDirection` on the button that fired,
--- and ours has none. The skinned override bar has its own buttons, and `IsShown` rather than
--- `IsVisible` picks between them: the bar slides out still visible.
local ACTION_SLOT_SNIPPET = [==[
	local slotButton
	local actionSlot = ActionSlots[winner.clickbutton]
	if (actionSlot) then
		if (actionSlot.extra and not HasExtraActionBar()) then
			return false
		end
		if (actionSlot.pet) then
			if (not UnitExists("pet")) then
				return false
			end
			slotButton = winner.clickbutton
		else
			local page = actionSlot.page
			if (not page) then
				if (HasVehicleActionBar()) then
					page = GetVehicleBarIndex()
				elseif (HasOverrideActionBar()) then
					page = GetOverrideBarIndex()
				elseif (HasTempShapeshiftActionBar()) then
					page = GetTempShapeshiftBarIndex()
				elseif (HasBonusActionBar() and GetActionBarPage() == 1) then
					page = GetBonusBarIndex()
				else
					page = GetActionBarPage()
				end
			end
			local slot = actionSlot.index + (page - 1) * 12
			if (GetActionInfo(slot) == "flyout") then
				slotButton = actionSlot.bar
				if (actionSlot.overrideBar and OverrideActionBar and OverrideActionBar:IsShown()) then
					slotButton = actionSlot.overrideBar
				end
				if (not slotButton) then
					return false
				end
			else
				DefaultClickFrame:SetAttribute(actionSlot.attr, slot)
				slotButton = winner.clickbutton
			end
		end
	end
]==];

--- The unit the winner is cast at, as `unit`. Spliced into the click wrapper and into the DEBUG
--- eval hooks.
local RESOLVE_UNIT_SNIPPET = [==[
	-- **hover는 조건을 판정한 그 유닛에 그대로 쏜다.** UnitAliasMap["unitframe"]는 enter와 폴링이
	-- 채우는 캐시라 프레임의 유닛이 바뀌면 늦게 따라온다. 조건은 live로 읽어놓고 대상만
	-- 캐시에서 가져오면 **판정한 유닛과 시전 대상이 갈린다** - 우호로 판정해 놓고 옛 유닛에
	-- 쏘는 것이다. 옛 경로는 둘 다 캐시라 적어도 일관됐으니 그보다 나빠진다.
	--
	-- 우호/적대로 효과가 갈리는 주문(회개 같은)에서는 이게 "액션이 안 나감"이 아니라
	-- **"다른 액션이 나감"**이고 되돌릴 수 없다. 반드시 같은 유닛이어야 한다.
	local unit
	if (winner.unit) then
		unit = winner.unit
	elseif (winner.unitAlias) then
		if (winner.unitAlias == "unitframe") then
			unit = unitframeUnit
		else
			unit = UnitAliasMap[winner.unitAlias]
		end

		-- **An alias that resolves to nothing gets a unit that does not exist.** Left nil the action
		-- has no target and goes at the current one -- `@tank` set up, played alone, casts at
		-- whatever is targeted.
		--
		-- 옛 경로는 delegate가 `unit or "raid41"`을 들고 있어서(`SetUnit`) 게임이
		-- `GetConvertedButtonUnitAndActionType`의 `UnitExists` 검사에서 중단했다.
		-- 아무 일도 일어나지 않는 것이 맞는 동작이고, 같은 자리를 지킨다.
		unit = unit or "raid41"
	end
]==];

--- The button a press actually ends at, as `castButton`. Spliced into the click wrapper and into
--- the DEBUG eval hook, so what a test reads is what fires.
---
--- **A target the reader chose turns the engine's automatic self-cast off**, by going out through
--- the twin button `StampBinding` baked -- a macro body that flips the CVar around the real
--- button. Without it the same profile answers two ways: a chosen unit that exists casts and gets
--- redirected to the caster, and one that does not exist is dropped by the client's `UnitExists`
--- guard with nothing happening at all
--- (`devdocs/matching-the-clients-cast-targeting.md` §2-2).
---
--- **Press-and-hold keeps the direct route.** The macro runs once, and the hold the gate starts on
--- the down edge has no release to pair with inside one; wrapping it would trade a chosen target
--- for a spell that never finishes.
---
--- Needs `winner` and `unit` declared by the caller.
local SELFCAST_OFF_SNIPPET = [==[
	local castButton = winner.clickbutton
	if (unit and not winner.pressAndHold) then
		local wrapper = SelfCastWrappers[castButton]
		if (wrapper) then
			CastFrame:SetAttribute("unit", unit)
			castButton = wrapper
		end
	end
]==];

BindingDriver:SetAttribute("SetSwitch", [[
	local name, value, skipUpdate = ...
	if (States[name] ~= value) then
		if (not _switchesUpdating[name]) then
			_switchesUpdating[name] = true
			
			States[name] = value
			DirtyFlags[name] = true
			
			if (not skipUpdate) then
				if (MacroTextsMap[name]) then
					self:RunAttribute("UpdateMacroTexts", name)
				end

				debind_driver:SetAttribute("state-unitexists", name)
			end

			self:CallMethod("OnSwitchChanged", name, value)
			_switchesUpdating[name] = false
		end
	end
]]);

BindingDriver:SetAttribute("ToggleSwitch", [[
	local name = ...
	return self:RunAttribute("SetSwitch", name, not States[name])
]]);

BindingDriver:SetAttribute("SetUnit", [[
	local alias, unit, force = ...
	local changed = UnitAliasMap[alias] ~= unit
	local dirty = false
	if (changed or force) then
		UnitAliasMap[alias] = unit

		local delegateFrame = DelegateFrames[alias]
		if (delegateFrame) then
			delegateFrame:SetAttribute("unit", unit or "raid41")
		end

		-- **The row's existence is how a snippet asks "is this alias measured".** A rebuild wipes
		-- `UnitStates` and puts a row back for every unit in `_measuredUnitAxes`, so there is one
		-- here exactly when moving this alias can change what a key answers.
		if (UnitStates[alias] ~= nil) then
			dirty = true
		end

		if (MacroTextsMap[alias]) then
			self:RunAttribute("UpdateMacroTexts", alias)
		end

		-- **Hover is not announced outside** (2026-08-22). What sets it apart from the other
		-- aliases is not how often it moves but **what knowing it is good for**. `custom1` was
		-- pointed at somebody a while ago, so asking who that is now makes sense; hover is the
		-- unit on the frame the cursor is on right now, and looking at the cursor is faster.
		--
		-- So this one line was crossing to the insecure side **twice per frame the cursor swept**
		-- (enter and leave) to fire a `UNIT_CHANGED` nobody was listening for.
		-- `DebindPrivate.Units.unitframe` is empty from here on.
		if (not force and alias ~= "unitframe") then
			self:CallMethod("OnSpecialUnitChanged", alias, unit)
		end
	end

	return dirty;
]]);

--- 역할 헤더 하나가 방금 배치한 결과를 `UnitRoles`에 옮긴다.
---
--- 부르는 쪽(`UnitWatch.lua`의 `CheckUnits`)은 UnitWatch의 환경에서 돌고 `UnitRoles`는 여기
--- 드라이버 환경에 있다. 토큰을 마흔 개까지 인자로 넘기는 대신 여기서 자식을 직접 읽으면,
--- 걷는 일이 표가 있는 쪽에서 끝난다.
---
--- **헤더는 인자가 아니라 frameref로 온다.** 프레임 핸들을 `RunAttribute`의 인자로 넘기면
--- 저쪽에 nil로 도착한다(2026-08-28 게임에서 확인). 블리자드도 프레임을 다른 환경에 건네는
--- 자리는 `RunFor`의 `self`뿐이고, 핸들을 가변 인자로 흘리는 코드는 클라이언트에 없다.
--- `UnitWatch.lua`가 헤더를 배선할 때 `rolehdr_<별칭>`으로 붙여둔다.
---
--- 유닛이 없는 칸에서 멈춘다. 헤더는 채운 칸을 앞에서부터 쓰고 남은 칸을 비우므로, 첫 빈 칸이
--- 곧 끝이다.
BindingDriver:SetAttribute("SetRoleUnits", BakeSnippet([==[
	local alias, numFrames = ...
	if (not UnitRoles) then
		return
	end
	local header = self:GetFrameRef("rolehdr_"..alias)
	if (not header) then
		return
	end

	local owned = RoleOwners[alias]
	if (not owned) then
		owned = newtable()
		RoleOwners[alias] = owned
	end
	for i = 1, #owned do
		UnitRoles[owned[i]] = nil
		owned[i] = nil
	end

	for i = 1, numFrames do
		local unit = header:GetFrameRef("child"..i):GetAttribute("unit")
		if (not unit) then
			break
		end
		UnitRoles[unit] = alias
		owned[i] = unit
	end

	-- **역할이 바뀌는 사건은 이 자리 하나뿐이다.** 슬롯의 유닛은 그대로인데 그 사람의 역할만
	-- 바뀌는 것도 여기서만 생기므로, 폴링이 비트마다 다시 잴 이유가 없다. 슬롯을 들고 있으면
	-- 여기서 한 번 맞춰주고, 달라졌을 때만 깨운다.
	local unitframe = States.unitframe
	if (unitframe and unitframe.unit) then
		local role
		if (unitframe.frameType == CONSTANTS.FRAMETYPE_GROUP) then
			role = UnitRoles[unitframe.unit] or "norole"
		end
		if (unitframe.role ~= role) then
			unitframe.role = role
			DirtyFlags.unitframe = true
			self:SetAttribute("state-unitexists", "unitframe")
		end
	end
]==]));

--- **역할 조건을 한 번도 안 쓴 사람도 여기로 온다.** `tank`와 `healer`는 별칭이면서 역할
--- 헤더라, `@tank` 바인딩을 지우는 것만으로 `DisableUnitWatch`가 이것을 부른다. 그때 표는 로드
--- 이후 한 번도 안 선 `false`이므로, `SetRoleUnits`와 같은 가드가 여기도 있어야 한다.
BindingDriver:SetAttribute("ClearRoleUnits", [==[
	local alias = ...
	if (not RoleOwners) then
		return
	end
	local owned = RoleOwners[alias]
	if (owned) then
		for i = 1, #owned do
			UnitRoles[owned[i]] = nil
			owned[i] = nil
		end
	end
]==]);

BindingDriver:SetAttribute("UpdateAllUnits", [[
	self:RunAttribute("SetUnit", "tank", UnitAliasMap["tank"], true)
	self:RunAttribute("SetUnit", "healer", UnitAliasMap["healer"], true)
	self:RunAttribute("SetUnit", "maintank", UnitAliasMap["maintank"], true)
	self:RunAttribute("SetUnit", "mainassist", UnitAliasMap["mainassist"], true)
	self:RunAttribute("SetUnit", "custom1", UnitAliasMap["custom1"], true)
	self:RunAttribute("SetUnit", "custom2", UnitAliasMap["custom2"], true)
	self:RunAttribute("SetUnit", "unitframe", UnitAliasMap["unitframe"], true)
]]);

--- 클릭캐스팅 클릭이 우리 프레임까지 왔는지 보고한다. **빌드 시점에 가른다** - 릴리스에서는
--- 문자열이 비어서 스니펫에 이 줄이 아예 없다.
---
--- 이 갈래의 실패는 전부 조용하다. 라우팅이 안 걸리면 클릭이 아예 안 오고, 색인이 어긋나면
--- 와서 아무것도 못 찾는다. 둘 다 오류도 로그도 없어서 **로그가 안 나오는 것 자체가 답이
--- 되도록** 도착 즉시 찍는다.
---
--- 맨이름 마우스 버튼으로 이 프레임에 도착하는 길은 클릭캐스팅 라우팅뿐이다. 키 바인딩은
--- `"@" + 키` 이름으로 오고 옛 위임은 `deb1xx`로 오므로 여기 안 걸린다.
local CLICKCAST_ARRIVAL_SNIPPET = DebindPrivate.DEBUG and [==[

			debind_driver:CallMethod("OnClickCastArrival", button, mod,
				bindings and #bindings or 0)
]==] or "";

BindingDriver:SetAttribute("InitFrame", [==[
	local button = self
	ccframes[button] = ccframes[button] or newtable()
	ccframes[button].frame = button
	ccframes[button].frameType = 0
	-- `*clickbutton-debind1`은 여기 없다. 값이 프레임이라 보안 스니펫이 쓰면 핸들이 그대로
	-- 저장되고 비보안 쪽이 진짜 프레임을 못 얻는다. 등록 때 비보안 쪽에서 한 번 쓴다
	-- (`FrameRegistry.lua`의 `ApplyDebindRouting`).
]==]);

BindingDriver:SetAttribute("DeinitFrame", [==[
	local button = self
	local info = ccframes[button]
	if (info) then
		if (info == States.unitframe) then
			States.unitframe = nil
			if (debind_driver:RunAttribute("SetUnit", "unitframe", nil)) then
				DirtyFlags.unitframe = true
				debind_driver:SetAttribute("state-unitexists", "unitframe")
			end
		end
		info.frame = nil
	end
	ccframes[button] = nil
]==]);

-- **A frame with no row stands down, and empties the slot on its way out.** The wrapper is never
-- taken off (`FrameRegistry.lua`), so this body still runs on a frame the addon stopped watching.
-- Leaving quietly would be wrong: the cursor being inside that frame is proof it is not inside
-- whatever was recorded last, and `setup_onleave` is the cleanup for an `OnLeave` that never
-- arrived. Keeping the wrapper is what makes a deregistered frame one more witness to it.
--
-- **The call is a statement and the `return` carries nothing**, rather than `return <call>`.
-- A wrapped `OnEnter` reads the first value its pre-body answers with and skips the frame's own
-- handler on `false` (`SecureHandlers.lua`, `Wrapped_OnEnter`). Forwarding whatever
-- `setup_onleave` happens to answer with would put that contract in the other body's hands.
--
-- A frame whose unit does not exist counts as **not hovering**, and the frame is still recorded
-- so the poll can pick it back up when the unit returns. Recording it is what makes recovery
-- possible: neither enter nor leave fires while the cursor sits still, so dropping the frame
-- here would strand the hover slot until the user moved the mouse.
--
-- `reaction == nil` is the marker. Every reader gates on it rather than on the frame being
-- present, which is what the click path was already doing on its own.
--- **`setup_onenter` goes on a frame as it is**, because nothing has to run around it: what
--- `Reassemble` takes off a frame it puts straight back, so the chain runs the other addon's enter
--- bodies itself.
---
--- **`setup_onleave` is the one that needs a second attribute.** `setup_onleave_wrap` is this text
--- with the one leave body the client will not reach spliced after it (`FrameRegistry.lua`), and
--- that is what goes on a frame; the plain one is what `clickcast_onleave` runs for an addon that
--- copies it, and what `setup_onenter` falls to when the frame has no row.
---
--- **Spliced and not called.** The wrapped body is the hover hot path, and a `RunAttribute` between
--- it and the epilogue would be paid on every frame boundary the cursor crosses. One source, two
--- attributes, no drift.
---
--- **Neither fragment may end in a `return` that leaves the body.** What follows it is what answers
--- Blizzard, so an early exit here would skip it. That is why the "no row" case below is an
--- `if/else` rather than a return.
local SETUP_ONENTER_SNIPPET = [==[
	local unit = self:GetEffectiveAttribute("unit")

	local unitframe = ccframes[self]
	if (not unitframe) then
		debind_driver:RunAttribute("setup_onleave")
	else

	local reaction
	local role
	if (unit and UnitExists(unit)) then
		if (PlayerCanAssist(unit)) then
			reaction = CONSTANTS.REACTION_HELP
		elseif (PlayerCanAttack(unit)) then
			reaction = CONSTANTS.REACTION_HARM
		else
			reaction = CONSTANTS.REACTION_OTHER
		end
		-- **nil이 "답할 수 없다"다**, `reaction`이 nil로 "호버 아님"을 말하는 것과 같은 모양.
		-- 판정하는 쪽은 nil이면 그냥 지나가므로 두 경우를 가릴 필요가 없다.
		--
		-- 표가 없으면 세 헤더가 다 서 있지 않다는 뜻이라 `"norole"`조차 낼 수 없다. 그리고
		-- 파티/공대 개체창이 아니면 토큰을 안 본다. 맵의 키가 그룹 유닛 토큰이라, 플레이어
		-- 프레임의 `player`는 파티에서는 맵에 있고 공대에서는 없다.
		if (UnitRoles and unitframe.frameType == CONSTANTS.FRAMETYPE_GROUP) then
			role = UnitRoles[unit] or "norole"
		end
	else
		unit = nil
	end

	local unitChanged = unitframe.unit ~= unit or unitframe.reaction ~= reaction
			or unitframe.role ~= role
	if (States.unitframe ~= unitframe or unitChanged) then
		unitframe.unit = unit
		unitframe.reaction = reaction
		unitframe.role = role
		States.unitframe = unitframe
		if (debind_driver:RunAttribute("SetUnit", "unitframe", unit)) then
			DirtyFlags.unitframe = true
			debind_driver:SetAttribute("state-unitexists", "unitframe")
		end
	end

	end
]==];

local SETUP_ONLEAVE_SNIPPET = [==[
	local unitframe = States.unitframe
	if (unitframe) then
		States.unitframe = nil
		if (debind_driver:RunAttribute("SetUnit", "unitframe", nil)) then
			DirtyFlags.unitframe = true
			debind_driver:SetAttribute("state-unitexists", "unitframe")
		end
	end
]==];

BindingDriver:SetAttribute("setup_onenter", BakeSnippet(SETUP_ONENTER_SNIPPET));

BindingDriver:SetAttribute("setup_onleave", SETUP_ONLEAVE_SNIPPET);

--- The one leave body the client will not reach, run here in its own header's environment
--- (`FrameRegistry.lua`, `Reassemble`).
---
--- **Only `OnLeave` has one of these.** Everything `Reassemble` takes off a frame goes straight
--- back on, so the enter and click chains go on running themselves; `Wrapped_OnLeave` clears
--- `_wrapentered` before it descends, so the body that was outermost stops being reached the
--- moment we are.
---
--- **The empty case costs one lookup**, which is what the `Overs` shape is arranged for: a frame
--- nobody else wrapped has no row at all, so `Overs[self]` is nil and the block is skipped.
---
--- **What it answers with is what we answer with.** Those two values are the ones
--- `Wrapped_OnLeave` would have read off that body had it still been outermost: `false` stops the
--- descent, and a message is the only thing that gets a post body called at all. Handing them out
--- rather than storing them is also what puts its post in reach, since Blizzard calls ours only
--- where our pre answered with something.
local OVERS_LEAVE_RUN_SNIPPET = [==[
	local over = Overs[self]
	if (over and over.pre) then
		return over.handle:RunFor(self, over.pre)
	end
]==];

--- The other half, after the frame's own handler has run. `message` is what that body answered
--- with a moment ago, handed back to us by the client.
local OVERS_LEAVE_POST_SNIPPET = [==[
	local over = Overs[self]
	if (over and over.post) then
		over.handle:RunFor(self, over.post, message)
	end
]==];

BindingDriver:SetAttribute("setup_onleave_wrap",
	BakeSnippet(SETUP_ONLEAVE_SNIPPET .. OVERS_LEAVE_RUN_SNIPPET));
BindingDriver:SetAttribute("setup_onleave_post", BakeSnippet(OVERS_LEAVE_POST_SNIPPET));

--- **Part of the `ClickCastHeader` shape and read by nobody here.** These are the bodies the
--- header protocol expects a click-casting header to carry, so that an addon which copies them
--- onto its own children gets hover casting the way it would from Clique. Nothing of ours copies
--- them any more: our own frames get the hover wrappers instead (`FrameRegistry.Reassemble`), and
--- the header door hands out a name rather than setting a child up (`clickcast_register` below).
---
--- **So they resolve the header themselves.** They used to read a `debind_driver` that the header
--- door planted in the child's own environment, which meant they only worked on a child we had
--- set up -- and once that planting went, a body copied by anyone else would have died on a nil.
--- This is the shape Clique's own two carry (`Clique/core/core.lua`), and it asks the frame's
--- parent for the header the way the protocol already requires.
BindingDriver:SetAttribute("clickcast_onenter", [==[
	local header = self:GetParent():GetFrameRef("clickcast_header")
	header:RunFor(self, header:GetAttribute("setup_onenter"))
]==]);

BindingDriver:SetAttribute("clickcast_onleave", [==[
	local header = self:GetParent():GetFrameRef("clickcast_header")
	header:RunFor(self, header:GetAttribute("setup_onleave"))
]==]);

--- **One body, whatever Clique is doing.** Every unit frame is ours, Clique's included, so a hover
--- over any of them fills `States.unitframe` the ordinary way and there is no frame left for a
--- second shape to answer for
--- (`devdocs/legacy/taking-every-unit-frame-with-one-blacklist.md` §1-1).
BindingDriver:SetAttribute("GetUnitFrameUnit", [==[
	local unitframe = States.unitframe
	if (unitframe and unitframe.frame) then
		local unit = unitframe.frame:GetEffectiveAttribute("unit")
		if (unit and UnitExists(unit)) then
			return unit
		end
	end
]==]);

--- **The header door hands out a name and registers nothing.** It used to set the frame up
--- from in here and write our row from `CallMethod`, which was always half the job: what wires
--- a frame for us is `SecureHandlerWrapScript` on its `OnClick` and the routing attributes
--- beside it (`FrameRegistry.ApplyDebindRouting`), and both of those are insecure calls that a
--- fight blocks. A child registered here mid-fight had its restricted half done and its clicks
--- sitting in `RegisterClickQueue` until the fight ended.
---
--- What signalling buys is **one gate instead of two**. The pack switch, the refusals a frame
--- is written off for, the combat queue and the kind are asked once, in `RegisterFrame`, for
--- every door. The pack switch is the one that never got a second copy written: a pack the
--- reader had turned off went on registering through its group headers, and what the box did
--- depended on which layout that reader had picked.
---
--- **What it costs.** This body runs in the restricted environment, so it ran during a fight
--- and the `clickcast_onenter` it used to hang on the child filled the hover slot there. Now a
--- child first created mid-fight waits for the queue like every other frame. It is only ever
--- first creation -- a header runs `initialConfigFunction` once per child, and makes new ones
--- only when the group outgrows the largest size it has laid out this session.
---
--- **The name is all that can cross.** `CallMethod` scrubs its arguments down to strings,
--- numbers and booleans (`RestrictedFrames.lua`), so a header whose own name is nil hands its
--- children names that are nil too (`SecureGroupHeaders.lua` builds them as
--- `name and (name.."UnitButton"..i)`) and they cannot come through here. Clique is in the
--- same position and answers it the same way. `CollectHeaderChildren` reaches those frames by
--- object and needs no name.
BindingDriver:SetAttribute("clickcast_register", [==[
	local button = self:GetAttribute("clickcast_button")
	self:CallMethod("OnClickCastRegister", button:GetName())
]==]);

--- **Part of the `ClickCastHeader` shape and does nothing.** A header taking a child back is a
--- deregistration arriving from outside, and one of those means nothing here
--- (`devdocs/legacy/taking-every-unit-frame-with-one-blacklist.md` §1-5). The attribute stays
--- because a header calls it by name and a missing body raises where it is called from.
BindingDriver:SetAttribute("clickcast_unregister", "");

--- **A tick later, because the header is still building the child.** This is called from the
--- header's `initialConfigFunction`, inside the restricted environment, and registering runs
--- `InitFrame` straight back in through `SecureHandlerExecute`. Nothing here is urgent enough
--- to re-enter on a frame its own header has not finished configuring.
---
--- **Told group, never read.** A header hands its children whichever unit they are filling
--- right now, so the token on one says which slot it is and not what the frame is.
function BindingDriver:OnClickCastRegister(buttonName)
	if (not buttonName) then
		return;
	end
	C_Timer.After(0, function()
		local button = _G[buttonName];
		if (not button) then
			return;
		end
		-- **The mark goes on before the offer and `RegisterFrame` does the rest of it**,
		-- `hccframes` included. Writing that list here instead read the row at a moment when
		-- a fight had put the registration in the queue and there was none, so a child first
		-- created mid-fight went missing from the list Clique exposes.
		DebindPrivate.MarkHeaderOwned(button);
		DebindPrivate.RegisterFrame(button, "group");
	end);
end

--- 클릭캐스팅 클릭이 우리 프레임에 도착했다. DEBUG 빌드에서만 불린다.
---
--- **안 나오는 것도 답이다.** 유닛 프레임 클릭에 이게 안 찍히면 라우팅이 안 걸린 것이다
--- (`<접두사>type<N>`/`<접두사>clickbutton<N>`을 못 썼거나, 프레임이 자기 것으로 덮었거나).
--- 찍히는데 `n=0`이면 도착은 했고 그 버튼·수식어에 등록된 키가 없다는 뜻이다.
function BindingDriver:OnClickCastArrival(button, mod, n)
	DebindPrivate.log(format("|cff88ccff[Debind/clickcast]|r %s mod=%s -> %s",
		tostring(button), tostring(mod),
		(tonumber(n) or 0) > 0 and (tostring(n) .. "개") or "|cffff4444등록 없음|r"));
end

function BindingDriver:OnSpecialUnitChanged(alias, value)
	DebindPrivate.OnSpecialUnitChanged(alias, value);
end

function BindingDriver:OnSwitchChanged(name, value)
	DebindPrivate.OnSwitchChanged(name, value);
end

--- The condition evaluation, kept as its own string so more than one wrapper can carry it.
---
--- It is spliced in textually rather than called, which is what lets the locals it declares
--- (`unitframe`, `unitframeUnit`, `winner`) stay visible to whatever follows -- a `RunAttribute`
--- could not hand those back without turning each one into a shared global.
---
--- The caller owes it `bindings` (the records to walk) and `evalFrame` (which unit frame hover
--- means for this click, or nil), and must have declared `winner` and `unitframeUnit` itself -- they
--- are what it answers with, and a caller that only reaches this on one branch still has to read
--- them on the other.
---
--- The name has to end in `_SNIPPET`: that is what `tools/lib/snippets.js` resolves back into
--- the body it belongs to, and a body it cannot resolve leaves every static check silently.
local EVAL_SNIPPET = [==[
	-- hover는 루프 밖에서 클릭당 한 번만 푼다. 레코드마다 다시 물으면 같은 C 호출이 반복된다.
	-- 그 프레임의 unit과 반응은 지금 다시 읽는다 - 폴링이 놓치는 창이 여기서 닫힌다.
	--
	-- **어느 프레임이냐는 호출부가 정한다**(`evalFrame`). 키로 들어오면 enter/leave가 남긴
	-- 캐시를 볼 수밖에 없지만, 유닛 프레임 클릭으로 들어오면 그 프레임이 곧 자기 자신이라
	-- 캐시를 볼 이유가 없다.
	ClickSwitchesReady = false
	local unitframe = evalFrame
	local unitframeFrameType
	local unitframeRole
	if (unitframe) then
		unitframeUnit = unitframe.frame:GetEffectiveAttribute("unit")
		if (unitframeUnit and UnitExists(unitframeUnit)) then
			unitframeFrameType = unitframe.frameType
			-- 역할도 클릭당 한 번. **nil이 "답할 수 없다"다.** 표가 없으면 세 헤더가 다 서
			-- 있지 않다는 뜻이고, 파티/공대 개체창이 아니면 토큰이 맵의 키와 다르다.
			if (UnitRoles and unitframeFrameType == CONSTANTS.FRAMETYPE_GROUP) then
				unitframeRole = UnitRoles[unitframeUnit] or "norole"
			end
		else
			unitframe = nil
			unitframeUnit = nil
		end
	end

	-- **클릭 시점에 잴 수 있는 것은 잰다. 캐시는 안 읽는다.**
	--
	-- 상태 루프의 값은 구조적으로 낡아 있다 - 폴링이 최대 0.2초에, 계기가 이벤트인 축은
	-- 이벤트→매니저→틱 지연까지 얹힌다. 클릭은 진실을 잴 수 있는 시점이므로 잰다. 기준은
	-- 성능이 아니라 정확성이다.
	--
	-- **이 로컬들이 클릭 1회 메모다.** `nil`이면 아직 안 쟀다는 뜻이고, 한 번 재면 이 클릭이
	-- 끝날 때까지 그 값을 쓴다. 아무 레코드도 안 묻는 축은 C 호출이 아예 안 나간다.
	-- 측정된 값은 절대 nil이 아니므로(불리언·숫자) 이 표시가 값과 겹치지 않는다.
	local group, form, bonusbar
	local combat, stealth, specialbar, extrabar, petbattle
	local mounted, indoors, skyriding
	local flyable, advflyable, flying

	local memoReady = false

	-- 어느 갈래로 들어왔느냐가 곧 어느 레코드를 보느냐다. 한 키가 양쪽 레코드를 다 가질 수
	-- 있고 조건도 서로 다르므로, 도착한 경로의 것만 본다.
	local subset = clickCast and "isClickCast" or "holdsKey"

	-- **The held modifier picks the tier before any record is read, and only that tier is walked**
	-- (`devdocs/implementing-focus-and-self-cast.md` §3-4). Every action has a self and a focus
	-- twin, so walking the whole key would pass over two records per action on every press with
	-- nothing held. A tier with no winner ends the press there.
	--
	-- The client hides the modifiers that are part of the binding the press arrived on, so what
	-- `IsModifiedClick` answers here is only what was held on top of it (§2-1). A frame click has
	-- no binding name to hide them behind, and a modifier held there picked the binding itself
	-- (§3-10).
	--
	-- A key turned off in the settings is not asked about. It has no twins, so its tier holds
	-- nothing, and holding it has to land where holding nothing does (§3-12).
	local castModifier
	if (clickCast) then
		castModifier = CONSTANTS.CASTMOD_NONE
	elseif (SelfCastKeyOn and IsModifiedClick("SELFCAST")) then
		castModifier = CONSTANTS.CASTMOD_SELF
	elseif (FocusCastKeyOn and IsModifiedClick("FOCUSCAST")) then
		castModifier = CONSTANTS.CASTMOD_FOCUS
	else
		castModifier = CONSTANTS.CASTMOD_NONE
	end
	PROBE.MockState(castModifier)

	local first, last
	if (castModifier == CONSTANTS.CASTMOD_SELF) then
		first, last = 1, bindings.focusFrom - 1
	elseif (castModifier == CONSTANTS.CASTMOD_FOCUS) then
		first, last = bindings.focusFrom, bindings.noneFrom - 1
	else
		first, last = bindings.noneFrom, #bindings
	end

	for i = first, last do
		local t = bindings[i]
		if (t[subset]) then
			local match = true

			-- 호버 유닛의 존재와 반응은 아래 t.units["unitframe"]가 답한다. 그쪽도 여기서 잰
			-- unitframeUnit을 쓰므로 값이 갈릴 자리가 없다. 남은 것은 프레임의 종류뿐이다.
			if (match and t.frameTypes) then
				if (not unitframe) then
					match = false
				elseif ((t.frameTypes % (unitframeFrameType + unitframeFrameType)) < unitframeFrameType) then
					match = false
				end
			end

			-- **Switches first.** A manual one is a table read and the computed ones are worked out
			-- once for the whole press, so a record turned away here pays for none of the calls
			-- below.
			if (match and t.switches) then
]==] .. COMPUTE_SWITCHES_SNIPPET .. [==[
				for state, v in pairs(t.switches) do
					local value = ClickSwitches[state]
					if (value == nil) then
						value = States[state]
					end
					if (value ~= v) then
						match = false
						break
					end
				end
			end

			-- 아래는 **묻는 축만, 클릭당 한 번** 잰다. `match`가 이미 거짓이면 그 레코드의
			-- 남은 축은 아예 안 잰다 - 순서가 곧 비용인 것은 그대로고, 이제 그 비용이 테이블
			-- 조회가 아니라 C 호출이라 더 그렇다. 싼 것부터 놓는다.
			--
			-- **These have to match `Constants.STATE_EVAL_EXPRESSIONS`.** Written out rather than
			-- interpolated in, because `tools/lib/snippets.js` cannot resolve an assembled body and
			-- every snippet check then skips it. `tools/check-state-eval.js` holds the two together.
			if (match and t.combat ~= nil) then
				if (combat == nil) then
					combat = PlayerInCombat()
					PROBE.MockState(combat)
				end
				if (t.combat ~= combat) then
					match = false
				end
			end

			if (match and t.stealth ~= nil) then
				if (stealth == nil) then
					stealth = IsStealthed()
					PROBE.MockState(stealth)
				end
				if (t.stealth ~= stealth) then
					match = false
				end
			end

			if (match and t.mounted ~= nil) then
				if (mounted == nil) then
					mounted = IsMounted()
					PROBE.MockState(mounted)
				end
				if (t.mounted ~= mounted) then
					match = false
				end
			end

			if (match and t.indoors ~= nil) then
				if (indoors == nil) then
					indoors = IsIndoors()
					PROBE.MockState(indoors)
				end
				if (t.indoors ~= indoors) then
					match = false
				end
			end

			if (match and t.flyable ~= nil) then
				if (flyable == nil) then
					flyable = IsFlyableArea()
					PROBE.MockState(flyable)
				end
				if (t.flyable ~= flyable) then
					match = false
				end
			end

			if (match and t.advflyable ~= nil) then
				if (advflyable == nil) then
					advflyable = IsAdvancedFlyableArea()
					PROBE.MockState(advflyable)
				end
				if (t.advflyable ~= advflyable) then
					match = false
				end
			end

			if (match and t.flying ~= nil) then
				if (flying == nil) then
					flying = IsFlying()
					PROBE.MockState(flying)
				end
				if (t.flying ~= flying) then
					match = false
				end
			end

			if (match and t.skyriding ~= nil) then
				if (skyriding == nil) then
					skyriding = GetBonusBarOffset() == 5
					PROBE.MockState(skyriding)
				end
				if (t.skyriding ~= skyriding) then
					match = false
				end
			end

			if (match and t.extrabar ~= nil) then
				if (extrabar == nil) then
					extrabar = HasExtraActionBar()
					PROBE.MockState(extrabar)
				end
				if (t.extrabar ~= extrabar) then
					match = false
				end
			end

			if (match and t.groups ~= nil) then
				if (group == nil) then
					group = (UnitPlayerOrPetInRaid("player") and CONSTANTS.GROUP_RAID) or (UnitPlayerOrPetInParty("player") and CONSTANTS.GROUP_PARTY) or CONSTANTS.GROUP_NONE
					PROBE.MockState(group)
				end
				if ((t.groups % (group + group)) < group) then
					match = false
				end
			end

			-- **목은 잰 값에 걸리고 자리옮김은 그 뒤다.** 상태 루프가 `States.form`에 담는 것은
			-- 자세 번호이지 비트가 아니므로, 주입도 번호에 걸려야 양쪽이 같은 것을 뜻한다.
			if (match and t.forms) then
				if (form == nil) then
					form = GetShapeshiftForm()
					PROBE.MockState(form)
					form = 2 ^ (form or 0)
				end
				if ((t.forms % (form + form)) < form) then
					match = false
				end
			end

			if (match and t.bonusbars) then
				if (bonusbar == nil) then
					bonusbar = GetBonusBarOffset()
					PROBE.MockState(bonusbar)
					bonusbar = 2 ^ (bonusbar or 0)
				end
				if ((t.bonusbars % (bonusbar + bonusbar)) < bonusbar) then
					match = false
				end
			end

			-- **`petbattle`도 잰다.** 캐시로 둘 이유가 없었다 - 그 캐시를 채우는 것이 클릭이
			-- 없어도 영원히 도는 5Hz 파싱이라, "클릭당 파싱 대 캐시 읽기"라는 비교 자체가
			-- 채우는 값을 비용에서 빼놓고 있었다.
			if (match and t.petbattle ~= nil) then
				if (petbattle == nil) then
					petbattle = PROBE.SecureCmdOptionParse("[petbattle]") and true or false
					PROBE.MockState(petbattle)
				end
				if (t.petbattle ~= petbattle) then
					match = false
				end
			end

			-- **`specialbar`는 `petbattle`을 접어 쓴다** - 상태 루프의 측정식과 같은 모양이라야
			-- 답이 안 갈린다. 앞이 참이면 파싱까지 안 간다.
			if (match and t.specialbar ~= nil) then
				if (specialbar == nil) then
					specialbar = HasVehicleActionBar() or HasOverrideActionBar() or HasTempShapeshiftActionBar() or false
					if (not specialbar) then
						if (petbattle == nil) then
							petbattle = PROBE.SecureCmdOptionParse("[petbattle]") and true or false
							PROBE.MockState(petbattle)
						end
						specialbar = petbattle
					end
					PROBE.MockState(specialbar)
				end
				if (t.specialbar ~= specialbar) then
					match = false
				end
			end

			-- **`known`도 잰다.** 예전 주석은 *"답이 바뀌는 계기가 SPELLS_CHANGED 하나뿐이라
			-- 누를 때마다 파싱할 이유가 없다"*였는데, 이벤트로 무효화하는 길이 **없다** -
			-- 핸들러로 들어오는 값이 넷뿐이라 어느 틱이 SPELLS_CHANGED 때문인지 못 고른다.
			-- 그래서 그 캐시는 캐시가 아니라 클릭이 없어도 도는 재파싱이었다.
			--
			-- 메모를 안 둔다. 한 키의 `known` 레코드 수만큼이고 첫 일치에서 끊기므로, 프로필
			-- 전체의 서로 다른 주문 수를 5Hz로 파싱하던 것과 자릿수가 다르다.
			--
			-- `t.known`은 대괄호까지 포함해 구워둔다. 여기서 결합하면 클릭마다 문자열이
			-- 하나씩 나고, 이 판은 할당을 안 하는 판이다.
			if (match and t.known ~= nil and not PROBE.SecureCmdOptionParse(t.known)) then
				match = false
			end

			-- The spellbook gate, for the one spell `[known:]` cannot see: the warlock's pet dispel is
			-- in the spellbook only while the imp is out, and by name it answers true without one
			-- (`SpecSpells.lua`). Right under `known` for the same reason: a per-record check, cheaper than units.
			if (match and t.spellbook ~= nil and not PROBE.FindSpellBookSlotBySpellID(t.spellbook)) then
				match = false
			end

			if (match and t.units) then
				if (not memoReady) then
					memoReady = true
					wipe(ClickUnitExists)
					wipe(ClickUnitReaction)
					wipe(ClickUnitDead)
					wipe(ClickUnitGroup)
				end

				-- **The cache is not trusted here; every value is measured again.** `UnitStates`
				-- is filled by the update loop and so can be a tick old, and a click is rare
				-- enough that measuring again is both cheap and correct. The memo lives for the
				-- length of this one click.
				for u, cond in pairs(t.units) do
					local ok = true
					do
						local unit, needsExists
						if (u == "unitframe") then
							-- 위에서 프레임에서 직접 읽은 값을 쓴다. UnitAliasMap["unitframe"]는
							-- 캐시라 여기서만 그걸 보면 hover 조건과 다른 유닛을 판정하게
							-- 된다. 대상도 같은 값을 쓴다(아래 SetAttribute).
							unit = unitframeUnit
							-- **역할은 이 갈래에만 있다.** 가리킨 프레임에 대해서만 답이 나오는
							-- 축이라, 유닛 공통 자리에 두면 다른 유닛마다 헛도는 검사가 된다.
							-- `unitframeRole`이 nil이면 답할 수 없다는 뜻이라 이 축은 안 선다.
							if (unitframeRole and cond.role and not cond.role[unitframeRole]) then
								ok = false
							end
						else
							-- **한 번만 조회한다.** nil이면 별칭이 아니고, 아니면 그 값이
							-- 곧 답이다. false가 답인 별칭이 있으므로 `~= nil`로 가른다.
							needsExists = UnitAliasNeedsExists[u]
							if (needsExists ~= nil) then
								unit = UnitAliasMap[u]
							else
								unit = u
								needsExists = true
							end
						end

						-- Existence is resolved first now. The old shape could let
						-- `PlayerCanAssist` stand in for it -- false for an absent unit -- and
						-- save a call, but reaction has to come back as one of three names and
						-- an absent unit would resolve to "other". One more call on a path that
						-- runs once per keypress.
						local exists
						if (not unit) then
							exists = false
						elseif (needsExists) then
							exists = ClickUnitExists[unit]
							if (exists == nil) then
								exists = UnitExists(unit) and true or false
								ClickUnitExists[unit] = exists
							end
						else
							exists = true
						end

						if (cond.exists ~= nil and cond.exists ~= exists) then
							ok = false
						elseif (exists) then
							if (cond.reaction) then
								local reaction = ClickUnitReaction[unit]
								if (reaction == nil) then
									reaction = (PlayerCanAssist(unit) and "help")
											or (PlayerCanAttack(unit) and "harm")
											or "other"
									ClickUnitReaction[unit] = reaction
								end
								if (not cond.reaction[reaction]) then
									ok = false
								end
							end

							-- `ok` first: two C calls are worth a local read to skip when the
							-- reaction above already decided. `UnitIsDead` alone is not `[dead]` --
							-- a ghost answers false to it -- and the restricted environment has no
							-- `UnitIsDeadOrGhost`.
							if (ok and cond.dead ~= nil) then
								local dead = ClickUnitDead[unit]
								if (dead == nil) then
									dead = (UnitIsDead(unit) or UnitIsGhost(unit)) and true or false
									PROBE.MockUnitDead(unit)
									ClickUnitDead[unit] = dead
								end
								if (cond.dead ~= dead) then
									ok = false
								end
							end

							-- 조건은 네 칸으로 구워져 있고(`UpdateBindings.lua`), 그 칸은 두
							-- 답이 다 있어야 나온다. 겹치는 술어라 하나만 물어서는 "공대이면서
							-- 같은 소그룹"을 이웃 칸과 못 가른다.
							if (ok and cond.group) then
								local group = ClickUnitGroup[unit]
								if (group == nil) then
									local raid = UnitPlayerOrPetInRaid(unit)
									local party = UnitPlayerOrPetInParty(unit)
									group = (raid and (party and "both" or "raid"))
											or (party and "party")
											or "neither"
									PROBE.MockUnitGroup(unit)
									ClickUnitGroup[unit] = group
								end
								if (not cond.group[group]) then
									ok = false
								end
							end

						end
					end

					if (not ok) then
						match = false
						break
					end
				end
			end

			if (match) then
				winner = t
				PROBE.Winner(i)
				break
			end
		end
	end
]==];

--- 클릭 시점 평가. `DefaultClickFrame`의 OnClick을 감싼다.
---
--- **`PreClick`이 아니라 `OnClick`이다.** 래퍼는 자기가 감싼 스크립트만 붙들고 있어서
--- (`SecureHandlers.lua`의 `SaveWrapHandler`), PreClick에 걸면 바꾼 버튼 이름이 실제로
--- 액션을 실행하는 `SecureActionButton_OnClick`까지 전달되지 않는다. 스니펫은 돌고 로그도
--- 나오는데 액션만 아무것도 안 나가서 증상이 조용하다.
---
--- 반환값이 버튼 이름을 대신하고, 게임은 그 이름으로 `*type-<이름>` 등을 조회한다.
--- 액션 속성은 `SetBindingAttributes`가 이미 버튼 이름별로 구워둔 그대로 쓴다.
---
--- What a registered unit frame runs on its own OnClick, so a click-cast decision is made while
--- the frame is still underneath us.
---
--- **Returning nil here is the whole point.** It leaves the button name alone, so the click
--- carries on into Blizzard's click bindings and then the frame's own handler. That fallback is
--- only reachable from this side: once the click has been sent on to our button the frame is
--- behind us and there is nothing left to fall back to. So the conditions are judged here, and
--- our button is only named when one of them actually matched.
---
--- The name it answers with is `debind1`, which pairs with the fixed `*type-debind1` /
--- `*clickbutton-debind1` put on the frame at registration. It is a suffix nobody else uses, so
--- unlike the old routing this leaves the frame's own `type1`/`type2` untouched.
---
--- Nothing is stored anywhere the frame can see; the winner is handed to the wrapper on our own
--- button through the restricted environment both share.
--- **`nil` and not `false` wherever this declines.** The first value is what `Wrapped_Click` reads,
--- `false` there stops the descent, and the frame's own handler is not ours to cancel. Any other
--- value renames the button for everything below, so answering with `button` unchanged would put a
--- name on every click that used to carry none.
DebindPrivate.InstallSnippet(function(pre)
	DebindPrivate.UnitFrameClickPre = pre;
	-- 처음 구울 때는 아직 아무것도 안 감쌌고 `FrameRegistry`도 안 올라왔다. 재베이크에서만
	-- 할 일이 있다.
	if (DebindPrivate.RewrapUnitFrames) then
		DebindPrivate.RewrapUnitFrames();
	end
end, [==[
	local info = ccframes[self]
	if (not info) then
		return
	end

	local bindings
	local n = MouseButtonNumbers[button]
	if (n) then
		local mod = 0
		if (IsAltKeyDown()) then
			mod = mod + CONSTANTS.MOD_ALT
		end
		if (IsControlKeyDown()) then
			mod = mod + CONSTANTS.MOD_CTRL
		end
		if (IsShiftKeyDown()) then
			mod = mod + CONSTANTS.MOD_SHIFT
		end

		local byMod = ClickCastKeys[n]
		bindings = byMod and byMod[mod]
	end

	if (not bindings) then
		return
	end

	local clickCast = true
	local winner, unitframeUnit
	local evalFrame = info
]==] .. EVAL_SNIPPET .. [==[

	if (not winner or not winner.clickbutton) then
		return
	end

	-- **The edge we do not act on is swallowed.** Both edges are registered because
	-- which ones arrive is the frame's state and not ours (`FrameRegistry.lua`), so the press is
	-- there to be dealt with whether we wanted it or not, and it has to be spent: left alone it
	-- would run the frame's own action on the press and ours on the release, casting twice for one
	-- click. Answering it with `debindnull` -- a suffix nobody wrote an attribute for -- takes the
	-- click without running anything, and the frame's own `type1` is not read for it either.
	--
	-- **Which edge that is, is the reader's.** `ClickCastOnMouseDown` carries their answer, and
	-- where they left it alone it carries the game's (`ApplyOptions`). The release is what every
	-- unit frame Blizzard ships is registered for (`SecureUnitButton_OnLoad`), so that is what
	-- leaving it alone comes out as.
	--
	-- Only a click we are actually taking is swallowed. One we decline is left alone on both
	-- edges, and `SecureActionButton_OnClick` gates the frame's own action to one of them by
	-- itself: `clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)`.
	if ((down and true or false) ~= ClickCastOnMouseDown) then
		return "debindnull"
	end

	HandoffBindings = bindings
	HandoffWinner = winner
	HandoffUnitFrameUnit = unitframeUnit
	return "debind1"
]==]);

--- **이 판에서는 할당을 하지 않는다.** `newtable()`도 문자열 결합도 없다 - 클릭 경로의
--- GC 스파이크는 평균 비용보다 훨씬 아프게 나타난다. 메모는 미리 만들어 둔 테이블을 쓴다.
DebindPrivate.InstallSnippet(function(pre, post)
	-- Re-wrapping stacks another wrapper on top rather than replacing, so the previous one is
	-- unwrapped first. Left in place both would run and both would return a button name, and the
	-- one that answered would be the stale one.
	if (DebindPrivate.clickWrapped) then
		SecureHandlerUnwrapScript(DebindPrivate.DefaultClickFrame, "OnClick");
	end
	SecureHandlerWrapScript(DebindPrivate.DefaultClickFrame, "OnClick", BindingDriver, pre, post);
	DebindPrivate.clickWrapped = true;
end, [==[
	local bindings = ClickTimeKeys[button]

	-- **클릭캐스팅으로 온 클릭.** 유닛 프레임이 `type="click"`으로 넘긴 것이라 버튼 이름이
	-- 아니라 원래 마우스 버튼("LeftButton" 등)으로 도착한다. 어느 키인지는 도착한 버튼과
	-- 지금 눌린 수식어로 되찾는다.
	--
	-- 자릿값은 `UpdateBindings.lua`의 `GetModifierIndex`와 같아야 한다. 여기만 바꾸면
	-- 수식어가 걸린 클릭캐스팅만 조용히 다른 목록을 찾는다.
	--
	-- 이 갈래로 들어온 클릭은 아래 판정에서 **`isClickCast` 레코드**를 본다. 같은 키의 키보드
	-- 쪽(`holdsKey`)과 조건이 다를 수 있으므로 섞으면 안 된다.
	-- **유닛 프레임 래퍼가 보낸 클릭.** 그쪽은 조건까지 다 보고 왔으므로 여기서는 고르지 않는다
	-- (§4-2 - 안 맞으면 그쪽이 `nil`을 반환해 프레임의 원래 동작으로 떨어지고, 여기까지 오지도
	-- 않는다). `clickCast`와 따로 두는 이유는 아직 옛 경로가 살아 있어서다 - 그쪽은 마우스 버튼
	-- 이름으로 도착해 아래에서 스스로 고른다.
	local clickCast, handoff
	if (button == "debind1") then
		bindings = HandoffBindings
		clickCast = true
		handoff = true
	elseif (not bindings) then
		local n = MouseButtonNumbers[button]
		if (n) then
			local mod = 0
			if (IsAltKeyDown()) then
				mod = mod + CONSTANTS.MOD_ALT
			end
			if (IsControlKeyDown()) then
				mod = mod + CONSTANTS.MOD_CTRL
			end
			if (IsShiftKeyDown()) then
				mod = mod + CONSTANTS.MOD_SHIFT
			end
			local byMod = ClickCastKeys[n]
			bindings = byMod and byMod[mod]
			clickCast = bindings and true or false
]==] .. CLICKCAST_ARRIVAL_SNIPPET .. [==[
		end
	end

	-- **A bare attribute stays on the frame.** Not written means the previous click's value, not
	-- none, so every click settles all of them -- the ones that came the old way (deb1xx, a
	-- delegated /click) included. A `unit` left behind sends the next action with no target of its
	-- own at the last one's, with no error and nothing logged.
	--
	-- `pressAndHoldAction`은 아래에서 이긴 액션의 값으로 다시 쓴다. 여기서 지우는 것은
	-- 앞 클릭의 잔류를 막기 위해서다. `useOnKeyDown`은 키 갈래에서는 건드리지 않는다(nil) -
	-- 사용자 CVar가 정하게 둔다. 클릭캐스팅 갈래는 바로 아래에서 다시 쓴다.
	self:SetAttribute("unit", nil)
	self:SetAttribute("pressAndHoldAction", nil)
	self:SetAttribute("useOnKeyDown", nil)
	self:SetAttribute("type", nil)
	self:SetAttribute("macrotext", nil)

	-- **클릭캐스팅은 언제나 `down=false`로 도착한다.** `SECURE_ACTIONS.click`이
	-- `delegate:Click(button)`이라 엣지를 못 싣는다(`/click`은 세 번째 인자로 실었다).
	--
	-- 그런데 게이트는 `clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)`
	-- 이고 `useOnKeyDown`이 nil이면 `ActionButtonUseKeyDown` CVar로 떨어진다
	-- (SecureTemplates.lua:795-814). **그 CVar가 켜져 있으면 둘 다 거짓이 되어 아무것도
	-- 안 나간다.** 오류도 로그도 없다.
	--
	-- 그래서 이 갈래에서만 거짓으로 못박는다. 도착 엣지가 고정이므로 CVar에 물어볼 것이 없다.
	-- 진짜 클릭이 어느 엣지에 오느냐와는 별개다 - 그건 OnClick 래퍼가 보고, 래퍼는 뗄 때
	-- 발동한다. 여기까지 온 시점에는 이미 그 결정이 끝나 있다.
	if (clickCast) then
		self:SetAttribute("useOnKeyDown", false)
	end

	if (not bindings) then
		-- 우리 키가 아니다. 버튼 이름을 바꾸지 않고 그대로 흘려보낸다.
		return
	end

	-- **놓는 엣지.** down에서 press-and-hold를 시작했으면 여기서 다시 고르지 않는다 -
	-- 시전한 것과 다른 것을 놓으면 시전한 쪽이 눌린 채로 남는다. 대상도 그때 확정한 값을
	-- 그대로 쓴다. 조건을 다시 보는 자리가 아니라 **같은 것을 놓는** 자리다.
	--
	-- `pressAndHoldAction`을 여기서도 켜야 게이트의 `releasePressAndHoldAction`이 참이 되어
	-- `typerelease`가 나간다(SecureTemplates.lua:815). 안 켜면 `ActionButtonUseKeyHeldSpell`
	-- CVar에 운을 맡기게 된다.
	if (not down) then
		local held = HeldButtons[button]
		if (held) then
			local heldUnit = HeldUnits[button]
			HeldButtons[button] = nil
			HeldUnits[button] = nil

			-- **놓을 것이 남아 있을 때만 놓는다.** `typerelease`는 "놓기"라는 동작이 아니라
			-- 그냥 그 주문을 다시 시전하는 것이다(`SECURE_ACTIONS.spell` -> `CastSpellByID`).
			-- 시전 중이면 그게 놓기가 되지만, 이미 끝난 뒤라면 **새 시전**이 된다.
			--
			-- 실제로 밟았다: 누른 채로 시전이 끝나고 재사용 대기시간까지 지난 뒤에 떼면
			-- 주문이 한 번 더 나갔다.
			if (not PlayerIsChanneling()) then
				return false
			end

			self:SetAttribute("unit", heldUnit)
			self:SetAttribute("pressAndHoldAction", true)
			return held.clickbutton
		end
	end

	local winner, unitframeUnit

	if (handoff) then
		-- 유닛 프레임 래퍼가 이미 골랐다. 여기서 다시 도는 것은 같은 답을 두 번 내는 것이고,
		-- hover는 그쪽이 자기 자신을 보고 읽은 값이라 여기서 캐시로 다시 읽으면 오히려 나빠진다.
		winner = HandoffWinner
		unitframeUnit = HandoffUnitFrameUnit
		HandoffBindings = nil
		HandoffWinner = nil
		HandoffUnitFrameUnit = nil
	else
	-- 키로 들어온 클릭이라 hover는 캐시에서 온다.
	local evalFrame = States.unitframe
]==] .. EVAL_SNIPPET .. [==[
	end

	-- **Nothing to fire cancels the click.** The winner is the BLOCK that closes the tier, or
	-- nothing matched at all (`devdocs/dropping-the-game-fallback.md` §3). Leaving the name would
	-- come to the same, since there is no `*type-@<key>`, but only by accident.
	if (not winner or not winner.clickbutton) then
		return false
	end
]==] .. RESOLVE_UNIT_SNIPPET .. BAKE_WINNER_MACROTEXT_SNIPPET .. ACTION_SLOT_SNIPPET .. [==[

	-- 대상을 맨이름으로 넣는다. 새 경로는 delegate 프레임을 쓰지 않는다.
	self:SetAttribute("unit", unit)

	-- **B-11.** 게이트는 이 값을 맨이름으로만 읽는다(SecureTemplates.lua:812). 버튼별로
	-- 구운 `*pressAndHoldAction-<버튼>`은 거기 안 닿아서 유지·시전 주문이 눌러도 시작을 안
	-- 하고 뗄 때 평범하게 시전됐다. 클릭 순간에 맨이름으로 쓰면 닿는다.
	--
	-- 이게 켜지면 게이트가 `useOnKeyDown`을 CVar와 무관하게 강제로 참으로 만든다(813) -
	-- **누를 때 시작하고 뗄 때 놓는다.** 액션바가 하는 것과 같아진다.
	--
	-- **down에서만 켠다.** up에서 다시 골라 나온 승자가 press-hold라고 여기서 켜면,
	-- 게이트가 `clickAction`을 거짓으로 만들고 `releasePressAndHoldAction`으로 넘어가
	-- **누른 적 없는 주문의 `typerelease`가 나간다.** 놓기는 위의 캐리 자리에서만 켠다.
	if (down) then
		if (winner.pressAndHold) then
			self:SetAttribute("pressAndHoldAction", winner.pressAndHold)
		else
			self:SetAttribute("pressAndHoldAction", nil)
		end
	end

	-- 위 "놓는 엣지"가 재사용할 자리. **down에서 반드시 확정한다. 조건부로 기록만 하면
	-- 안 된다.** up 엣지가 온다는 보장이 없어서다 - 창 포커스를 잃거나, 누른 채로 리빌드가
	-- 돌거나, 바인딩이 바뀌면 안 온다. 그러면 앞의 기록이 남고, 다음에 press-hold가 아닌
	-- 액션을 눌렀다 뗄 때 그 낡은 것이 재사용된다. 맨이름 속성과 같은 규칙이다.
	if (down) then
		if (winner.pressAndHold) then
			HeldButtons[button] = winner
			HeldUnits[button] = unit
		else
			HeldButtons[button] = nil
			HeldUnits[button] = nil
		end
	end

]==] .. SELFCAST_OFF_SNIPPET .. [==[
	return slotButton or castButton
]==], [==[
	-- 클릭이 끝난 뒤. **맨이름 `pressAndHoldAction`을 반드시 지운다.**
	--
	-- delegate 프레임들은 이 프레임의 자식이고 `useparent*`가 켜져 있다. `unit`은
	-- `useparent-unit=false`로 막아뒀지만 이건 안 막혀 있어서, 켜둔 채로 두면 **delegate로
	-- 걸린 옛 경로 키들이 그 값을 물려받는다.** 그 키들은 이 래퍼를 안 거치므로 스스로 지울
	-- 방법이 없고, 결과는 CVar와 무관하게 down에서 발동하고 `typerelease`까지 한 번 더 나가는
	-- 것이다 - 위의 `PlayerIsChanneling` 가드도 없이.
	--
	-- preBody에서 지울 수는 없다. 게이트가 그 뒤에 읽는다.
	--
	-- **`useOnKeyDown`도 같다.** 클릭캐스팅 갈래가 이걸 false로 못박는데(도착 엣지가 고정이라
	-- CVar에 물어볼 것이 없다), 남겨두면 같은 경로로 delegate에 새어나간다 - `ActionButtonUseKeyDown`
	-- 을 켜둔 사용자의 대상 있는 옛 경로 키가 클릭캐스팅 한 번 뒤부터 up에서 발동하게 된다.
	self:SetAttribute("pressAndHoldAction", nil)
	self:SetAttribute("useOnKeyDown", nil)
]==]);

--- A way to reach the click-time decision without a click. **DEBUG only** - in a shipped build
--- the attribute is never set, so there is no second caller of `EVAL_SNIPPET` to keep in step.
---
--- **Hardware input is the only thing that can drive the real wrapper.** `Click()` on a protected
--- button does not fire `OnClick` from insecure code (`SecureHandlers.lua`'s `Wrapped_Click` never
--- runs), and the restricted environment is no way round it -- frame handles carry
--- `SetBindingClick` but nothing that presses one. That left the suite with a choice between
--- stopping to ask a person to press a key on every run and reaching the decision another way.
--- **A test addon exists to spend less of someone's time, so it reaches it another way.**
---
--- What this covers is what actually changes: the same `EVAL_SNIPPET` text the wrappers splice,
--- with the wrapper's prologue replaced by an argument. What it cannot see is that a real press
--- arrives and arrives under this button name -- and `GetBindingAction` answers both of those
--- without anyone clicking anything.
if (DebindPrivate.DEBUG) then
	DebindPrivate.InstallSnippet(function(body)
		BindingDriver:SetAttribute("EvalClickTimeKey", body);
	end, [==[
		local button = ...
		local bindings = ClickTimeKeys[button]
		if (not bindings) then
			return
		end

		-- 키로 들어온 클릭과 같은 자리에 선다: 클릭캐스팅이 아니므로 `holdsKey` 레코드를 보고,
		-- hover는 enter/leave가 남긴 캐시에서 온다.
		local clickCast = false
		local winner, unitframeUnit
		local evalFrame = States.unitframe
]==] .. EVAL_SNIPPET .. [==[
		if (not winner or not winner.clickbutton) then
			return
		end
]==] .. RESOLVE_UNIT_SNIPPET .. BAKE_WINNER_MACROTEXT_SNIPPET .. ACTION_SLOT_SNIPPET
		.. SELFCAST_OFF_SNIPPET .. [==[
		-- The winner's place as well, because the button no longer names it: the self and focus
		-- twins click the same button as their original.
		for i = 1, #bindings do
			if (bindings[i] == winner) then
				return slotButton or castButton, i
			end
		end
		return slotButton or castButton
	]==]);

	--- The same door for the click-cast side. Run it **for the unit frame** (`RunFor`), which is
	--- what the real wrapper does -- `evalFrame` being the frame itself is the whole reason that
	--- path does not read the hover cache.
	---
	--- Answering `nil` is the fall-through: the wrapper leaves the button name alone and the click
	--- carries on into the frame's own handler. A test can read that answer, but only a real click
	--- can show the carrying-on, so that half stays uncovered.
	DebindPrivate.InstallSnippet(function(body)
		BindingDriver:SetAttribute("EvalClickCastFrame", body);
	end, [==[
		local n, mod = ...
		local info = ccframes[self]
		if (not info) then
			return
		end

		local byMod = ClickCastKeys[n]
		local bindings = byMod and byMod[mod]
		if (not bindings) then
			return
		end

		local clickCast = true
		local winner, unitframeUnit
		local evalFrame = info
]==] .. EVAL_SNIPPET .. [==[
		if (not winner or not winner.clickbutton) then
			return
		end
]==] .. RESOLVE_UNIT_SNIPPET .. BAKE_WINNER_MACROTEXT_SNIPPET .. [==[
		return winner.clickbutton
	]==]);
end

