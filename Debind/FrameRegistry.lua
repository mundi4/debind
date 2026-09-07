local _, DebindPrivate           = ...;
local Constants                    = DebindPrivate.Constants;
local BindingDriver                = DebindPrivate.BindingDriver;
local L                            = DebindPrivate.L;

DebindPrivate.ccframes           = {};
--- The header door's registrations by frame name, mirrored for `Clique.hccframes` (`DebindCliqueFake`):
--- Clique keeps the frames that arrived through `clickcast_register` in a second list keyed by
--- name, since a name is what the restricted side can hand out, and addons walking Clique's
--- registrations read both. Ours are the `hd` rows of `ccframes`; this is the same set in that shape.
DebindPrivate.hccframes          = {};
DebindPrivate.blizzardFrames     = {};
--- Registrations and deregistrations that arrived under lockdown, in the order they arrived.
---
--- **One queue and not two, because the order between them is the answer.** A frame taken back and
--- offered again during one fight, drained out of two queues, ended with the deregistration last
--- however it had arrived - so the frame came out unregistered when the last word was "register".
--- Entries are `{ op, button, type }` and `op` is `"register"` or `"unregister"`.
DebindPrivate.FrameQueue         = {};

--- The last word queued for a frame, keyed by the frame. **While one of these stands, the row is
--- not what the frame's owner last said** - a deregistration leaves the row in place until the
--- fight ends, so the two gates that read `ccframes` to decide whether there is anything to do have
--- to read this first. Cleared with the queue.
local _queued = setmetatable({}, { __mode = "k" });
DebindPrivate.QueuedFrameOp      = _queued;
DebindPrivate.RegisterClickQueue = {};

--- 클릭캐스팅이 쓰는 `<접두사>clickbutton<번호>` 이름들. `UpdateBindingsMap`이 리빌드마다
--- 채운다(그쪽이 같은 자리에서 `<접두사>type<번호>`를 굽는다).
---
--- **이것만 비보안 쪽에 있는 이유.** 값이 프레임이라서다. 보안 스니펫이 프레임 핸들로
--- 속성을 쓰면 그 핸들이 그대로 저장되고, 비보안 쪽은 진짜 프레임을 못 얻는다 -
--- `SECURE_ACTIONS.click`이 `delegate:HasAccessConstraints()`에서 nil 호출로 죽는다
--- (SecureTemplates.lua:564). 실제로 그렇게 죽었다.
---
--- 다행히 값이 **언제나 같은 프레임**이라 상태에 안 달렸다. 그래서 전투 밖에 프레임마다
--- 한 번 쓰면 되고, 승자가 바뀔 때 다시 쓸 일이 없다. 승자에 따라 갈리는 것은
--- `<접두사>type<번호>` 하나뿐이고 그건 문자열이라 보안 쪽이 쓴다.


local BLIZZARD_UNITFRAME_OPTIONS   = {
    player = { type = "player" },
    pet = { type = "pet" },
    target = { type = "target" },
    targettarget = { type = "targettarget" },
    focus = { type = "focus" },
    focustarget = { type = "focustarget" },
    boss = {
        type = "boss",
    },
    party = {
        type = "group",
    },
    raid = {
        type = "group",
    },
    arena = {
        type = "arena",
    },
};

local UNITFRAME_TYPES              = {
    player = Constants.FRAMETYPE_PLAYER,
    pet = Constants.FRAMETYPE_PET,
    group = Constants.FRAMETYPE_GROUP,
    target = Constants.FRAMETYPE_TARGET,
    targettarget = Constants.FRAMETYPE_TARGET, --Constants.FRAMETYPE_TARGETTARGET,
    focus = Constants.FRAMETYPE_TARGET,        --Constants.FRAMETYPE_FOCUS,
    focustarget = Constants.FRAMETYPE_TARGET,  --Constants.FRAMETYPE_FOCUSTARGET,
    boss = Constants.FRAMETYPE_BOSS,
    arena = Constants.FRAMETYPE_ARENA,
    unknown = Constants.FRAMETYPE_UNKNOWN,
};

--- What the frame says it is, for the frames nobody tells us about.
---
--- The Clique protocol another addon registers through has no field for the kind, so
--- `UNITFRAME_TYPES` above is fed by our own Blizzard registration and by nothing else. Every
--- frame any other unit frame addon hands over came in as `unknown` because of that, and the
--- frame was carrying the answer the whole time.
---
--- **Only the tokens that hold still are here.** A header hands its children units and takes them
--- back, so a child's token says which slot it is filling right now and not what the frame is.
--- Every one those slots can hold is a party or raid token, which answers group either way, so a
--- child read on the wrong pass still comes out a group frame. A token that could move a frame
--- from one category to another has no business in this table.
---
--- **So every `<owner>pet` spelling is out, `playerpet` with the rest.** A pet frame carries `pet`,
--- which is what Blizzard's own pet header gives the slot for your own pet (`GetPetUnit` in
--- `SecureGroupHeaders.lua`) and what `playerpet` never appears as anywhere in the game's code. A
--- frame that does carry `playerpet` got it from an addon counting its slots `player`, `party1`,
--- `party2` and their pets alongside them, which makes that frame a column in a group block and
--- not the pet frame at all.
local UNIT_FRAMETYPES              = {
    pet = Constants.FRAMETYPE_PET,
    target = Constants.FRAMETYPE_TARGET,
    targettarget = Constants.FRAMETYPE_TARGET,
    focus = Constants.FRAMETYPE_TARGET,
    focustarget = Constants.FRAMETYPE_TARGET,
};

