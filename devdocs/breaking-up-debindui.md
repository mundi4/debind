# DebindUI.lua를 가른다 (2026-08-18 초안)

> 상태: **초안이다. 방안만 늘어놓았고 고른 것은 없다.**
>
> 전제 넷은 대화에서 이미 정해졌다(아래 "정해진 전제"). 방안 넷은 그 전제 위에서 어디까지
> 갈 것인가만 다르다.
>
> ~~**`fixing-what-the-review-found.md`를 먼저 읽어라.** 아직 둘이 열려 있고 그중 하나가 여기서
> 옮길 파일에 산다.~~ **풀렸다**(2026-08-20). 남아 있던 하나는 `Import.lua`에 살아서 여기서 옮길
> 파일과 겹치지 않았고, 그것까지 닫히면서 그 문서는 지워졌다.
>
> ~~**툴팁 작업(`sharing-one-action-tooltip.md`)도 먼저다.**~~ **끝났다**(2026-08-19에 `legacy/`로
> 갔다). `DebindUI.lua`에서 426줄이 이미 나갔으니 여기서 옮길 것이 그만큼 줄었다.

`Debind/DebindUI.lua`는 6274줄이고 리포에서 두 번째로 큰 파일의 세 배가 넘는다. 믹스인 열넷과
파일 지역 함수 예순몇 개가 한 스코프를 공유한다.

## 문제 셋

**1. 창이 열을 겸직한다.** 오른쪽 레이어 열에는 자기 믹스인이 없고, 그 열의 행동이 전부
`DebindFrameMixin`에 붙어 있다. `InitializeSideTabs`, `UpdateSideTabs`, `UpdateActionCounts`,
`InitializeScrollBox`, `Refresh`, `SetSelectedAction`, `ToggleActionSelected`, `SelectRangeTo`,
`ScrollActionIntoView`, `FindElementDataByActionInfo`, `UpdateListStrip`. 왼쪽 순서 열은
`DebindResultPanelMixin`을 갖고 있어서, 두 열이 비대칭이다. 이건 코드에 이미 적혀 있다
(`DebindUI.lua`의 "`OverviewPanel`과 `LayerPanel`에 믹스인이 없고 그것이 finding이다").

**2. 참조가 안 보인다.** 두 열이 서로를 부르는 자리가 실제로는 좁은데, 한 스코프라서 그게
드러나지 않는다. 세어보면 밖에서 `DebindResultPanel`을 만지는 것은 `:Refresh()`, `:Close()`,
`:RefreshKeyboard()`, 그리고 `.BindOverlay` 넷뿐이다. 반대 방향은 `GoToAction` 하나이고 그것도
창을 거친다. 경계는 거의 그어져 있는데 경계라고 부를 수가 없는 상태다.

**3. 죽은 코드를 가릴 수가 없다.** 이번 회차에만 넷이 나왔고 전부 우연히 나왔다.

- `showLayerIcons`: 읽는 데 둘, 세우는 데 없음. 통 목록 툴팁의 범위 줄과 아이콘 자리 코드가
  통째로 도달 불가. **지운다고 이미 정해졌다.**
- `DebindLineTemplate`의 `TopBorder` / `BottomBorder`: `hidden`으로 선언만 되고 켜는 코드 없음.
  묶어둔 `parentArray="Textures"`도 읽는 데 없음.
- `DebindOrderLineTemplate`의 "층 칸" 주석: 그 템플릿에 `LayerIcon`이 하나도 없다. 설명만 남았다.
- 툴팁 호버 블록 맨 앞의 `wipe(_lines)`: 그 블록은 `_lines`를 안 쓴다
  (`sharing-one-action-tooltip.md`가 먼저 찾았다).

**왜 안 잡히나.** luacheck의 unused 경고는 지역 변수만 본다. 위 넷은 전부 테이블 필드이거나
XML 리전이라 경고가 안 난다. 그리고 스코프가 6274줄이라 "이거 읽는 데 있나"를 물으려면 파일
전체를 훑어야 하고, 훑어서 없다는 것이 곧 없다는 뜻인지도 확신이 안 선다.

## 정해진 전제

**1. UI 코드는 분리가 선명해야 한다.** 성능에 민감하지 않아서 지역 변수를 함수 호출로 바꾸는
대가가 0이고, 서로 참조하기 시작하면 순식간에 지저분해지며, `npm run check`가 UI를 못 보므로
디버깅에서 기댈 것이 코드 모양뿐이다.

