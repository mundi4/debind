local _, DebindPrivate = ...;
local LLL = DebindPrivate.L;

--- **The functions that open it hang on `DebindUI`.** `DebindPrivate` is the core's table and
--- everything here is UI, so opening a window has no place there.
local DebindUI = DebindPrivate.DebindUI;

--- The help window. What it is made of is in `DebindMessageFrame.xml`; what is here is which page
--- it shows.
---
--- **It lives outside the main window.** Neither looks at the other: the settings tab opens it,
--- and that tab opens with the main window not up.
---
--- **This file comes before the XML in the `.toc`.** The XML's `mixin=` looks this global up as
--- the frame is made, and the other order says "Unknown method OnLoad". It has happened once.
DebindMessageFrameMixin = {};

--- `HelpTopics.lua`, generated from `docs/ingamehelp/index.md`, by page name.
local TOPICS = {};
for _, section in ipairs(DebindPrivate.HELP_SECTIONS) do
    for _, topic in ipairs(section.topics) do
        TOPICS[topic.name] = topic;
    end
end

function DebindMessageFrameMixin:OnLoad()
    self:SetTitle(LLL["ADDON_NAME"]);
    self:RegisterForDrag("LeftButton");
    self:SetScript("OnDragStart", self.StartMoving);
    self:SetScript("OnDragStop", self.StopMovingOrSizing);

    -- ESC is left to the game's net; the reason is on `DebindDialogMixin:InitDialog` in
    -- `DebindUI.lua`.
    --
    -- **No `HandleEscape` slot and no `OnDialogHide`, on purpose.** Those let the main window own
    -- the lifetime of what is under it, and this window is not under it. One ESC closing only this
    -- is the main window's doing instead: it leaves that press unstamped while this is up
    -- (`DebindFrameMixin:OnKeyDown`).
    tinsert(UISpecialFrames, self:GetName());

    self.Dropdown:SetPoint("RIGHT", self.ScrollFrame.ScrollBar, "RIGHT");

    --- The pages left, with where each was scrolled to, newest last.
    self.history = {};
    self.BackButton:SetOnClickHandler(function()
        self:GoBack();
    end);
    self.BackButton:SetEnabledState(false);

    self.Dropdown:SetupMenu(function(_, rootDescription)
        for _, section in ipairs(DebindPrivate.HELP_SECTIONS) do
            rootDescription:CreateTitle(LLL[section.title]);
            for _, topic in ipairs(section.topics) do
                rootDescription:CreateRadio(LLL[topic.title], function()
                    return self.topic == topic.name;
                end, function()
                    DebindUI.ShowHelp(topic.name);
                end);
            end
        end
    end);
end

--- **Lit whatever page is on it** (2026-09-22, owner): each button names a page, but the ring says
--- this window is up, and walking to another page through the dropdown never left it.
local function SetHelpButtonsLit(lit)
    local frame = DebindFrame;
    if (frame == nil) then
        return;
    end
    frame.OverviewPanel.PortraitRow.HelpPortrait:SetSelectedState(lit);
    frame.SwitchesPanel.PortraitRow.HelpPortrait:SetSelectedState(lit);
end

function DebindMessageFrameMixin:OnShow()
    SetHelpButtonsLit(true);
end

--- One of the question marks that open a page. **Hooked rather than set**: the portrait mixin runs
--- its own load on the first `OnShow` and clears the ring there, so a tab first opened while this
--- window is already up would come in unlit.
function DebindUI.WireHelpPortrait(button, page)
    button:SetScript("OnClick", function()
        DebindUI.ToggleHelp(page);
    end);
    button:HookScript("OnShow", function(self)
        self:SetSelectedState(DebindMessageFrame:IsShown());
    end);
end

--- **History lasts as long as the window is up.** Whoever opens it again came for the page they
--- opened, and a Back into whatever they read last time would take them somewhere unasked
--- (2026-09-17, owner).
function DebindMessageFrameMixin:OnHide()
    wipe(self.history);
    self.BackButton:SetEnabledState(false);
    SetHelpButtonsLit(false);
end

