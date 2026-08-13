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
SecureHandlerExecute(BindingDriver, [[
	-- FALSE_VALUES = newtable()
	-- FALSE_VALUES[0] = true
	-- FALSE_VALUES["0"] = true
	-- FALSE_VALUES[false] = true
	-- FALSE_VALUES["false"] = true
	-- FALSE_VALUES["FALSE"] = true
	-- FALSE_VALUES["f"] = true
	-- FALSE_VALUES["F"] = true
	-- FALSE_VALUES["off"] = true
	-- FALSE_VALUES["OFF"] = true

	debind_driver = self
	ccframes = newtable()

	MacroMap = newtable()
	
	DefaultClickFrame = self:GetFrameRef("clickFrame")
	DefaultClickFrameName = DefaultClickFrame:GetName()
	
	CustomStateExpressions = newtable()

	-- 배선이 상태에 달린 키들. 키 -> 그 키의 레코드 배열.
	--
	-- **모든 키가 아니다.** 배선이 고정된 키(`IsKeyAlwaysOurs`)는 빌드 시점에 한 번 걸고 끝이라
	-- 여기 안 들어온다 - 이름이 말하는 그대로다. 모양(키 -> 배열)만 보고 "전부 있겠지"로 읽으면
	-- 안 된다. 아래 상태 루프가 이 표의 유일한 독자다.
	StateDrivenBindings = newtable()

	-- 클릭 시점 평가로 넘긴 키들. 버튼 이름("@" + 키) -> 그 키의 레코드 배열.
	-- OnClick 래퍼가 도착한 버튼 이름으로 여기를 찾아 자기 키인지 가른다.
	--
	-- **배선이 고정된 키는 이 표에만 있다.** 그런 키의 배열을 붙드는 것이 여기 하나뿐이다.
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

	MacroTextsMap = newtable()
	UnitAliasMap = newtable()
	UnitStates = newtable()
	States = newtable()
	DirtyFlags = newtable()

	-- 호버 **프레임**이 바뀌었을 때 다시 걸 것이 있나. `UpdateBindings`가 리빌드마다 굽는다.
	--
	-- 아래 세 자리에서 `SetUnit`의 반환값과 `or`로 묶인다. 둘은 **서로 다른 사건**이다:
	-- 반환값은 *호버 유닛이 바뀜*, 이쪽은 *유닛은 그대로인데 프레임이 바뀜*. 뒤엣것을
	-- 신경 쓰는 것은 `frameTypes` 레코드뿐이라 대개 거짓이고, 그러면 커서가 공대 프레임을
	-- 쓸고 지나가도 유닛이 안 바뀌는 한 리빌드가 안 나간다.
	RebindOnHoverFrame = false
	OldStates = newtable()

	_macrotextsSeen = newtable()
	_isUpdatingMacrotests = false
	_customStatesUpdating = newtable()

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
	self:CallMethod("printMacroText", t.attr or t.state or "?", s)
]] or "";

BindingDriver:SetAttribute("UpdateMacroTexts", [=[
	--self:CallMethod("print", "UpdateMacroTexts", ...)

	-- local wasUpdating = _isUpdatingMacrotests
	-- if (not wasUpdating) then
	-- 	_isUpdatingMacrotests = true
	-- end

	local key = ...
	for state, dependents in pairs(MacroTextsMap) do
		if (key == true or key == state or DirtyFlags[state]) then
			for i = 1, #dependents do
				local t = dependents[i]
				--if (not _macrotextsSeen[t.id]) then
					--_macrotextsSeen[t.id] = true
					local s
					if (t.fragments) then
						for i = 1, #t.args do
							local arg = t.args[i]
							local value
							if (arg.unit) then
								value = UnitAliasMap[arg.unit] or "raid41"
							elseif (arg.state) then
								value = States[arg.state] and true or false
								if (arg.reverse) then
									value = not value
								end
								value = value and "" or "known:0"
							elseif (arg.fixed) then
								value = arg.fixed
							end
							t.fragments[i * 2] = value
						end
						s = table.concat(t.fragments)
					else
						s = format(t.formatString,
								UnitAliasMap["tank"] or "raid41",
								UnitAliasMap["healer"] or "raid41",
								UnitAliasMap["maintank"] or "raid41",
								UnitAliasMap["mainassist"] or "raid41",
								UnitAliasMap["custom1"] or "raid41",
								UnitAliasMap["custom2"] or "raid41",
								UnitAliasMap["hover"] or "raid41")
					end

					-- 실제로 버튼에 올라가는 문자열. 여기가 **보안 쪽에서 매크로 본문이
					-- 완성되는 유일한 자리**라 로그도 여기 있어야 한다 - 아래 SetAttribute를
					-- 지나면 다시 읽을 방법이 없다(속성은 열거가 안 된다).
					--
					-- 이 갈래는 `@custom1`·`@hover`처럼 **실행 시점에 바뀌어야 하는 것이
					-- 있는** 본문만 지난다. 조용하면 그것도 답이다 - 그 본문은 정적이라
					-- `SetBindingAttributes`가 쓴 그대로라는 뜻이다(그쪽 로그를 볼 것).
]=] .. PRINT_MACROTEXT_SNIPPET .. [=[

					if (t.attr) then
						DefaultClickFrame:SetAttribute(t.attr, s)
					end
					if (t.state) then
						if (true or CustomStateExpressions[t.state] ~= s) then
							CustomStateExpressions[t.state] = s
							local newValue = SecureCmdOptionParse(s) and true or false
							if (States[t.state] ~= newValue) then
								self:RunAttribute("SetCustomState", t.state, newValue, true)
							end
						end
					end
				--end
			end
		end
	end

	-- if (not wasUpdating) then
	-- 	_isUpdatingMacrotests = false
	-- 	wipe(_macrotextsSeen)
	-- end
]=]);

BindingDriver:SetAttribute("SetCustomState", [[
	local name, value, skipUpdate = ...
	--self:CallMethod("print","SetCustomState",name,value,skipUpdate,States[name])
	if (States[name] ~= value) then
		if (not _customStatesUpdating[name]) then
			_customStatesUpdating[name] = true
			
			States[name] = value
			DirtyFlags[name] = true
			
			if (not skipUpdate) then
				if (MacroTextsMap[name]) then
					self:RunAttribute("UpdateMacroTexts", name)
				end

				debind_driver:SetAttribute("state-unitexists", name)
			end

			self:CallMethod("OnCustomStateChanged", name, value)
			_customStatesUpdating[name] = false
		end
	end
]]);

BindingDriver:SetAttribute("ToggleCustomState", [[
	local name = ...
	local value = not States[name]
	return self:RunAttribute("SetCustomState", name, not States[name])
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

		if (UnitStates[alias] ~= nil) then
			dirty = true
			-- local existsKey = alias.."-exists"
			-- local existsValue
			-- if (alias == "custom1" or alias == "custom2") then
			-- 	existsValue = unit ~= nil and UnitExists(unit) and true or false
			-- 	if (unit) then
			-- 		RegisterAttributeDriver(self, existsKey, format("[@%s,exists]1;0", unit))
			-- 	else
			-- 		UnregisterAttributeDriver(self, existsKey)
			-- 		self:SetAttribute(existsKey, 0)
			-- 	end
			-- else
			-- 	existsValue = unit ~= nil
			-- end

			-- if (UnitStates[alias] ~= existsValue) then
			-- 	UnitStates[alias] = existsValue
			-- 	DirtyFlags[existsKey] = true
			-- 	dirty = true
			-- end
		end

		if (MacroTextsMap[alias]) then
			self:RunAttribute("UpdateMacroTexts", alias)
		end

		if (not force) then
			self:CallMethod("OnSpecialUnitChanged", alias, unit)
		end
	end

	return dirty;
]]);

BindingDriver:SetAttribute("UpdateAllUnits", [[
	self:RunAttribute("SetUnit", "tank", UnitAliasMap["tank"], true)
	self:RunAttribute("SetUnit", "healer", UnitAliasMap["healer"], true)
	self:RunAttribute("SetUnit", "maintank", UnitAliasMap["maintank"], true)
	self:RunAttribute("SetUnit", "mainassist", UnitAliasMap["mainassist"], true)
	self:RunAttribute("SetUnit", "custom1", UnitAliasMap["custom1"], true)
	self:RunAttribute("SetUnit", "custom2", UnitAliasMap["custom2"], true)
	self:RunAttribute("SetUnit", "hover", UnitAliasMap["hover"], true)
]]);

BindingDriver:SetAttribute("ClearUnitAttributes", [==[
]==]);

BindingDriver:SetAttribute("UpdateBindings", (DebindPrivate.DEBUG and [[
	local vargs = newtable()
	if (DirtyFlags.forceAll) then
		tinsert(vargs, "forceAll")
	end
	for k in pairs(DirtyFlags) do
		if (k ~= "forceAll") then
			tinsert(vargs, k)
		end
	end
	self:CallMethod("dump", "[SECURE] UpdateBindings",
		vargs[1],
		vargs[2],
		vargs[3],
		vargs[4],
		vargs[5],
		vargs[6],
		vargs[7],
		vargs[9],
		vargs[10],
		vargs[11],
		vargs[12],
		vargs[13],
		vargs[14],
		vargs[15]
	)
]] or "") .. BakeSnippet([==[
	local forceAll = DirtyFlags.forceAll
	local unitframe = States.unitframe
	if (unitframe and not unitframe.reaction) then unitframe = nil end
	local group = States.group
	local form = 2 ^ (States.form or 0)
	local bonusbar = 2 ^ (States.bonusbar or 0)
	local combat = States.combat
	local stealth = States.stealth
	local specialbar = States.specialbar
	local extrabar = States.extrabar
	local pet = States.pet
	local petbattle = States.petbattle

	-- **배선이 고정된 키는 이 표에 없다.** `UpdateBindingsMap`이 안 넣는다 - 그 키는 빌드
	-- 시점에 한 번 걸고 끝이고, 어느 액션인지는 래퍼가 클릭 순간에 정한다. 여기서 걸러내던
	-- 시절에는 훑기는 훑고 매번 "볼 것 없음"으로 끝났다.
	--
	-- **alwaysOurs이지 clickTime이 아니다.** clickTime 키 중 배선이 고정 아닌 것은 여기 있고,
	-- "잡느냐 놓느냐"를 계속 정해야 한다 - 빼면 놓아줘야 할 때 못 놓는다.
	for key, bindings in pairs(StateDrivenBindings) do
		local check = forceAll
		if (not check and bindings.updateFlags) then
			for flag in pairs(DirtyFlags) do
				if (bindings.updateFlags[flag]) then
					check = true
					break
				end
			end
		end

		if (check) then
			local keyBound = not bindings.hasNonClick

			for i = 1, #bindings do
				local t = bindings[i]
				local match = true

				-- 호버 중이냐, 그 유닛이 어떠냐는 아래 t.units["hover"]가 답한다. 여기 남은
				-- 것은 프레임의 종류뿐이라 제 존재 검사를 직접 들고 있다.
				if (t.frameTypes) then
					if (not unitframe) then
						match = false
					elseif ((t.frameTypes % (unitframe.frameType + unitframe.frameType)) < unitframe.frameType) then
						match = false
					end
				end

				if (match and
					(t.groups ~= nil and (t.groups % (group + group)) < group) or
					(t.combat ~= nil and t.combat ~= combat) or
					(t.forms and (t.forms % (form + form)) < form) or
					(t.bonusbars and (t.bonusbars % (bonusbar + bonusbar)) < bonusbar) or
					(t.specialbar ~= nil and t.specialbar ~= specialbar) or
					(t.extrabar ~= nil and t.extrabar ~= extrabar) or
					(t.stealth ~= nil and t.stealth ~= stealth) or
					(t.petbattle ~= nil and t.petbattle ~= petbattle) or
					(t.pet ~= nil and t.pet ~= pet)
				) then
					match = false
				end
				
				if (match and t.known ~= nil) then
					if (States[t.known] ~= true) then
						match = false
					end
				end

				if (match and t.units) then
					for checkedUnit, cond in pairs(t.units) do
						local s = UnitStates[checkedUnit]
						if (not s or cond.exists ~= s.exists
								or (cond.reaction and not cond.reaction[s.reaction])
								or (cond.dead ~= nil and cond.dead ~= s.dead)) then
							match = false
							break
						end
					end
				end

				if (match and t.customStates) then
					for state, v in pairs(t.customStates) do
						if (States[state] ~= v) then
							match = false
							break
						end
					end
				end

				if (match) then
					if (not keyBound and t.isNonClick) then
						-- **무엇을 걸 것인가는 이긴 액션이 아니라 세 갈래 중 하나다.**
						--
						-- clickTime 키는 어느 클릭 액션이 이기든 거는 것이 `"@"..key` 하나다.
						-- 그래서 이긴 것으로 비교하면 승자가 뒤집힐 때마다 같은 값을 다시 거는
						-- SetOverrideBinding이 나간다 - hover가 걸린 키에서 이게 제일 잦다.
						-- 결과로 비교하면 그 재바인딩이 통째로 없어진다.
						--
						-- 셋은 서로 겹치지 않는다: false(놓아줌) / 명령 문자열 / 버튼 이름.
						-- clickTime이 아니면 옛 규약대로 t 자체를 쓴다.
						local outcome
						if (t.type == CONSTANTS.UNUSED) then
							outcome = false
						elseif (t.command) then
							outcome = t.command
						elseif (t.clickbutton) then
							outcome = bindings.clickTimeButton or t
						end

						if (bindings.bound ~= outcome) then
							bindings.bound = outcome
							if (t.type == CONSTANTS.UNUSED) then
								self:ClearBinding(key)
							elseif (t.command) then
								self:SetBinding(true, key, t.command)
							elseif (t.clickbutton) then
								if (bindings.clickTimeButton) then
									-- 어느 액션인지는 래퍼가 클릭 순간에 정한다. 여기서는
									-- "클릭이 이겼다"까지만 정한다.
									self:SetBindingClick(true, key, DefaultClickFrameName, bindings.clickTimeButton)
								else
									self:SetBindingClick(true, key, t.clickframe or DefaultClickFrameName, t.clickbutton)
								end
							end
						end
						keyBound = i
					end

					if (keyBound) then
						break
					end
				end
			end

			if (not keyBound and bindings.hasNonClick) then
				bindings.bound = nil
				self:ClearBinding(key)
			end

		end
	end

	wipe(DirtyFlags)
]==]));

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
	ccframes[button].reaction = 0
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
			if (debind_driver:RunAttribute("SetUnit", "hover", nil) or RebindOnHoverFrame) then
				DirtyFlags.unitframe = true
				debind_driver:SetAttribute("state-unitexists", "unitframe")
				--debind_driver:RunAttribute("UpdateBindings")
			end
		end
		info.frame = nil
	end
	ccframes[button] = nil
]==]);

