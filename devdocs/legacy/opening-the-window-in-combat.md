> 상태 (2026-09-09): **닫혔다. §7의 일곱 자리가 전부 들어갔다.** 설계대로 안 간 자리 둘은
> §8이 든다 - 공유 대화상자도 `UISpecialFrames`에 있었다는 것과, 전파를 세우라던 "로드 때"라는
> 자리가 이 창에는 없었다는 것. 무엇을 재서 알았고 무엇을 코드로 알았는지는 §5가, 테스트가
> 무엇을 덮고 무엇을 원리상 못 보는지는 §9가 나눈다.

# 전투 중에도 창을 띄우기

지금은 전투가 시작되면 창이 숨고(`DebindFrameMixin:OnEnterCombat`), 전투 중에는 열리지도 않는다
(`Public.lua`의 `ToggleUI`). 바인딩 리빌드는 어차피 전투가 끝나는 이벤트에 예약되므로, 창이 떠
있는 것 자체는 리빌드와 무관하다. 막고 있던 것은 키보드 배관 하나였다.

## 1. 유일한 걸림돌은 `SetPropagateKeyboardInput`이었다

프레임 API 문서에서 이 함수만 `HasRestrictions = true`를 달고 있다(`SimpleFrameAPIDocumentation.lua`).
`SimpleFrame`의 함수 중 이 태그를 단 것은 이것 하나뿐이고, 프레임이 보호되었는지와 무관한 전역
제약이다.

같은 문서에서 `EnableKeyboard`, `Show`, `Hide`, `SetScale`은 `IsProtectedFunction = true`인데 그것은
**보호된 프레임**에서만 걸리는 부류다. 우리 창에는 보호된 자식이 하나도 없다(§4).

우회로도 없다. 제한 환경의 HANDLE 메서드에 `EnableKeyboard`는 있고
`SetPropagateKeyboardInput`은 없다(`RestrictedFrames.lua`). 스니펫으로 우회할 수 없다.

## 2. 세 자리 모두 그 호출을 없앨 수 있다

전파 값은 프레임에 남는 상태값이고 기본값은 false다. 즉 "받은 키를 먹는다"가 기본이다.

**캡처 창**(`KeyCapture.lua`)은 이미 호출이 없다. 키 하나를 받아 지정하고 닫히는 동안 답이 언제나
"먹는다"이고, 그게 기본값이라 아무것도 안 부른다. 지금 그대로 돌고 있는 것이 이 방식이 성립한다는
증거다.

**벌크 모드**도 답이 모드 내내 false 하나다. 그런데 `BindMode_OnKeyDown`이 키마다 false를 쓰고
있는데(`DebindUI.lua`), 그것은 바로 위 줄이 모드가 꺼진 상태에서 true로 올리기 때문이다. 그 true
줄은 도달 경로가 없다. `SetBindingMode(false)`가 같은 호출 안에서 `EnableKeyboard(false)`를 같이
하므로, 모드가 꺼진 동안 그 버튼에는 키가 들어오지 않는다. **두 줄을 다 빼면** 값이 기본값에서
움직이지 않고 캡처 창과 같은 모양이 된다.

지금 모양은 전투에서 조용히 틀린다. 전투 가드가 false 쓰기를 건너뛰는데 그 직전에 true가 올라가
있을 수 있고, 그러면 전투 중에 켠 모드에서 키가 지정도 되고 원래 바인딩도 같이 발동한다.

**메인 창**만 사정이 다르다. 창은 ESC를 받으려고 키보드를 켜둔 채라 모든 키가 창을 먼저 지나고,
답이 키마다 갈린다. ESC면 먹고 나머지는 흘려야 한다. 고정하면 한쪽은 ESC 한 번에 창이 접히면서
게임메뉴까지 뜨고, 다른 쪽은 창이 떠 있는 동안 이동키까지 전부 먹혀서 캐릭터가 안 움직인다.

## 3. 메인 창은 흘리기로 고정하고 ESC는 `UISpecialFrames`로 받는다