for i = 1, MAX_PARTY_MEMBERS do
    UNIT_FRAMETYPES["party" .. i] = Constants.FRAMETYPE_GROUP;
end

for i = 1, MAX_RAID_MEMBERS do
    UNIT_FRAMETYPES["raid" .. i] = Constants.FRAMETYPE_GROUP;
end

for i = 1, MAX_BOSS_FRAMES do
    UNIT_FRAMETYPES["boss" .. i] = Constants.FRAMETYPE_BOSS;
end

for i = 1, MAX_ARENA_ENEMIES do
    UNIT_FRAMETYPES["arena" .. i] = Constants.FRAMETYPE_ARENA;
end

--- Names that answer group whatever the frame is holding at the time.
---
--- **This is one pack's naming, and it is here because that pack's frames carry nothing else.**
--- VuhDo hands its panel buttons over as `Vd<panel>H<button>`, with `Tg` and `Tot` appended for the
--- two extra columns, and the name says nothing about what the panel shows. The unit does not
--- settle it either: a slot holds `player` in a party panel, a pet token in a pet panel, and
--- `<unit>target` in the target column, so reading the unit called one panel three different
--- things. Every button in a VuhDo panel is a slot in a group display, which is the same answer
--- the header door gives every child that arrives through it.
---
--- **Anchored and shaped, not a word searched for.** A substring would be the misread that
--- `GROUP_NAME_WORDS` below is kept away from: a pack's own prefix sits in every name it makes.
--- Matching from the start with the digits spelled out is the pack saying which of its frames this
--- is, rather than us guessing from a word.
local GROUP_NAME_PATTERNS          = {
    "^vd%d+h%d+",
};

--- The words that name a slot in a group frame set. Asked of `player` and of nothing else.
local GROUP_NAME_WORDS             = { "party", "raid" };

--- Whether the frame is a slot in a `SecureGroupHeaderTemplate` header.
---
--- **Asked before the unit, because the unit on a header child answers only sometimes.** The
--- header writes the slot's unit and takes it away again (`SecureGroupHeaders.lua` clears every
--- slot it is not showing), so a child handed over while the header is showing nobody carries no
--- unit at all -- which is exactly when a unit frame addon registers it, from its own styling
--- pass. Reading the unit there gave `unknown` and nothing came back to ask again.
---
--- **The parent's script is the test.** Blizzard's own `OnEvent` is what makes a header a header,
--- and it is one value that no other frame in the client shares. An addon's header carries it
--- because the template it inherits does, so this recognises a pack's own group header as well as
--- the client's own.
---
--- **A pet header's children are group frames too**, which is what the header door
--- (`clickcast_register`) already calls every child that arrives through it. Every slot either
--- header can hold is a group unit or a group member's pet, so there is no slot here that another
--- category would fit better.
local function IsGroupHeaderChild(button)
    local parent = button.GetParent and button:GetParent();
    if (not parent or not parent.GetScript) then
        return false;
    end

    local onEvent = parent:GetScript("OnEvent");
    return onEvent ~= nil
        and (onEvent == SecureGroupHeader_OnEvent or onEvent == SecureGroupPetHeader_OnEvent);
end

--- **`player` is the one unit that does not settle it.** Every other token here is the frame:
--- something showing `target` is the target frame and cannot turn into a boss frame. `player` is
--- also what a party frame set gives its own slot, since such a set has five slots and there are
--- only four party units. Blizzard's compact container does exactly that
--- (`Blizzard_CompactRaidFrameContainer.lua` hands the self slot `"player"`), and a unit frame
--- addon drawing its own party block does the same, sometimes writing the token on the frame for
--- good. So that one token gets a second question, and the frame's name answers it: a self slot is
--- named for the set it is drawn in.
---
--- **The name is asked there and nowhere else**, because an addon's own prefix sits in every name
--- it makes. A pack named for one of these words hands that word to its player frame, its target
--- frame and all the rest, so reading the name first would have believed the prefix over the unit.
--- Under `player` a misread needs the pack to be named for a group frame as well, and what it
--- costs is the difference between two answers the unit could not tell apart anyway.
---
--- **`GetAttribute`, not `GetEffectiveAttribute`.** What we want is the unit the frame owns, and
--- following `useparent-unit` up to a header would answer with the slot the header is filling.
---
--- **The unit may not be there to read yet.** A frame library can hand the frame over from its
--- styling pass and write the unit attribute only after that pass returns, so the first call on
--- such a frame sees no unit at all. That is why an `unknown` answer is never treated as settled -
--- see `RegisterFrame`.
local function ReadFrameType(button)
    if (IsGroupHeaderChild(button)) then
        return Constants.FRAMETYPE_GROUP;
    end

    local name = button.GetName and button:GetName();
    name = type(name) == "string" and strlower(name) or nil;

    if (name) then
        for i = 1, #GROUP_NAME_PATTERNS do
            if (strfind(name, GROUP_NAME_PATTERNS[i])) then
                return Constants.FRAMETYPE_GROUP;
            end
        end
    end

    local unit = button:GetAttribute("unit");
    if (type(unit) ~= "string") then
        return;
    end

    unit = strlower(unit);
    if (unit ~= "player") then
        return UNIT_FRAMETYPES[unit];
    end

    if (name) then
        for i = 1, #GROUP_NAME_WORDS do
            if (strfind(name, GROUP_NAME_WORDS[i], 1, true)) then
                return Constants.FRAMETYPE_GROUP;
            end
        end
    end

    return Constants.FRAMETYPE_PLAYER;
