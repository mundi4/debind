local _, DebindPrivate                 = ...;
local Constants                          = DebindPrivate.Constants;
DebindPrivate.DEBUG                    = Constants.DEBUG;
DebindPrivate.callbacks                = LibStub("CallbackHandler-1.0"):New(DebindPrivate);
DebindPrivate.CliqueDetected           = C_AddOns.IsAddOnLoaded("Clique");
DebindPrivate.Units                    = {};

local L                                  = DebindPrivate.L;
local DEBUG                              = DebindPrivate.DEBUG;
local SPECIAL_UNITS                      = Constants.SPECIAL_UNITS;
local BASIC_UNITS                        = Constants.BASIC_UNITS;

local dump                               = DebindPrivate.dump;
local luatype                            = type;
local format, tostring                   = format, tostring;
local wipe, ipairs, pairs, tinsert, sort = wipe, ipairs, pairs, tinsert, sort;
local band, bor, bnot                    = bit.band, bit.bor, bit.bnot;
local InCombatLockdown                   = InCombatLockdown;
local GetSpellNameAndIconID              = DebindPrivate.GetSpellNameAndIconID;

local GetSpellSubtext                    = C_Spell.GetSpellSubtext;
local GetMountInfoByID                   = C_MountJournal.GetMountInfoByID;
local IsConditionalAction                = DebindPrivate.IsConditionalAction;

local BindingDriver                      = CreateFrame("Frame", DEBUG and "DebindBindingDriver" or nil, nil, "SecureHandlerBaseTemplate,SecureHandlerAttributeTemplate");
BindingDriver:SetAttribute("unit", "player");
RegisterUnitWatch(BindingDriver, true);
SecureHandlerExecute(BindingDriver, [[
	DelegateFrames = newtable()
	DelegateFrameNames = newtable()
]]);
DebindPrivate.BindingDriver       = BindingDriver;

DebindPrivate.ClickDelegateFrames = {};

local DefaultClickFrameName         = "DebindClickButton"
local DefaultClickFrame             = CreateFrame("Button", DefaultClickFrameName, nil, "SecureActionButtonTemplate");
DefaultClickFrame:RegisterForClicks("AnyUp", "AnyDown");
DefaultClickFrame:SetAttribute("checkselfcast", true);
DefaultClickFrame:SetAttribute("checkfocuscast", true);
DefaultClickFrame:SetAttribute("checkmouseovercast", true);
DebindPrivate.DefaultClickFrame = DefaultClickFrame;


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

	function DebindPrivate.GetDelegateFrame(key)
		local delegateFrame = DebindPrivate.ClickDelegateFrames[key];
		if (delegateFrame == nil) then
			if (SPECIAL_UNITS[key] or BASIC_UNITS[key]) then
				delegateFrame = CreateFrame("Button", "DebindClickButton_" .. key, DefaultClickFrame, "SecureActionButtonTemplate");
				delegateFrame.unit = key;
				if (SPECIAL_UNITS[key]) then
					delegateFrame:SetAttribute("alias", key);
					delegateFrame:SetAttribute("unit", "raid41");
				else
					delegateFrame:SetAttribute("unit", key);
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
				DebindPrivate.ClickDelegateFrames[key] = delegateFrame;

				if (DEBUG) then
					hooksecurefunc(delegateFrame, "SetAttribute", setAttributeHook);
				end
			else
				DebindPrivate.log("No delegate frame:", key);
			end
		end
		return delegateFrame;
	end
end


DebindPrivate.KeyMap                 = {};
DebindPrivate.ActiveActions          = {};
DebindPrivate.BindingInfoToActionMap = {};

--- 액션 선택을 클릭 시점에 하는 키. `키 -> 클릭 프레임에 건 버튼 이름`.
--- 보안 쪽 `ClickTimeKeys`는 같은 것을 버튼 이름으로 색인한 것이다(래퍼가 그 방향으로 찾는다).
--- 여기 없는 키는 키를 잡는 레코드가 아예 없는 키다(클릭캐스팅 전용).
---
--- **"이 키가 항상 우리 것인가"와는 다르다.** 그쪽은 `bindings.alwaysOurs`이고, 여기 있는
--- 키 중 일부다 - 나머지는 "잡느냐 놓느냐"를 상태 루프가 계속 정하고 어느 액션인지만
--- 클릭 시점에 정한다.
---
--- **재할당하지 말 것.** DevTool이 이 참조를 들고 있으므로 갈아치우면 그쪽이 옛 표를 계속
--- 본다. 갱신은 `wipe` 후 채우기다.
DebindPrivate.ClickTimeKeys          = {};
dump("ClickTimeKeys", DebindPrivate.ClickTimeKeys);