전파를 true로 못박으면 창은 키를 받되 아무것도 안 먹는다. **못박는 자리는 Lua가 아니라 XML의
`propagateKeyboardInput` 속성이다**(§8-2). `OnKeyDown`은 "이번 프레임에 ESC가
눌렸다"를 남기는 신호로만 쓴다. `GetTime()`은 한 프레임 동안 상수이므로 그 도장 하나로 충분하다.

ESC 자체는 `UISpecialFrames`가 받는다. `CloseSpecialWindows`가 등록된 프레임을 `Hide()`하고
(`UIParentPanelManager.lua:1038`), 그 `Hide`가 우리 `OnHide`를 태운다. 그러니 훅이 필요 없다.
`OnHide`에서 도장을 보고 되열면서 사다리를 대신 돌린다.

성립하는 순서 근거가 하나 있다. 창의 `OnKeyDown`이 `ToggleGameMenu`보다 먼저 돈다는 것은 지금
동작이 증명한다. 반대였다면 ESC로 창을 닫을 때마다 게임메뉴가 떴을 것이다.

딸려오는 이득이 둘이다.

- `CloseSpecialWindows`가 `found`를 돌려주므로 `TryHandleGameMenuEsc`가 참을 받고 게임메뉴가 안
  뜬다.
- 더 높은 우선순위 핸들러가 ESC를 먼저 가져가면(`StaticPopup`, 시전 중) `CloseSpecialWindows`가
  아예 안 돌아서 창이 그대로 남는다. `BlizzardOwnsEscape`가 손으로 하던 양보가 저절로 따라온다.

딸려오는 비용도 있다. `UISpecialFrames`의 그물은 ESC 전용이 아니라서, `ShowUIPanel` 경로도
`CloseWindows`를 지나며 `CloseSpecialWindows`를 태운다. P로 주문서를 열면 창이 같이 닫힌다. 이것을
가르려면 우리 닫기에 도장을 찍어 `OnHide`에서 남이 닫은 것과 구분해야 한다. 우리 닫기는 X 버튼,
`ToggleUI`, `OnEnterCombat`, 사다리 바닥 넷이고, X 버튼은 `onCloseCallback`이 자리를 내준다
(`SharedUIPanelTemplates.lua`의 `UIPanelCloseButton_OnClick`).

### 못 쓰는 길 둘

**`RegisterGameMenuEscHandler`**는 등록만으로 블리자드의 ESC 경로가 우리 taint를 뒤집어쓴다.
이유는 `DebindFrameMixin:OnLoad`의 주석이 든다.

**`CloseAllWindows`에는 `hooksecurefunc`이 안 먹는다.** ESC 핸들러가 등록 시점에 함수 **값**을
붙잡아 두는데(`UIParentPanelManager.lua:1106`) `hooksecurefunc`은 전역만 갈아끼우기 때문이다.
ESC는 붙잡아 둔 원본으로 가고 훅은 안 돈다. 그래서 ESC와 `ShowUIPanel`을 그 함수로는 못 가른다.

## 4. 커서에 든 액션

블리자드의 ESC 핸들러 중 커서를 비우는 칸은 없다. 등록된 핸들러 전부를 훑었고, 제일 가까운 것이
`Casting` 우선순위의 `SpellStopTargeting()`인데 그것은 시전 대상 지정 커서지 액션을 집어 든
커서가 아니다. 즉 ESC를 흘려도 집어 든 액션은 그대로 남는다.

사다리 첫 칸(`GetActionTypeAndValueFromCursorInfo`를 보고 `ClearMouse`)은 그러므로 우리가 만든
규칙이다. 근거는 있다. 우리 창에서 커서에 든 것은 화면 상태를 만든다. `_pickedupInfo`가 서고
목록에 떨굴 자리가 빛나므로, 물러날 화면이 실제로 있다.