end

--- **Under `pcall` for the same reason `SetPropagateOne` is.** `GetName` is the call this file was
--- already burnt by - the compact frame hook carries an `ignoreCUFNameRequirement` guard because
--- it raised "calling 'GetName' on bad self" - and on 12.1 `IsForbidden` answering false at the
--- gate above no longer means a frame can be touched. A frame that cannot answer forfeits the
--- derivation and registers as `unknown`, which is where it stood before any of this.
local function DeriveFrameType(button)
    local ok, frameType = pcall(ReadFrameType, button);
    if (ok) then
        return frameType;
    end
end


--- 이미 `OnEnter`/`OnLeave`를 감싼 프레임. 아래 `_wrapped`와 같은 물건이고, 같은 이유로
--- 비운 적이 없다.
---
--- **등록이 풀려도 안 뗀다.** `SecureHandlerUnwrapScript`이 떼는 것은 맨 위 래퍼인데
--- (`SecureHandlers.lua`의 `RemoveWrapper`가 `frame:GetScript`으로 지금 걸린 것을 잡는다),
--- 그것이 우리 것이라는 보장이 없다. 남이 나중에 같은 스크립트를 감쌌으면 우리가 부르는 그
--- 호출은 **남의 것을 떼고 우리 것은 남긴다.** 그러면 `ccframes`에 행이 없는 프레임에서 우리
--- 본문이 계속 돌고, 남의 래퍼는 영영 사라진다. 우리가 감싼 `OnClick`이 진작 이렇게 하고
--- 있었고 `OnEnter`/`OnLeave`만 안 그랬다.
---
--- **그래서 해제는 본문이 한다.** `ccframes[self]`에 행이 없으면 `setup_onenter`는 물러나고,
--- 물러나면서 호버 슬롯을 비운다. 추적 안 하는 프레임 안에 커서가 있다는 것 자체가 우리가
--- 마지막으로 적어둔 프레임 안에는 없다는 뜻이라, 그 빈 자리가 곧 맞는 답이다.
local _hoverWrapped = setmetatable({}, { __mode = "k" });

--- 이미 `OnClick`을 감싼 프레임. **`ccframes` 엔트리로는 못 센다** - 우리는 래퍼를 떼지 않는데
--- 해제 때 그 엔트리는 사라지므로, 다시 등록되면 두 번 감싸게 된다.
local _wrapped = setmetatable({}, { __mode = "k" });

---------------------------------------------------------------------------
-- Standing on top of another addon's wrappers
--
-- `devdocs/legacy/standing-on-top-of-foreign-wrappers.md`.
---------------------------------------------------------------------------

--- The three scripts we wrap, and the only ones the hooks below answer for.
local REASSEMBLED_SCRIPTS = { OnEnter = true, OnLeave = true, OnClick = true };

--- How many times one frame may be reassembled in a session before we conclude somebody is
--- fighting us for the top rather than merely wiring their frame up.
---
--- **Ordinary use spends one per script.** A pack wraps as it registers, and again when its own
--- click casting is switched on or off; each of those is one pass here. What this catches is the
--- other shape -- an addon that re-wraps because we wrapped, which comes back every time.
local REASSEMBLE_LIMIT = 8;

--- The frame a reassembly is in the middle of. **Read before anything else in the hooks**, and set
--- and cleared synchronously: two engines that both re-wrap on being wrapped over pile up on the
--- call stack rather than over time, so deferring the judgement to a timer leaves the stack to grow
--- in between. Measured without a guard: 198 frames deep and a C stack overflow.
local _reassembling = setmetatable({}, { __mode = "k" });
local _reassembleCount = setmetatable({}, { __mode = "k" });
local _warnedContested = false;

