-- Probe_CombatUI.lua
-- 일회성 프로브: "전투 중에도 창을 띄울 수 있는가" 조사의 게임 확인 배터리.
-- 결론이 나면 파일째로 지우고 TOC에서 한 줄 빼면 된다.
--
-- 사용법:
--   /debcui setup      F8에 오버라이드 바인딩을 건다(전투 밖에서 한 번). 전파 감지용
--   /debcui            배터리 실행. 전투 밖에서 한 번, 전투 중에 한 번
--   /debcui arm        PLAYER_REGEN_DISABLED 디스패치 안에서 A~C를 다시 잰다
--   /debcui esc        UISpecialFrames에 든 테스트 창을 띄운다(ESC로 닫히는지 손으로 확인)
--   /debcui keys       키보드를 켠 테스트 창을 띄운다(F8을 눌러 전파 여부를 손으로 확인)
--   /debcui close      테스트 창 둘 다 닫는다
--   /debcui last       지난 배터리 결과 다시 출력
--
-- 답하려는 것:
--   A. 전투 중 SetPropagateKeyboardInput이 실제로 먹히는가 (GetPropagateKeyboardInput으로 되읽기)
--   B. 전투 중 EnableKeyboard가 먹히는가 (IsKeyboardEnabled로 되읽기)
--   C. 전투 중 보호되지 않은 프레임의 Show/Hide가 먹히는가
--   D. 전투 중에도 OnKeyDown이 들어오는가, 그리고 그 키가 바인딩으로 전파되는가
--   E. 전투 중 UISpecialFrames + ESC로 창이 닫히는가
--   F. 막힐 때 ADDON_ACTION_BLOCKED가 나오는가, 아니면 조용한가
--
-- 전부 이 파일이 자기가 만든 프레임에만 한다. Debind의 프레임도 블리자드 프레임도 안 건드린다.
-- 유일한 예외가 `/debcui setup`의 오버라이드 바인딩인데, owner가 이 파일의 프레임이라
-- `ClearOverrideBindings`로 되돌아가고 `/debcui close`가 그걸 한다.

local out = {}

local function Emit(fmt, ...)
    local line = format(fmt, ...)
    tinsert(out, line)
    print("|cff33ff99[CUI]|r " .. line)
end

--- 막힌 protected 호출은 에러를 안 던지고 ADDON_ACTION_BLOCKED로 나간다
--- (`reading-back-what-you-just-set.md`). 배터리가 도는 동안 들어온 것만 모은다.
local blocked = {}
local watching = false
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watcher:SetScript("OnEvent", function(_, event, addonName, func)
    if (not watching) then
        return
    end
    tinsert(blocked, format("%s %s / %s", event, tostring(addonName), tostring(func)))
end)

-- 배터리가 만지는 프레임. 보호되지 않은 평범한 프레임이라 우리 창과 같은 부류다.
local subject = CreateFrame("Frame", "DebindProbeCombatSubject", UIParent)
subject:SetSize(1, 1)
subject:SetPoint("CENTER")
subject:Hide()

--- 쓰고 곧바로 되읽는다. pcall은 막혀도 ok를 답하므로 판별은 되읽기뿐이다.
local function SetAndReadBack(label, setter, getter, value)
    local ok, err = pcall(setter, subject, value)
    local got = getter(subject)
    Emit("%s(%s): pcall=%s%s readback=%s -> %s",
        label,
        tostring(value),
        ok and "ok" or "ERR",
        ok and "" or (" (" .. tostring(err) .. ")"),
        tostring(got),
        (got == value) and "TOOK" or "BLOCKED")
    return got == value
end