그런데 `_pickedupInfo`는 **값을 읽는 곳이 없다.** `{ type, value }`로 세우고 지우기만 하고, 쓰는
자리는 글로우를 켤지 정하는 `~= nil` 하나뿐이다. 떨구는 쪽은 이미 그 시점에 커서에서 직접 읽는다.
그러니 그 변수는 `GetActionTypeAndValueFromCursorInfo()` 호출로 대체되고, 대체되면 커서와 어긋날
사본이 없어져서 ESC가 커서를 비울 이유도 같이 사라진다.

여기서 갈래가 둘인데 **둘 다 지우거나 둘 다 두거나**여야 한다. 사본만 버리면 창은 "든 것 없음"으로
그려지는데 커서에는 주문이 있고, 그것을 그대로 목록에 떨굴 수 있다.

어느 쪽이든 이 조사를 막지 않는다. 최악이 글로우가 한 박자 어긋나는 것이고, `CURSOR_CHANGED`가
다시 그릴 계기를 준다.

## 5. 무엇을 재서 알았나

**게임에서 잰 것은 하나다.** 전투 중 `EnableKeyboard`가 통한다(2026-09-09). `DebindFrame`에서
껐다 켜고 `IsKeyboardEnabled`로 되읽어 `true false true`를 받았다. 문서의 `IsProtectedFunction`이
보호된 프레임에서만 걸린다는 것이 이걸로 확인된다.

나머지는 전부 코드가 답했다. §1의 태그, §2의 `SetBindingMode` 경로, §3의 `CloseSpecialWindows`와
`RegisterGameMenuEscHandler`, §4의 핸들러 목록과 `_pickedupInfo` 사용처.

**`DebindDev/Probe_CombatUI.lua`는 남아 있고 TOC에서 주석 처리되어 있다.** 여섯 항목짜리 배터리인데
그중 다섯이 이미 답이 있는 것을 세운 칸이었다. 되살릴 값이 있는 부분은 `ADDON_ACTION_BLOCKED`를
모으면서 쓰고 곧바로 되읽는 틀 정도다.

## 6. 전투 중에도 못 하는 것

**매크로 슬롯에 쓰는 것.** 2026-09-09에 `/run` 한 줄로 쟀다. `GetNumMacros`는 전투 중에도 값을
답하는데 `CreateMacro`·`EditMacro`·`DeleteMacro`는 셋 다 조용히 아무것도 안 한다 - `pcall`은
`true`를 답하고 되읽기가 비어 있다. 읽기는 되고 쓰기만 막힌다.

닿는 자리는 `ActionDisplay.lua`의 `GetMacrotextIcon` 하나다. 임시 슬롯에 본문을 넣어보고 아이콘을
받아오는 길이라 전투 중에는 답이 없고, **저장된 아이콘이 물음표일 때만** 부른다. 그래서 전투 중에
매크로를 커스텀 매크로로 바꾸면(`ConvertToMacroText`) 그 한 칸이 물음표로 남는다. 전환 자체는
막지 않는다 - 프로필 필드만 쓰고, 원본 매크로를 읽는 `GetMacroInfo`는 전투 중에도 답하며,
막힌 결과는 캐시에 안 들어가서 전투가 끝나면 저절로 제자리로 온다. 그 "전투가 끝나면"을 실제로
그리는 것이 `OnShow`가 거는 `PLAYER_REGEN_ENABLED`다.

**스위치 토글은 전투 중 비활성으로 남는다.** 그것을 전투 중에 눌리게 하려면 secure 버튼이어야
하는데, 그러면 보호된 프레임이 창 안에 들어와서 창을 전투 중에 여닫는 것 자체가 막힌다.
`SwitchesUI.xml`이 이미 그 선택을 적어두었고, 이 조사는 그 근거를 하나 더 얹는다.

지금 창이 보호된 자식을 하나도 안 갖고 있다는 것은 확인했다. UI XML 다섯 개에 secure 템플릿을
상속하는 프레임이 없고, secure 프레임을 만드는 자리는 부모가 `nil`이거나 자기네 secure
프레임이다. `Debind/` 전체에 `SetParent` 호출이 없어서 나중에 밑으로 들어올 길도 없다.

