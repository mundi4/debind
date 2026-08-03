local _, DebouncePrivate                 = ...;
local Constants                          = DebouncePrivate.Constants;
DebouncePrivate.DEBUG                    = Constants.DEBUG;
DebouncePrivate.callbacks                = LibStub("CallbackHandler-1.0"):New(DebouncePrivate);
DebouncePrivate.CliqueDetected           = C_AddOns.IsAddOnLoaded("Clique");
DebouncePrivate.Units                    = {};

local L                                  = DebouncePrivate.L;
local DEBUG                              = DebouncePrivate.DEBUG;
local SPECIAL_UNITS                      = Constants.SPECIAL_UNITS;
local BASIC_UNITS                        = Constants.BASIC_UNITS;

local dump                               = DebouncePrivate.dump;
local luatype                            = type;
local format, tostring                   = format, tostring;
local wipe, ipairs, pairs, tinsert, sort = wipe, ipairs, pairs, tinsert, sort;
local band, bor, bnot                    = bit.band, bit.bor, bit.bnot;
local InCombatLockdown                   = InCombatLockdown;
local GetSpellNameAndIconID              = DebouncePrivate.GetSpellNameAndIconID;

local GetSpellSubtext                    = C_Spell.GetSpellSubtext;
local GetMountInfoByID                   = C_MountJournal.GetMountInfoByID;
local IsConditionalAction                = DebouncePrivate.IsConditionalAction;

local BindingDriver                      = CreateFrame("Frame", DEBUG and "DebounceBindingDriver" or nil, nil, "SecureHandlerBaseTemplate,SecureHandlerAttributeTemplate");
BindingDriver:SetAttribute("unit", "player");
RegisterUnitWatch(BindingDriver, true);
SecureHandlerExecute(BindingDriver, [[
	DelegateFrames = newtable()
	DelegateFrameNames = newtable()
]]);
DebouncePrivate.BindingDriver       = BindingDriver;

DebouncePrivate.ClickDelegateFrames = {};

local DefaultClickFrameName         = "DebounceClickButton"
local DefaultClickFrame             = CreateFrame("Button", DefaultClickFrameName, nil, "SecureActionButtonTemplate");
DefaultClickFrame:RegisterForClicks("AnyUp", "AnyDown");
DefaultClickFrame:SetAttribute("checkselfcast", true);
DefaultClickFrame:SetAttribute("checkfocuscast", true);
DefaultClickFrame:SetAttribute("checkmouseovercast", true);
DebouncePrivate.DefaultClickFrame = DefaultClickFrame;


do
	local _attrsSet = {};
	local setAttributeHook = function(self, name, value)
		local frameName = self:GetName() or tostring(self);
		_attrsSet[frameName] = _attrsSet[frameName] or {};
		_attrsSet[frameName][name] = value;
	end

	if (DEBUG) then
		hooksecurefunc(DefaultClickFrame, "SetAttribute", setAttributeHook);
		dump("Binding Attributes", _attrsSet);
	end

	function DebouncePrivate.GetDelegateFrame(key)
		local delegateFrame = DebouncePrivate.ClickDelegateFrames[key];
		if (delegateFrame == nil) then
			if (key == Constants.COMBINED or SPECIAL_UNITS[key] or BASIC_UNITS[key]) then
				local delegateName = key == Constants.COMBINED and "DebounceKey" or "DebounceClickButton_" .. key;
				delegateFrame = CreateFrame("Button", delegateName, DefaultClickFrame, "SecureActionButtonTemplate");
				if (key == Constants.COMBINED) then
				else
					delegateFrame.unit = key;
					if (SPECIAL_UNITS[key]) then
						delegateFrame:SetAttribute("alias", key);
						delegateFrame:SetAttribute("unit", "raid41");
					else
						delegateFrame:SetAttribute("unit", key);
					end
				end
				delegateFrame:SetAttribute("useparent*", true);
				delegateFrame:SetAttribute("useparent-unit", false);
				delegateFrame:RegisterForClicks("AnyUp", "AnyDown");
				SecureHandlerSetFrameRef(BindingDriver, "clickFrame", delegateFrame);
				SecureHandlerExecute(BindingDriver, [[
local frame = self:GetFrameRef("clickFrame")
local unit = frame:GetAttribute("alias") or frame:GetAttribute("unit")
if (unit) then
	DelegateFrames[unit] = frame
end
DelegateFrames[frame:GetName()] = frame
DelegateFrameNames[frame] = frame:GetName()
]]);
				DebouncePrivate.ClickDelegateFrames[key] = delegateFrame;

				if (DEBUG) then
					hooksecurefunc(delegateFrame, "SetAttribute", setAttributeHook);
				end
			elseif (DEBUG) then
				print("No delegate frame:", key);
			end
		end
		return delegateFrame;
	end
