local _, DebindPrivate = ...;

--- The help plate: an (i) over each part of a window, with a balloon on hover.
---
--- **This is a second copy of `Blizzard_HelpPlate`, and the reason is taint.** That addon keeps one
--- canvas, one balloon and one tile pool for the whole client, and `HelpPlate.Show` writes its
--- module locals (`currentHelpInfo`, `forTutorial`) on the way. Calling it from here would leave our
--- taint on values the map and the spell book read when they raise their own plates, and anything
--- their path reaches after that read carries it. The blocked-action line in the chat frame names
--- the addon that touched the value, which would be us, in somebody else's window.
---
--- **The art is still theirs, and none of it is copied.** `HelpPlateTile`, `MainHelpPlateButton` and
--- the glow box the balloon is built from are virtual templates, so inheriting one makes a frame of
--- our own that draws the same picture. The only piece that had to be written out again is the
--- balloon, because `HelpPlateTooltip` is a named frame rather than a template; its layout is the
--- same one, and its behaviour is still `HelpPlateTooltipMixin` (`HelpPlate.xml`).
---
--- What is deliberately not here: the tutorial path. Blizzard's plate can pulse an (i) and fade a
--- balloon in once for a reader who has never opened the window, gated on a CVar bitfield of frame
--- numbers that are theirs. Ours opens when the (?) is pressed and at no other time.
local HelpPlate = {};
DebindPrivate.HelpPlate = HelpPlate;

local _shownInfo;
local _tiles = {};

--- **Whether the reader asked for help, which is not whether a plate is up.** A plate is one tab's
--- and goes down when that tab does; this does not, so crossing to another tab raises that tab's
--- plate in the first one's place. Only the (?), Escape and the window closing clear it
--- (`HelpPlate.Dismiss`).
local _wanted = false;

local function GetTile(index)
	local tile = _tiles[index];
	if (not tile) then
		tile = CreateFrame("Frame", nil, DebindHelpPlateCanvas, "HelpPlateTile");
		_tiles[index] = tile;
	end
	return tile;
end

--- **The title bar stays outside the plate, and that is what this number is for.**
--- The canvas takes the mouse over everything it covers and hands nothing through, so a
--- plate that started at the very top of the window left it impossible to drag and impossible to
--- close while the help was up. The close button is 24 tall in its corner
--- (`UIPanelCloseButtonNoScripts`), so 26 clears it, the gear beside it and the title strip the
--- window is dragged by. It also clears the (?) itself, which hangs 26 below the window's top edge
--- and has to stay pressable to put the plate away. Blizzard's own windows inset the same way
--- (world map -26, spell book -22).
local TOP_INSET = 26;

local BUTTON_SIZE = 46;

--- Lays `plate` over `parent` and hands back the maker for its sections: `section(frame, dir,
--- text)` lights the whole of `frame` and puts one (i) in the middle of it.
---
--- **Every rectangle is measured here, at the moment the plate opens.** The window changes width
--- with the tab, the columns are anchored to each other, and the user moves the whole thing around
--- the screen; coordinates fixed at load would point at empty air after any of that.
---
--- The canvas is parented to the top level, not to the window, so everything measured on the
--- window has to be carried into that scale first (`Blizzard_SpellBookFrameTutorials.lua` does the
--- same arithmetic for the same reason).
function HelpPlate.Measure(plate, parent)
	local relativeScale = parent:GetEffectiveScale() / DebindHelpPlateCanvas:GetEffectiveScale();
	local left = parent:GetLeft() * relativeScale;
	local top = (parent:GetTop() * relativeScale) - TOP_INSET;

	plate.FramePos = { x = 0, y = -TOP_INSET };
	plate.FrameSize = {
		width = parent:GetWidth() * relativeScale,
		height = (parent:GetHeight() * relativeScale) - TOP_INSET,
	};

	return function(frame, tooltipDir, tooltipText)
		local x = (frame:GetLeft() * relativeScale) - left;
		local y = (frame:GetTop() * relativeScale) - top;
		local width = frame:GetWidth() * relativeScale;
		local height = frame:GetHeight() * relativeScale;

		return {
			ButtonPos = {
				x = x + (width - BUTTON_SIZE) / 2,
				y = y - (height - BUTTON_SIZE) / 2,
			},
			HighLightBox = { x = x, y = y, width = width, height = height },
			ToolTipDir = tooltipDir,
			ToolTipText = tooltipText,
		};
	end;
end

--- With no argument, whether any plate is up at all. That is what the window's Escape asks, since
--- the press takes down whichever tab's plate is standing.
function HelpPlate.IsShowing(helpInfo)
	if (_shownInfo == nil) then
		return false;
	end
	return helpInfo == nil or _shownInfo == helpInfo;
end