## 7. 바꿀 자리

1. `BindMode_OnKeyDown`의 `SetPropagateKeyboardInput` 두 줄을 뺀다.
2. 메인 창의 `OnKeyDown`을 ESC 도장 하나로 줄이고, 전파는 XML 속성으로 세운다(§8-2).
3. 창을 `UISpecialFrames`에 넣고, `OnHide`에서 우리 닫기와 남의 닫기를 도장으로 가른다. 남이
   닫았으면 되열고, 그것이 ESC였으면 사다리를 돌린다.
4. 우리 닫기 넷을 한 자리로 모은다.
5. `_pickedupInfo`를 걷어내고 §4의 갈래를 고른다.
6. `OnEnterCombat`의 `Hide()`와 `ToggleUI`의 전투 거절을 걷어낸다.
7. 창이 전투에 숨는다는 전제 위에 선 가드들을 다시 본다(`SpellPicker.lua`의 두 자리와 그 우클릭
   메뉴). 액션 추가가 전투 중에 허용되는지는 리빌드 예약이 답한다.

## 8. 설계대로 안 간 자리

### 8-1. 공유 대화상자 둘

**§3이 그물의 비용을 반만 셌다.** `ShowUIPanel`이 창을 닫는 것은 봤는데, 그 그물에 **우리 대화상자
둘도 이미 들어 있다**는 것을 안 봤다. 붙여넣기 창과 복사 창은 `DebindDialogMixin:InitDialog`가
`UISpecialFrames`에 등록한다. 창까지 같은 표에 들어가면 ESC 한 번이 셋을 한꺼번에 쓸어간다.

그러면 사다리가 무의미해진다. 사다리는 "한 번 누르면 한 칸"인데, 쓸린 뒤에 도는 사다리가 보는
화면에는 대화상자가 이미 없다. 바닥까지 내려가서 창까지 닫힌다. `pairs`는 순서를 약속하지
않으므로 어느 것이 먼저 쓸릴지도 갈린다.

**답은 창에 쓴 것과 같은 표시를 대화상자에도 두는 것이다.** `CloseDialog`가 일부러 닫는 유일한
길이고, 표시 없이 닫힌 대화상자는 `OnDialogHide`가 되연다 - **메인 창이 떠 있을 때만**이다. 창이
없으면 되열 이유가 없고, 그 경우를 위해 등록이 있는 것이다(복사 창은 자기 탭보다 오래 산다).
순서는 어느 쪽이든 성립한다. 창이 먼저 쓸리면 사다리가 아직 서 있는 대화상자를 닫고, 대화상자가
먼저 쓸리면 스스로 되열린 것을 사다리가 닫는다.

딸려온 것이 하나 있다. 붙여넣기 창은 `OnShow`에서 입력칸을 비우고 있었는데, 되열리는 것만으로
반쯤 친 글이 날아간다. 비우는 일을 `Open`으로 옮겼다 - 그 창을 여는 길이 하나뿐이라 덮는 범위가
같다.

### 8-2. 닫기 도장도 시각이어야 했다

§3은 ESC 도장을 `GetTime()`으로 잡아놓고 닫기 도장은 "찍는다"고만 적었다. 그것을 세웠다 지우는
불리언으로 만들면 깨진다. 사다리 바닥이 창을 닫는 자리가 `OnHide` 안이라, 부르는 쪽에서
`Hide()` 다음 줄에 지우면 그 닫기를 읽어야 할 `OnHide`가 이미 지워진 값을 본다. 그러면 자기가
닫은 창을 남의 닫기로 읽고 도로 연다.

물어야 하는 것이 "지금 닫기 호출 안에 있나"가 아니라 **"이번 누름에서 우리가 닫기로 했나"**라서
그렇다. 프레임 단위 물음에는 프레임 단위 값이 답한다. `escAt`과 `closeAt`이 같은 꼴인 것은
같은 물음이기 때문이고, 지우는 자리가 없는 것도 그래서다.