BindingDriver:SetAttribute("update_hit_bounds", [==[
	local info = ccframes[self]
	local _, _, w, h = self:GetRect()
	if (w and h and w > 0 and h > 0) then
		w = floor(w + 0.5)
		h = floor(h + 0.5)
		info.l = info.insetL / w
		info.r = 1 - info.insetR / w
		info.t = 1 - info.insetT / h
		info.b = info.insetB / h
	end
]==])

-- A frame whose unit does not exist counts as **not hovering**, and the frame is still recorded
-- so the poll can pick it back up when the unit returns. Recording it is what makes recovery
-- possible: neither enter nor leave fires while the cursor sits still, so dropping the frame
-- here would strand the hover slot until the user moved the mouse.
--
-- `reaction == nil` is the marker. Every reader gates on it rather than on the frame being
-- present, which is what the click path was already doing on its own.
BindingDriver:SetAttribute("setup_onenter", BakeSnippet([==[
	local unit = self:GetEffectiveAttribute("unit")

	local unitframe = ccframes[self]
    local reaction
    if (unit and UnitExists(unit)) then
        if (PlayerCanAssist(unit)) then
            reaction = CONSTANTS.REACTION_HELP
        elseif (PlayerCanAttack(unit)) then
            reaction = CONSTANTS.REACTION_HARM
        else
            reaction = CONSTANTS.REACTION_OTHER
        end
    else
        unit = nil
    end

    local unitChanged = unitframe.unit ~= unit or unitframe.reaction ~= reaction
	if (States.unitframe ~= unitframe or unitChanged) then
        unitframe.unit = unit
        unitframe.reaction = reaction
		States.unitframe = unitframe
        -- if (unitframe.insetL and not unitframe.l) then
        --     debind_driver:RunFor(self, debind_driver:GetAttribute("update_hit_bounds"))
        -- end
		if (debind_driver:RunAttribute("SetUnit", "hover", unit) or RebindOnHoverFrame) then
			DirtyFlags.unitframe = true
			debind_driver:SetAttribute("state-unitexists", "unitframe")
			--debind_driver:RunAttribute("UpdateBindings")
		end
	end
]==]));


