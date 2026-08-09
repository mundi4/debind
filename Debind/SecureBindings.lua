--[[
FIXME 유닛 popup메뉴에 들어갔다가 나오면 hover값이 nil로 변경되지 않음
]]

local _, DebindPrivate = ...;
local BindingDriver      = DebindPrivate.BindingDriver;
local Constants          = DebindPrivate.Constants;

--- **반드시 값 하나만 돌려준다.** `gsub`은 (문자열, 치환횟수)를 주는데, 그걸 그대로 흘리면
--- 마지막 인자 자리에서 남는 값이 다음 매개변수로 들어간다. `SetAttribute(name, body)`는
--- 남는 인자를 무시해서 표가 안 났지만, `SecureHandlerWrapScript(f, script, header, preBody,
--- postBody)`에서는 치환 횟수가 postBody가 되어 "Invalid post-handler body"로 터진다.
--- 그리고 그 오류는 **이 파일의 나머지를 통째로 중단시킨다** - 아래 속성들이 전부 정의되지
--- 않은 채로 게임이 계속 돌아서, 증상이 엉뚱한 곳(FrameRegistry의 OnEnter 래핑)에서 난다.
local function applyConstants(str)
	local result = str:gsub("CONSTANTS%.([_A-Za-z0-9]+)", function(m)
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
	ClickAttrDefaultValues = newtable()
	
	DefaultClickFrame = self:GetFrameRef("clickFrame")
	DefaultClickFrameName = DefaultClickFrame:GetName()
	
	CustomStateExpressions = newtable()
	BindingsMap = newtable()

	-- 클릭 시점 평가로 넘긴 키들. 버튼 이름("@" + 키) -> 그 키의 BindingsMap 배열.
	-- OnClick 래퍼가 도착한 버튼 이름으로 여기를 찾아 자기 키인지 가른다.
	ClickTimeKeys = newtable()

	-- 실행 엣지가 down일 때 down의 선택을 up이 재사용하기 위한 자리. 버튼 이름 -> 이긴 레코드,
	-- 그리고 그때 확정한 대상. down이 항상 먼저 오므로 덮어쓰기로 자가 치유된다.
	HeldButtons = newtable()
	HeldUnits = newtable()

	-- 어느 엣지가 실행 엣지인가. 제한 환경에서는 CVar를 못 읽으므로 리빌드가 실어 보낸다.
	UseOnKeyDown = false

	-- 래퍼가 클릭 안에서 쓰는 메모. **클릭 경로에서는 newtable()을 부르지 않는다** -
	-- GC 스파이크는 평균 비용보다 아프게 나타난다. 그래서 미리 만들어 두고 재사용한다.
	-- 같은 유닛을 여러 레코드가 물을 때 C 호출이 반복되는 것을 막는다.
	ClickUnitExists = newtable()
	ClickUnitAssist = newtable()
	ClickUnitAttack = newtable()

	MacroTextsMap = newtable()
	UnitMap = newtable()
	UnitStates = newtable()
	States = newtable()
	DirtyFlags = newtable()
	HoverBindings = false
	OldStates = newtable()

	_macrotextsSeen = newtable()
	_isUpdatingMacrotests = false
	_customStatesUpdating = newtable()

	-- 유닛 조건을 클릭 시점에 풀 때 필요한 분류. 화이트리스트 밖이라 스니펫이 스스로
	-- 알 수 없으므로 아래에서 실어 보낸다.
	--   SpecialUnits - UnitMap으로 풀어야 하는 별칭
	--   CustomUnits  - 그 중 실제 존재까지 확인해야 하는 것 (custom1/custom2)
	SpecialUnits = newtable()
	CustomUnits = newtable()
]]);