### 8-3. "로드 때 한 번"이라는 자리가 없었다

§7-2가 전파를 로드 때 한 번 세우라고 했는데, **이 창의 `OnLoad`는 로드 때 안 돈다.** XML에
`OnLoad` 스크립트가 없어서 첫 `OnShow`가 그것을 대신 부른다. 그러니 "한 번"이 첫 열기이고, 첫
열기는 액션바에 걸어둔 매크로일 수 있다. 실제로 그렇게 잡혔다:

```
[ADDON_ACTION_BLOCKED] AddOn 'Debind' tried to call the protected function
'DebindFrame:SetPropagateKeyboardInput()'.
  [Debind/DebindUI.lua]: in function 'OnLoad'
  [C]: in function 'Show'
  [Debind/Public.lua]: in function 'ToggleUI'
  [Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua]: in function 'ParseText'
  [C]: in function 'UseAction'
```

답은 그 호출을 아예 없애는 것이다. `propagateKeyboardInput`이 XSD에 있고(`UI.xsd`), 블리자드
자신도 그 한 가지 목적의 템플릿을 그렇게 만든다(`InsecureKeyboardInputPropagatorTemplate`).
속성으로 두면 프레임이 만들어질 때 정해지고 아무한테도 안 묻는다.

**§1이 "우회로도 없다"고 적은 것은 제한 환경 쪽 이야기였다.** 스니펫에서 부를 방법이 없다는
것은 맞는데, 애초에 부르지 않는 길이 XML에 있었다. 없는 것은 우회로가 아니라 그 호출이 필요한
이유였다.

### 8-4. 되열기는 자손 전부의 `OnHide`를 태운다

되열기가 산 것은 창 하나인데, 숨는 것은 **창 아래 전부**다. 자손의 `OnHide`가 남의 쓸기마다
한 번씩 돌고, 그중 "숨었다 = 사용자가 떠났다"로 읽는 핸들러는 주문책을 여는 것만으로 무언가를
버린다. 셋이 걸렸다.

- **벌크 모드.** 토글 버튼의 `OnHide`가 `SetBindingMode(false)`를 부르는데 그건 **커밋** 경로라
  되돌릴 목록까지 사라졌다. 수명을 창의 `OnHide` 진짜 닫기 갈래로 옮겼다.
- **붙여넣기 창.** 저장 패널의 `OnHide`가 반쯤 친 글을 버렸다. 그 뜻이 서는 자리는 탭을 떠날
  때(`SelectPanel`)와 창을 닫을 때 둘이고, 각각으로 옮겼다.
- **`OnShow`가 하는 여는 일 전부.** 목록을 다시 지으면서 스크롤 자리가 날아가고, 편집 중인
  액션이 그려진 행이 아니면 매크로 편집기가 닫힌다(`DebindLayerPanelMixin:Refresh`). 되열기에
  도장(`reopenAt`)을 찍고 `OnShow`가 그것을 보면 그냥 돌아선다 - 그 갈래는 등록을 푼 적이
  없으니 다시 걸 것도 없다. 처음에는 스크롤만 지키려고 `Refresh`에 인자를 넘겼는데, 그것은
  증상 하나만 덮는 것이었다.

규칙으로 적으면 둘이다. **수명은 창이 든다** - 자손의 `OnHide`가 결정하는 것은 그 프레임 자신의
일뿐이다. 그리고 **되돌아온 것은 연 것이 아니다** - 여는 일은 여는 자리에서만 한다.

### 8-5. 벌크 모드의 키보드는 행으로 갔다