--- Hands the restricted side everything this pass took off the frame, replacing that frame's list
--- for that script whole.
---
--- **The entries are read out of numbered slots on the driver** rather than passed as arguments: a
--- frame handle arrives nil through `RunAttribute`'s varargs (measured 2026-08-28), and a header is
--- a frame. `SecureHandlerSetFrameRef` is the one door for one.
---
--- **What this pass took goes in front of what earlier passes took**, because that is where it was
--- on the frame: they wrapped on top of us, and we were on top of everything we had already taken.
--- Replacing the list instead would drop an addon's first wrapper the moment it added a second.
---
--- `over_replace` is the other case, and it is not an optimisation. A leave list holds one entry
--- because the client runs one leave body, so a newer one buries whatever was there. And where our
--- own wrapper was taken off by somebody else, what is left on the frame is the whole truth again.
---
--- Emptying is the case that has to leave nothing behind, because the three hot paths read
--- `Overs[button]` first and a row that exists costs them a second lookup for nothing.
local STORE_OVERS_SNIPPET = [=[
	local button = self:GetFrameRef("clickcast_button")
	local script = self:GetAttribute("over_script")
	local n = self:GetAttribute("over_count")
	local byScript = Overs[button]
	local kept = byScript and byScript[script]
	if (self:GetAttribute("over_replace")) then
		kept = nil
	end

	if (n == 0 and not kept) then
		if (byScript) then
			byScript[script] = nil
			if (next(byScript) == nil) then
				Overs[button] = nil
			end
		end
		return
	end

	if (not byScript) then
		byScript = newtable()
		Overs[button] = byScript
	end

	local list = newtable()
	byScript[script] = list
	for i = 1, n do
		local over = newtable()
		over.handle = self:GetFrameRef("over_"..i)
		over.pre = self:GetAttribute("over_pre_"..i)
		over.post = self:GetAttribute("over_post_"..i)
		list[i] = over
	end
	if (kept) then
		for i = 1, #kept do
			list[n + i] = kept[i]
		end
	end
]=];

--- What a wrapped post body is given. The client compiles one as `self,message` for the motion
--- scripts and `self,message,button,down` for a click; running it through `RunFor` gives it
--- `self,...` instead, so the names it expects are declared for it here. One line covers all three
--- -- a motion body never mentions the two it did not ask for.
local OVER_POST_PROLOGUE = "local message, button, down = ...\n";

local Reassemble;

--- Our own pre and post for one script.
local function OurBodies(script)
	if (script == "OnClick") then
		return DebindPrivate.UnitFrameClickPre, DebindPrivate.UnitFrameClickPost;
	end
	if (script == "OnEnter") then
		return BindingDriver:GetAttribute("setup_onenter_wrap"),
			BindingDriver:GetAttribute("setup_onenter_post");
	end
	return BindingDriver:GetAttribute("setup_onleave_wrap"),
		BindingDriver:GetAttribute("setup_onleave_post");
end

--- Whether this script on this frame is one we put a wrapper on. A frame that arrived through the
--- header door has a row and no wrapper of ours on the motion scripts -- it carries
--- `clickcast_onenter` instead -- so the row alone is not the question.
local function WrappedByUs(button, script)
	if (script == "OnClick") then
		return _wrapped[button] and true or false;
	end
	return _hoverWrapped[button] and true or false;
end

--- **Steps off a frame rather than trading the top with another engine forever.**
---
--- Taking the row away is what makes it stick: every gate below reads it, so nothing reassembles
--- this frame again. The wrapper stays where it is, as every wrapper of ours does, and the body it
--- runs stands down on its own once the restricted row is gone. What we took off the frame is
--- **not** given back and not thrown away -- it is still in `Overs` and still replayed, because
--- stopping it is the one thing that would break the addon we stood down for.
local function StandDown(button)
	local row = DebindPrivate.ccframes[button];
	DebindPrivate.ccframes[button] = nil;
	if (row and row.hd) then
		local name = button.GetName and button:GetName();
		if (name) then
			DebindPrivate.hccframes[name] = nil;
		end
	end

	if (row and not InCombatLockdown()) then
		SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "clickcast_button", button);
		SecureHandlerExecute(DebindPrivate.BindingDriver, [=[
			local button = self:GetFrameRef("clickcast_button")
			self:RunFor(button, self:GetAttribute("DeinitFrame"))
		]=]);
	end

	if (not _warnedContested) then
		_warnedContested = true;
		DebindPrivate.DisplayMessage(L["WARNING_MESSAGE_UNIT_FRAME_CONTESTED"]);
	end
end

