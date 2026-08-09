--[[
FIXME 유닛 popup메뉴에 들어갔다가 나오면 hover값이 nil로 변경되지 않음
]]

local _, DebindPrivate = ...;
local BindingDriver      = DebindPrivate.BindingDriver;
local Constants          = DebindPrivate.Constants;

local function applyConstants(str)
	return str:gsub("CONSTANTS%.([_A-Za-z0-9]+)", function(m)
		local value = Constants[m];
		assert(value ~= nil, m);
		if (type(value) == "string") then
			return format("%q", value);
		else
			return tostring(value);
		end
	end);
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
]]);


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

		if (check) then
			local keyBound, clickBound = not bindings.hasNonClick, not bindings.hasClick
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

function BindingDriver:OnSpecialUnitChanged(alias, value)
	DebindPrivate.OnSpecialUnitChanged(alias, value);
end

function BindingDriver:OnCustomStateChanged(name, value)
	DebindPrivate.OnCustomStateChanged(name, value);
end
