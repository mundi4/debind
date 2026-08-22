# DebindUI.lua를 가른다 (2026-08-18 초안)

> 상태 (2026-08-22): **C까지 가기로 정해졌다.** 아래 방안 넷은 그 결정이 무엇을 고른 것인지
> 알아보라고 그대로 둔다.
>
> **순서는 다섯이고, 보관함 개편이 가운데 낀다** (`building-export-import.md`,
> `0-ROADMAP.md`).
>
> 1. ~~**A.** 오른쪽 열에 자기 믹스인을 준다. 싸고 옮기기뿐이다~~ **했다**(2026-08-22).
>    `DebindLayerPanelMixin`이 서고 열한 개가 그리로 갔다. 파일은 안 갈랐고 정의 자리도 안
>    옮겼다. 아래 "A를 하고 나서"
> 2. ~~**"창보다 위로 올릴 것" 셋.** 개편의 미리보기 패널이 그것들을 쓴다~~ **했다**(2026-08-22).
>    파일 셋이 `DebindUI.xml`에서 `DebindUI.lua`보다 먼저 선다. 아래 "2를 하고 나서"
> 3. **보관함 개편.** 창에 `CallbackRegistryMixin`을 섞고 그 패널이 첫 등록자가 된다
> 4. **C.** 버스가 실제로 도는 것을 보고 오버뷰 두 열을 옮긴다
> 5. **B**는 아무 때나. **D**는 C 끝나고 다시 잰다
>
> **3번이 C 앞에 서는 이유는 위험이 어디 있느냐다.** C의 위험 2번(순서 의존이 등록 순서로
> 숨는다)은 **옛 코드를 옮길 때만** 생긴다. 새로 짓는 패널에는 잃을 순서가 없으므로, 같은
> 기계를 위험이 없는 자리에서 먼저 세우고 그것이 도는 것을 보고 오버뷰로 간다.
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
- `UpdateSideTabs`의 `self.currentSpec`: 세우는 데 하나, 읽는 데 없음. 같은 줄에서 잡은 지역
  변수 `currentSpec`으로 그 함수가 다 쓴다. A를 하다 다섯 번째로 나왔고, 이것도 우연히 나왔다.

**왜 안 잡히나.** luacheck의 unused 경고는 지역 변수만 본다. 위 넷은 전부 테이블 필드이거나
XML 리전이라 경고가 안 난다. 그리고 스코프가 6274줄이라 "이거 읽는 데 있나"를 물으려면 파일
전체를 훑어야 하고, 훑어서 없다는 것이 곧 없다는 뜻인지도 확신이 안 선다.

**그런데 지역 변수도 안 잡힌다 (2026-08-22에 확인).** `.luacheckrc`의 `ignore`가 211(unused
local), 231(never accessed), 311(assigned but unused)을 전부 끄고 있다. 위 문단이 "지역 변수는
본다"고 적은 것은 luacheck의 기본값이지 이 리포의 설정이 아니다. 2번을 하다 `luatype`,
`GetSpellNameAndIconID`, `QUESTION_MARK_ICON_NUM` 셋이 옮겨간 코드를 따라 죽었는데 검사는 조용히
통과했고, 손으로 세어서 찾았다. `DebindUI.lua`의 `dump`와 `_GetKeyInfo`는 이번 작업
**전부터** 죽어 있었다. 안 지웠다.

이게 아래 "죽은 코드를 어떻게 다시 안 쌓나"의 전제를 바꾼다. 가른다고 unused가 일하기
시작하지는 않는다.

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

**이 전제를 왜 이 강도로 요구했는지가 여기 안 적혀 있었다 (2026-08-22에 소유자가 밝혔다).**
자립이 목적이 아니라 **재사용이 목적이었고 자립이 그 조건**이었다. 오른쪽 레이어 열을 가져오기·
내보내기 탭에서도 쓰려던 것이다. 적혀 있던 것은 판정 방법뿐이라, 뒤에 읽는 사람은 무엇을 재는지는
알고 왜 재는지는 몰랐다. `building-export-import.md`의 "왜 저장 포맷을 닮았나"가 기록해 둔 그
실패와 같은 모양이다.