**2. 자립해야 분리한 것이다.** 상대 열이 없어도 서는가가 기준이다. 확인하는 방법은 그 파일을
빼면 그 열만 없어지고 창은 열리는가. Export와 Import 패널이 이미 그 기준을 통과한다. 각자
`.lua`와 `.xml`을 갖고 `parent=` + `parentKey=`로 `DebindFrame`의 자식으로 앉는다.

**자립은 코드 의존이 없다는 뜻이지 화면에서 혼자 쓸모 있다는 뜻이 아니다.** 순서 열은 오른쪽에서
고른 액션의 키 그룹을 답하는 열이라 아무것도 안 골랐으면 비어 있는 것이 원래 동작이다. 이 구분을
안 해두면 "혼자서는 의미가 없으니 못 가른다"로 미끄러진다.

**3. 자립 가능한 것만 분리하고, 아니면 부모로 올린다.** 두 열이 함께 쓰는 것은 창으로, 창 밖에서도
쓰는 것은 창보다 위로 올린다.

**4. 열끼리는 서로의 이름을 모른다.** 열은 창에게 묻고 창이 열에게 다시 그리라고 한다. 검사는
grep으로 된다. **열 파일 안에 다른 열의 이름이 한 번도 안 나오면 통과다.**

## 무엇이 어디로 가는가

전제 3을 적용하면 이렇게 갈린다. 어느 방안을 고르든 이 분류는 같다.

**자립함 (뗄 수 있음)**

- 오른쪽 열: `DebindLineMixin`, `DebindTabMixin`, `DebindSideTabMixin`, 자기 스크롤박스,
  `BuildSortedElements`
- 왼쪽 열: `DebindResultPanelMixin`, `DebindOrderLineMixin`, `DebindKeyHeaderMixin`,
  `BuildKeyboardElements`
- 창 단위 대화상자 셋: `DebindIconSelectorFrameMixin`(165줄), `DebindMacroFrameMixin`(230줄),
  `DebindMigrationDialogMixin`(120줄)

**창으로 올릴 것 (열이 혼자 못 듦)**

- 선택, 필터, 검색어, 지금 탭. 지금은 파일 지역 변수다
- 지정 모드와 키 잡기(670줄). 두 열을 다 만진다. **`KeyCapture.lua`가 이미 있고 그 창의
  믹스인이 거기 산다.** `BeginKeyCapture`, `SetActionKey`, `GiveKeyGroupTheKey`,
  `ShowKeyGroupConflictDialog`가 이쪽에 남아 있는 것이 오히려 갈라진 상태다

**창보다 위로 올릴 것 (오버뷰 밖에서도 씀)**

- `GetLayerID`, `GetLayerLabel`, `GetLayerShortName`, `IsLayerOffWorld`, `GetSideTabIcon`
- `NameAndIconForAction`, `ColoredNameAndIconForAction`, `SetActionIcon`. 지금도 `DebindUI`
  테이블에 올라가 있어서 Export가 부른다
- 액션 툴팁. 저쪽 작업이 `DebindPrivate.AddActionToTooltip`으로 올리는 중이다

**순서가 하나로 정해진다.** 올릴 것을 먼저 올리고, 그 다음에 자립한 것만 파일로 뗀다. 뒤집으면
뗀 파일이 남의 지역 변수를 찾다가 그 자리에서 급조하게 된다.

## 방안

### A. 믹스인만 만들고 파일은 안 가른다

`DebindLayerPanelMixin`을 세우고 위 "창이 열을 겸직한다"의 메서드들을 옮긴다. 파일은 그대로
6274줄.

- 산다: 문제 1이 없어진다. 두 열이 대칭이 되고, 무엇이 창의 일이고 무엇이 열의 일인지가 읽힌다
- 안 산다: 문제 2와 3. 한 스코프라 참조도 죽은 코드도 여전히 안 보인다
- 값: 싸다. 옮기는 것뿐이고 동작이 안 바뀐다
- **어느 방안을 고르든 이건 먼저 한다.** B와 C의 0단계이기도 하다

### B. 자립한 것만 뗀다, 두 열은 그대로

대화상자 셋과 지정 모드와 툴팁을 각자 파일로 뺀다. 오버뷰 두 열은 `DebindUI.lua`에 남는다.

- 나가는 양: 1600줄쯤. 지정 모드 670 + 툴팁 426 + 대화상자 515
- 산다: 파일이 4600줄대로 내려간다. 뺀 것들은 경계가 이미 그어져 있어서 위험이 낮다.
  지정 모드는 갈 파일이 있고, 툴팁은 저쪽 작업이 만들어 준다