BindingDriver:SetAttribute("setup_onleave", [==[
	local unitframe = States.unitframe
	if (not unitframe) then return end
	States.unitframe = nil
	if (debind_driver:RunAttribute("SetUnit", "hover", nil) or RebindOnHoverFrame) then
		DirtyFlags.unitframe = true
		debind_driver:SetAttribute("state-unitexists", "unitframe")
		--debind_driver:RunAttribute("UpdateBindings")
	end
]==]);

BindingDriver:SetAttribute("clickcast_onenter", [==[
	debind_driver:RunFor(self, debind_driver:GetAttribute("setup_onenter"))
]==]);

BindingDriver:SetAttribute("clickcast_onleave", [==[
	debind_driver:RunFor(self, debind_driver:GetAttribute("setup_onleave"))
]==]);

if (DebindPrivate.CliqueDetected) then
	SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "clique_header", _G.Clique.header);

	_G.Clique.header:SetAttribute("debind_gethoverunit", [[
		return danglingButton and danglingButton:GetAttribute("unit") or nil
	]]);

	BindingDriver:SetAttribute("GetHoveredUnit", [==[
		local clique_header = self:GetFrameRef("clique_header")
		local unit = clique_header:RunAttribute("debind_gethoverunit")
		return unit
	]==]);

	BindingDriver:SetAttribute("clickcast_register", "");

	BindingDriver:SetAttribute("clickcast_unregister", "");
