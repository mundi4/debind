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
-- **The client's three targeting branches are off, and spelled out as off.**
--
-- Self cast and focus cast are decided by the click wrapper instead, because the client's order
-- lets a pointed unit beat a held modifier and a unit of ours stops the branches from being
-- reached at all (`devdocs/implementing-focus-and-self-cast.md` §1, §3-7). Left on, they would
-- still redirect every press that fires with no unit.
--
-- Mouseover cast cannot reach a right answer on this button. `SecureButton_GetModifiedUnit` decides
-- it with `C_ActionBar.IsHelpfulAction(self:CalculateAction(button))`, and `CalculateAction` answers
-- `1` for a button with no `GetID()` and no `action` attribute -- this one has neither, and never
-- will. So the branch would judge every Debind key by whatever sits in action bar slot 1 instead of
-- by the spell the key fires, and filling `action` in needs the helpful/harmful answer the branch is
-- being asked for.
DefaultClickFrame:SetAttribute("checkselfcast", false);
DefaultClickFrame:SetAttribute("checkfocuscast", false);
DefaultClickFrame:SetAttribute("checkmouseovercast", false);
DebindPrivate.DefaultClickFrame = DefaultClickFrame;

-- **Where a cast with a chosen target goes out.** A binding whose target the reader picked is
-- fired through a macro body that turns `autoSelfCast` off around it, and that body clicks this
-- frame rather than the one above (`devdocs/matching-the-clients-cast-targeting.md` §2-2).
--
-- **The click wrapper is on `DefaultClickFrame`, and its prologue wipes the bare `unit`.** Sending
-- the inner click back to that frame would clear the target the wrapper had just settled, which is
-- the very thing this route exists to keep. Nothing wraps this frame, so what is written here
-- stands until the cast reads it.
--
-- `useOnKeyDown` is pinned rather than left to the reader's CVar: the inner `/click` carries no
-- edge, so it always arrives as up, and with the CVar on the gate's `clickAction` would be false
-- and the cast would go nowhere with nothing said (`SecureTemplates.lua`'s 795-814, the same trap
-- the click-cast branch pins it for).
--- **The action attributes are written here as well as on the click frame, and `useparent*` is not
--- how this frame gets them.** It used to be a child of the click frame carrying `useparent*` with
--- `useparent-unit` off, which reads back exactly right -- `GetEffectiveAttribute("*type-deb103")`
--- answers `spell` and `SecureButton_GetModifiedUnit` answers the unit -- and casts nothing at all.
--- Measured on 2026-09-11 across four runs: inherited, no cast; stamped on this frame, the cast
--- goes out, with the frame a child either way. **So the parentage was never what broke it**, and
--- reading an attribute back is not proof that the gate will find it.
---
--- **And with nothing left to inherit there is nothing left to be a child for.** The three
--- `check*cast` attributes are the only ones the click frame carries that this frame would have
--- wanted, and every one of them is a branch `SecureButton_GetModifiedUnit` reaches only where the
--- button has no `unit` -- which this one always has, because the snippet that routes a click here
--- writes it first (`SecureBindings.lua`, `SELFCAST_OFF_SNIPPET`).
local CastFrameName                 = "DebindCastButton";
local CastFrame                     = CreateFrame("Button", CastFrameName, nil, "SecureActionButtonTemplate");
CastFrame:RegisterForClicks("AnyUp", "AnyDown");
CastFrame:SetAttribute("useOnKeyDown", false);
DebindPrivate.CastFrame = CastFrame;
DebindPrivate.CastFrameName = CastFrameName;


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

