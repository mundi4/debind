local _, DebindPrivate = ...;

--- The balloon with the arrow: a line of help pinned to a button, closed by the reader.
---
--- **This is a second copy of `HelpTip`, and the reason is taint** - the same one `HelpPlate.lua`
--- opens with. The client keeps one `HelpTip.framePool` for the whole game and `HelpTip:Show` takes
--- a frame out of it, so calling it from here leaves our taint on a table the action bar reads on
--- its way to raising its own tip (`ActionButton.lua`, `UpdateSpellAlert` ->
--- `EvaluateTutorials`), and anything that path reaches after that read carries it.
---
--- **The art is still theirs and none of it is copied** (`HelpTip.xml`).
---
--- What is deliberately not here, out of Blizzard's module: systems and priorities, edge flipping
--- and horizontal sliding, appended frames, and the frame watcher. Ours stand on a button that is
--- on screen for as long as they are.
---
--- **`hideHelptips` is not read either, and that is a decision rather than an omission.** What was
--- taken from the client is a style and a template; that CVar answers for the client's own
--- tutorials, and these are not those. Drawing the same picture does not put us under their switch.
---
--- **Being closed is remembered in the profile, not in a CVar.** Blizzard's writes
--- `closedInfoFrames` bitfields, whose flag numbers are the client's own
--- (`Enum.FrameTutorialAccount`), and there is no number in there for us.
local HelpTip = {};
DebindPrivate.HelpTip = HelpTip;

HelpTip.Point = {
	TopEdgeLeft = 1,
	TopEdgeCenter = 2,
	TopEdgeRight = 3,
	BottomEdgeLeft = 4,
	BottomEdgeCenter = 5,
	BottomEdgeRight = 6,
	RightEdgeTop = 7,
	RightEdgeCenter = 8,
	RightEdgeBottom = 9,
	LeftEdgeTop = 10,
	LeftEdgeCenter = 11,
	LeftEdgeBottom = 12,
};

--- Left, Center and Right are the three the balloon has; Top and Bottom are the same three read
--- sideways, which is why they share indices. Blizzard's table does the same and says so.
HelpTip.Alignment = {
	Left = 1,
	Center = 2,
	Right = 3,
	Top = 1,
	Bottom = 3,
};

HelpTip.ButtonStyle = {
	None = 1,
	Close = 2,
	GotIt = 3,
};

local ArrowRotation = {
	Down = 1,
	Left = 2,
	Up = 3,
	Right = 4,
};

local PointInfo = {
	[HelpTip.Point.TopEdgeLeft]      = { arrowRotation = ArrowRotation.Down,  relativeAnchor = "TOPLEFT" },
	[HelpTip.Point.TopEdgeCenter]    = { arrowRotation = ArrowRotation.Down,  relativeAnchor = "TOP" },
	[HelpTip.Point.TopEdgeRight]     = { arrowRotation = ArrowRotation.Down,  relativeAnchor = "TOPRIGHT" },
	[HelpTip.Point.RightEdgeTop]     = { arrowRotation = ArrowRotation.Left,  relativeAnchor = "TOPRIGHT" },
	[HelpTip.Point.RightEdgeCenter]  = { arrowRotation = ArrowRotation.Left,  relativeAnchor = "RIGHT" },
	[HelpTip.Point.RightEdgeBottom]  = { arrowRotation = ArrowRotation.Left,  relativeAnchor = "BOTTOMRIGHT" },
	[HelpTip.Point.BottomEdgeRight]  = { arrowRotation = ArrowRotation.Up,    relativeAnchor = "BOTTOMRIGHT" },
	[HelpTip.Point.BottomEdgeCenter] = { arrowRotation = ArrowRotation.Up,    relativeAnchor = "BOTTOM" },
	[HelpTip.Point.BottomEdgeLeft]   = { arrowRotation = ArrowRotation.Up,    relativeAnchor = "BOTTOMLEFT" },
	[HelpTip.Point.LeftEdgeBottom]   = { arrowRotation = ArrowRotation.Right, relativeAnchor = "BOTTOMLEFT" },
	[HelpTip.Point.LeftEdgeCenter]   = { arrowRotation = ArrowRotation.Right, relativeAnchor = "LEFT" },
	[HelpTip.Point.LeftEdgeTop]      = { arrowRotation = ArrowRotation.Right, relativeAnchor = "TOPLEFT" },
};