else
	BindingDriver:SetAttribute("GetHoveredUnit", [==[
		return States.unitframe and States.unitframe.unit or nil
	]==]);

	BindingDriver:SetAttribute("clickcast_register", BakeSnippet([==[
		local button = self:GetAttribute("clickcast_button")
		if (ccframes[button]) then
			return
		end

		self:RunFor(button, self:GetAttribute("InitFrame"))
		ccframes[button].hd = true
		ccframes[button].frameType = CONSTANTS.FRAMETYPE_GROUP
		button:SetAttribute("useparent-clickbutton", true)
		
		button:Run([[debind_driver = self:GetParent():GetFrameRef("clickcast_header")]])
		if (not clique_header) then
			button:SetAttribute("clickcast_onenter", self:GetAttribute("clickcast_onenter"))
			button:SetAttribute("clickcast_onleave", self:GetAttribute("clickcast_onleave"))
		end

		self:CallMethod("OnClickCastRegister", button:GetName())
	]==]));

	BindingDriver:SetAttribute("clickcast_unregister", [==[
		local button = self:GetAttribute("clickcast_button")
		if (ccframes[button]) then
			self:RunFor(button, self:GetAttribute("DeinitFrame"))
			if (not clique_header) then
				button:SetAttribute("clickcast_onenter", nil)
				button:SetAttribute("clickcast_onleave", nil)
			end
			button:Run([[debind_driver = nil]])
			self:CallMethod("OnClickCastUnregister", button:GetName())
		end
	]==]);

	function BindingDriver:OnClickCastRegister(buttonName)
		if (buttonName) then
			local button = _G[buttonName];
			if (button) then
				DebindPrivate.ccframes[button] = { hd = true, type = "group", frameType = DebindPrivate.Constants.FRAMETYPE_GROUP };
				DebindPrivate.UpdateRegisteredClicks(button);
			end
		end
	end

	function BindingDriver:OnClickCastUnregister(buttonName)
		if (buttonName) then
			local button = _G[buttonName];
			if (button and DebindPrivate.ccframes[button] and DebindPrivate.ccframes[button].hd) then
				-- **여기서 되돌리지 않으면 영영 못 되돌린다.** `UnregisterFrame`은 `hd`
				-- 프레임을 건너뛰므로(FrameRegistry.lua) 헤더로 들어온 프레임이 되돌아가는
				-- 자리는 이 한 곳뿐이다. 안 부르면 그 프레임의 클릭이 계속 우리에게 온다.
				--
				DebindPrivate.ccframes[button] = nil;
			end
		end
	end
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

