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
-- **`unit` stays and the watch is gone.** Blizzard's `RegisterUnitWatch(frame, true)` wrote
-- `state-unitexists` here five times a second, and the pass it woke measured values that only a
-- computed switch announcing a change ever read. Those announce nothing now
-- (`SwitchesChangedCallback`, `Misc.lua`), so the pass went with them and every condition is
-- measured at the press instead. The attribute is what `RegisterUnitWatch` would resolve, and it
-- costs nothing standing here.
BindingDriver:SetAttribute("unit", "player");
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
-- reached at all (`implementing-focus-and-self-cast.md` §1, §3-7). Left on, they would
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
-- frame rather than the one above (`matching-the-clients-cast-targeting.md` §2-2).
--
-- **The click wrapper is on `DefaultClickFrame`, and its prologue wipes the bare `unit`.** Sending
-- the inner click back to that frame would clear the target the wrapper had just settled, which is
-- the very thing this route exists to keep. Nothing wraps this frame, so what is written here
-- stands until the cast reads it.
--
-- `useOnKeyDown` is pinned rather than left to the reader's CVar: the `/click` we bake carries no
-- edge, so it always arrives as up, and with the CVar on the gate's `clickAction` would be false
-- and the cast would go nowhere with nothing said (`SecureTemplates.lua`'s 795-814, the same trap
-- the click-cast branch pins it for).
--
-- **A `/click` can carry an edge; ours does not.** The third token goes through `StringToBoolean`
-- into `Click(mouseButton, down)`, so `true` there would arrive as a down edge (2026-09-21, in the
-- game). This pin stays because the baked body has no reason to send one, not because sending one
-- is impossible -- which is what this said until it was measured.
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
--- button has no `unit`.
---
--- **Not carrying them is what leaves the client's own rules standing where the reader chose no
--- target.** A wrapped press writes this frame's `unit` on the way through and writes nothing when
--- it has none (`SecureBindings.lua`, `CAST_BUTTON_SNIPPET`), so an action with no target reaches
--- the cast with no unit and no check of ours, which is how an action bar button behaves. The
--- self and focus twins do not come through here for their unit either: Debind settles those and
--- hands the unit over already chosen.
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

