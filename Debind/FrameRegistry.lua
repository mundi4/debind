local _, DebindPrivate           = ...;
local Constants                    = DebindPrivate.Constants;
local BindingDriver                = DebindPrivate.BindingDriver;
local L                            = DebindPrivate.L;

DebindPrivate.ccframes           = {};
DebindPrivate.blizzardFrames     = {};
DebindPrivate.RegisterQueue      = {};
DebindPrivate.UnregisterQueue    = {};
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
--- Those frames arrive from the header instead, which calls them all group frames, and that path
--- is the one that wins. Not because it runs later - `CollectOUFFrames` reaches the same children
--- on every loading screen, and running order alone had the two trading the frame back and forth.
--- It wins because it names a category and this reading cannot, which is what `RegisterFrame`
--- compares before it lets a second registration through.
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

--- The words that name a slot in a group frame set. Asked of `player` and of nothing else.
local GROUP_NAME_WORDS             = { "party", "raid" };

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
    local unit = button:GetAttribute("unit");
    if (type(unit) ~= "string") then
        return;
    end

    unit = strlower(unit);
    if (unit ~= "player") then
        return UNIT_FRAMETYPES[unit];
    end

    local name = button.GetName and button:GetName();
    if (type(name) == "string") then
        name = strlower(name);
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