--- Takes every wrapper another addon has on this script, hands the bodies to the restricted side,
--- and puts ours back on top.
---
--- **The walk stops at our own header, and our own has already come off by then** -- the call that
--- reported it is the call that removed it. Reaching nil instead means nothing of ours was on this
--- script yet, which is the first registration.
---
--- **What comes back is only what was above us.** Anything below stays in the chain and goes on
--- running there, which is what it did before we arrived: the enter and click bodies down there
--- still run, and the leave ones still do not, because the client runs only the outermost leave
--- body and that was never them.
---
--- **`leave` keeps one and only one.** Blizzard's `Wrapped_OnLeave` clears `_wrapentered` before it
--- descends, so of everything that was above us exactly the first entry ever ran. Replaying the
--- rest would be inventing behaviour that never existed on this frame.
function Reassemble(button, script, fromUnwrap)
	local pre, post = OurBodies(script);
	if (type(pre) ~= "string") then
		return;
	end

	_reassembling[button] = true;
	-- **Every unwrap below is ours**, and `DebindCliqueFake` listens on the same global to hear the
	-- holder let a frame go. It cannot tell from the arguments -- an unwrap carries no header -- so
	-- the flag is what says so, the same way `RewrapUnitFrames` says it. Restored rather than
	-- cleared, because that function is one of the callers that reaches here with it already up.
	local wasUnwrappingOwn = DebindPrivate.unwrappingOwnScripts;
	DebindPrivate.unwrappingOwnScripts = true;

	local taken = 0;
	while (true) do
		local header, tookPre, tookPost = SecureHandlerUnwrapScript(button, script);
		if (not header or header == BindingDriver) then
			break;
		end
		if (script ~= "OnLeave" or taken == 0) then
			taken = taken + 1;
			SecureHandlerSetFrameRef(BindingDriver, "over_" .. taken, header);
			BindingDriver:SetAttribute("over_pre_" .. taken, tookPre);
			BindingDriver:SetAttribute("over_post_" .. taken,
				tookPost and (OVER_POST_PROLOGUE .. tookPost) or nil);
		end
	end

	DebindPrivate.unwrappingOwnScripts = wasUnwrappingOwn;

	BindingDriver:SetAttribute("over_script", script);
	BindingDriver:SetAttribute("over_count", taken);
	BindingDriver:SetAttribute("over_replace", fromUnwrap or script == "OnLeave");
	SecureHandlerSetFrameRef(BindingDriver, "clickcast_button", button);
	SecureHandlerExecute(BindingDriver, STORE_OVERS_SNIPPET);

	SecureHandlerWrapScript(button, script, BindingDriver, pre, post);

	_reassembling[button] = nil;
end

--- Whether this pass is one more than the frame should have needed, and steps off if it is.
local function ContestedNow(button)
	if (_reassembling[button]) then
		StandDown(button);
		return true;
	end

	local count = (_reassembleCount[button] or 0) + 1;
	_reassembleCount[button] = count;
	if (count > REASSEMBLE_LIMIT) then
		StandDown(button);
		return true;
	end

	return false;
end

--- Somebody wrapped one of the three scripts on a frame we are on, so we are no longer the
--- outermost. Take the top back and carry what they left.
local function OnForeignWrap(frame, script, header)
	if (header == BindingDriver or not REASSEMBLED_SCRIPTS[script]) then
		return;
	end
	if (not DebindPrivate.ccframes[frame] or not WrappedByUs(frame, script)) then
		return;
	end
	if (InCombatLockdown()) then
		return;
	end
	if (ContestedNow(frame)) then
		return;
	end
	Reassemble(frame, script, false);
end

--- Somebody unwrapped one, and the top was ours, so what came off was ours.
---
--- **Which addon asked cannot be known** -- `SecureHandlerUnwrapScript(frame, script)` carries no
--- header. So this reassembles from whatever is left, and what is left is whatever they still have
--- on the frame. Where they had only the one wrapper, the list comes out empty and their bodies
--- stop running, which is what they asked for.
local function OnForeignUnwrap(frame, script)
	if (DebindPrivate.unwrappingOwnScripts or _reassembling[frame]) then
		return;
	end
	if (not REASSEMBLED_SCRIPTS[script]) then
		return;
	end
	if (not DebindPrivate.ccframes[frame] or not WrappedByUs(frame, script)) then
		return;
	end
	if (InCombatLockdown()) then
		return;
	end
	if (ContestedNow(frame)) then
		return;
	end
	Reassemble(frame, script, true);
end

if (not DebindPrivate.CliqueDetected) then
	hooksecurefunc("SecureHandlerWrapScript", OnForeignWrap);
	hooksecurefunc("SecureHandlerUnwrapScript", OnForeignUnwrap);
end

