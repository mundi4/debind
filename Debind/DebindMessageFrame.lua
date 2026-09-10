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
    tinsert(UISpecialFrames, self:GetName());
end

--- 제목과 본문을 갈아 끼운다.
---
--- **본문 프레임 높이를 여기서 잡는다.** 스크롤 폭은 XML이 정하지만 높이는 글이 정하고, 그
--- 값이 없으면 `ScrollFrame`이 스크롤할 것이 없다고 보고 막대를 안 세운다.
---
--- **매번 맨 위로 돌린다.** 다른 글을 띄우면서 앞 글에서 굴려둔 자리를 그대로 두면, 짧은 글을
--- 열었을 때 빈 화면이 뜬다.
function DebindMessageFrameMixin:SetMessage(title, body)
    local content = self.ScrollFrame.Content;
    self.Title:SetText(title);
    content.Body:SetText(body);
    content:SetHeight(max(1, content.Body:GetStringHeight()));
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
};

--- 도움말을 띄운다. 모르는 이름이면 아무 일도 안 한다 - 링크는 번역된 본문 안에 있어서 오타가
--- 이 길로 들어올 수 있고, 그때 창이 빈 채로 뜨는 것보다 안 뜨는 편이 낫다.
function DebindUI.ShowHelp(topic)
    local entry = HELP_TOPICS[topic];
    if (not entry) then
        return;
    end

    DebindMessageFrame:SetMessage(LLL[entry.title], LLL[entry.body]);
    DebindMessageFrame:Show();
    DebindMessageFrame:Raise();
end