--- The keys this rebuild bound to the click frame, `key -> button name`. The restricted
--- `ClickTimeKeys` holds the same pairs indexed by button name, which is the way the wrapper looks.
---
--- **Filled on the line that binds the key** (`UpdateBindings.lua`'s `UpdateBindingsMap`), which is
--- what lets `IsKeyOurs` answer from it.
---
--- **Never reassigned.** DevTool holds this reference, so a new table would leave it reading the old
--- one; a rebuild wipes and refills it.
DebindPrivate.ClickTimeKeys          = {};
dump("ClickTimeKeys", DebindPrivate.ClickTimeKeys);

--- Keys an action on a live layer holds whether or not any of its bindings reached `KeyMap`.
--- `BuildKeyMap` fills it and `UpdateBindingsMap` binds every key in it.
DebindPrivate.KeysToHold             = {};
dump("KeysToHold", DebindPrivate.KeysToHold);

--- **Keys a press on which reaches this addon.** Not the same question as either table above, and
--- the only one the window has any business asking: what a reader wants to know about a key is
--- whether pressing it does anything of ours, not how it was wired.
---
--- Wider than `KeysToHold` by exactly one case, and that case is why this exists. A mouse button
--- that runs over a unit frame holds no key at all -- the press arrives through the frame -- and it
--- works. Asked of the other two tables it reads as a key we do not have.
---
--- Narrower by one as well: the game menu key is in neither, because nothing can take it.
DebindPrivate.HandledKeys            = {};
dump("HandledKeys", DebindPrivate.HandledKeys);

--- Is the key bound to us by the last rebuild. A key waiting on a queued rebuild
--- (`IsUpdateBindingsQueued`) is still answered as that rebuild left it.
---
--- **This is about the override, not about whether the key does anything.** `IsKeyHandled` is the
--- second one, and a screen asking on a reader's behalf wants that.
function DebindPrivate.IsKeyOurs(key)
	return DebindPrivate.ClickTimeKeys[key] ~= nil;
end

--- Does pressing this key reach us at all, however it is wired.
function DebindPrivate.IsKeyHandled(key)
	return DebindPrivate.HandledKeys[key] == true;
end

do
	local KeyMap = DebindPrivate.KeyMap;
	local ActiveActions = DebindPrivate.ActiveActions;
	local KeysToHold = DebindPrivate.KeysToHold;
	local HandledKeys = DebindPrivate.HandledKeys;

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
	local _unroll = {};

	--- Lays the sorted originals out as the key, in four tiers: every self twin, every focus twin,
	--- every hover twin, every original (`which-action-a-key-runs.md` §3). A probe goes with
	--- the binding it gates, right ahead of it.
	---
	--- **Tiers, not each action's bindings side by side.** Side by side, an original placed first
	--- took a pointed press before a hover twin behind it had a turn, so the same key went at the
	--- target or at the pointed unit depending on which of the two was hostile. The self and focus
	--- tiers change no winner either way, since a held modifier and none held never meet.
	---
	--- **Every tier is in the originals' order, the hover tier included** (2026-09-16, owner). That
	--- order is the one the window draws, and an order the reader cannot see is an order they cannot
	--- fix. The hover tier used to sort itself by where each twin's own condition would have put it.
	---
	--- **The last tier leaves out an original whose Normal Cast is off**, which is what makes a press
	--- with nothing held and nothing pointed at fall through to the next action (§6).
	---
	--- **No tier takes a binding that cannot stand** (`binding.dead`). Nothing downstream drops it: a
	--- zero in its box the solver neither marks nor drops, and the solo rule is not in the box at all.
	local function UnrollIntoTiers(bindings)
		local count = #bindings;
		for i = 1, count do
			_unroll[i] = bindings[i];
		end

		local out = 0;
		for tier = 1, 4 do
			local castModifier = Constants.CASTMOD_NONE;
			if (tier == 1) then
				castModifier = Constants.CASTMOD_SELF;
			elseif (tier == 2) then
				castModifier = Constants.CASTMOD_FOCUS;
			end
			local wantHover = tier == 3;
			for i = 1, count do
				local list = Lists[_unroll[i]];
				for j = #list, 1, -1 do
					local binding = list[j];
					if (not binding.dead and binding.castModifier == castModifier
							and (binding.hoverTwin or false) == wantHover
							and (tier ~= 4 or binding.normalCast ~= false)) then
						out = out + 1;
						bindings[out] = binding;
					end
				end
			end
		end

		for i = out + 1, count do
			bindings[i] = nil;
		end

		wipe(_unroll);
	end

	function DebindPrivate.BuildKeyMap()
		wipe(KeyMap);
		wipe(ActiveActions);
		wipe(KeysToHold);
		wipe(HandledKeys);
		wipe(Lists);
		DebindPrivate.ClearUnreachableBindingCache();
		-- **What is taken moves under the reader's hands**, unlike what can be obtained
		-- (`Spells.lua` keeps that one per specialization). Every change that moves it raises a
		-- rebuild, so dropping it here is dropping it on each of them.
		DebindPrivate.Talents.Wipe();

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
				-- that shape is gone (`building-export-import.md` 12절). Which also means
				-- accepting is the moment a key starts working, where it used to leave the set
				-- parked; the prompt on [Accept all] is where that difference is paid for.
				-- **An action the reader turned off gets the same treatment as a quarantined one**,
				-- and for the same reason: drawn, greyed, reaching nothing. Unlike every filter
				-- below this line it also hands the key back, because "I am not using this" is what
				-- the reader said and a key we hold for nothing is a key the game cannot use.
				local binding, list, outcome;
				if (action.key and not action.arrivalID and not action.disabled) then
					list = DebindPrivate.GetBindingsForAction(action);
					binding = list[1];
					outcome = DebindPrivate.GetIssueOutcome(action);

					local key = action.key;
					-- **The key is held before anything below can leave the action out.** Every filter
					-- under this one is the rebuild settling an answer early, and an answer settled
					-- early must not hand the key back to the game: baked, the binding would lose every
					-- press and the key would do nothing (2026-09-15, owner). That includes an action
					-- with no binding at all, every press turned off in its Cast Options menu
					-- (`which-action-a-key-runs.md` §6): the key is still held for it.
					--
					-- **A specialization condition naming another class's specializations holds the
					-- key too**, though nothing behind it can ever fire on this character
					-- (2026-09-19, owner). It is the same rule: the filter under this line is an
					-- optimization, and an optimization must not change what a press does.
					--
					-- Two things still let the key go. An action that runs over a unit frame fires
					-- through the frame on a mouse button and holds nothing (`ActionUnitFrameIsOn`, which
					-- the bare left and right click always answer yes); and an issue whose outcome is
					-- RELEASE says this key cannot be taken at all, where the game menu key would take
					-- Escape with it.
					--
					-- **A key a binding context has claimed is not one of them.** It is baked like any
					-- other and handed over on the restricted side while the claim stands
					-- (`BindingContexts.lua`), so a claim that ends puts the key back without a rebuild.
					--
					-- **Only RELEASE takes the key out of our hands.** The frame case above still
					-- answers the press, which is the whole difference between the two tables, and
					-- `HandledKeys` is the one a screen asks (`IsKeyHandled`).
					if (outcome ~= Constants.ISSUE_OUTCOME_RELEASE) then
						HandledKeys[key] = true;
						if (not (DebindPrivate.ActionUnitFrameIsOn(action)
								and DebindPrivate.GetMouseButtonAndPrefix(key))) then
							KeysToHold[key] = true;
						end
					end
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
				-- actions behind it and hand every press a conditional that is false for the life
				-- of this build.
				--
				-- **The talent condition is the third, and it is the same rule again**: talents
				-- cannot change in combat and every change that moves them rebuilds everything
				-- (`adding-a-talent-condition.md` §4), so this build has one answer
				-- to it.
				if (binding and DebindPrivate.SpecConditionHolds(binding)
						and DebindPrivate.KnownConditionCanHold(binding)
						and DebindPrivate.TalentConditionHolds(binding)) then
					Lists[binding] = list;

					-- 활성 레이어만 도므로 전문화 순위는 언제나 동률이다. 다른 전문화의 순서를
					-- 묻는 것은 창 쪽이고, 그쪽은 `CollectActionsForKey`로 간다.
					Placements[binding] = DebindPrivate.MakeOrderRecord(
						action, layerRank, nil, Placements[binding]);

					local key = action.key;
					-- **The issue's outcome decides, never its grade** (`Constants.BINDING_ISSUE_OUTCOMES`).
					-- The gate read the grade, which made a retired type orange so that its block kept
					-- the key.
					if (outcome == nil or outcome == Constants.ISSUE_OUTCOME_KEEP) then
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