function DebindPrivate.RegisterFrame(button, type)
    if (DebindPrivate.CliqueDetected) then
        return;
    end

    if (DebindPrivate.ccframes[button] == false) then
        return;
    end

    --- **`unknown` is the absence of an answer, so it does not close the question.** An addon
    --- registers the same frame more than once, and the second call is often the one that can be
    --- answered: a frame library registers from its styling pass and only writes the unit
    --- attribute after it, and the addon on top of that library registers again once the frame is
    --- finished. Standing down on `type` matching alone spent the second call on a frame we had
    --- already given up on.
    ---
    --- **And what is compared is the answer, not the argument the caller happened to pass.** The
    --- same frame arrives under different arguments from different doors - `"group"` off our own
    --- Blizzard registration, `true` through the Clique shape - and comparing those re-registered
    --- it on every pass that reached it.
    --- **`hd` is outside what a queued word can override.** A header owns those rows and takes them
    --- back itself; a deregistration queued before the header wrote one would otherwise let this
    --- rebuild the row and the drain tear it down after.
    local seen = DebindPrivate.ccframes[button];
    local told = UNITFRAME_TYPES[type];
    if (seen and (seen.hd or (_queued[button] ~= "unregister"
            and seen.frameType ~= Constants.FRAMETYPE_UNKNOWN
            and (told == nil or told == seen.frameType)))) then
        return;
    end

    if (not button.IsProtected or not button:IsProtected()) then
        DebindPrivate.ccframes[button] = false;
        return;
    end

    if (button.IsForbidden and button:IsForbidden()) then
        DebindPrivate.ccframes[button] = false;
        return;
    end

    if (button.IsAnchoringRestricted and button:IsAnchoringRestricted()) then
        DebindPrivate.ccframes[button] = false;
        return;
    end

    if (not button.RegisterForClicks) then
        DebindPrivate.ccframes[button] = false;
        return;
    end

    if (InCombatLockdown()) then
        tinsert(DebindPrivate.FrameQueue, { "register", button, type });
        _queued[button] = "register";
        if (#DebindPrivate.FrameQueue == 1) then
            DebindPrivate.DisplayMessage(L["UNABLE_TO_REGISTER_UNIT_FRAME_IN_COMBAT"]);
        end
        return;
    end

    local frameType = told or DeriveFrameType(button) or UNITFRAME_TYPES.unknown;
    button:SetAttribute("debind_frametype", frameType);

    SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "clickcast_button", button);
    SecureHandlerExecute(DebindPrivate.BindingDriver, [=[
		local button = self:GetFrameRef("clickcast_button")
		self:RunFor(button, self:GetAttribute("InitFrame"))
		ccframes[button].frameType = button:GetAttribute("debind_frametype")
	]=]);

    if (not DebindPrivate.CliqueDetected and not _hoverWrapped[button]) then
        _hoverWrapped[button] = true;
        Reassemble(button, "OnEnter");
        Reassemble(button, "OnLeave");
    end

    DebindPrivate.ccframes[button] = { type = type, frameType = frameType };
    DebindPrivate.UpdateRegisteredClicks(button);
end

function DebindPrivate.UnregisterFrame(button)
    if (DebindPrivate.CliqueDetected) then
        return;
    end

    local row = DebindPrivate.ccframes[button];
    if (InCombatLockdown()) then
        -- A frame registered earlier in this same fight has no row yet, and taking it back is
        -- still what its owner just asked for. An `hd` row is the header's and is never ours to
        -- queue away, whatever was queued before it appeared.
        if (row and row.hd) then
            return;
        end
        if (row or _queued[button] == "register") then
            tinsert(DebindPrivate.FrameQueue, { "unregister", button });
            _queued[button] = "unregister";
        end
        return;
    end

    if (row and not row.hd) then
        SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "clickcast_button", button);
        SecureHandlerExecute(DebindPrivate.BindingDriver, [=[
			local button = self:GetFrameRef("clickcast_button")
			self:RunFor(button, self:GetAttribute("DeinitFrame"))
		]=]);
        DebindPrivate.ccframes[button] = nil;
    end
end

--- A forbidden object errors on **any** method call from addon-tainted code, so the whole branch
--- is skipped rather than just the call - descending into its children would raise the same error
--- one level down. `IsForbidden` is the one method that stays answerable there.
---
--- The check at the registration gate (`IsForbidden` above) is not enough: it sees the button we
--- were handed, and what turns up forbidden here is a **child** of a Blizzard frame that passed it.
---
--- **`IsForbidden` answering false no longer means the call is safe.** On 12.1, private-aura
--- frames attached to unit frames answer false and still raise the forbidden-object error from
--- `SetPropagateMouseMotion` (access constraints without the explicit mark - observed in an
--- arena, where such a frame sat under every Grid2 button). And a 12.1 `GetChildren` can hand
--- back secret values, which blow up on the `not frame` test itself. There is no pre-check that
--- covers those, so each frame is handled under `pcall`: everything that touches the frame is
--- inside, and a frame that cannot be touched forfeits its subtree - same policy as the
--- forbidden skip, which stays as the cheap first gate.
local function SetPropagateOne(frame)
    if (not frame or (frame.IsForbidden and frame:IsForbidden())) then
        return;
    end
    if (frame.SetPropagateMouseMotion) then
        frame:SetPropagateMouseMotion(true);
    end
    if (frame.GetChildren) then
        return frame:GetChildren();
    end
end

local SetPropagate;

--- Counted across the whole recursion, reported per registered frame at the call site.
--- DEBUG-only surfacing: a release user can do nothing with it, and the cost of a refused
--- frame is only that hover may release over that subtree - which was already true of every
--- frame the walk could not see.
local _walkRefused = 0;

--- Only a frame whose own handling succeeded gets its children walked; the varargs pass
--- `GetChildren`'s returns through without a table in between.
local function Descend(ok, ...)
    if (ok) then
        SetPropagate(...);
    else
        _walkRefused = _walkRefused + 1;
    end
end

function SetPropagate(...)
    local n = select("#", ...);
    for i = 1, n do
        Descend(pcall(SetPropagateOne, (select(i, ...))));
    end
end