**그리고 그 의도는 없어졌다 (2026-08-22, 소유자).** 그러니 이 두 문단은 같이 읽어야 한다. 하나만
남기면 다음 사람이 또 이유를 지어낸다. 재사용이 빠져도 자립 기준은 그대로 서는데 **근거가 갈린다.**
전제 1(성능 대가 0, 서로 참조하면 지저분해진다, 검사가 UI를 못 본다)과 문제 2·3이 재사용과
무관하게 살아 있기 때문이다. 바뀌는 것은 강도의 근거 하나다. **재사용이 목적이면 열이 부모를
모르는 것이 필수인데, 읽히는 경계가 목적이면 그건 선택이다.** C의 당김 설계는 값이 싸서 그대로
가지만, 그 조항이 무엇 위에 서 있는지는 이제 다르다.

**본보기 둘 중 하나가 곧 사라진다.** 보관함 개편이 Export와 Import 패널을 하나로 합치고, 그
하나는 **두 열짜리**가 되어 오버뷰와 같은 모양이 된다. 패널째 재사용은 아니다. 공유는
`BuildSortedElements`와 행 믹스인 층까지다.

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

**창보다 위로 올릴 것 (오버뷰 밖에서도 씀)** — **끝났다**(2026-08-22). 실제로 무엇이 어느 파일로
갔고 무엇이 안 갔는지는 아래 "2를 하고 나서"가 들고 있다. 여기 셋은 그때 무엇을 셌는지다.

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

## A를 하고 나서 (2026-08-22)

`DebindLayerPanelMixin`이 서고 열한 개가 그리로 갔다. `LayerPanel`은 `mixin=`과 함께
`name="DebindLayerPanel"`도 받았다. 오른쪽 열을 밖에서 부르는 자리가 왼쪽의 `DebindResultPanel`과
같은 모양이 되어야 두 열이 이름에서도 대칭이 되기 때문이다. 호출부는 쉰 곳가량 바뀌었고, 얇은
위임은 하나도 안 남겼다. 남기면 A의 목적인 "무엇이 창의 일이고 무엇이 열의 일인가"가 반만 선다.

**정의 자리는 안 옮겼다.** 열한 개는 지금도 `DebindFrameMixin`의 메서드들 사이에 흩어져 있고
바뀐 것은 앞의 이름뿐이다. 한 덩어리로 모으려면 파일 지역 함수의 정의 순서에 걸린다.
`InitializeScrollBox`는 `ScrollBox_OnClick`보다, `SetSelectedAction`은 `CommitSelection`보다
뒤에 있어야 하고, Lua에서 뒤에 선언된 지역은 앞선 본문의 upvalue가 아니라 전역이 된다. 실패하면
nil 호출이라 요란하지만, 그 대가를 치를 이유가 없다. C가 어차피 파일로 뗀다.

**같이 간 필드 셋.** `dataProvider`, `SideTabs`, `currentSpec`. 셋 다 쓰는 자리가 옮긴 열한 개
안에 있어서 창에 남겨두면 열이 창의 필드에 쓰는 모양이 된다. 창 쪽에 남은 읽는 자리는
`self.LayerPanel.`을 앞에 붙였다(`UpdateEmptyText`, `GetSelectedActions`, `UpdateButtons`,
`SetTab`).

**선택은 안 갔다.** 쓰는 셋(`SetSelectedAction`, `ToggleActionSelected`, `SelectRangeTo`)만
열로 갔고 읽는 넷(`GetSelectedAction`, `IsActionSelected`, `GetSelectionCount`,
`GetSelectedActions`)은 창에 남았다. 왼쪽 열도 그 값을 읽으므로 어느 한 열의 것이 아니다.
C의 당김 목록에 `GetCurrentSelection()`과 `IsActionSelected()`가 있는 것과 같은 갈래다.

**옮긴 열한 개가 창을 되짚는 자리는 셋이고, C의 밀기 이벤트가 지울 자리가 정확히 이것들이다.**

| 어디 | 무엇을 |
|---|---|
| `Refresh` | `DebindFrame:SetTitle`, `DebindFrame:UpdateEmptyText` |
| `CommitSelection` (파일 지역, 부르는 셋이 전부 열이다) | `DebindFrame:Update` |
| `UpdateListStrip` | `DebindFrame:IsCapturingKey`, `OverviewPanel.SearchBox`, `OverviewPanel.FilterDropdown` |