local function RunBattery()
    wipe(out)
    wipe(blocked)
    watching = true

    Emit("---- %s / InCombatLockdown=%s ----",
        date("%H:%M:%S"), tostring(InCombatLockdown()))

    -- A. 전파 제어. 우리 창의 ESC 처리 전체가 이 한 함수에 걸려 있다.
    Emit("A. SetPropagateKeyboardInput")
    SetAndReadBack("  SetPropagateKeyboardInput", subject.SetPropagateKeyboardInput,
        subject.GetPropagateKeyboardInput, false)
    SetAndReadBack("  SetPropagateKeyboardInput", subject.SetPropagateKeyboardInput,
        subject.GetPropagateKeyboardInput, true)

    -- B. 키보드 켜기. 단축키 지정 모드가 이걸로 켜고 끈다.
    Emit("B. EnableKeyboard")
    SetAndReadBack("  EnableKeyboard", subject.EnableKeyboard,
        subject.IsKeyboardEnabled, true)
    SetAndReadBack("  EnableKeyboard", subject.EnableKeyboard,
        subject.IsKeyboardEnabled, false)

    -- C. Show/Hide. 문서상 IsProtectedFunction이지만 그건 보호된 프레임에서의 이야기라
    -- 예상은 통과다. 예상이 틀리면 조사 자체가 끝나므로 첫 칸에 둔다.
    Emit("C. Show/Hide")
    local okShow = pcall(subject.Show, subject)
    Emit("  Show(): pcall=%s IsShown=%s -> %s", okShow and "ok" or "ERR",
        tostring(subject:IsShown()), subject:IsShown() and "TOOK" or "BLOCKED")
    local okHide = pcall(subject.Hide, subject)
    Emit("  Hide(): pcall=%s IsShown=%s -> %s", okHide and "ok" or "ERR",
        tostring(subject:IsShown()), (not subject:IsShown()) and "TOOK" or "BLOCKED")

    -- F. 위 셋 중 무엇이 막혔는지 이벤트 쪽으로도 본다.
    if (#blocked == 0) then
        Emit("F. ADDON_ACTION_BLOCKED: 없음")
    else
        for _, line in ipairs(blocked) do
            Emit("F. %s", line)
        end
    end

    watching = false
end

-- ---------------------------------------------------------------------------
-- D. 키 입력이 들어오는가 / 그 키가 전파되는가
--
-- 전파 감지는 오버라이드 바인딩 하나로 한다. `/debcui setup`이 전투 밖에서 F8을 숨은 버튼에
-- 걸어두면, 전투 중에 F8을 눌렀을 때
--   "OnKeyDown F8"만 뜨면      전파가 끊긴 것(SetPropagateKeyboardInput(false)가 먹혔다)
--   "BINDING FIRED"까지 뜨면   전파된 것(키를 못 먹는다)
-- 이다. 창이 안 떠 있을 때 F8은 그냥 BINDING FIRED만 낸다 - 그게 기준선이다.
-- ---------------------------------------------------------------------------

local bindTarget = CreateFrame("Button", "DebindProbeCombatBindTarget", UIParent,
    "SecureActionButtonTemplate")
bindTarget:Hide()
bindTarget:SetScript("PreClick", function()
    print("|cffffff00[CUI]|r BINDING FIRED (F8이 바인딩까지 갔다)")
end)

local keyFrame = CreateFrame("Frame", "DebindProbeCombatKeyFrame", UIParent,
    "BackdropTemplate")
keyFrame:SetSize(320, 90)
keyFrame:SetPoint("CENTER", 0, 160)
keyFrame:SetFrameStrata("DIALOG")
keyFrame:EnableKeyboard(true)
keyFrame:SetPropagateKeyboardInput(false)
keyFrame:Hide()
keyFrame.text = keyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
keyFrame.text:SetPoint("CENTER")
keyFrame.text:SetText("CUI keys: F8을 눌러라 (ESC는 이 창을 안 닫는다)")
keyFrame:SetScript("OnKeyDown", function(self, key)
    print(format("|cff33ff99[CUI]|r OnKeyDown %s (combat=%s propagate=%s)",
        key, tostring(InCombatLockdown()), tostring(self:GetPropagateKeyboardInput())))
end)

-- ---------------------------------------------------------------------------
-- E. UISpecialFrames가 전투 중에도 ESC로 창을 닫는가
--
-- `CloseSpecialWindows`는 블리자드 코드에서 `frame:Hide()`를 부르고, 이 프레임은 보호된
-- 프레임이 아니다(UIParentPanelManager.lua:1038). 그러니 통해야 하는데, 통하는지를 재는 게
-- 이 창이다. 키보드를 안 켜므로 ESC는 오로지 그 경로로만 여기 닿는다.
-- ---------------------------------------------------------------------------

local escFrame = CreateFrame("Frame", "DebindProbeCombatEscFrame", UIParent,
    "BackdropTemplate")
escFrame:SetSize(320, 90)
escFrame:SetPoint("CENTER", 0, 40)
escFrame:SetFrameStrata("DIALOG")
escFrame:Hide()
escFrame.text = escFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
escFrame.text:SetPoint("CENTER")
escFrame.text:SetText("CUI esc: ESC로 이 창이 닫히나?")
escFrame:SetScript("OnHide", function()
    print(format("|cff33ff99[CUI]|r esc 창이 닫혔다 (combat=%s)",
        tostring(InCombatLockdown())))
end)
tinsert(UISpecialFrames, "DebindProbeCombatEscFrame")

local function Backdrop(frame)
    if (frame.SetBackdrop) then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end
end
Backdrop(keyFrame)
Backdrop(escFrame)

-- ---------------------------------------------------------------------------
-- arm: PLAYER_REGEN_DISABLED 디스패치 안에서 다시 잰다.
--
-- 그 자리에서는 아직 안 잠겨 있다는 것이 이미 나와 있으므로
-- (`memory/not-locked-yet-at-regen-disabled`), 여기서 A가 TOOK이면 "전투 들어가는 순간
-- 전파 상태를 정상값으로 되돌려 놓을 수 있다"가 된다. 그게 되면 전투 중 창을 띄우는
-- 설계가 성립한다.
-- ---------------------------------------------------------------------------

local armed = CreateFrame("Frame")
armed:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    Emit("== PLAYER_REGEN_DISABLED 디스패치 안 ==")
    RunBattery()
    -- 그리고 잠긴 뒤에 한 번 더. 위와 갈리면 그 사이가 경계다.
    C_Timer.After(1, function()
        Emit("== 전투 시작 1초 뒤 ==")
        RunBattery()
    end)
end)

