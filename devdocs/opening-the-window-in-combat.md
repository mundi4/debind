> 상태: 조사가 끝났고 구현은 아직 없다. 걸리는 protected 호출은 없다는 것이 결론이고, 그 근거와
> 바꿔야 할 자리는 아래가 든다. 무엇을 재서 알았고 무엇을 코드로 알았는지는 §5가 나눈다.

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

전파를 true로 못박으면 창은 키를 받되 아무것도 안 먹는다. `OnKeyDown`은 "이번 프레임에 ESC가
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

**스위치 토글은 전투 중 비활성으로 남는다.** 그것을 전투 중에 눌리게 하려면 secure 버튼이어야
하는데, 그러면 보호된 프레임이 창 안에 들어와서 창을 전투 중에 여닫는 것 자체가 막힌다.
`SwitchesUI.xml`이 이미 그 선택을 적어두었고, 이 조사는 그 근거를 하나 더 얹는다.

지금 창이 보호된 자식을 하나도 안 갖고 있다는 것은 확인했다. UI XML 다섯 개에 secure 템플릿을
상속하는 프레임이 없고, secure 프레임을 만드는 자리는 부모가 `nil`이거나 자기네 secure
프레임이다. `Debind/` 전체에 `SetParent` 호출이 없어서 나중에 밑으로 들어올 길도 없다.

## 7. 바꿀 자리

1. `BindMode_OnKeyDown`의 `SetPropagateKeyboardInput` 두 줄을 뺀다.
2. 메인 창의 `OnKeyDown`을 ESC 도장 하나로 줄이고, 전파는 로드 때 true로 한 번만 세운다.
3. 창을 `UISpecialFrames`에 넣고, `OnHide`에서 우리 닫기와 남의 닫기를 도장으로 가른다. 남이
   닫았으면 되열고, 그것이 ESC였으면 사다리를 돌린다.
4. 우리 닫기 넷을 한 자리로 모은다.
5. `_pickedupInfo`를 걷어내고 §4의 갈래를 고른다.
6. `OnEnterCombat`의 `Hide()`와 `ToggleUI`의 전투 거절을 걷어낸다.
7. 창이 전투에 숨는다는 전제 위에 선 가드들을 다시 본다(`SpellPicker.lua`의 두 자리와 그 우클릭
   메뉴). 액션 추가가 전투 중에 허용되는지는 리빌드 예약이 답한다.