행 믹스인(`DebindLineMixin`)은 이 표에 안 넣었다. 그쪽이 `DebindFrame`을 부르는 자리는 대개
지정 모드, 드롭다운, 드롭처럼 **원래 창의 일**이고, 선택을 읽는 것만 위와 같은 갈래다. 함께
세어놓으면 C가 지울 것과 안 지울 것이 한 목록에 섞인다.

`GetParent()` 사슬은 하나도 안 썼다. `DebindFrame`을 이름으로 부른다. 1단계에서
`DebindTabMixin:OnClick`이 부모가 바뀌자 조용히 깨진 자리가 그것이었다(`.zzz/resolved.md`).

**밖에서 이 열을 짚는 철자는 `DebindLayerPanel` 하나다.** `DebindFrame.LayerPanel.ScrollBox`로
쓰던 둘(`DebindLineMixin:OnClick`, `GetHoveredLine`)도 그리로 맞췄다. 같은 프레임에 철자가 둘이면
grep이 반만 잡는다. 창 자신은 `self.LayerPanel`을 그대로 쓴다.

**2026-08-14에 이 이동을 재고 접은 결정을 뒤집은 것이다.** 무엇이었고 왜 뒤집혔는지는
`0-DECISION-LOG.md`.

## 2를 하고 나서 (2026-08-22)

파일 셋이 섰고 전부 `DebindUI.xml`에서 `DebindUI.lua`보다 **먼저** 선다. 순서도 이 순서여야 한다.

| 파일 | |
|---|---|
| `ActionDisplay.lua` | 액션 이름·아이콘 해석기와 그것에 붙는 낱말들. `NameAndIconForAction`, `ColoredNameAndIconForAction`, `SetActionIcon`, `BINDING_TYPE_NAMES`, `UNIT_INFO`, `SORTED_UNIT_LIST`, `GetMacrotextIcon`과 그 캐시, `IMPORTED_FONT_COLOR`, `QUESTION_MARK_ICON_NUM` |
| `LayerDisplay.lua` | 레이어 이름과 그 옆 그림. `GetLayerTabs`, `GetTabLabel`, `GetSideTabaLabel`, `GetLayerShortName`, `GetLayerLabel`, `IsLayerOffWorld`, `GetSideTabIcon` |
| `ActionTooltip.lua` | 액션 툴팁 통째로. `AddActionToTooltip`/`HideActionTooltip`의 `do` 블록, `GetActionBarTypeLabel`, `UNIT_FRAME_REACTIONS`/`UNIT_FRAME_TYPES` |

`DebindUI.lua`가 6667줄에서 5688줄이 됐다. 세 파일 합이 1081줄이고, 차액은 각자 붙은 머리말과
`local` 재선언이다. 바닥의 `-- temp` 공개 블록도 그만큼 줄었다.

**`DebindPrivate.DebindUI`를 만드는 자리가 `ActionDisplay.lua`로 옮겼다.** `DebindUI.lua`는 이제
그 표를 있는 그대로 받는다. 순서를 뒤집으면 먼저 온 파일의 첫 줄이 nil을 인덱싱하고 **로드
시점에 요란하게** 죽는다. 조용히 안 깨지는 것이 이 배치의 조건이었다.

**둘은 안 올라갔다.** `GetLayerID`와 `GetSideTabDescription`이다. 인자를 안 주면 지금 열려 있는
탭을 답하는데, 그건 전제 3이 말하는 "두 열이 함께 쓰는 것"이라 창의 것이다. 그래서 경계를 넘는
값은 `layerID` 하나가 됐다. 위 목록이 `GetLayerID`를 올릴 것으로 세었던 것은 이 갈래를 안 보고
센 것이다.

