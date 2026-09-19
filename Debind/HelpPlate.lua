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

local function GetTile(index)
	local tile = _tiles[index];
	if (not tile) then
		tile = CreateFrame("Frame", nil, DebindHelpPlateCanvas, "HelpPlateTile");
		_tiles[index] = tile;
	end
	return tile;
end

--- The scale everything handed to `Show` has to be in. The canvas hangs off `UIParent`, not off the
--- window being explained, so a window at another scale has to carry its numbers over first.
function HelpPlate.GetEffectiveScale()
	return DebindHelpPlateCanvas:GetEffectiveScale();
end

function HelpPlate.IsShowing(helpInfo)
	return _shownInfo ~= nil and _shownInfo == helpInfo;
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

--- `helpInfo` is the shape Blizzard's plate takes, so a reader can hold one description against the
--- other: `FramePos` and `FrameSize` place the canvas over `parent`, and each numbered entry carries
--- `HighLightBox`, `ButtonPos`, `ToolTipDir` and `ToolTipText`.
function HelpPlate.Show(helpInfo, parent)
	HelpPlate.Hide();
	_shownInfo = helpInfo;

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

function HelpPlate.Hide()
	if (not _shownInfo) then
		return;
	end

	_shownInfo = nil;

	for _, tile in ipairs(_tiles) do
		tile:Hide();
		tile.Button:Hide();
	end

	DebindHelpPlateCanvas:Hide();
	HelpPlate.HideTooltip();
end
