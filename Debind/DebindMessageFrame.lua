local _, DebindPrivate = ...;
local LLL = DebindPrivate.L;

--- **여는 함수는 `DebindUI`에 건다.** `DebindPrivate`는 코어의 표이고 여기 있는 것은 전부 UI라,
--- 창 하나 여는 일이 거기 설 자리가 없다. `ActionMenu`와 `Store`도 각자 자기 표를 갖는다.
local DebindUI = DebindPrivate.DebindUI;

--- 긴 글 한 편을 띄우는 창. 창이 무엇으로 되어 있는지는 `DebindMessageFrame.xml`에 있고, 여기
--- 있는 것은 **무엇을 띄우느냐**뿐이다.
---
--- **창 밖에 산다.** 이 창은 메인 창을 안 보고 메인 창도 이 창을 안 본다 - 지금 부르는 데가
--- 설정 패널이고, 그쪽은 메인 창이 서 있지 않아도 열린다(`breaking-up-debindui.md`의
--- "창보다 위로 올릴 것").
---
--- **`.toc`에서 이 파일이 XML보다 먼저다.** XML의 `mixin=`이 이 파일의 전역을 프레임 만드는
--- 시점에 찾으므로, 뒤에 서면 "Unknown method OnLoad"가 난다. 실제로 한 번 났다.
DebindMessageFrameMixin = {};

function DebindMessageFrameMixin:OnLoad()
    -- `BasicFrameTemplate`이라 초상화가 없다. 제목도 `SetTitle`이 아니라 `TitleText`다.
    self.TitleText:SetText(LLL["ADDON_NAME"]);
    self:RegisterForDrag("LeftButton");
    self:SetScript("OnDragStart", self.StartMoving);
    self:SetScript("OnDragStop", self.StopMovingOrSizing);

    -- ESC는 게임의 그물에 맡긴다. 이유는 `DebindUI.lua`의 `DebindDialogMixin:InitDialog` 주석에.
    --
    -- **`HandleEscape`의 칸도 `OnDialogHide`도 일부러 없다.** 그 둘은 메인 창이 자기 아래 것의
    -- 수명을 쥐는 장치인데 이 창은 메인 창 밖에 산다. 그래서 `CloseSpecialWindows`가 떠 있는
    -- 것을 전부 닫는 탓에 ESC 한 번이 이 창과 메인 창을 같이 닫는데, 그것을 고치려면 둘을
    -- 엮어야 하므로 안 한다. 끄는 길은 띄운 그 버튼이다 (code review, 2026-09-11).
    tinsert(UISpecialFrames, self:GetName());
end

local CONTENT_WIDTH = 452;
local INDENT = 20;
local MARKER_GAP = 4;

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

--- Swap the title and the body in. The body is cut into blocks (`ParseHelpText`) and each gets a
--- FontString of its own; an item's marker gets a second one, so a wrapped line stands under the
--- item's text and not under its number.
---
--- **The body is `GameFontNormal`, gold.** In `GameFontHighlight` its colour would be
--- `HIGHLIGHT_FONT_COLOR`, and every word a page picks out in that colour would stop standing out.
---
--- **The content frame's height is set here.** Without it `ScrollFrame` sees nothing to scroll
--- and puts up no bar.
---
--- **Back to the top every time.** A position scrolled to on a long page, kept for a short one,
--- opens on an empty window.
function DebindMessageFrameMixin:SetMessage(title, body)
    self.Title:SetText(title);
    self.bodyStrings = self.bodyStrings or {};

    local used, y, previous = 0, 0, nil;
    for _, block in ipairs(DebindPrivate.ParseHelpText(body)) do
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
        fontString:SetFontObject(block.kind == "heading" and GameFontHighlightMedium or GameFontNormal);
        fontString:SetJustifyH("LEFT");
        fontString:SetWidth(CONTENT_WIDTH - x);
        fontString:SetText(block.text);
        fontString:SetPoint("TOPLEFT", x, -y);

        y = y + fontString:GetStringHeight();
        previous = block;
    end

    for i = used + 1, #self.bodyStrings do
        self.bodyStrings[i]:Hide();
    end

    self.ScrollFrame.Content:SetHeight(max(1, y));
    self.ScrollFrame:SetVerticalScroll(0);
end

--- 본문 안의 링크. `link`는 우리가 심은 값 그대로 오고, `text`는 번역과 색이 섞인 화면 문자열
--- 이라 갈래를 타는 데 쓰지 않는다.
function DebindMessageFrameMixin:OnHyperlinkClick(link)
    local topic = link and link:match("^debind:help:(.+)$");
    if (topic) then
        DebindUI.ShowHelp(topic);
    end
end

--- 도움말 한 편. 값은 로케일 열쇠이고, 이름은 `debind:help:<이름>` 링크에 그대로 들어간다.
local HELP_TOPICS = {
    ordering = { title = "HELP_ORDERING_TITLE", body = "HELP_ORDERING_BODY" },
    targeting = { title = "HELP_TARGETING_TITLE", body = "HELP_TARGETING_BODY" },
};

--- 도움말을 띄운다. 모르는 이름이면 아무 일도 안 한다 - 링크는 번역된 본문 안에 있어서 오타가
--- 이 길로 들어올 수 있고, 그때 창이 빈 채로 뜨는 것보다 안 뜨는 편이 낫다.
function DebindUI.ShowHelp(topic)
    local entry = HELP_TOPICS[topic];
    if (not entry) then
        return;
    end

    DebindMessageFrame:SetMessage(LLL[entry.title], LLL[entry.body]);
    DebindMessageFrame.topic = topic;
    DebindMessageFrame:Show();
    DebindMessageFrame:Raise();
end

--- The (i)'s press: the same page closes, any other opens. Judged by the topic on the frame and
--- not by whether it is shown, so a press while a different page is up swaps to this one.
function DebindUI.ToggleHelp(topic)
    if (DebindMessageFrame:IsShown() and DebindMessageFrame.topic == topic) then
        DebindMessageFrame:Hide();
        return;
    end
    DebindUI.ShowHelp(topic);
end