--- 우리 자리를 프레임에 얹는다.
---
--- **남의 자리를 안 건드리는 것이 요점이다.** 접미사가 `-debind1`이라 블리자드의 `type1`/`type2`와
--- 겹치지 않는다. 값이 상태에 안 달려서(언제나 같은 프레임) 등록 때 한 번 쓰면 끝이고, 승자가
--- 바뀌어도 다시 쓸 일이 없다 - 어느 액션인가는 래퍼가 클릭 순간에 정한다.
---
--- 그 래퍼가 `nil`을 반환하면 버튼 이름이 그대로 남아 프레임의 원래 동작으로 떨어진다. 우리가
--- 아무 자리도 안 뺏었으므로 되돌릴 것이 없다.
local function ApplyDebindRouting(button)
    button:SetAttribute("*type-debind1", "click");
    button:SetAttribute("*clickbutton-debind1", DebindPrivate.DefaultClickFrame);

    if (not _wrapped[button] and DebindPrivate.UnitFrameClickPre) then
        _wrapped[button] = true;
        Reassemble(button, "OnClick");
    end
end

--- 본문이 다시 구워졌을 때(테스트 키트의 프로브 스위치) 감싼 것을 새 본문으로 갈아준다.
---
--- 여기서는 떼도 된다. **재베이크는 테스트 세션에서만 도는 길이고** 전투 밖이다. 실제 플레이에
--- 이 함수가 도달하는 경로는 없다.
function DebindPrivate.RewrapUnitFrames()
    -- **우리 호출을 남의 것으로 듣지 않게 하는 표시.** `DebindCliqueFake`가 wrap과 unwrap을
    -- 다 후킹해서 홀더가 프레임을 잡고 놓는 순간을 듣는데, **unwrap 쪽은 인자에 헤더가
    -- 없다**(`SecureHandlers.lua`의 `SecureHandlerUnwrapScript(frame, script)`). wrap 쪽에서
    -- 우리 것을 걸러내는 헤더 비교가 거기서는 언제나 nil을 보므로 아무 일도 안 한다.
    --
    -- 그러면 아래 루프가 우리 프레임마다 "홀더가 놓았다"를 한 번씩 내보내고, 다음 틱에
    -- 전부 다시 물어보게 된다. 인자로는 못 가르니 부르는 쪽이 말해준다.
    -- 아래 `_reassertingClicks`가 같은 이유로 있는 같은 수법이다.
    DebindPrivate.unwrappingOwnScripts = true;

    for button in pairs(_wrapped) do
        _wrapped[button] = nil;
        SecureHandlerUnwrapScript(button, "OnClick");
    end

    DebindPrivate.unwrappingOwnScripts = nil;

    for button, entry in pairs(DebindPrivate.ccframes) do
        if (entry) then
            ApplyDebindRouting(button);
        end
    end
end

--- Frames whose click input we are listening to, and the guard that keeps our own calls from
--- being heard as somebody else's. Never emptied, for the reason `_hoverWrapped` is not: a hook
--- is not removable, so forgetting one only means installing a second.
local _clickHooked                 = {};
local _reassertingClicks           = false;

--- **Both edges, because this call has no owner.** `RegisterForClicks` is the frame's state rather
--- than a subscription, so the last addon to call it decides for every wrapper on that frame.
--- Asking for the release alone left us with nothing at all on a frame somebody else had since
--- moved to the press, and the failure is silent: the key stops working and no error is raised
--- anywhere.
---
--- **It is not us overruling the frame's own choice of edge.** A frame library leaves this to
--- whoever takes the frame for click casting - oUF never calls it at all, and a UI pack built on
--- oUF registers the left and right buttons for its own menu and says in as many words that the
--- click-cast engine sets its own. Widening it is also what makes a binding on the middle or thumb
--- buttons arrive: a frame registered for left and right delivers nothing else.
---
--- **It does not make the frame's own action fire twice.** Delivery and action are separate:
--- `SecureActionButton_OnClick` computes
--- `clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)`, so the frame acts on
--- exactly one of the two edges however many are delivered, and `useOnKeyDown` falls back to
--- `ActionButtonUseKeyDown`. Registering an edge only decides what arrives.
---
--- Which of the two we answer on is the reader's, and the click wrapper's to apply
--- (`SecureBindings.lua`).
---
--- **The wheel is set here with them**, because the two travel together: an addon that narrows
--- the click registration on a frame turns the wheel off in the next line, so putting only the
--- edges back leaves a wheel binding dead.
local function ReassertClickInput(button)
    _reassertingClicks = true;
    button:RegisterForClicks("AnyUp", "AnyDown");
    button:EnableMouseWheel(true);
    _reassertingClicks = false;
end