local ArrowOffsets = {
	[HelpTip.Alignment.Center] = { 0, 5 },
	[HelpTip.Alignment.Left]   = { 35, 5 },
	[HelpTip.Alignment.Right]  = { -35, 5 },
};

local ArrowGlowOffsets = { 0, 4 };

local DistanceOffsets = {
	[HelpTip.Alignment.Center] = { 0, -20 },
	[HelpTip.Alignment.Left]   = { -35, -20 },
	[HelpTip.Alignment.Right]  = { 35, -20 },
};

local Rotations = {
	[ArrowRotation.Down]  = { modOffsetX = 1,  modOffsetY = -1, swapOffsets = false, degrees = 0,   anchors = { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" } },
	[ArrowRotation.Left]  = { modOffsetX = -1, modOffsetY = -1, swapOffsets = true,  degrees = 90,  anchors = { "TOPLEFT", "LEFT", "BOTTOMLEFT" } },
	[ArrowRotation.Up]    = { modOffsetX = 1,  modOffsetY = 1,  swapOffsets = false, degrees = 180, anchors = { "TOPLEFT", "TOP", "TOPRIGHT" } },
	[ArrowRotation.Right] = { modOffsetX = 1,  modOffsetY = -1, swapOffsets = true,  degrees = 270, anchors = { "TOPRIGHT", "RIGHT", "BOTTOMRIGHT" } },
};

local Buttons = {
	[HelpTip.ButtonStyle.None]  = { textWidthAdj = 0,  heightAdj = 0 },
	[HelpTip.ButtonStyle.Close] = { textWidthAdj = -6, heightAdj = 0,  parentKey = "CloseButton" },
	[HelpTip.ButtonStyle.GotIt] = { textWidthAdj = 0,  heightAdj = 30, parentKey = "OkayButton", text = HELP_TIP_BUTTON_GOT_IT },
};

local VERTICAL_PADDING   = 31;
local MINIMUM_HEIGHT     = 72;
local DEFAULT_TEXT_WIDTH = 196;
local WIDTH              = 226;

--------------------------------------------------------------------------------
-- 무엇을 닫았는지
--------------------------------------------------------------------------------

--- 닫은 사람은 다시 안 본다. 표는 `db.global`에 있다 - 캐릭터가 아니라 **읽은 사람**의
--- 것이라서, 알트로 창을 열 때마다 같은 말을 다시 듣게 두지 않는다.
---
--- 키는 부르는 쪽이 준다(`seenKey`). 안 주면 기록하지 않는다 - 커서가 올라올 때만 뜨고
--- 커서를 떼면 사라지는 말풍선에는 닫는 버튼도, 닫았다는 사실도 없다.
local function SeenTable()
	local db = DebindPrivate.db.global;
	db.tipsSeen = db.tipsSeen or {};
	return db.tipsSeen;
end

function HelpTip.WasSeen(seenKey)
	return SeenTable()[seenKey] == true;
end

function HelpTip.MarkSeen(seenKey)
	SeenTable()[seenKey] = true;
end

--- 테스트와 개발용. 사람이 쓰는 길은 없다 - 한 번 닫은 안내를 되살리는 것은 읽은 사람이
--- 바라는 일이 아니다.
function HelpTip.ForgetSeen(seenKey)
	if (seenKey) then
		SeenTable()[seenKey] = nil;
	else
		DebindPrivate.db.global.tipsSeen = nil;
	end
end

--------------------------------------------------------------------------------
-- 말풍선
--------------------------------------------------------------------------------

DebindHelpTipMixin = {};

local function TransformOffsetsForRotation(offsets, rotationInfo)
	local offsetX = offsets[1];
	local offsetY = offsets[2];
	if (rotationInfo.swapOffsets) then
		offsetX, offsetY = offsetY, offsetX;
	end
	return offsetX * rotationInfo.modOffsetX, offsetY * rotationInfo.modOffsetY;
end

function DebindHelpTipMixin:OnLoad()
	self.Arrow.Arrow:ClearAllPoints();
	self.Arrow.Arrow:SetPoint("CENTER");
	self.Arrow.Glow:ClearAllPoints();

	local function Acknowledge()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
		self:Acknowledge();
	end
	self.OkayButton:SetScript("OnClick", Acknowledge);
	self.CloseButton:SetScript("OnClick", Acknowledge);
end

function DebindHelpTipMixin:RotateArrow(rotation)
	if (self.Arrow.rotation == rotation) then
		return;
	end

	local rotationInfo = Rotations[rotation];
	SetClampedTextureRotation(self.Arrow.Arrow, rotationInfo.degrees);
	SetClampedTextureRotation(self.Arrow.Glow, rotationInfo.degrees);
	local offsetX, offsetY = TransformOffsetsForRotation(ArrowGlowOffsets, rotationInfo);
	self.Arrow.Glow:SetPoint("CENTER", self.Arrow.Arrow, "CENTER", offsetX, offsetY);

	self.Arrow.rotation = rotation;
end

function DebindHelpTipMixin:AnchorAndRotate()
	local info = self.info;
	local pointInfo = PointInfo[info.targetPoint or HelpTip.Point.BottomEdgeCenter];
	local alignment = info.alignment or HelpTip.Alignment.Center;
	local rotationInfo = Rotations[pointInfo.arrowRotation];

	local offsetX, offsetY = TransformOffsetsForRotation(DistanceOffsets[alignment], rotationInfo);
	self:ClearAllPoints();
	self:SetPoint(rotationInfo.anchors[alignment], self.relativeRegion, pointInfo.relativeAnchor,
		offsetX + (info.offsetX or 0), offsetY + (info.offsetY or 0));

	self:RotateArrow(pointInfo.arrowRotation);
	local arrowX, arrowY = TransformOffsetsForRotation(ArrowOffsets[alignment], rotationInfo);
	self.Arrow:ClearAllPoints();
	self.Arrow:SetPoint("CENTER", self, rotationInfo.anchors[alignment], arrowX, arrowY);
end

--- 높이는 글에서 나온다. 폭은 고정이고, 버튼이 있으면 그 몫만큼 늘어난다.
function DebindHelpTipMixin:Layout()
	local info = self.info;
	local pointInfo = PointInfo[info.targetPoint or HelpTip.Point.BottomEdgeCenter];
	local buttonInfo = Buttons[info.buttonStyle or HelpTip.ButtonStyle.None];

	local textWidth = DEFAULT_TEXT_WIDTH + buttonInfo.textWidthAdj;
	local textOffsetY = 1 + buttonInfo.heightAdj / 2;
	local height = VERTICAL_PADDING + buttonInfo.heightAdj;

	if (buttonInfo.parentKey) then
		local button = self[buttonInfo.parentKey];
		button:Show();
		if (buttonInfo.text) then
			button:SetText(buttonInfo.text);
		end
	end

	self.Text:SetText(info.text);
	self.Text:SetTextColor((info.textColor or HIGHLIGHT_FONT_COLOR):GetRGB());
	-- 한 줄이면 가운데, 여러 줄이면 왼쪽. 블리자드가 같은 자리에서 같은 판정을 한다.
	self.Text:SetJustifyH(info.textJustifyH or (self.Text:GetNumLines() == 1 and "CENTER" or "LEFT"));
	self.Text:SetWidth(textWidth);
	self.Text:ClearAllPoints();
	self.Text:SetPoint("LEFT", 15, textOffsetY);

	height = height + self.Text:GetHeight();
	-- 화살표가 옆으로 날 때는 상자가 화살표보다 낮으면 안 된다.
	if (pointInfo.arrowRotation == ArrowRotation.Left or pointInfo.arrowRotation == ArrowRotation.Right) then
		height = max(height, MINIMUM_HEIGHT);
	end
	self:SetHeight(height);
end

function DebindHelpTipMixin:Init(info, relativeRegion)
	self.info = info;
	self.relativeRegion = relativeRegion;
	self:SetParent(relativeRegion);
	self:SetFrameStrata("DIALOG");
	self:SetWidth(WIDTH);

	self.OkayButton:Hide();
	self.CloseButton:Hide();
	self.Arrow:SetShown(not info.hideArrow);

	self:AnchorAndRotate();
	self:Layout();
end

--- 읽고 닫았다. **기록은 여기서만 남는다** - 창이 닫히면서 같이 사라진 말풍선은 읽힌 적이
--- 없으므로, 다음에 다시 서야 한다.
function DebindHelpTipMixin:Acknowledge()
	local seenKey = self.info and self.info.seenKey;
	if (seenKey) then
		HelpTip.MarkSeen(seenKey);
	end
	self:Close();
end

function DebindHelpTipMixin:Close()
	local info = self.info;
	self.info = nil;
	self.relativeRegion = nil;
	self:Hide();
	self:ClearAllPoints();
	self:SetParent(UIParent);
	if (info and info.onHideCallback) then
		info.onHideCallback();
	end
end

--------------------------------------------------------------------------------
-- 창구
--------------------------------------------------------------------------------

--- 만들어 둔 말풍선 전부. 블리자드의 풀 대신이고, 우리 것만 든다.
local _tips = {};

--- 가리키던 프레임이 화면에서 사라지면 말풍선도 같이 사라진다(부모라서). 그때 이 표만은
--- 아직 서 있다고 알고 있으므로, 여기서 정리하지 않으면 그 자리는 영영 다시 안 선다.
---
--- **읽었다고 치지 않는다.** 창이 닫히면서 같이 내려간 안내는 읽힌 적이 없다.
local function Reap()
	for _, tip in ipairs(_tips) do
		if (tip.info and not tip:IsVisible()) then
			tip:Close();
		end
	end
end

local function FreeTip()
	for _, tip in ipairs(_tips) do
		if (not tip.info) then
			return tip;
		end
	end

	local tip = CreateFrame("Frame", nil, UIParent, "DebindHelpTipTemplate");
	_tips[#_tips + 1] = tip;
	return tip;
end

local function FindTip(relativeRegion, text)
	for _, tip in ipairs(_tips) do
		if (tip.info and tip.relativeRegion == relativeRegion
			and (text == nil or tip.info.text == text)) then
			return tip;
		end
	end
	return nil;
end

--- `relativeRegion`이 말풍선이 가리키는 것이고 부모이기도 하다. 그 프레임이 숨으면 말풍선도
--- 같이 숨으므로, 블리자드처럼 감시자를 둘 일이 없다.
---
--- **이미 닫은 안내는 서지 않는다**(`seenKey`). 그 판정이 여기 있는 것은 부르는 쪽마다
--- 같은 조건문을 적지 않게 하려는 것이다.
function HelpTip.Show(relativeRegion, info)
	if (info.seenKey and HelpTip.WasSeen(info.seenKey)) then
		return false;
	end

	Reap();
	if (FindTip(relativeRegion, info.text)) then
		return true;
	end

	local tip = FreeTip();
	tip:Init(info, relativeRegion);
	tip:Show();
	return true;
end

--- 닫는다. **읽었다고 치지 않는다** - 이것으로 닫히는 것은 커서가 떠났거나 창이 닫힌
--- 경우이고, 둘 다 읽었다는 말이 아니다.
function HelpTip.Hide(relativeRegion, text)
	local tip = FindTip(relativeRegion, text);
	if (tip) then
		tip:Close();
	end
end

--- [알겠습니다]를 누른 것과 같다. 닫고, **읽었다고 기록한다**.
function HelpTip.Acknowledge(relativeRegion, text)
	local tip = FindTip(relativeRegion, text);
	if (tip) then
		tip:Acknowledge();
	end
end

function HelpTip.HideAll()
	for _, tip in ipairs(_tips) do
		if (tip.info) then
			tip:Close();
		end
	end
end

function HelpTip.IsShowing(relativeRegion, text)
	return FindTip(relativeRegion, text) ~= nil;
end