do
	local KeyMap = DebindPrivate.KeyMap;
	local ActiveActions = DebindPrivate.ActiveActions;

	dump("KeyMap", KeyMap);
	dump("ActiveActions", ActiveActions);

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

	--- The full list an original binding stands for (`Misc.lua`'s `GetBindingsForAction`), and the
	--- hover twin in it where there is one.
	---
	--- **Wiped each rebuild rather than made weak like `Placements` above.** The value here is the
	--- list whose `[1]` is the key, and Lua 5.1 marks a weak-keyed table's values strongly -- so
	--- the entry would keep its own key reachable and never be collected (ephemerons are 5.2).
	--- Nothing is allocated by the wipe: the lists themselves are `Misc.lua`'s to keep.
	local Lists = {};
	local HoverTwins = {};
	local _unroll = {};
	local _pointed = {};

	local function HoverTwinSortComparison(lhs, rhs)
		return CompareActionOrder(Placements[HoverTwins[lhs]], Placements[HoverTwins[rhs]]);
	end

	--- Lays the sorted originals out as the key, in four tiers: every self twin, every focus twin,
	--- every hover twin, every original (`devdocs/implementing-focus-and-self-cast.md` §3-4). A probe
	--- goes with the binding it gates, right ahead of it.
	---
	--- **Tiers, not each action's bindings side by side.** Side by side, an original placed first
	--- took a pointed press before a hover twin behind it had a turn, so the same key went at the
	--- target or at the pointed unit depending on which of the two was hostile. The self and focus
	--- tiers change no winner either way, since a held modifier and none held never meet.
	---
	--- **The hover tier has an order of its own.** A twin stands where the action the reader would
	--- have made by hand, with the twin's condition, would stand. Put in its own action's place, the
	--- twin of an action with no condition fell behind every action with a hover condition,
	--- whatever the reader had put first.
	local function UnrollIntoTiers(bindings)
		local count = #bindings;
		for i = 1, count do
			_unroll[i] = bindings[i];
		end

		local out = 0;
		for tier = 1, 2 do
			local castModifier = tier == 1 and Constants.CASTMOD_SELF or Constants.CASTMOD_FOCUS;
			for i = 1, count do
				local list = Lists[_unroll[i]];
				for j = #list, 2, -1 do
					if (list[j].castModifier == castModifier) then
						out = out + 1;
						bindings[out] = list[j];
					end
				end
			end
		end

		local pointed = 0;
		for i = 1, count do
			if (HoverTwins[_unroll[i]]) then
				pointed = pointed + 1;
				_pointed[pointed] = _unroll[i];
			end
		end
		if (pointed > 1) then
			sort(_pointed, HoverTwinSortComparison);
		end
		for k = 1, pointed do
			local list = Lists[_pointed[k]];
			for j = #list, 2, -1 do
				if (list[j].hoverTwin) then
					out = out + 1;
					bindings[out] = list[j];
				end
			end
		end

		for i = 1, count do
			local list = Lists[_unroll[i]];
			for j = #list, 1, -1 do
				if (list[j].castModifier == Constants.CASTMOD_NONE and not list[j].hoverTwin) then
					out = out + 1;
					bindings[out] = list[j];
				end
			end
		end

		wipe(_unroll);
		wipe(_pointed);
	end

	function DebindPrivate.BuildKeyMap()
		wipe(KeyMap);
		wipe(ActiveActions);
		wipe(Lists);
		wipe(HoverTwins);
		DebindPrivate.ClearUnreachableBindingCache();

		-- **The layers are walked here rather than through an enumerator because both numbers are
		-- wanted.** `layerRank` goes to the order record and the flat `ordinal` to `ActiveActions`,
		-- and anything handing over one count with the rank folded in would have to be undone at
		-- the comparator.
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
				local binding, list;
				if (action.key and not action.arrivalID) then
					list = DebindPrivate.GetBindingsForAction(action);
					binding = list[1];
				end

				-- **The specialization index is filtered here and nowhere below.** It is the only
				-- condition the insecure side settles by itself: it cannot change in combat, and a
				-- change rebuilds everything, so the world this build is made for has one answer to
				-- it (`Misc.lua`'s `SpecConditionHolds`).
				--
				-- **Which is also why the solver needs no column for it.** Every binding that gets
				-- past this line satisfies its own specialization condition, so the condition is
				-- true across the whole space the solver reasons over, and a box that spans the
				-- space is what "no condition" already means there. An axis that told the two
				-- apart would be an axis with one reachable value.
				--
				-- **A `known` with nothing to ask about is filtered here for the same reason**
				-- (`KnownConditionCanHold`). Left in, the binding would take the key from the
				-- actions behind it and put a conditional that is false for the life of this
				-- build into the state loop to be measured every tick.
				if (binding and DebindPrivate.SpecConditionHolds(binding)
						and DebindPrivate.KnownConditionCanHold(binding)) then
					Lists[binding] = list;

					-- 활성 레이어만 도므로 전문화 순위는 언제나 동률이다. 다른 전문화의 순서를
					-- 묻는 것은 창 쪽이고, 그쪽은 `CollectActionsForKey`로 간다.
					Placements[binding] = DebindPrivate.MakeOrderRecord(
						action, layerRank, nil, Placements[binding]);

					for j = 2, #list do
						local twin = list[j];
						if (twin.hoverTwin and not twin.spellbook) then
							HoverTwins[binding] = twin;
							Placements[twin] = DebindPrivate.MakeOrderRecord(
								action, layerRank, nil, Placements[twin], twin);
							break;
						end
					end

					local key = action.key;
					local issue = DebindPrivate.GetBindingIssue(action);
					-- A key the game has claimed gets no override, and comes back when the claim ends.
					-- keepInBindingContext overrides the house editor only: the editor goes on showing
					-- the key on its own button while it does nothing, so the reader turns it on knowing.
					local yielded = (DebindPrivate.IsKeyYielded(key) and not action.keepInBindingContext)
						or DebindPrivate.IsKeyYieldedToPetBattle(key);
					-- **Only an ERROR keeps the action off its key.** That is what the grades mean
					-- (`Constants.BINDING_ISSUE_GRADES`), and this gate read `not issue` until the
					-- first WARNING code arrived (the hover twin lost to Clique, since retired):
					-- measured then, `KeyMap` came out with no record for that key at all, so an
					-- action that was to lose the aiming over frames and nothing else fired on no
					-- unit whatever.
					if ((not issue or DebindPrivate.IssueKeepsKey(issue)) and not yielded) then
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
			end
			UnrollIntoTiers(bindings);
			if (#bindings > 1) then
				DebindPrivate.CheckUnreachableBindings(bindings);
			end
		end
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