- 안 산다: 두 열의 문제 1, 2, 3이 그대로 남는다. 제일 얽힌 부분을 안 건드린 것이다
- 값: 싸고 안전하다. A와 겹치지 않아서 같이 해도 된다

### C. 두 열을 각자 파일과 XML로 완전 분리

Export/Import와 같은 모양으로 짓는다. `OverviewPanel` 컨테이너는 남기고 두 열이 그 자식으로
각자 파일에서 앉는다. 공유 상태는 창 소유가 되고, 열은 두 통로로만 창과 말한다.

- **당김**: `DebindOverviewColumnMixin`을 두 열이 함께 쓴다. `GetCurrentSelection()`,
  `IsActionSelected()`, `PassesFilters()`, `GetSearchText()`, `IsNarrowed()`,
  `GetCurrentLayerID()`. 소유자는 `OnLoad`에서 한 번 잡는다. 그래서 **열 파일 안에 창의 이름이
  한 번도 안 나온다**
- **밀기**: 창이 상태를 바꾸고 한 번 쏜다. `OnSelectionChanged`, `OnFilterChanged`,
  `OnProfileChanged`, `OnKeyGroupChanged`, `OnLayerChanged`, `OnBindModeChanged`. 열은 자기가
  듣고 싶은 것만 구현한다
- 산다: 문제 1, 2, 3 전부. 그리고 `DebindResultPanel.BindOverlay`를 밖에서 켜던 규칙 위반이
  왼쪽 열의 `OnBindModeChanged(active)`로 저절로 없어진다
- 값: 제일 비싸다. 아래 "C의 위험" 참고

### D. 컨테이너까지 내리고 창은 껍데기만

C에 더해 `OverviewPanel`도 자기 파일을 갖고, `DebindFrame`은 탭 전환과 공유 상태만 남는다.

- 산다: 창이 진짜로 창만 한다
- 안 산다: 아직 살 사람이 없다. 오버뷰 탭이 두 열로 서는 것은 화면의 사실이고 컨테이너가 그
  사실을 들고 있을 뿐이라, 지금 그것을 또 가르면 파일 하나가 늘고 얻는 것이 없다
- **C를 하고 나서 다시 재는 것이 맞다.** C가 끝난 시점에도 컨테이너에 코드가 남아 있으면 그때
  이 항목이 살아난다

## C의 위험

**1. 이벤트를 굵게 잡으면 이중 작업이 돌아온다.** `CommitSelection`에 그 경고가 이미 있다.
왼쪽 열을 거기서 다시 그리지 않는 이유가 아래 `Update`가 이미 그 일을 하기 때문이고, 둘 다
부르면 선택이 한 번 바뀔 때마다 프로필 전 레이어를 훑는 일을 두 번 한다. "뭔가 바뀜" 하나로
뭉뚱그리면 그 자리가 그대로 재발한다.

**2. 순서 의존이 숨는다.** 지금 `CommitSelection`은 `Close` 먼저, 그 다음 `Update`가 `Refresh`
라는 순서를 손으로 쥐고 있다. 이벤트로 바꾸면 그게 등록 순서가 되고, 등록 순서는 코드에 안
보인다. 옮기면서 순서가 뜻을 갖는 자리를 짚어야 하고, 있으면 그 이유를 그 자리에 적어야 한다.

**3. 검사가 못 본다.** 전부 UI다. 800줄이 움직이는데 `npm run check`가 답할 수 있는 것은 문법과
XML 참조뿐이다.

## 이벤트를 무엇으로 돌리나

**블리자드의 `CallbackRegistryMixin`을 창에 섞는다.** 등록 목록을 손으로 돌릴 이유가 없다.
`EventRegistry`가 바로 그 믹스인의 전역 인스턴스이므로, 같은 기계를 우리 창에만 있는 사설
버스로 쓰는 것이다. 전역 버스를 피하자던 이유는 기계가 아니라 전역이었다.

받는 것: `RegisterCallback(event, func, owner)`, `UnregisterCallback(event, owner)`,
`TriggerEvent(event, ...)`, `UnregisterEvents()`, 그리고 `HasRegistrantsForEvent(event)`.
마지막 것으로 듣는 열이 없으면 아예 안 짓게 할 수 있다.

**제일 큰 것은 `GenerateCallbackEvents(eventTable)`이다.** 이벤트 이름이
`DebindFrame.Event.OnSelectionChanged` 같은 상수가 되고, 선언 안 한 이름으로 쏘면 그 자리에서
에러가 난다(`SetUndefinedEventsAllowed`가 기본으로 막는다). **오타가 조용한 no-op이 되지
않는다.** 전제 1의 세 번째 근거가 조용한 실패였으니 여기서 그 값이 직접 나온다.