§2가 벌크 모드에서 전파 호출을 걷어내라고 했고 그것은 맞았는데, 근거가 틀렸다. 문서는 "모드가
꺼진 동안에는 키보드도 꺼져 있어서 키가 안 들어온다"고 적었는데 **그 버튼은 만들어질 때부터
키보드를 든다.** `enableKeyboard="false"`를 줘도 그렇다. 그래서 지운 전파 줄이 사실은 창이 떠
있는 동안 모든 키를 흘려보내던 줄이었고, 지우자 창이 키를 통째로 먹었다.

바로잡는 길이 둘이었다. 전파를 켜면 안 먹기는 하는데 지정한 키가 게임으로도 나가고, ESC의
뜻도 사다리에 먹힌다. 그래서 **키보드를 행으로 옮겼다** - 행이 `OnEnter`에서 켜고 `OnLeave`에서
끈다.

이쪽이 옳은 이유는 전투가 아니라 뜻이다. 지정은 **행 위에서** 하는 것이라, 행 밖에서 누른 키는
지정할 대상이 없는데도 삼켜지고 있었다. 범위를 행으로 좁히면 그 삼킴이 사라지고, 전파 호출도
한 번도 안 부르게 되어 전투 제약이 따라서 없어진다.

행 밖의 ESC는 아무도 안 먹어 바인딩으로 가고, 사다리의 `IsCapturingKey()` 칸이 그것을 취소로
받는다. 그 칸은 원래 폴백으로 적혀 있던 것인데 여기서 본래 경로가 됐다. **보장은 아니다** -
정적 팝업이나 센터 패널이 ESC를 먼저 가져가면 사다리가 안 돈다. 확실한 나가는 길은 오버레이의
[취소]와 토글 버튼이고 둘 다 마우스다.

## 9. 테스트가 무엇을 덮나

`/debtest`에 두 항목이 있다. `PressEscape`가 클라이언트가 하는 네 걸음을 그대로 편다: 도장 →
대화상자 둘 `Hide` → 창 `Hide`. **표시 없는 `Hide`가 곧 `CloseSpecialWindows`가 남기는 모양**이라,
되열기와 사다리가 한 번에 걸린다.

- **"the sharing dialogs close before the window"** - 대화상자 둘을 세워놓고 ESC 세 번. 한 번에
  하나씩, 순서대로, 창은 마지막에. §8이 막는 것이 이 항목이다.
- **"a close the window did not ask for is undone"** - 도장 없는 `Hide` 뒤에 창이 그대로인지,
  벌크 모드가 살아남는지, 대화상자가 되열리면서 친 글을 들고 오는지, 공유 탭을 띄운 채 쓸려도
  그 글이 남는지, 탭을 떠나면 비로소 닫히는지, 그리고 우리 `CloseWindow`는 여전히 닫는지.
  마지막 둘을 같이 보는 이유는 앞의 것들만으로는 틀린 이유로 통과하기 때문이다 - 무엇에도 안
  닫히는 창은 닫을 수가 없다.

**원리상 못 보는 것이 둘이다.**

- **전투 그 자체.** 키트는 전투를 만들 수 없다. "창이 전투 중에 열리고 떠 있는다"는 이 변경의
  본문인데, 그것을 확인하는 길은 사람이 전투에 들어가 보는 것뿐이다. 대신 그 자리에 남은 것이
  **`SetPropagateKeyboardInput` 호출이 하나도 없다**는 사실이고, 그건 grep이 답한다.
- **진짜 ESCAPE 키.** 키트가 도는 동안에는 게임의 바인딩이 풀려 있어서, 실제 키를 누르면 창이
  아니라 러너를 재게 된다. 그래서 `PressEscape`는 키가 아니라 그 키가 일으키는 네 걸음을 편다.
  `ToggleGameMenu`의 우선순위 사다리(§3)는 그 바깥이라 여기서 안 걸린다.

**스크롤 자리는 못 덮은 것이 아니라 안 덮었다.** 시드가 세우는 목록이 스크롤이 생길 만큼 길지
않아서, 지금 쓰면 무엇을 넣어도 통과하는 검사가 된다. 목록을 그만큼 길게 만드는 항목을 세우면
덮인다.
