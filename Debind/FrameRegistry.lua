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
DebindPrivate.ClickCastRouting   = {};

local ApplyClickCastRouting;
local RestoreClickCastRouting;

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


function DebindPrivate.RegisterFrame(button, type)
    if (DebindPrivate.CliqueDetected) then
        return;
    end

    if (DebindPrivate.ccframes[button] == false) then
        return;
    end

    if (DebindPrivate.ccframes[button] and (DebindPrivate.ccframes[button].hd or DebindPrivate.ccframes[button].type == type)) then
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

    local frameType = UNITFRAME_TYPES[type] or UNITFRAME_TYPES.unknown;
    button:SetAttribute("debind_frametype", frameType);
    -- if (DebindPrivate.blizzardFrames[button]) then
    --     local insetL, insetR, insetT, insetB = button:GetHitRectInsets();
    --     insetL = floor(insetL + 0.5);
    --     insetR = floor(insetR + 0.5);
    --     insetT = floor(insetT + 0.5);
    --     insetB = floor(insetB + 0.5);
    --     button:SetAttribute("debind_insets", format("%d,%d,%d,%d", insetL, insetR, insetT, insetB));
    -- end

    SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "clickcast_button", button);
    SecureHandlerExecute(DebindPrivate.BindingDriver, [=[
		local button = self:GetFrameRef("clickcast_button")
		self:RunFor(button, self:GetAttribute("InitFrame"))
		ccframes[button].frameType = button:GetAttribute("debind_frametype")
		-- local insets = button:GetAttribute("debind_insets")
		-- if (insets) then
		-- 	local l, r, t, b = strsplit(",", insets)
		-- 	ccframes[button].insetL, ccframes[button].insetR, ccframes[button].insetT, ccframes[button].insetB = tonumber(l), tonumber(r), tonumber(t), tonumber(b)
		-- end
	]=]);

    if (not DebindPrivate.CliqueDetected) then
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
        -- 등록을 먼저 지운다. `RestoreClickCastRouting`이 "아직 등록돼 있나"로 미뤄둔
        -- 되돌리기와 살아 있는 등록을 가른다.
        DebindPrivate.ccframes[button] = nil;
        RestoreClickCastRouting(button);

        if (not DebindPrivate.CliqueDetected) then
            SecureHandlerUnwrapScript(button, "OnEnter");
            SecureHandlerUnwrapScript(button, "OnLeave");
        end
    end
end

local function SetPropagate(...)
    local n = select("#", ...);
    for i = 1, n do
        local frame = select(i, ...);
        if (frame and frame.SetPropagateMouseMotion) then
            frame:SetPropagateMouseMotion(true);
        end
        if (frame.GetChildren) then
            SetPropagate(frame:GetChildren());
        end
    end
end

--- 되돌릴 값. **`ccframes` 엔트리 안에 두면 안 된다.**
---
--- 헤더로 등록된 프레임은 `OnClickCastUnregister`가 그 엔트리를 통째로 지운다. 백업이 거기
--- 있으면 같이 사라져서, 우리가 쓴 `clickbutton`이 프레임에 남았는데 **되돌릴 값이 없는**
--- 상태가 된다. 게다가 전투 중 해제면 그 자리에서 되돌릴 수도 없어서(보호된 프레임에 비보안
--- 쓰기) 전투가 끝난 뒤에 처리해야 하는데, 그때는 엔트리가 이미 없다.
---
--- 약한 키라 프레임이 사라지면 같이 사라진다.
local _routingBackup = setmetatable({}, { __mode = "k" });

--- 각 프레임이 실제로 **어느 대상에** 라우팅을 얹었는지. 헤더로 들어온 프레임은 자기가
--- 아니라 부모(헤더)에 얹으므로 되돌릴 때 그 대상을 다시 찾아야 하는데, `ccframes`로는 못
--- 찾는다 - 되돌리기는 등록이 풀린 **뒤에** 오는 길이 있다(전투 중 해제 → 전투 종료 후 처리).
local _routedTarget  = setmetatable({}, { __mode = "k" });

--- 한 대상에 몇 개의 프레임이 얹혀 있나. 헤더 하나를 그 밑 버튼 전부가 공유하므로, 버튼
--- 하나가 빠졌다고 헤더를 되돌리면 남은 버튼들의 클릭이 그 자리에서 끊긴다.
local _routingRefs   = setmetatable({}, { __mode = "k" });

--- 전투 중에 해제돼 되돌리지 못한 프레임. `PLAYER_REGEN_ENABLED`가 처리한다.
DebindPrivate.RestoreRoutingQueue = {};

