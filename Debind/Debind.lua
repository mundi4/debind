local _, DebindPrivate                 = ...;
local Constants                          = DebindPrivate.Constants;
DebindPrivate.DEBUG                    = Constants.DEBUG;
DebindPrivate.callbacks                = LibStub("CallbackHandler-1.0"):New(DebindPrivate);
DebindPrivate.CliqueDetected           = C_AddOns.IsAddOnLoaded("Clique");
DebindPrivate.Units                    = {};

local DEBUG                              = DebindPrivate.DEBUG;
local SPECIAL_UNITS                      = Constants.SPECIAL_UNITS;
local BASIC_UNITS                        = Constants.BASIC_UNITS;

local dump                               = DebindPrivate.dump;
local tostring                           = tostring;
local wipe, pairs, tinsert, sort         = wipe, pairs, tinsert, sort;


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

	--- 어느 바인딩이 이 키에서 몇 번째로 서는지. `Misc.lua`의 `MakeOrderRecord`가 채우고,
	--- 규칙 자체는 `Ordering.lua`에 있다.
	---
	--- **바인딩 옆에 두고 바인딩 안에 안 넣는다.** 바인딩은 액션 하나의 순수 파생이라,
	--- 프로필 안에서의 자리처럼 액션만 봐서는 안 나오는 값이 거기 앉으면 그 성질이 깨진다.
	--- 예전에는 아래 루프가 `layerRank`/`seq`/`isConditional`을 바인딩에 직접 써넣었고,
	--- 아무도 그것을 지우지 않아서 다음 리빌드까지 남아 있었다.
	---
	--- 키가 약해서(weak) 바인딩이 죽으면 같이 사라진다. `wipe`하지 않는 것은 레코드 표를
	--- 재사용하기 위해서다. 이 함수는 리빌드마다 모든 바인딩을 도는데, 예전에는 여기서
	--- 아무것도 할당하지 않았다.
	local Placements = setmetatable({}, { __mode = "k" });
	local CompareActionOrder = DebindPrivate.CompareActionOrder;

	local function BindingSortComparison(lhs, rhs)
		return CompareActionOrder(Placements[lhs], Placements[rhs]);
	end

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
				-- **The badge is the whole of the gate now.** An arrival keeps the key it was sent
				-- on, so the key says nothing about whether it is the reader's yet - this line
				-- used to have a second test for a number standing in for an undecided key, and
				-- that shape is gone (`devdocs/building-export-import.md` 12절). Which also means
				-- accepting is the moment a key starts working, where it used to leave the set
				-- parked; the prompt on [Accept all] is where that difference is paid for.
				if (action.key and not action.arrivalID) then
					local binding = DebindPrivate.GetBindingInfoForAction(action);
					BindingInfoToActionMap[binding] = action;

					-- 활성 레이어만 도므로 전문화 순위는 언제나 동률이다. 다른 전문화의 순서를
					-- 묻는 것은 창 쪽이고, 그쪽은 `CollectActionsForKey`로 간다.
					Placements[binding] = DebindPrivate.MakeOrderRecord(
						action, layerRank, nil, Placements[binding]);

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