do
	local lines = {};
	for alias in pairs(Constants.SPECIAL_UNITS) do
		lines[#lines + 1] = format("SpecialUnits[%q]=true", alias);
	end
	-- custom1/custom2만 두 겹이다. tank/healer/maintank/mainassist/hover는 UnitWatch가
	-- UnitMap에 넣어준 것 자체가 존재 증거라는 규약이고, 옛 경로(UpdateBindings.lua의
	-- 유닛 상태 표현식)가 이미 그렇게 갈라져 있다. 여기서 통일하면 조건이 조용히 빡빡해진다.
	lines[#lines + 1] = [[CustomUnits["custom1"]=true]];
	lines[#lines + 1] = [[CustomUnits["custom2"]=true]];
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
								value = UnitMap[arg.unit] or "raid41"
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
								UnitMap["tank"] or "raid41",
								UnitMap["healer"] or "raid41",
								UnitMap["maintank"] or "raid41",
								UnitMap["mainassist"] or "raid41",
								UnitMap["custom1"] or "raid41",
								UnitMap["custom2"] or "raid41",
								UnitMap["hover"] or "raid41")
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
	local changed = UnitMap[alias] ~= unit
	local dirty = false
	if (changed or force) then
		UnitMap[alias] = unit

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
	self:RunAttribute("SetUnit", "tank", UnitMap["tank"], true)
	self:RunAttribute("SetUnit", "healer", UnitMap["healer"], true)
	self:RunAttribute("SetUnit", "maintank", UnitMap["maintank"], true)
	self:RunAttribute("SetUnit", "mainassist", UnitMap["mainassist"], true)
	self:RunAttribute("SetUnit", "custom1", UnitMap["custom1"], true)
	self:RunAttribute("SetUnit", "custom2", UnitMap["custom2"], true)
	self:RunAttribute("SetUnit", "hover", UnitMap["hover"], true)
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
]] or "") .. applyConstants([==[
	local forceAll = DirtyFlags.forceAll
	local unitframe = States.unitframe
	local group = States.group
	local form = 2 ^ (States.form or 0)
	local bonusbar = 2 ^ (States.bonusbar or 0)
	local combat = States.combat
	local stealth = States.stealth
	local specialbar = States.specialbar
	local extrabar = States.extrabar
	local pet = States.pet
	local petbattle = States.petbattle

	for key, bindings in pairs(BindingsMap) do
		local check = forceAll
		if (not check and bindings.updateFlags) then
			for flag in pairs(DirtyFlags) do
				if (bindings.updateFlags[flag]) then
					check = true
					break
				end
			end
		end

		-- 클릭 시점 키이면서 클릭캐스팅 절반도 없으면 여기서 볼 것이 없다.
		-- 키는 UpdateBindingsMap이 이미 한 번 걸어놨고 다시 걸 일이 없다.
		if (check and bindings.clickTime and not bindings.hasClick) then
			check = false
		end

		if (check) then
			local keyBound, clickBound = not bindings.hasNonClick, not bindings.hasClick

			-- 키 절반은 클릭 시점이 맡는다. keyBound를 세워두면 아래 isNonClick 분기도,
			-- 끝의 `not keyBound` 해제도 안 돈다. 클릭캐스팅 절반은 그대로 돈다.
			if (bindings.clickTime) then
				keyBound = true
			end
			for i = 1, #bindings do
				local t = bindings[i]
				local match = true

				if (t.hover ~= nil) then
					if (t.hover == false) then
						if (unitframe) then
							match = false
						end
					elseif (not unitframe) then
						match = false
					else
						if (t.reactions and ((t.reactions % (unitframe.reaction + unitframe.reaction)) < unitframe.reaction)) then
							match = false
						elseif (t.frameTypes and ((t.frameTypes % (unitframe.frameType + unitframe.frameType)) < unitframe.frameType)) then
							match = false
						end
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

				if (match and t.checkedUnits) then
					for checkedUnit, cond in pairs(t.checkedUnits) do
						-- val은 nil(아직 계산 전) / false / true / "help" / "harm".
						-- **"존재"만 값 비교가 아니다.** 어떤 값이 오는지는 다른 바인딩들이 그
						-- 유닛에 무엇을 걸었는지에 달려서, 누군가 우호/적대를 걸어두면 true 대신
						-- "help"/"harm"이 온다. cond ~= val로 뭉뚱그리면 true ~= "help"가 되어
						-- 남의 조건 때문에 내 바인딩이 조용히 죽는다.
						--
						-- 나머지는 전부 정확히 그 값이어야 한다. false("없을 때")도 마찬가지라
						-- 아래 비교가 그대로 맡는다 - nil은 false와 다르고, 상태를 모르는 동안
						-- "없다"로 읽어서 발동시키면 안 된다.
						local val = UnitStates[checkedUnit]
						if (cond == true) then
							if (not val) then
								match = false
							end
						elseif (cond ~= val) then
							match = false
						end
						if (not match) then
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
					if (not clickBound and unitframe and t.isClick) then
						if (unitframe.clicks[key] ~= t) then
							if (t.type == CONSTANTS.UNUSED) then
								for k, v in pairs(t.clickAttrs) do
									unitframe.frame:SetAttribute(k, ClickAttrDefaultValues[unitframe.frame][k])
								end
							else
								for k, v in pairs(t.clickAttrs) do
									unitframe.frame:SetAttribute(k, v or nil)
								end
							end
							unitframe.clicks[key] = t
						end
						clickBound = t
					end

					if (not keyBound and t.isNonClick) then
						if (bindings.bound ~= t) then
							bindings.bound = t
							if (t.type == CONSTANTS.UNUSED) then
								self:ClearBinding(key)
							elseif (t.command) then
								self:SetBinding(true, key, t.command)
							elseif (t.clickbutton) then
								self:SetBindingClick(true, key, t.clickframe or DefaultClickFrameName, t.clickbutton)
							end
						end
						keyBound = i
					end

					if (keyBound and clickBound) then
						break
					end
				end
			end

			if (not keyBound and bindings.hasNonClick) then
				bindings.bound = nil
				self:ClearBinding(key)
			end

			if (unitframe and bindings.hasClick and not clickBound) then
				local current = unitframe.clicks[key]
				if (unitframe.clicks[key]) then
					for k, v in pairs(current.clickAttrs) do
						unitframe.frame:SetAttribute(k, ClickAttrDefaultValues[unitframe.frame][k])
					end
					unitframe.clicks[key] = nil
				end
			end
		end
	end

	wipe(DirtyFlags)
]==]));