function DebindMessageFrameMixin:GoBack()
    local entry = tremove(self.history);
    if (entry) then
        self:ShowTopic(entry.name, entry.scroll);
    end
    self.BackButton:SetEnabledState(#self.history > 0);
end

local INDENT = 20;
local MARKER_GAP = 4;

--- **Asked for, not built at load.** A font object named here is a global this file would read
--- before the frame XML that declares it has run.
local BODY_FONTS;
local function BodyFont(kind)
    if (not BODY_FONTS) then
        BODY_FONTS = {
            heading = GameFontHighlightMedium,
            note = GameFontDisable,
        };
    end
    return BODY_FONTS[kind] or GameFontNormal;
end

local function GapBefore(previous, block)
    if (not previous) then
        return 0;
    elseif (block.kind == "heading") then
        return 16;
    elseif (previous.kind == "heading") then
        return 6;
    elseif (previous.kind == "item" and block.kind == "item") then
        return 4;
    end
    return 10;
end

local function AcquireFontString(self, index)
    local fontString = self.bodyStrings[index];
    if (not fontString) then
        fontString = self.ScrollFrame.Content:CreateFontString(nil, "ARTWORK");
        fontString:SetJustifyV("TOP");
        fontString:SetWordWrap(true);
        self.bodyStrings[index] = fontString;
    end
    fontString:ClearAllPoints();
    fontString:Show();
    return fontString;
end

--- Lay a page out. The body is cut into blocks (`ParseHelpText`) and each gets a FontString of its
--- own; an item's marker gets a second one, so a wrapped line stands under the item's text and not
--- under its number.
---
--- **The body is `GameFontNormal`, gold.** In `GameFontHighlight` its colour would be
--- `HIGHLIGHT_FONT_COLOR`, and every word a page picks out in that colour would stop standing out.
---
--- **The content frame's height is set here.** Without it `ScrollFrame` sees nothing to scroll
--- and puts up no bar.
---
--- **Back to the top unless `scroll` says where.** A position scrolled to on a long page, kept for
--- a short one, opens on an empty window; `GoBack` hands in the position it saved for that page.
function DebindMessageFrameMixin:ShowTopic(name, scroll)
    local topic = TOPICS[name];
    self.topic = name;
    local title = self.ScrollFrame.Content.Title;
    title:SetText(LLL[topic.title]);
    self.bodyStrings = self.bodyStrings or {};

    local width = self.ScrollFrame.Content:GetWidth();
    local used, y, previous = 0, title:GetStringHeight() + 12, nil;
    for _, block in ipairs(DebindPrivate.ParseHelpText(LLL[topic.body])) do
        y = y + GapBefore(previous, block);

        local x = 0;
        if (block.kind == "item") then
            x = block.level * INDENT;
            used = used + 1;
            local marker = AcquireFontString(self, used);
            marker:SetFontObject(GameFontNormal);
            marker:SetJustifyH("RIGHT");
            marker:SetWidth(INDENT);
            marker:SetText(block.marker == "-" and "•" or block.marker);
            marker:SetPoint("TOPLEFT", x, -y);
            x = x + INDENT + MARKER_GAP;
        end

        used = used + 1;
        local fontString = AcquireFontString(self, used);
        fontString:SetFontObject(BodyFont(block.kind));
        fontString:SetJustifyH("LEFT");
        fontString:SetWidth(width - x);
        fontString:SetText(block.text);
        fontString:SetPoint("TOPLEFT", x, -y);

        y = y + fontString:GetStringHeight();
        previous = block;
    end

    for i = used + 1, #self.bodyStrings do
        self.bodyStrings[i]:Hide();
    end

    self.ScrollFrame.Content:SetHeight(max(1, y));
    -- The range has to be measured again before the saved position is inside it, or it is clamped
    -- to the range the previous page left.
    self.ScrollFrame:UpdateScrollChildRect();
    self.ScrollFrame:SetVerticalScroll(min(scroll or 0, self.ScrollFrame:GetVerticalScrollRange()));

    -- A page opened from a link or from outside the window moves no radio, so the picker is told.
    self.Dropdown:GenerateMenu();
end

--- A link in the body. `link` comes as it was written; `text` is the translated screen string with
--- colour in it, so it decides nothing.
function DebindMessageFrameMixin:OnHyperlinkClick(link)
    local name = link and link:match("^debind:help:(.+)$");
    if (name) then
        DebindUI.ShowHelp(name);
    end
end

--- Open a page. An unknown name does nothing: `build-help.js` refuses a link to a page that does
--- not exist, but a page left out of `index.md` has no entry here and its name can still be called.
function DebindUI.ShowHelp(name)
    if (not TOPICS[name]) then
        return;
    end

    local frame = DebindMessageFrame;
    if (frame:IsShown() and frame.topic ~= name) then
        tinsert(frame.history, { name = frame.topic, scroll = frame.ScrollFrame:GetVerticalScroll() });
        frame.BackButton:SetEnabledState(true);
    end

    frame:ShowTopic(name);
    frame:Show();
    frame:Raise();
end

--- The (i)'s press: the same page closes, any other opens. Judged by the page on the frame and not
--- by whether it is shown, so a press while a different page is up swaps to this one.
function DebindUI.ToggleHelp(name)
    if (DebindMessageFrame:IsShown() and DebindMessageFrame.topic == name) then
        DebindMessageFrame:Hide();
        return;
    end
    DebindUI.ShowHelp(name);
end