--- The frames a group header has told us are its children.
---
--- **Being a header's child is what the frame is, so it outranks every other answer.** A header
--- hands a child whichever unit it is filling and takes it back, so reading that child gives the
--- slot it holds this second: `player` in the self slot of a party block, and nothing at all in a
--- spare the header has emptied. Neither is what the frame is.
---
--- **The other doors reach these same frames and cannot say so.** oUF writes every object it builds
--- into `ClickCastFrames`, header children included, and `CollectOUFFrames` fetches the ones that
--- write never reached - both through the Clique shape, which has no field for the kind. So the
--- header's answer has to survive them rather than be the most recent one.
---
--- **Never emptied, and weak so a frame can still go.** Registration is taken away and given back
--- while the frame stays what it is: an addon reclaiming a frame writes `nil` into
--- `ClickCastFrames` and adds it again later, and between those two the row this would otherwise
--- live on is gone.
local _headerChildren = setmetatable({}, { __mode = "k" });


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
    --- same frame arrives under different arguments from different doors - `"group"` off its
    --- header, `true` through the Clique shape - and comparing those had a header's child
    --- re-registered on every pass that reached it, with the frame read afresh each time
    --- (`_headerChildren` says why that reading is wrong).
    local seen = DebindPrivate.ccframes[button];
    local told = _headerChildren[button] and Constants.FRAMETYPE_GROUP or UNITFRAME_TYPES[type];
    if (seen and (seen.hd or (seen.frameType ~= Constants.FRAMETYPE_UNKNOWN
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
        tinsert(DebindPrivate.RegisterQueue, { button, type });
        if (#DebindPrivate.RegisterQueue == 1) then
            DebindPrivate.DisplayMessage(L["UNABLE_TO_REGISTER_UNIT_FRAME_IN_COMBAT"]);
        end
        return;
    end

    if (DebindPrivate.ccframes[button]) then
        DebindPrivate.UnregisterFrame(button);
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
        SecureHandlerWrapScript(button, "OnEnter", BindingDriver, BindingDriver:GetAttribute("setup_onenter"));
        SecureHandlerWrapScript(button, "OnLeave", BindingDriver, BindingDriver:GetAttribute("setup_onleave"));
    end

    DebindPrivate.ccframes[button] = { type = type, frameType = frameType };
    DebindPrivate.UpdateRegisteredClicks(button);
end

function DebindPrivate.UnregisterFrame(button)
    if (DebindPrivate.CliqueDetected) then
        return;
    end

    if (DebindPrivate.ccframes[button] and not DebindPrivate.ccframes[button].hd) then
        if (InCombatLockdown()) then
            tinsert(DebindPrivate.UnregisterQueue, button)
            return
        end

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

--- 이미 `OnClick`을 감싼 프레임. **`ccframes` 엔트리로는 못 센다** - 우리는 래퍼를 떼지 않는데
--- 해제 때 그 엔트리는 사라지므로, 다시 등록되면 두 번 감싸게 된다.
---
--- 떼지 않는 이유는 `SecureHandlerUnwrapScript`이 **맨 위 것**을 뗀다는 데 있다. 우리가 감싼 뒤
--- 남이 또 감쌌으면 우리가 부르는 그 호출이 **남의 것을 떼고 우리 것은 남긴다.**
--- (`click-time-phase3.md` §4-3)
local _wrapped = setmetatable({}, { __mode = "k" });

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
        SecureHandlerWrapScript(button, "OnClick", BindingDriver, DebindPrivate.UnitFrameClickPre);
    end
end

--- 본문이 다시 구워졌을 때(테스트 키트의 프로브 스위치) 감싼 것을 새 본문으로 갈아준다.
---
--- 여기서는 떼도 된다. **재베이크는 테스트 세션에서만 도는 길이고** 전투 밖이다. 실제 플레이에
--- 이 함수가 도달하는 경로는 없다.
function DebindPrivate.RewrapUnitFrames()
    for button in pairs(_wrapped) do
        _wrapped[button] = nil;
        SecureHandlerUnwrapScript(button, "OnClick");
    end

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

--- **The frames a frame library made that never reached us, asked of the library itself.**
--- oUF hands every frame it builds to `ClickCastFrames` on its way out, so these frames were always
--- addressed to us. What loses them is who holds that name at the time: a unit frame addon running
--- click casting of its own can put its own table over the global, and from that moment every
--- registration goes there instead, its own frames and every other addon's alike. Reclaiming the
--- name afterwards gets the table back and not the frames already written into the other one, and
--- there is nothing to read them back out of - a proxy that keeps its store in an upvalue answers
--- `pairs` with nothing, and an addon has no `debug.getupvalue`.
---
--- **`X-oUF` is oUF's own contract and not an addon name.** An addon shipping the library declares
--- the global it wants the library under, and the library reads that field and installs itself
--- there (`local global = C_AddOns.GetAddOnMetadata(parent, "X-oUF")`, then `_G[global] = oUF`).
--- Asking every loaded addon the same question is asking oUF where it is, whoever is carrying it,
--- so no UI pack's name is written down here.
---
--- **`objects` is all of them, whatever its own comment says.** oUF documents the field as the
--- frames `Spawn` made, and `initObject` appends to it before the branch that separates a spawned
--- frame from a header's child, so a header's children are in there too. Which is what we want:
--- the header hands its children over itself only if its addon speaks a protocol, and this reaches
--- them either way. `headers` is left alone for that reason - it holds nothing `objects` does not.
--- The libraries to ask, keyed by the global each publishes itself under, valued by how far into
--- its list we have got. `{ ["oUF_Foo"] = 12 }`.
---
--- **Built once, because the answer cannot change.** `X-oUF` is read out of the `.toc`, which the
--- client parses for every addon at startup whether it loads it or not - the addon list draws icons
--- and categories for disabled addons off the same call. So the walk over `GetNumAddOns()` happens
--- on the first pass and never again, and what is left after it is one or two entries.
---
--- Keyed by the name and not by the library, because an addon that has not loaded yet has no
--- global at all. Its entry sits here reading nil until it does.
---
--- **The number is a mark and not a "have we run yet" flag.** `objects` is appended to for as long as
--- the session lasts - a header gets more children as the roster grows, and a frame spawned later
--- lands on the end - so a pass that ran once would only ever see what existed at that moment.
--- Starting from the mark means every pass takes the new tail and leaves the frames already
--- offered alone, which is what makes running this on every `PLAYER_ENTERING_WORLD` cost nothing.
--- One mark each, because two addons carrying their own copy of oUF are two separate lists.
local _oufLibraries;

function DebindPrivate.CollectOUFFrames()
    if (DebindPrivate.CliqueDetected) then
        return;
    end

    if (not _oufLibraries) then
        _oufLibraries = {};
        for i = 1, C_AddOns.GetNumAddOns() do
            local global = C_AddOns.GetAddOnMetadata(i, "X-oUF");
            if (type(global) == "string" and global ~= "") then
                _oufLibraries[global] = 0;
            end
        end
    end

    for global, seen in pairs(_oufLibraries) do
        local library = _G[global];
        local objects = type(library) == "table" and library.objects;

        if (type(objects) == "table") then
            for j = seen + 1, #objects do
                -- Handed over the way the Clique protocol hands one over, since that is the door
                -- these frames were aimed at. Everything a frame can be turned away for is
                -- `RegisterFrame`'s: a refusal it already recorded, unprotected, forbidden,
                -- anchor-tied, or unable to take a click.
                --
                -- Under `pcall` for the reason `SetPropagateOne` gives: on 12.1 a frame answering
                -- `IsForbidden` false is no longer proof that touching it will not raise. A frame
                -- that cannot be looked at is left where it already stood.
                pcall(DebindPrivate.RegisterFrame, objects[j], true);
            end
            _oufLibraries[global] = #objects;
        end
    end
end

--- **The children of a group header, taken off the header itself.**
---
--- Every other way we hear about one of these depends on its addon connecting to us. The header
--- protocol connection is made once, when the header is built, by reading a global we have to be
--- standing in at that moment (`Public.lua`); a header built before that, or one whose addon does
--- not speak the protocol at all, is never joined and none of its children ever arrive. The table
--- is no better: whoever holds its name at the time gets the writes.
---
--- **A header knows its children exactly.** `configureChildren` puts each unit button in a `child<i>`
--- attribute as it makes it (`SecureGroupHeaders.lua`), so the attributes enumerate the unit buttons
--- and nothing else. `GetChildren()` would hand back the backgrounds and textures with them.
---
--- **They are group frames, all of them.** A header hands its children whichever unit they are
--- filling right now and takes it back, so the token on a child says which slot it is and not what
--- the frame is. The pet headers are here for the same answer: what someone reading "pet frame"
--- pictures is their own pet's frame, not a grid of other people's pets.
local function CollectHeaderChildren(header)
    -- **Ours are group headers too, and the hook below cannot tell.** `UnitWatch.lua` builds its
    -- role watchers out of `SecureGroupHeaderTemplate`, so they come through here like anyone
    -- else's, and their children pass every gate `RegisterFrame` has. Registering them wires
    -- click-casting onto frames that have no size and are never on screen.
    if (DebindPrivate.OwnGroupHeaders[header]) then
        return;
    end

    local i = 1;
    while (true) do
        local child = header:GetAttribute("child" .. i);
        if (not child) then
            return;
        end
        -- **Marked before it is offered, and the mark stays.** This is the only door that knows
        -- these frames are a header's, and the answer has to hold for the doors that do not
        -- (`_headerChildren`).
        _headerChildren[child] = true;
        -- Under `pcall` for the reason `SetPropagateOne` gives: on 12.1 a frame answering
        -- `IsForbidden` false is no longer proof that touching it will not raise.
        pcall(DebindPrivate.RegisterFrame, child, "group");
        i = i + 1;
    end
end

--- **Two hooks, because one of them may never fire.** `OnLoad` is the earliest a header can be
--- caught and the only one that catches a header that is never shown, but the template names it in
--- XML and what that binds is not ours to see. `SecureGroupHeader_Update` is named from Lua by
--- `SecureGroupHeader_OnEvent` and `_OnAttributeChanged`, so hooking it resolves at the call and is
--- certain. It is also where the children are made, which makes it the re-walk: a header gains
--- children as the group does, and this runs the moment after it did.
---
--- Both are cheap to run twice. A child already registered leaves `RegisterFrame` on the row it
--- already has, before any of the checks.
if (not DebindPrivate.CliqueDetected) then
    hooksecurefunc("SecureGroupHeader_OnLoad", CollectHeaderChildren);
    hooksecurefunc("SecureGroupHeader_Update", CollectHeaderChildren);
    hooksecurefunc("SecureGroupPetHeader_OnLoad", CollectHeaderChildren);
    hooksecurefunc("SecureGroupPetHeader_Update", CollectHeaderChildren);
end

local function registerBlizzardFrame(frame, category)
    if (DebindPrivate.Options.blizzframes[category] ~= false) then
        local options = BLIZZARD_UNITFRAME_OPTIONS[category];
        DebindPrivate.RegisterFrame(frame, options and options.type);
    else
        DebindPrivate.UnregisterFrame(frame);
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