--- 헤더에 속성을 쓸 때 씌운다. **없으면 무한 재귀다.**
---
--- `SecureGroupHeader_OnAttributeChanged`는 속성이 하나 바뀔 때마다 `SecureGroupHeader_Update`를
--- 통째로 돈다. 그런데 우리가 여기 오는 길 하나가 **그 갱신 안**이다 - 헤더가 버튼을 만들며
--- 돌리는 `initialConfigFunction`이 `clickcast_register`를 부르고, 그게 `CallMethod`로 우리에게
--- 온다. 게다가 그 시점은 헤더가 만든 버튼을 `child<N>`에 기록하기 **전**이라
--- (SecureGroupHeaders.lua:176-177) 재진입한 갱신이 **버튼을 또 만들고** 그 버튼이 또 등록을
--- 부른다. 끝이 없다 - Grid2에서 C 스택이 실제로 터졌다.
---
--- `_ignore`는 블리자드가 같은 문제에 쓰는 그 수단이다(`setAttributesWithoutResponse`).
--- 우리가 쓰는 것은 클릭 순간에 조회되는 값이라 헤더 갱신이 필요 없다.
local function BeginQuietWrite(target)
    local oldIgnore = target:GetAttribute("_ignore");
    target:SetAttribute("_ignore", "attributeChanges");
    -- 원래 값이 `nil`이면 `nil`로 되돌려야 하므로 그대로 돌려준다. 호출부가 이 값을 그대로
    -- `EndQuietWrite`에 넘긴다.
    return oldIgnore;
end

local function EndQuietWrite(target, oldIgnore)
    target:SetAttribute("_ignore", oldIgnore);
end

--- 한 프레임을 대상에서 뗀다. **마지막 하나가 빠질 때만** 원래 값을 돌려준다.
local function ReleaseRoutingTarget(button)
    local target = _routedTarget[button];
    if (not target) then
        return;
    end

    _routedTarget[button] = nil;

    local refs = (_routingRefs[target] or 1) - 1;
    if (refs > 0) then
        _routingRefs[target] = refs;
        return;
    end
    _routingRefs[target] = nil;

    local backup = _routingBackup[target];
    if (not backup) then
        return;
    end
    _routingBackup[target] = nil;

    local viaHeader = target ~= button;
    local oldIgnore;
    if (viaHeader) then
        oldIgnore = BeginQuietWrite(target);
    end

    for attr, original in pairs(backup) do
        target:SetAttribute(attr, original or nil);
    end

    if (viaHeader) then
        EndQuietWrite(target, oldIgnore);
    end
end

--- 유닛 프레임의 클릭을 우리 클릭 프레임으로 보내는 `clickbutton`을 맞춘다.
---
--- **맨이름 `clickbutton` 하나로는 안 된다.** 우리가 거는 `type`이 `<접두사>type<번호>`라
--- 조회도 그 구체성에서 시작하는데, 프레임이 자기 `*clickbutton2` 같은 것을 들고 있으면
--- 맨이름보다 그게 이긴다. 그래서 `type`을 쓴 자리마다 짝을 맞춰 쓴다.
---
--- 되돌릴 값은 `_routingBackup`이 들고 있는다. 보안 쪽 `ClickAttrDefaultValues`는
--- `t.clickAttrs`의 키만 도는데 `clickbutton`은 거기 없다 - 여기가 그 짝이다.
---
--- `seen`은 한 판에서 이미 맞춘 대상을 담는다. 헤더 하나를 공대 버튼 전부가 공유하므로
--- 없으면 같은 자리를 버튼 수만큼 다시 쓰게 된다.
function ApplyClickCastRouting(button, seen)
    local entry = DebindPrivate.ccframes[button];
    if (not entry) then
        return;
    end

    local target = button;
    if (entry.hd) then
        target = button.bar or button:GetParent() or button;
    end
    local viaHeader = target ~= button;

    -- 대상이 바뀌었으면 옛 대상에서 먼저 손을 뗀다. 같은 대상이면 아무것도 하지 않는다 -
    -- 뗐다 다시 걸면 원래 값을 되돌려 썼다가 곧바로 다시 덮게 된다.
    if (_routedTarget[button] ~= target) then
        ReleaseRoutingTarget(button);
        _routedTarget[button] = target;
        _routingRefs[target] = (_routingRefs[target] or 0) + 1;
    end

    if (seen) then
        if (seen[target]) then
            return;
        end
        seen[target] = true;
    end

    local backup = _routingBackup[target];
    local wanted = DebindPrivate.ClickCastRouting;

    local oldIgnore;
    if (viaHeader) then
        oldIgnore = BeginQuietWrite(target);
    end

    for attr in pairs(wanted) do
        if (not (backup and backup[attr] ~= nil)) then
            backup = backup or {};
            -- 원래 값이 없으면 `false`로 표시한다. `nil`은 "백업한 적 없다"와 구별이 안 된다.
            backup[attr] = target:GetAttribute(attr) or false;
            _routingBackup[target] = backup;
        end
        target:SetAttribute(attr, DebindPrivate.DefaultClickFrame);
    end

    -- 더 이상 안 쓰는 자리는 돌려준다. 안 그러면 바인딩을 지운 뒤에도 그 프레임의 원래
    -- 클릭이 우리에게 계속 온다.
    if (backup) then
        for attr, original in pairs(backup) do
            if (not wanted[attr]) then
                target:SetAttribute(attr, original or nil);
                backup[attr] = nil;
            end
        end
        if (not next(backup)) then
            _routingBackup[target] = nil;
        end
    end

    if (viaHeader) then
        EndQuietWrite(target, oldIgnore);
    end