--- 클릭 시점 평가가 옛 경로와 같은 답을 내는지 대조한다. **빌드 시점에 가른다** - 릴리스에서는
--- 문자열이 비어서 스니펫에 이 줄들이 아예 없다.
---
--- 통과 기준이 "동작이 안 바뀌는 것"이라 관찰이 필요하다. 캐시로 남긴 상태들(combat, forms,
--- known …)은 양쪽이 **같은 값을 읽으므로 불일치가 곧 버그**다. 반대로 hover와 유닛 조건은
--- 어긋나는 것이 정상이고 - 그게 이 공사가 노린 개선분이다 - 그 빈도가 성과 지표가 된다.
--- 그래서 둘을 갈라서 보고한다.
local CLICKTIME_VERIFY_SNIPPET = DebindPrivate.DEBUG and [==[

	do
		-- 옛 경로의 판정을 캐시 값으로 그대로 재현한다(UpdateBindings 스니펫의 루프와 같다).
		local cachedIndex
		local uf = States.unitframe
		for i = 1, #bindings do
			local t = bindings[i]
			if (t.isNonClick) then
				local m = true

				if (t.hover ~= nil) then
					if (t.hover == false) then
						if (uf) then m = false end
					elseif (not uf) then
						m = false
					else
						if (t.reactions and ((t.reactions % (uf.reaction + uf.reaction)) < uf.reaction)) then
							m = false
						elseif (t.frameTypes and ((t.frameTypes % (uf.frameType + uf.frameType)) < uf.frameType)) then
							m = false
						end
					end
				end

				if (m and (
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
					m = false
				end

				if (m and t.known ~= nil and States[t.known] ~= true) then
					m = false
				end

				if (m and t.checkedUnits) then
					for u, cond in pairs(t.checkedUnits) do
						-- 옛 규약: "존재"는 값 비교가 아니라 진리값 검사다.
						local val = UnitStates[u]
						if (cond == true) then
							if (not val) then m = false end
						elseif (cond ~= val) then
							m = false
						end
						if (not m) then break end
					end
				end

				if (m and t.customStates) then
					for state, v in pairs(t.customStates) do
						if (States[state] ~= v) then
							m = false
							break
						end
					end
				end

				if (m) then
					cachedIndex = i
					break
				end
			end
		end

		if (cachedIndex ~= winnerIndex) then
			-- hover나 유닛 조건이 걸린 레코드가 관련돼 있으면 "갈리는 게 정상"인 쪽이다.
			local expected = false
			local a = winnerIndex and bindings[winnerIndex]
			local b = cachedIndex and bindings[cachedIndex]
			if (a and (a.hover ~= nil or a.checkedUnits)) then expected = true end
			if (b and (b.hover ~= nil or b.checkedUnits)) then expected = true end
			debind_driver:CallMethod("OnClickTimeMismatch", button,
				winnerIndex or 0, cachedIndex or 0, expected)
		end
	end
]==] or "";

BindingDriver:SetAttribute("ClearClickBindings", [==[
	for frame, info in pairs(ccframes) do
		if (info.clicks) then
			for _, t in pairs(info.clicks) do
				for attr, _ in pairs(t.clickAttrs) do
					info.frame:SetAttribute(attr, ClickAttrDefaultValues[info.frame][attr])
				end
			end
			wipe(info.clicks)
		end
	end
]==]);

BindingDriver:SetAttribute("ClearClickBindingsForButton", [==[
	local info = ccframes[self]
	if (info and info.clicks) then
		for _, t in pairs(info.clicks) do
			for attr, _ in pairs(t.clickAttrs) do
				info.frame:SetAttribute(attr, ClickAttrDefaultValues[info.frame][attr])
			end
		end
		wipe(info.clicks)
	end
]==]);

BindingDriver:SetAttribute("InitFrame", [==[
	local button = self
	ccframes[button] = ccframes[button] or newtable()
	ccframes[button].frame = button
	ccframes[button].clicks = ccframes[button].clicks or newtable()
	ccframes[button].frameType = 0
	ccframes[button].reaction = 0
	if (not ClickAttrDefaultValues[button]) then
		ClickAttrDefaultValues[button] = newtable()
		for i = 1, 5 do
			ClickAttrDefaultValues[button]["*type"..i] = button:GetAttribute("*type"..i)
			ClickAttrDefaultValues[button]["*macro"..i] = button:GetAttribute("*macro"..i)
			ClickAttrDefaultValues[button]["*macrotext"..i] = button:GetAttribute("*macrotext"..i)
			ClickAttrDefaultValues[button]["type"..i] = button:GetAttribute("type"..i)
			ClickAttrDefaultValues[button]["macro"..i] = button:GetAttribute("macro"..i)
			ClickAttrDefaultValues[button]["macrotext"..i] = button:GetAttribute("macrotext"..i)
		end
	end
]==]);

BindingDriver:SetAttribute("DeinitFrame", [==[
	local button = self
	debind_driver:RunFor(button, debind_driver:GetAttribute("ClearClickBindingsForButton"))
	local info = ccframes[button]
	if (info) then
		if (info == States.unitframe) then
			States.unitframe = nil
			if (debind_driver:RunAttribute("SetUnit", "hover", nil) or HoverBindings) then
				DirtyFlags.unitframe = true
				debind_driver:SetAttribute("state-unitexists", "unitframe")
				--debind_driver:RunAttribute("UpdateBindings")
			end
		end
		info.frame = nil
	end
	ccframes[button] = nil
	ClickAttrDefaultValues[button] = nil
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

BindingDriver:SetAttribute("setup_onenter", applyConstants([==[
	local unit = self:GetEffectiveAttribute("unit")
    if (not unit) then return end
	
	local unitframe = ccframes[self]
    local reaction
    if (PlayerCanAssist(unit)) then
        reaction = CONSTANTS.REACTION_HELP
    elseif (PlayerCanAttack(unit)) then
        reaction = CONSTANTS.REACTION_HARM
    else
        reaction = CONSTANTS.REACTION_OTHER
    end

    local unitChanged = unitframe.unit ~= unit or unitframe.reaction ~= reaction
	if (States.unitframe ~= unitframe or unitChanged) then
        unitframe.unit = unit
        unitframe.reaction = reaction
		States.unitframe = unitframe
        -- if (unitframe.insetL and not unitframe.l) then
        --     debind_driver:RunFor(self, debind_driver:GetAttribute("update_hit_bounds"))
        -- end
		if (debind_driver:RunAttribute("SetUnit", "hover", unit) or HoverBindings) then
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
	if (debind_driver:RunAttribute("SetUnit", "hover", nil) or HoverBindings) then
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

	BindingDriver:SetAttribute("clickcast_register", applyConstants([==[
		local button = self:GetAttribute("clickcast_button")
		if (ccframes[button]) then
			return
		end

		self:RunFor(button, self:GetAttribute("InitFrame"))
		ccframes[button].hd = true
		ccframes[button].frameType = CONSTANTS.FRAMETYPE_GROUP
		
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
				DebindPrivate.ccframes[button] = nil;
			end
		end
	end
end

--- 클릭 시점 평가와 옛 경로의 판정이 갈렸다. DEBUG 빌드에서만 불린다.
---
--- `expected`가 참이면 hover나 유닛 조건이 얽힌 것이라 **갈리는 게 정상**이다 - 옛 경로는
--- 최대 0.2초 묵은 값을 보고, 이쪽은 지금 값을 본다. 그 빈도가 이 공사의 성과 지표다.
--- 거짓이면 양쪽이 같은 캐시 값을 읽었는데도 답이 달랐다는 뜻이고, **그건 버그다.**
function BindingDriver:OnClickTimeMismatch(button, liveIndex, cachedIndex, expected)
	DebindPrivate.log(format("%s[Debind/clicktime]|r %s  live=%s cached=%s%s",
		expected and "|cff888888" or "|cffff4444",
		tostring(button), tostring(liveIndex), tostring(cachedIndex),
		expected and "  (hover/유닛 - 정상)" or "  <- 같은 값을 읽고 답이 갈렸다"));
end

function BindingDriver:OnSpecialUnitChanged(alias, value)
	DebindPrivate.OnSpecialUnitChanged(alias, value);
end

function BindingDriver:OnCustomStateChanged(name, value)
	DebindPrivate.OnCustomStateChanged(name, value);
end

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
--- **이 판에서는 할당을 하지 않는다.** `newtable()`도 문자열 결합도 없다 - 클릭 경로의
--- GC 스파이크는 평균 비용보다 훨씬 아프게 나타난다. 메모는 미리 만들어 둔 테이블을 쓴다.
SecureHandlerWrapScript(DebindPrivate.DefaultClickFrame, "OnClick", BindingDriver, applyConstants([==[
	local bindings = ClickTimeKeys[button]

	-- **맨이름 속성은 프레임에 남는다.** "안 쓰면 없다"가 아니라 "안 쓰면 앞의 것이 남는다"라
	-- 매 클릭 전부 확정해야 한다. 옛 경로로 들어온 클릭(deb1xx, /click 위임)에도 반드시
	-- 적용한다 - 앞 클릭이 남긴 unit 하나가 자가시전·주시시전·마우스오버시전을 통째로
	-- 죽인다(`checkselfcast`류는 unit이 없을 때만 동작한다). 오류도 로그도 안 난다.
	--
	-- pressAndHoldAction과 useOnKeyDown은 **항상 nil로만 쓴다.** 켜는 것은 B-11 수선이고
	-- 이번 범위가 아니다. 여기서 지우는 것은 앞 클릭의 잔류를 막기 위해서다.
	self:SetAttribute("unit", nil)
	self:SetAttribute("pressAndHoldAction", nil)
	self:SetAttribute("useOnKeyDown", nil)
	self:SetAttribute("type", nil)
	self:SetAttribute("macrotext", nil)

	if (not bindings) then
		-- 우리 키가 아니다. 버튼 이름을 바꾸지 않고 그대로 흘려보낸다.
		return
	end

	-- 실행 엣지가 down이면 up에서 `typerelease`가 한 번 더 나간다. **그때는 다시 고르면 안 된다** -
	-- down에서 A를 시전하고 up에서 B를 놓으면 A가 눌린 채로 남는다. 대상도 그때 확정한 값을
	-- 그대로 쓴다. 조건을 다시 보는 것이 아니라 **같은 액션을 놓는 것**이 이 자리의 일이다.
	--
	-- 실행 엣지가 up이면 캐리하지 않는다. 그때는 up이 유일한 실행 엣지라, 키를 오래 누르고
	-- 있었으면 down의 판단이 오히려 낡은 것이다.
	if (UseOnKeyDown and not down) then
		local held = HeldButtons[button]
		if (held) then
			HeldButtons[button] = nil
			self:SetAttribute("unit", HeldUnits[button])
			HeldUnits[button] = nil
			return held.clickbutton
		end
	end

	-- hover는 루프 밖에서 클릭당 한 번만 푼다. 레코드마다 다시 물으면 같은 C 호출이 반복된다.
	-- 어느 프레임을 hover 중인지는 enter/leave 이벤트로만 알 수 있어 캐시지만, 그 프레임의
	-- unit과 반응은 지금 다시 읽는다 - 폴링이 놓치는 창이 여기서 닫힌다.
	local unitframe = States.unitframe
	local hoverUnit, hoverReaction, hoverFrameType
	if (unitframe) then
		hoverUnit = unitframe.frame:GetEffectiveAttribute("unit")
		if (hoverUnit and UnitExists(hoverUnit)) then
			if (PlayerCanAssist(hoverUnit)) then
				hoverReaction = CONSTANTS.REACTION_HELP
			elseif (PlayerCanAttack(hoverUnit)) then
				hoverReaction = CONSTANTS.REACTION_HARM
			else
				hoverReaction = CONSTANTS.REACTION_OTHER
			end
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
	local winner, winnerIndex

	for i = 1, #bindings do
		local t = bindings[i]
		if (t.isNonClick) then
			local match = true

			if (t.hover ~= nil) then
				if (t.hover == false) then
					if (unitframe) then
						match = false
					end
				elseif (not unitframe) then
					match = false
				else
					if (t.reactions and ((t.reactions % (hoverReaction + hoverReaction)) < hoverReaction)) then
						match = false
					elseif (t.frameTypes and ((t.frameTypes % (hoverFrameType + hoverFrameType)) < hoverFrameType)) then
						match = false
					end
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

			if (match and t.checkedUnits) then
				if (not memoReady) then
					memoReady = true
					wipe(ClickUnitExists)
					wipe(ClickUnitAssist)
					wipe(ClickUnitAttack)
				end

				-- **조건마다 따로 묻는다.** 옛 경로는 유닛당 값 하나로 모든 질문자를
				-- 만족시켜야 해서 우호/적대에 우선순위를 두어야 했고, 그래서 남이 등록한
				-- 항 때문에 내 조건이 조용히 안 맞는 일이 있었다. 여기서는 그럴 이유가 없다.
				--
				-- 존재하지 않는 유닛에 대해 PlayerCanAssist/Attack이 둘 다 거짓이므로
				-- "help"/"harm"은 호출 한 번이 존재 검사까지 겸한다. 앞에 존재 게이트를
				-- 두면 흔한 쪽에서 C 호출이 하나 늘 뿐이다.
				for u, cond in pairs(t.checkedUnits) do
					local ok
					if (cond == "never") then
						ok = false
					else
						local unit, needsExists
						if (u == "hover") then
							-- 위에서 프레임에서 직접 읽은 값을 쓴다. UnitMap["hover"]는
							-- 캐시라 여기서만 그걸 보면 hover 조건과 다른 유닛을 판정하게
							-- 된다. 대상도 같은 값을 쓴다(아래 SetAttribute).
							unit = hoverUnit
						elseif (SpecialUnits[u]) then
							unit = UnitMap[u]
							needsExists = CustomUnits[u]
						else
							unit = u
							needsExists = true
						end

						if (not unit) then
							ok = (cond == false)
						elseif (cond == "help") then
							ok = ClickUnitAssist[unit]
							if (ok == nil) then
								ok = PlayerCanAssist(unit) and true or false
								ClickUnitAssist[unit] = ok
							end
						elseif (cond == "harm") then
							ok = ClickUnitAttack[unit]
							if (ok == nil) then
								ok = PlayerCanAttack(unit) and true or false
								ClickUnitAttack[unit] = ok
							end
						else
							local exists = true
							if (needsExists) then
								exists = ClickUnitExists[unit]
								if (exists == nil) then
									exists = UnitExists(unit) and true or false
									ClickUnitExists[unit] = exists
								end
							end
							ok = (cond == exists)
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
				winnerIndex = i
				break
			end
		end
	end
]==] .. CLICKTIME_VERIFY_SNIPPET .. [==[

	if (not winner) then
		-- 여기 오면 안 된다. IsKeyAlwaysClickBound가 "끝까지 무조건 액션이 없는" 키를
		-- 걸러내므로 반드시 하나는 맞아야 한다. 도달했다면 클릭을 취소하는 것이 옳다 -
		-- 이름을 그대로 두면 게임이 "@<키>"로 속성을 찾고, 그런 것은 없으니 오류도 로그도
		-- 없이 아무 일도 안 일어난다.
		return false
	end

	-- 대상을 맨이름으로 넣는다. 새 경로는 delegate 프레임을 쓰지 않는다.
	--
	-- **hover는 조건을 판정한 그 유닛에 그대로 쏜다.** UnitMap["hover"]는 enter와 폴링이
	-- 채우는 캐시라 프레임의 유닛이 바뀌면 늦게 따라온다. 조건은 live로 읽어놓고 대상만
	-- 캐시에서 가져오면 **판정한 유닛과 시전 대상이 갈린다** - 우호로 판정해 놓고 옛 유닛에
	-- 쏘는 것이다. 옛 경로는 둘 다 캐시라 적어도 일관됐으니 그보다 나빠진다.
	--
	-- 우호/적대로 효과가 갈리는 주문(참회 같은)에서는 이게 "액션이 안 나감"이 아니라
	-- **"다른 액션이 나감"**이고 되돌릴 수 없다. 반드시 같은 유닛이어야 한다.
	local unit
	if (winner.unit) then
		unit = winner.unit
	elseif (winner.unitAlias == "hover") then
		unit = hoverUnit
	elseif (winner.unitAlias) then
		unit = UnitMap[winner.unitAlias]
	end
	self:SetAttribute("unit", unit)

	-- 실행 엣지가 down이면 up이 이 선택을 그대로 재사용한다(위 캐리).
	-- `typerelease`가 구워진 액션에만 건다 - 그 밖의 액션은 up에서 조회가 nil이라 아무 일도
	-- 안 나므로 붙들 이유가 없고, 붙들면 낡은 판단을 재사용하는 쪽이 손해다.
	if (UseOnKeyDown and down and winner.pressAndHold) then
		HeldButtons[button] = winner
		HeldUnits[button] = unit
	end

	return winner.clickbutton
]==]));