--- 배선을 상태 루프가 정하는 키. DEBUG mirror of `StateDrivenBindings` membership, recorded
--- at emit time (`AppendBindingsList`) -- the same branch emits the insert and records the
--- key, so the mirror cannot diverge from the table.
---
--- **DEBUG 전용.** 읽는 것이 사람뿐이다.
---
--- **재할당하지 말 것.** DevTool이 이 참조를 들고 있다 - 갱신은 `wipe` 후 채우기다.
DebindPrivate.StateDrivenKeys        = {};
dump("StateDrivenKeys", DebindPrivate.StateDrivenKeys);

do
	local KeyMap = DebindPrivate.KeyMap;
	local ActiveActions = DebindPrivate.ActiveActions;
	local BindingInfoToActionMap = DebindPrivate.BindingInfoToActionMap;

	dump("KeyMap", KeyMap);
	dump("ActiveActions", ActiveActions);
	dump("BindingInfoToActionMap", BindingInfoToActionMap);

	-- 순서 규칙 자체는 Ordering.lua에 있다. binding 테이블이 그대로 레코드 역할을 한다
	-- (priority/hover는 GetBindingInfoForAction이, layerRank/index/isConditional은 아래 루프가 채운다).
	local BindingSortComparison = DebindPrivate.CompareActionOrder;

	function DebindPrivate.BuildKeyMap()
		wipe(KeyMap);
		wipe(ActiveActions);
		wipe(BindingInfoToActionMap);
		DebindPrivate.ClearUnreachableBindingCache();

		-- EnumerateActionsInActiveLayers와 같은 순서를 돌지만, 통짜 ordinal 대신
		-- layerRank를 따로 알아야 해서 레이어를 직접 훑는다.
		local ordinal = 0;
		for layerRank, layer in DebindPrivate.EnumerateProfileLayers() do
			for _, action in layer:Enumerate() do
				ordinal = ordinal + 1;
				-- **An imported action is quarantined until the badge comes off.** It is in the
				-- profile, it is drawn, and it does nothing: importing someone else's string must
				-- not change a single key until the reader says so, because there is no undo for
				-- "my F does something else now" and no way to see what changed.
				--
				-- **The test is here, outside, and not down at `KeyMap`.** Skipping further in
				-- would leave `ActiveActions[action]` set, and that field is what
				-- `IsInactiveAction` reads to grey a row out. Up here a quarantined action gets
				-- exactly the treatment a keyless one already gets - drawn, greyed, reaching
				-- nothing - and that costs no new drawing code.
				if (action.key and not action.imported) then
					local binding = DebindPrivate.GetBindingInfoForAction(action, true);
					BindingInfoToActionMap[binding] = action;

					binding.layerRank = layerRank;
					binding.seq = action.seq;
					binding.isConditional = IsConditionalAction(action);

					local key = action.key;
					local issue = DebindPrivate.GetBindingIssue(action);
					-- 게임이 바인딩 컨텍스트로 가져간 키는 KeyMap에 넣지 않는다. 즉 그 키에는
					-- 오버라이드를 걸지 않고, 편집기가 닫히면 다시 들어온다.
					-- keepInBindingContext를 켠 액션은 예외로 그대로 건다. 편집기가 자기 버튼에
					-- 그 키를 표시한 채로 안 먹게 되므로, 유저가 알고 켜는 것이어야 한다.
					local yielded = DebindPrivate.IsKeyYielded(key) and not action.keepInBindingContext;
					if (not issue and not yielded) then
						if (not KeyMap[key]) then
							KeyMap[key] = {};
							local button, buttonPrefix = DebindPrivate.GetMouseButtonAndPrefix(key);
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
				DebindPrivate.CheckUnreachableBindings(bindings);
			end
		end
	end

	function DebindPrivate.GetKeyMap()
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
	DebindPrivate.updateBindingsQueued = nil;
	DebindPrivate.UpdateBindings();
end

--- 다음 프레임에 돌기로 예약된 리빌드가 있나.
---
--- 리빌드는 `States`를 통째로 새로 채우므로, 그 사이에 상태를 읽으면 곧 뒤집힐 값을 읽는다.
--- 밖에서 "지금 물어봐도 되는 때인가"를 알 수 있게 노출한다.
function DebindPrivate.IsUpdateBindingsQueued()
	return DebindPrivate.updateBindingsQueued and true or false;
end

function DebindPrivate.QueueUpdateBindings()
	if (not DebindPrivate.updateBindingsQueued) then
		DebindPrivate.updateBindingsQueued = true;
		C_Timer.After(0, UpdateBindingsTimerCallback);
	end
end

if (DEBUG) then
	_G.DebindPrivate = DebindPrivate;
end
