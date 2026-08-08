local _, DebindPrivate           = ...;
local Constants                    = DebindPrivate.Constants;
local BindingDriver                = DebindPrivate.BindingDriver;
local L                            = DebindPrivate.L;

DebindPrivate.ccframes           = {};
DebindPrivate.blizzardFrames     = {};
DebindPrivate.RegisterQueue      = {};
DebindPrivate.UnregisterQueue    = {};
DebindPrivate.RegisterClickQueue = {};

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

function DebindPrivate.UpdateRegisteredClicks(button)
    if (DebindPrivate.CliqueDetected) then
        return;
    end

    if (InCombatLockdown()) then
        tinsert(DebindPrivate.RegisterClickQueue, button)
        return
    end

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