function HelpPlate.ShowTooltip(anchorTo, text, direction)
	DebindHelpPlateTooltip:Init(anchorTo, text, direction or "RIGHT");
end

function HelpPlate.HideTooltip()
	DebindHelpPlateTooltip:Hide();
end

--- The balloon the (?) itself puts up on hover. The text is the client's own
--- (`MAIN_HELP_BUTTON_TOOLTIP`, carried in by `MainHelpPlateButton`'s KeyValue).
function HelpPlate.ShowButtonTooltip(button)
	HelpPlate.ShowTooltip(button, button.mainHelpPlateButtonTooltipText, "RIGHT");
end

--- Everything down at once, and the tiles put back in the state `Show` expects to find them in.
---
--- **`Button:Reset` is what makes a tile reusable.** It stops the slide animation and drops the
--- `OnFinished` a fly-out left on it, so the next `Show` starts from a button at full alpha in its
--- own place and no stale callback fires into a plate that has already gone.
local function FinalizeHide()
	for _, tile in ipairs(_tiles) do
		tile.Button:Reset();
		tile.Button:Hide();
		tile:Hide();
	end

	DebindHelpPlateCanvas:Hide();
	HelpPlate.HideTooltip();
end

--- `helpInfo` is the shape Blizzard's plate takes, so a reader can hold one description against the
--- other: `FramePos` and `FrameSize` place the canvas over `parent`, and each numbered entry carries
--- `HighLightBox`, `ButtonPos`, `ToolTipDir` and `ToolTipText`.
---
--- **It clears up through the finaliser rather than through `Hide`.** A fly-out from the last
--- dismissal can still be in the air, and `_shownInfo` is already nil by then, so `Hide` would
--- return having touched nothing and leave those animations to land on top of this plate.
function HelpPlate.Show(helpInfo, parent)
	FinalizeHide();
	_shownInfo = helpInfo;
	_wanted = true;

	local canvas = DebindHelpPlateCanvas;

	for index, info in ipairs(helpInfo) do
		local tile = GetTile(index);
		local box = info.HighLightBox;

		tile:ClearAllPoints();
		tile:SetSize(box.width, box.height);
		tile:SetPoint("TOPLEFT", box.x, box.y);

		-- The template's own handlers light the box; these add the balloon. Set rather than hooked,
		-- because the entry they read changes from one opening to the next.
		tile:SetScript("OnEnter", function()
			HelpPlateTileMixin.OnEnter(tile);
			HelpPlate.ShowTooltip(tile.Button, info.ToolTipText, info.ToolTipDir);
		end);
		tile:SetScript("OnLeave", function()
			HelpPlateTileMixin.OnLeave(tile);
			HelpPlate.HideTooltip();
		end);

		tile:Show();

		tile.Button:ClearAllPoints();
		tile.Button:SetPoint("TOPLEFT", canvas, "TOPLEFT", info.ButtonPos.x, info.ButtonPos.y);
		tile.Button:Show();
	end

	canvas:ClearAllPoints();
	canvas:SetPoint("TOPLEFT", parent, "TOPLEFT", helpInfo.FramePos.x, helpInfo.FramePos.y);
	canvas:SetSize(helpInfo.FrameSize.width, helpInfo.FrameSize.height);
	canvas:Show();
end

--- **`fromUserInput` is what buys the animation**, the same split Blizzard's plate makes. Each (i)
--- flies back to the canvas's corner and fades as it goes (`HelpPlateButtonMixin:AnimateOut`,
--- 0.3s), which is the way it arrived played backwards; the yellow boxes and the canvas stay until
--- the last one lands. Everywhere else the plate is not being dismissed but replaced or carried
--- off screen, and a fly-out there would animate something the reader is not looking at any more.
function HelpPlate.Hide(fromUserInput)
	if (not _shownInfo) then
		return;
	end

	_shownInfo = nil;

	if (not fromUserInput) then
		FinalizeHide();
		return;
	end

	local flying = 0;
	for _, tile in ipairs(_tiles) do
		if (tile:IsShown()) then
			flying = flying + 1;
			tile.Button:AnimateOut(function(button)
				button:Hide();
				flying = flying - 1;
				if (flying == 0) then
					FinalizeHide();
				end
			end);
		end
	end

	if (flying == 0) then
		FinalizeHide();
	end
end

--- Whether the plate the reader asked for is owed to whichever tab comes up next.
function HelpPlate.IsWanted()
	return _wanted;
end

--- The plate goes down **and is not owed to the next tab.** This is the (?) pressed again, Escape,
--- and the window closing; everything else takes the plate down through `Hide` and leaves the
--- asking in place.
function HelpPlate.Dismiss(fromUserInput)
	_wanted = false;
	HelpPlate.Hide(fromUserInput);
end
