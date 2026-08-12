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
        DebindPrivate.ccframes[button] = nil;

        if (not DebindPrivate.CliqueDetected) then
            SecureHandlerUnwrapScript(button, "OnEnter");
            SecureHandlerUnwrapScript(button, "OnLeave");
        end
    end
end

--- A forbidden object errors on **any** method call from addon-tainted code, so the whole branch
--- is skipped rather than just the call - descending into its children would raise the same error
--- one level down. `IsForbidden` is the one method that stays answerable there.
---
--- The check at the registration gate (`IsForbidden` above) is not enough: it sees the button we
--- were handed, and what turns up forbidden here is a **child** of a Blizzard frame that passed it.
local function SetPropagate(...)
    local n = select("#", ...);
    for i = 1, n do
        local frame = select(i, ...);
        if (frame and not (frame.IsForbidden and frame:IsForbidden())) then
            if (frame.SetPropagateMouseMotion) then
                frame:SetPropagateMouseMotion(true);
            end
            if (frame.GetChildren) then
                SetPropagate(frame:GetChildren());
            end
        end
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

function DebindPrivate.UpdateRegisteredClicks(button)
    if (DebindPrivate.CliqueDetected) then
        return;
    end

    if (InCombatLockdown()) then
        tinsert(DebindPrivate.RegisterClickQueue, button)
        return
    end

    ApplyDebindRouting(button);

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