SLASH_DEBCUI1 = "/debcui"
SlashCmdList["DEBCUI"] = function(msg)
    msg = strtrim(msg or ""):lower()

    if (msg == "setup") then
        if (InCombatLockdown()) then
            print("|cffff0000[CUI]|r setup은 전투 밖에서만 된다")
            return
        end
        ClearOverrideBindings(bindTarget)
        SetOverrideBindingClick(bindTarget, true, "F8", "DebindProbeCombatBindTarget")
        print("|cff33ff99[CUI]|r F8 오버라이드 걸었다. 창 없이 F8을 눌러 기준선부터 확인해라")
        return
    end

    if (msg == "arm") then
        armed:RegisterEvent("PLAYER_REGEN_DISABLED")
        print("|cff33ff99[CUI]|r 다음 전투 진입에서 잰다")
        return
    end

    if (msg == "esc") then
        escFrame:Show()
        print("|cff33ff99[CUI]|r esc 창을 띄웠다. ESC를 눌러봐라")
        return
    end

    if (msg == "keys") then
        keyFrame:Show()
        print("|cff33ff99[CUI]|r keys 창을 띄웠다. F8을 눌러봐라. 끄려면 /debcui close")
        return
    end

    if (msg == "close") then
        keyFrame:Hide()
        escFrame:Hide()
        if (not InCombatLockdown()) then
            ClearOverrideBindings(bindTarget)
            print("|cff33ff99[CUI]|r 창을 닫고 F8 오버라이드도 거뒀다")
        else
            print("|cff33ff99[CUI]|r 창은 닫았다. F8 오버라이드는 전투 밖에서 거둔다")
        end
        return
    end

    if (msg == "last") then
        for _, line in ipairs(out) do
            print("|cff33ff99[CUI]|r " .. line)
        end
        return
    end

    RunBattery()
end