**`Debind.xml`이 아니라 `DebindUI.xml`에 넣었고, 이건 미룬 것이 하나 있다는 뜻이다.**
`testing-a-change.md`의 기준은 "UI냐"가 아니라 "프레임이 필요하냐"이고, `Debind.xml`에 있다는
것은 곧 파이프라인이 그것을 필요로 한다는 주장이다. 셋 중 그 주장이 서는 것은
`ActionDisplay.lua` 하나뿐이다. `ActionCatalog.lua`가 `AddEntry`에서 해석기를 부르는데, 그 파일은
`Debind.xml`에 있고 헤드리스로 돌며, 지금은 표를 **호출 시점에** 잡아서 그 의존을 피하고 있다.
`ActionDisplay.lua`를 `Misc.lua` 뒤로 옮기면 `AddEntry`가 헤드리스에서 실제로 돌 수 있게 된다
(`catalog_spec`이 지금 `Filter` 하나만 재는 이유가 그것이다). **안 했다.** 2번이 요구한 것은
"창보다 위로"였고 저건 "파이프라인 안으로"라 별개의 판단이다.

**여섯 번째 죽은 코드가 나왔고 이번엔 지웠다.** `ClearMacrotextIconCache`의
`if (DebindFrame:IsShown()) then return; end`. 부르는 자리가 `DebindFrameMixin:OnHide` 하나인데
`OnHide` 안에서는 창이 이미 내려가 있어서 이 가드는 막은 적이 없다. 위 넷과 달리 짚어만 둘 수가
없었다 - 올라간 파일이 창에게 보이느냐고 묻는 것이 2번이 없애려는 바로 그 되짚기다. 언제 지울지는
부르는 쪽 몫으로 남겼다.

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

가르는 것만으로는 절반이다. 테이블 필드와 XML 리전은 luacheck가 원래 못 본다. 지역 변수는
**`.luacheckrc`가 꺼놨었고, 2026-08-22에 켰다.**

### 211 / 231 / 311을 켰다 (2026-08-22)

**되돌리기도 뒤집기도 아니었다.** `.luacheckrc`는 2026-04-09 `8eaae4f`에서 **파일 자체가 생기면서**
211/212/213을 껐고, 그 커밋의 부제가 *"Also: add luacheck to CI"* 다. 린트를 한 번도 안 돌린
코드베이스에 검사를 붙이면서 치른 값이지 내려진 결정이 아니다. **껐을 때의 값이 안 적혀 있던
이유는 값이 없어서였다.**

**212 / 213 / 232는 껐다. 종류가 다르다.** 안 쓰는 인자는 게임이 넘겨주는 시그니처이지 우리가
쓰고 버린 코드가 아니다.

**`dump`은 이름째 뺐다**(`211/dump`). `DebindPrivate.dump`은 `Constants.lua`가 세운 실제 설비이고
파일마다 맨 위에 지역 별칭을 깔아두는 것이 관례다. 지우면 다음 디버깅에서 도로 넣게 되고,
남겨두면 경고 다섯이 영구히 떠서 **목록을 훑고 넘기게 된다.** 아무도 안 읽는 목록은 아무것도
안 잡는다.

34개를 하나씩 봤다. 헤더의 죽은 지역 캐시가 대부분이었고, 실제로 아무도 안 부르는 함수 넷
(`_GetKeyInfo`+`_keyInfoCache`+`_mods`, `_isSelected`, `_setSelected`, `formatValue`), 아무도 안
읽는 표 둘(`GROUP_ROLE_UNITS`, `_mergedUnits`), 값이 안 읽히는 대입 둘(`Misc.lua`의 `token`,
`UnitWatch.lua`의 `tmp`)이 나왔다.

**일괄로 지우면 안 되는 이유가 그 자리에서 하나 나왔다.** W231은 "안 쓴다"가 아니라 **"읽는 데가
없다"** 이다. `_dropdown`을 선언에서 이름만 빼자 대입 다섯이 그대로 **전역 쓰기**가 됐고 검사가
W111로 잡았다. 답은 선언과 대입을 같이 걷어내는 것이었다. 그 자리는 `.zzz/refactor-candidates.md`에
이미 올라가 있던 것이고, 다섯 번째 설정 함수가 여섯 번째 죽은 대입을 안 만들려고 일부러 비워둔
자리이기도 했다. 같이 닫았다.

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

1. ~~**어느 방안까지 갈 것인가.**~~ **C까지 간다 (2026-08-22).** 머리말에 순서가 있다
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