end
DebouncePrivate.GetDelegateFrame(Constants.COMBINED);


DebouncePrivate.KeyMap                 = {};
DebouncePrivate.ActiveActions          = {};
DebouncePrivate.BindingInfoToActionMap = {};
DebouncePrivate.CombinedKeys           = {};

do
	local KeyMap = DebouncePrivate.KeyMap;
	local ActiveActions = DebouncePrivate.ActiveActions;
	local BindingInfoToActionMap = DebouncePrivate.BindingInfoToActionMap;

	dump("KeyMap", KeyMap);
	dump("ActiveActions", ActiveActions);
	dump("BindingInfoToActionMap", BindingInfoToActionMap);

	-- 순서 규칙 자체는 Ordering.lua에 있다. binding 테이블이 그대로 레코드 역할을 한다
	-- (priority/hover는 GetBindingInfoForAction이, layerRank/index/isConditional은 아래 루프가 채운다).
	local BindingSortComparison = DebouncePrivate.CompareActionOrder;

	function DebouncePrivate.BuildKeyMap()
		wipe(KeyMap);
		wipe(ActiveActions);
		wipe(BindingInfoToActionMap);
		DebouncePrivate.ClearUnreachableBindingCache();

		-- EnumerateActionsInActiveLayers와 같은 순서를 돌지만, 통짜 ordinal 대신
		-- (layerRank, index)를 따로 알아야 해서 레이어를 직접 훑는다.
		local ordinal = 0;
		for layerRank, layer in DebouncePrivate.EnumerateProfileLayers() do
			for index, action in layer:Enumerate() do
				ordinal = ordinal + 1;
				if (action.key) then
					local binding = DebouncePrivate.GetBindingInfoForAction(action, true);
					BindingInfoToActionMap[binding] = action;

					binding.layerRank = layerRank;
					binding.index = index;
					binding.isConditional = IsConditionalAction(action);

					local key = action.key;
					local issue = DebouncePrivate.GetBindingIssue(action);
					-- 게임이 바인딩 컨텍스트로 가져간 키는 KeyMap에 넣지 않는다. 즉 그 키에는
					-- 오버라이드를 걸지 않고, 편집기가 닫히면 다시 들어온다.
					if (not issue and not DebouncePrivate.IsKeyYielded(key)) then
						if (not KeyMap[key]) then
							KeyMap[key] = {};
							local button, buttonPrefix = DebouncePrivate.GetMouseButtonAndPrefix(key);
							if (button) then
								KeyMap[key].button, KeyMap[key].buttonPrefix = button, buttonPrefix;
							end
						end
						tinsert(KeyMap[key], binding);
					end

					ActiveActions[action] = ordinal;
				end
			end
		end

		for _, bindings in pairs(KeyMap) do
			if (#bindings > 1) then
				sort(bindings, BindingSortComparison);
				DebouncePrivate.CheckUnreachableBindings(bindings);
			end
		end
	end

	function DebouncePrivate.GetKeyMap()
		local ret = {};
		for key, bindingArr in pairs(KeyMap) do
			local actionArr = {};
			for i = 1, #bindingArr do
				actionArr[i] = BindingInfoToActionMap[bindingArr[i]];
			end
			ret[key] = actionArr;
		end
		return ret;
	end
end

local function UpdateBindingsTimerCallback()
	DebouncePrivate.updateBindingsQueued = nil;
	DebouncePrivate.UpdateBindings();
end

function DebouncePrivate.QueueUpdateBindings()
	if (not DebouncePrivate.updateBindingsQueued) then
		DebouncePrivate.updateBindingsQueued = true;
		C_Timer.After(0, UpdateBindingsTimerCallback);
	end
end

if (DEBUG) then
	_G.DebouncePrivate = DebouncePrivate;
end