function BindingDriver:OnCustomStateChanged(name, value)
	DebindPrivate.OnCustomStateChanged(name, value);
end

--- The condition evaluation, kept as its own string so more than one wrapper can carry it.
---
--- It is spliced in textually rather than called, which is what lets the locals it declares
--- (`unitframe`, `hoverUnit`, `winner`) stay visible to whatever follows -- a `RunAttribute`
--- could not hand those back without turning each one into a shared global.
---
--- The caller owes it `bindings` (the records to walk) and `evalFrame` (which unit frame hover
--- means for this click, or nil), and must have declared `winner` and `hoverUnit` itself -- they
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
	local unitframe = evalFrame
	local hoverFrameType
	if (unitframe) then
		hoverUnit = unitframe.frame:GetEffectiveAttribute("unit")
		if (hoverUnit and UnitExists(hoverUnit)) then
			hoverFrameType = unitframe.frameType
		else
			unitframe = nil
			hoverUnit = nil
		end
	end

	-- 이벤트가 정확히 덮는 상태는 States에서 읽는다. 클릭 시점으로 옮겨도 정확도가 안 변하고
	-- C 호출만 는다. live로 읽는 것은 hover와 유닛 조건뿐이다.
	local group = States.group
	local form = 2 ^ (States.form or 0)
	local bonusbar = 2 ^ (States.bonusbar or 0)

	local memoReady = false

	-- 어느 갈래로 들어왔느냐가 곧 어느 레코드를 보느냐다. 한 키가 양쪽 레코드를 다 가질 수
	-- 있고 조건도 서로 다르므로, 도착한 경로의 것만 본다.
	local subset = clickCast and "isClick" or "isNonClick"

	for i = 1, #bindings do
		local t = bindings[i]
		if (t[subset]) then
			local match = true

			-- 호버 유닛의 존재와 반응은 아래 t.units["hover"]가 답한다. 그쪽도 여기서 잰
			-- hoverUnit을 쓰므로 값이 갈릴 자리가 없다. 남은 것은 프레임의 종류뿐이다.
			if (t.frameTypes) then
				if (not unitframe) then
					match = false
				elseif ((t.frameTypes % (hoverFrameType + hoverFrameType)) < hoverFrameType) then
					match = false
				end
			end

			-- 싼 것부터 본다. 여기까지는 전부 테이블 조회라 대부분의 불일치가 C 호출 없이
			-- 걸러진다. 첫 일치에서 멈추는 구조라 순서가 곧 비용이다.
			if (match and (
				(t.groups ~= nil and (t.groups % (group + group)) < group) or
				(t.combat ~= nil and t.combat ~= States.combat) or
				(t.forms and (t.forms % (form + form)) < form) or
				(t.bonusbars and (t.bonusbars % (bonusbar + bonusbar)) < bonusbar) or
				(t.specialbar ~= nil and t.specialbar ~= States.specialbar) or
				(t.extrabar ~= nil and t.extrabar ~= States.extrabar) or
				(t.stealth ~= nil and t.stealth ~= States.stealth) or
				(t.petbattle ~= nil and t.petbattle ~= States.petbattle) or
				(t.pet ~= nil and t.pet ~= States.pet)
			)) then
				match = false
			end

			if (match and t.customStates) then
				for state, v in pairs(t.customStates) do
					if (States[state] ~= v) then
						match = false
						break
					end
				end
			end

			-- known은 States에 남겨둔다. SecureCmdOptionParse는 이 판에서 제일 비싼 호출인데
			-- 답이 바뀌는 계기가 SPELLS_CHANGED 하나뿐이라 누를 때마다 파싱할 이유가 없다.
			if (match and t.known ~= nil and States[t.known] ~= true) then
				match = false
			end

			if (match and t.units) then
				if (not memoReady) then
					memoReady = true
					wipe(ClickUnitExists)
					wipe(ClickUnitReaction)
					wipe(ClickUnitDead)
				end

				-- **The cache is not trusted here; every value is measured again.** `UnitStates`
				-- is filled by the update loop and so can be a tick old, and a click is rare
				-- enough that measuring again is both cheap and correct. The memo lives for the
				-- length of this one click.
				for u, cond in pairs(t.units) do
					local ok = true
					do
						local unit, needsExists
						if (u == "hover") then
							-- 위에서 프레임에서 직접 읽은 값을 쓴다. UnitAliasMap["hover"]는
							-- 캐시라 여기서만 그걸 보면 hover 조건과 다른 유닛을 판정하게
							-- 된다. 대상도 같은 값을 쓴다(아래 SetAttribute).
							unit = hoverUnit
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
									ClickUnitDead[unit] = dead
								end
								if (cond.dead ~= dead) then
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

	local n = MouseButtonNumbers[button]
	if (not n) then
		return
	end

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
	local bindings = byMod and byMod[mod]
	if (not bindings) then
		return
	end

	local clickCast = true
	local winner, hoverUnit
	local evalFrame = info
]==] .. EVAL_SNIPPET .. [==[

	if (not winner or not winner.clickbutton) then
		return
	end

	HandoffBindings = bindings
	HandoffWinner = winner
	HandoffHoverUnit = hoverUnit
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
	-- 이 갈래로 들어온 클릭은 아래 판정에서 **`isClick` 레코드**를 본다. 같은 키의 키보드
	-- 쪽(`isNonClick`)과 조건이 다를 수 있으므로 섞으면 안 된다.
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

	-- **맨이름 속성은 프레임에 남는다.** "안 쓰면 없다"가 아니라 "안 쓰면 앞의 것이 남는다"라
	-- 매 클릭 전부 확정해야 한다. 옛 경로로 들어온 클릭(deb1xx, /click 위임)에도 반드시
	-- 적용한다 - 앞 클릭이 남긴 unit 하나가 자가시전·주시시전·마우스오버시전을 통째로
	-- 죽인다(`checkselfcast`류는 unit이 없을 때만 동작한다). 오류도 로그도 안 난다.
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
	-- 어느 엣지에 클릭이 오느냐는 유닛 프레임의 `RegisterForClicks`가 정하고, 그건 그 프레임
	-- 주인의 몫이다.
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

	local winner, hoverUnit

	if (handoff) then
		-- 유닛 프레임 래퍼가 이미 골랐다. 여기서 다시 도는 것은 같은 답을 두 번 내는 것이고,
		-- hover는 그쪽이 자기 자신을 보고 읽은 값이라 여기서 캐시로 다시 읽으면 오히려 나빠진다.
		winner = HandoffWinner
		hoverUnit = HandoffHoverUnit
		HandoffBindings = nil
		HandoffWinner = nil
		HandoffHoverUnit = nil
	else
	-- 키로 들어온 클릭이라 hover는 캐시에서 온다.
	local evalFrame = States.unitframe
]==] .. EVAL_SNIPPET .. [==[
	end

	-- **낼 것이 없으면 클릭을 취소한다.** 두 갈래로 도달한다:
	--
	--   winner 없음        live로 아무 조건도 안 맞았다
	--   clickbutton 없음   이긴 것이 UNUSED나 COMMAND다. 둘 다 클릭이 아니다
	--
	-- 배선이 고정된 키(alwaysOurs)에서는 둘 다 도달 불가다 - `IsKeyAlwaysOurs`가
	-- 조건 공간이 전부 덮였음을 보장한다. 나머지 clickTime 키에서는 **정상적으로 도달한다.**
	-- 상태 루프가 묵은 값으로 "클릭이 이긴다"고 보고 걸어둔 뒤, 누르는 순간 live로는 놓아줬어야
	-- 하는 경우다.
	--
	-- 그때 옳은 동작은 "와우에 돌려주기"인데 **여기서는 불가능하다.** `RunBinding`이 제한
	-- 환경에 없고(`click-time-eval.md` §2-5), 유일한 우회로인 `CallMethod`는 forceinsecure다.
	-- 입력은 이미 소비됐다. 그러니 아무것도 안 내는 것이 도달 가능한 것 중 옳음에 가장 가깝다 -
	-- 그 키를 우리에게 준 사용자는 대개 와우 쪽을 비워뒀으므로 흔한 경우에는 정확히 맞고,
	-- 틀리는 경우에도 **틀린 주문이 나가는 것보다 낫다.** 다음 폴링 틱에 상태 루프가 놓아준다.
	--
	-- `false` 대신 이름을 그대로 두어도 결과는 같지만(`*type-@<키>`가 없으니 조용히 끝난다),
	-- 우연에 기대지 않고 명시한다.
	if (not winner or not winner.clickbutton) then
		return false
	end

	-- 대상을 맨이름으로 넣는다. 새 경로는 delegate 프레임을 쓰지 않는다.
	--
	-- **hover는 조건을 판정한 그 유닛에 그대로 쏜다.** UnitAliasMap["hover"]는 enter와 폴링이
	-- 채우는 캐시라 프레임의 유닛이 바뀌면 늦게 따라온다. 조건은 live로 읽어놓고 대상만
	-- 캐시에서 가져오면 **판정한 유닛과 시전 대상이 갈린다** - 우호로 판정해 놓고 옛 유닛에
	-- 쏘는 것이다. 옛 경로는 둘 다 캐시라 적어도 일관됐으니 그보다 나빠진다.
	--
	-- 우호/적대로 효과가 갈리는 주문(참회 같은)에서는 이게 "액션이 안 나감"이 아니라
	-- **"다른 액션이 나감"**이고 되돌릴 수 없다. 반드시 같은 유닛이어야 한다.
	local unit
	if (winner.unit) then
		unit = winner.unit
	elseif (winner.unitAlias) then
		if (winner.unitAlias == "hover") then
			unit = hoverUnit
		else
			unit = UnitAliasMap[winner.unitAlias]
		end

		-- **안 풀리면 존재하지 않는 유닛을 넣는다.** nil로 두면 대상이 없는 것이 되어
		-- `checkselfcast`류가 끼어들거나 현재 대상에 그냥 나간다 - `@tank`를 걸어둔 채
		-- 혼자 있을 때 엉뚱한 데 시전된다.
		--
		-- 옛 경로는 delegate가 `unit or "raid41"`을 들고 있어서(`SetUnit`) 게임이
		-- `GetConvertedButtonUnitAndActionType`의 `UnitExists` 검사에서 중단했다.
		-- 아무 일도 안 일어나는 것이 맞는 동작이고, 같은 자리를 지킨다.
		unit = unit or "raid41"
	end
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
		self:SetAttribute("pressAndHoldAction", winner.pressAndHold)
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

	return winner.clickbutton
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

		-- 키로 들어온 클릭과 같은 자리에 선다: 클릭캐스팅이 아니므로 `isNonClick` 레코드를 보고,
		-- hover는 enter/leave가 남긴 캐시에서 온다.
		local clickCast = false
		local winner, hoverUnit
		local evalFrame = States.unitframe
]==] .. EVAL_SNIPPET .. [==[
		return winner and winner.clickbutton or nil
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
		local winner, hoverUnit
		local evalFrame = info
]==] .. EVAL_SNIPPET .. [==[
		return winner and winner.clickbutton or nil
	]==]);
end