end

--- 프레임을 놓아줄 때 원래 값을 돌려준다. 우리가 쓴 자리만 되돌린다.
---
--- **부르기 전에 `ccframes`에서 지울 것.** 전투 중이면 미루는데, 그 사이에 같은 프레임이
--- 다시 등록되면(전투 중 등록도 큐로 미뤄졌다가 전투가 끝나면 **이쪽보다 먼저** 처리된다)
--- 미뤄둔 되돌리기가 살아 있는 등록의 라우팅을 벗긴다. 그 갈림을 여기서 본다.
---
--- **전투 중이면 미룬다.** 보호된 프레임에 비보안으로 쓰는 일이라 그 자리에서는 막힌다.
--- 헤더 해제(`clickcast_unregister`)는 보안 쪽이라 전투 중에도 오므로 실재하는 경우다.
--- 미루는 동안 `clickbutton`이 우리를 가리킨 채로 남는데, 그 프레임은 이미 등록이 풀려서
--- 우리가 `type`을 쓰지 않으므로 아무도 그 값을 안 읽는다.
function RestoreClickCastRouting(button)
    if (not _routedTarget[button]) then
        return;
    end

    if (DebindPrivate.ccframes[button]) then
        return;
    end

    if (InCombatLockdown()) then
        tinsert(DebindPrivate.RestoreRoutingQueue, button);
        return;
    end

    ReleaseRoutingTarget(button);
end

DebindPrivate.RestoreClickCastRouting = function(button)
    RestoreClickCastRouting(button);
end;

--- 등록된 프레임 전부에 라우팅을 다시 맞춘다. 리빌드가 `ClickCastRouting`을 갈아치운 뒤
--- 부른다.
---
--- **전투 검사를 안 한다.** `UpdateBindings`가 전투 중이면 아예 짓지 않고 나가므로
--- (그쪽 첫 줄의 `InCombatLockdown`) 여기 오는 길이 전투 밖 하나뿐이다.
---
--- `UpdateRegisteredClicks`를 부르지 않는 이유는 그쪽이 `RegisterForClicks`와
--- `SetPropagate`(자식 전체 재귀)까지 같이 하기 때문이다. 그건 등록 시점에 한 번이면 되는
--- 일이라 리빌드마다 공대 프레임 전부에 돌릴 것이 아니다.
function DebindPrivate.RefreshClickCastRouting()
    if (DebindPrivate.CliqueDetected) then
        return;
    end

    local seen = {};
    for button in pairs(DebindPrivate.ccframes) do
        ApplyClickCastRouting(button, seen);
    end
end

function DebindPrivate.UpdateRegisteredClicks(button)
    if (DebindPrivate.CliqueDetected) then
        return;
    end

    if (InCombatLockdown()) then
        tinsert(DebindPrivate.RegisterClickQueue, button)
        return
    end

    ApplyClickCastRouting(button);

    SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "clickcast_button", button);
    SecureHandlerExecute(DebindPrivate.BindingDriver, [=[
		local b = self:GetFrameRef("clickcast_button")
		if (ccframes[b]) then
			ccframes[b].routed = true
		end
	]=]);

    -- 애드온이 다 로드되지 않은 상태에서 호출이 된다?
    -- 일단 급하게 픽스
    local trigger = DebindPrivate.Options and DebindPrivate.Options.unitframeUseMouseDown and "AnyDown" or "AnyUp";
    button:RegisterForClicks(trigger);
    button:EnableMouseWheel(true);

    -- 프레임 내에 마우스에 반응하는 자식 프레임이 있는 경우 그 자식 프레임으로 마우스를 올렸을 때
    -- 부모 프레임에서 onleave 스크립트가 호출되지 않게 함.
    SetPropagate(button:GetChildren());
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
        -- error : calling 'GetName' on bad self (Usage: local name = self:GetName())
        -- i don't know why `frame:GetName()` fails.
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