--- **Somebody else has narrowed the frame, so put it back.**
---
--- A click-casting addon carries an edge of its own and writes it onto every frame it takes, ours
--- among them, and it rewrites it on every re-registration rather than only when its setting moves.
--- Turning its own click casting off is the same thing again, with the wheel going off beside the
--- edges. Left alone, a frame stops delivering what the reader bound and their bindings go quietly
--- dead there. Waiting for the next loading screen or the end of the fight does not cover it.
---
--- **Both methods reach here, and each puts both back.** They are called one after the other, so
--- answering only for the one that was called would be undone by the next line.
---
--- **`hooksecurefunc`, which is what keeps this clean.** The wrapper it installs calls the original
--- and then `securecall`s this, so no execution that reaches the frame afterwards carries our
--- taint. What it does not lift is that `RegisterForClicks` is protected, so a call of our own is
--- refused in combat and goes to the queue that already exists for it. And `securecall` swallows
--- whatever is raised in here without a word, which is why there is so little of it.
local function OnFrameClickInputChanged(button)
    if (_reassertingClicks or not DebindPrivate.ccframes[button]) then
        return;
    end

    if (InCombatLockdown()) then
        tinsert(DebindPrivate.RegisterClickQueue, button);
        return;
    end

    ReassertClickInput(button);
end

function DebindPrivate.UpdateRegisteredClicks(button)
    if (DebindPrivate.CliqueDetected) then
        return;
    end

    if (InCombatLockdown()) then
        tinsert(DebindPrivate.RegisterClickQueue, button)
        return
    end

    ApplyDebindRouting(button);

    if (not _clickHooked[button]) then
        _clickHooked[button] = true;
        hooksecurefunc(button, "RegisterForClicks", OnFrameClickInputChanged);
        hooksecurefunc(button, "EnableMouseWheel", OnFrameClickInputChanged);
    end

    ReassertClickInput(button);

    -- 프레임 내에 마우스에 반응하는 자식 프레임이 있는 경우 그 자식 프레임으로 마우스를 올렸을 때
    -- 부모 프레임에서 onleave 스크립트가 호출되지 않게 함.
    _walkRefused = 0;
    SetPropagate(button:GetChildren());
    if (Constants.DEBUG and _walkRefused > 0) then
        print(format("[Debind] SetPropagate: %d refused frame(s) under %s",
            _walkRefused, button:GetName() or tostring(button)));
    end
end

--- **Turning a box off does not take the frame back.** Deregistering is the frame owner's to ask
--- for, and Blizzard never asks; a box that is off is a box we do not register from next login. The
--- boxes say so themselves (`REQUIRES_RELOAD` in `DropDownMenus.lua`).
local function registerBlizzardFrame(frame, category)
    if (DebindPrivate.Options.blizzframes[category] ~= false) then
        local options = BLIZZARD_UNITFRAME_OPTIONS[category];
        DebindPrivate.RegisterFrame(frame, options and options.type);
    end
end

function DebindPrivate.UpdateBlizzardFrames(firstTime)
    if (DebindPrivate.CliqueDetected) then
        return;
    end

    if (firstTime) then
        local function addFrame(frame, frameType)
            if (frame) then
                DebindPrivate.blizzardFrames[frame] = frameType;
            end
        end

        addFrame(PlayerFrame, "player");
        addFrame(PetFrame, "pet");
        addFrame(TargetFrame, "target");
        addFrame(TargetFrameToT, "target");
        addFrame(FocusFrame, "target");
        addFrame(FocusFrameToT, "target");

        for i = 1, MAX_PARTY_MEMBERS do
            addFrame(PartyFrame["MemberFrame" .. i], "party");
        end

        for i = 1, MAX_BOSS_FRAMES do
            addFrame(_G["Boss" .. i .. "TargetFrame"], "boss");
        end
    end

    for frame, category in pairs(DebindPrivate.blizzardFrames) do
        if (category) then
            registerBlizzardFrame(frame, category);
        end
    end
end

if (not DebindPrivate.CliqueDetected) then
    hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
        -- **The flag is Blizzard's own exemption from the name requirement**, and the frames that
        -- carry it are the ones we must not call `GetName` on. `CompactUnitFrame.lua:26` reads
        -- `if not self.ignoreCUFNameRequirement and not self:GetName()`, and the templates that
        -- set it are the nameplate unit frame, the raid-frame settings preview, and the compact
        -- frame container. The nameplate is the one that showed up here, as
        -- "calling 'GetName' on bad self".
        --
        -- None of the three is a frame click-casting has any business on, so leaving the branch
        -- is the whole of what is needed. Testing for a nameplate by name would be the wrong
        -- shape twice over: the name is what cannot be read, and Blizzard already keeps the list.
        if (frame.ignoreCUFNameRequirement) then
            return;
        end

        local category = DebindPrivate.blizzardFrames[frame];
        if (category == nil) then
            local name = frame:GetName();
            if (name) then
                local m1 = name:match("^Compact([A-Za-z]+)Frame[A-Za-z]*%d+$");
                if (m1 == "Party" or m1 == "Raid" or m1 == "Arena") then
                    category = strlower(m1);
                elseif (name:match("^CompactRaidGroup%d+Member%d+$")) then
                    category = "raid";
                end
            end

            DebindPrivate.blizzardFrames[frame] = category or false;

            if (category) then
                if (DebindPrivate.Options) then
                    registerBlizzardFrame(frame, category);
                end
            end
        end
    end);
end