**듣는 쪽은 `CallbackRegistrantTemplate`이다.** `OnShow`/`OnHide`에 걸려서 숨을 때 등록을 끊고
다시 뜰 때 되건다(`AddDynamicEventMethod`). 두 열은 탭 전환으로 숨었다 떴다 하므로 그 성질이
그대로 쓸모가 있다. 쿨다운 관리자 설정창이 같은 방식으로 자기 목록을 갱신한다.

서는 모양은 둘이다.

- **창**: `CallbackRegistryMixin`을 섞고 `OnLoad`에서 `GenerateCallbackEvents`로 여섯을 선언
- **두 열**: `CallbackRegistrantTemplate`을 물려받고 자기가 듣고 싶은 것만 등록

**`TriggerEvent`는 호출 순서를 보장하지 않는다.** 위 "C의 위험" 2번이 여기서 더 분명해진다.
순서에 기대는 자리는 이벤트로 옮기면 안 된다.

## 죽은 코드를 어떻게 다시 안 쌓나

가르는 것만으로는 절반이다. 스코프가 작아지면 luacheck의 unused 경고가 실제로 일하기 시작하지만,
**테이블 필드와 XML 리전은 여전히 안 잡힌다.** 이번에 나온 넷 중 셋이 그것이다.

그래서 정적 검사를 하나 더 다는 안이 있다. **XML에 `parentKey`로 선언됐는데 Lua 어디서도 안
읽히는 리전**을 찾는 검사다. `tools/check-xml-methods.js`가 `method=` 대상이 실재하는지 보는
것과 같은 종류이고, 그 선례가 이미 있다.

이번 넷 중 `TopBorder`, `BottomBorder`, `LayerIcons`가 그 검사에 걸린다. `showLayerIcons`는
XML 리전이 아니라 elementData 필드라 안 걸린다. 그건 스코프가 줄어야 보인다.

**아직 안 정했다.** 오탐이 얼마나 나오는지 모른다. 문자열로 조합해 읽는 자리
(`self.LayerIcons[i]`, `_G["..." .. i]`)가 있으면 그것부터 세어봐야 한다.

## 검증

`npm run check`가 못 보는 변경이다. A는 옮기기뿐이라 눈으로 네 화면을 열어보는 것으로 족하고,
C는 그것으로 부족하다.

C를 한다면 옮기기 **전에** `/debtest`에 기준선을 건다. 무엇을 걸지는 정하지 않았다. 후보는
"오른쪽 열에서 액션을 고르면 왼쪽 열이 그 키 그룹을 그린다"와 "다른 사이드탭으로 옮기면 왼쪽
열이 비워진다" 정도다.

## 안 정한 것

1. **어느 방안까지 갈 것인가.** A는 어차피 한다. B는 싸다. C가 결정이다
2. **공유 상태를 창의 무엇으로 만들 것인가.** 지금 파일 지역 변수인 것들을 `DebindFrameMixin`의
   필드로 올릴지, 별도 테이블 하나로 묶을지
3. **XML `parentKey` 미사용 검사를 만들 것인가.** 오탐 수를 세어보고 정한다
4. **`DebindOverviewColumnMixin`이라는 이름.** `DebindOverviewPanelMixin`은 `OverviewPanel`
   이라는 프레임 이름과 겹쳐서, 컨테이너 이야기인지 그 안의 열 이야기인지가 안 갈린다

## 같이 하게 되는 것

이 작업과 같은 파일을 건드리는 것들이라 순서를 맞춰야 한다.

- `DebindLineTemplate` / `DebindLineMixin` → `DebindLayerLine*` 리네임. 이름이 "그 줄"이라
  읽히는데 그게 참이던 것은 목록이 하나였을 때다. 참조 17군데, 파일 넷, 그중 둘은 주석
- `DebindActionLineMixin`. 액션을 그리는 행 셋(`DebindLineMixin`, `DebindOrderLineMixin`,
  `DebindExportRowMixin`)이 공유하는 행동. 툴팁 `OnEnter`/`OnLeave`와 이름·아이콘 넣기.
  **Export 행만 `ColoredNameAndIconForAction`을 안 써서 색 규칙이 없다**
- 28px 한 줄 행의 밑판 템플릿, 그리고 `ORDER_LINE_INDENT`/`ROW_INDENT`와
  `ORDER_LINE_HEIGHT`/`ROW_HEIGHT`를 한 곳으로
