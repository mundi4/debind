# 왼쪽 열에서 여럿 고르기 (2026-09-14 시작)

> 상태: **구현됐다(2026-09-15).** 아래 "고칠 자리"는 어디를 고쳤는지의 기록이다.

**이름.** 코드는 이 열을 `ResultPanel`(`DebindResultPanel`)이라 부르고, 문서와 주석은 "왼쪽 열"이라 부른다.
오른쪽은 `LayerPanel`, "오른쪽 목록"이다. `reworking-the-overview.md`의 이름 대조와 같다.

## 무엇을 하나

- 왼쪽 열의 행에서 CTRL, SHIFT, CTRL+SHIFT 클릭이 오른쪽 목록과 같은 뜻으로 선택을 손본다. 수식키가 붙은 클릭은
  **탭을 안 옮긴다.** 왼쪽 열은 모든 레이어를 담으므로 이 선택은 레이어를 넘는다. 수식키 없는 좌클릭은 지금처럼 그
  액션의 탭으로 데려간다(`GoToAction`).
- 머리글 좌클릭이 그 그룹을 고른다.
- 왼쪽 열의 **접기를 없애고**, 머리글의 요약도 없앤다. 그룹 사이를 조금 띄운다.
- 왼쪽 열의 우클릭이 오른쪽 목록과 같은 **액션 메뉴**를 열고, 거기에 순서 항목이 붙는다.
- 왼쪽 열의 행에 커서를 올리면 오른쪽 목록의 같은 행이 강조된다.

## 정한 것

### 선택은 탭을 건너 산다

`SetTab`에서 탭이 바뀔 때 선택을 푸는 줄을 뺀다. 레이어를 넘는 선택이 목적이라, 탭을 하나 옮겼다고 풀리면 성립하지
않는다.

그 줄이 막던 것은 화면에 없는 액션 위에 편집 창만 떠 있는 상태다. 그건 `DebindLayerPanelMixin:Refresh`가 이미
막는다. 앵커가 새 목록에 안 그려지면 매크로 창과 아이콘 선택기를 닫는 갈래가 있고, `SetTab`도 `Refresh`를 부른다.

### 접기와 요약을 없앤다

2026-08-17에 들어온 접기(`reworking-the-overview.md` "접기")를 되돌린다.

- 한 그룹은 보통 한두 줄이고 많아야 네다섯 줄이라, 접어서 줄어드는 양이 작다. 모두 접기도 없고 접힘은 저장되지 않는다.
- 레이어를 넘는 선택에서 접힌 그룹은 SHIFT 범위에 넣어도 틀리고 빼도 틀린다. 넣으면 안 보이는 행이 벌크 대상이
  된다. 빼면 범위가 머리글을 넘어 이어져 보이는데 그 키의 액션은 조용히 빠진다. CTRL로 고른 뒤 접는 것도 같은
  상태를 만든다.
- 키 없는 맨 아래 덩어리는 길어질 수 있지만 목록 끝에 서서 위의 키 그룹을 밀어내지 않는다. 이 덩어리에도 접기를
  안 남긴다.

**머리글의 요약(`첫 액션 +N`, 키 없는 덩어리의 `N개`)도 뺀다.** 그룹의 행이 늘 바로 아래 그려지므로 요약이 말할 것이
없다.

**그룹 사이를 띄운다.** 첫 머리글을 포함한 모든 머리글 위에 여백을 둔다. 머리글 요소의 높이를 늘리는 길은 안 된다. 머리글
배경은 프레임 크기대로 늘어나므로 띠가 굵어질 뿐 여백이 안 생긴다. 그래서 머리글 앞에 빈 요소를 끼운다.

**머리글 그림은 퀘스트 로그의 것이다.** `DebindKeyHeaderTemplate`이 `ListHeaderVisualTemplate`을 물려받고, 배경과
강조를 흐리고 배경 알파를 0.3으로 둔다(2026-09-15에 들어갔다). 이 템플릿의 +/-는 배경 그림이 아니라 `CollapseButton`
이라는 따로 된 버튼이다.

### 행의 CTRL과 SHIFT

오른쪽 목록과 같은 규칙이다. 앵커는 두 목록이 같이 쓰고, SHIFT 없이 마지막으로 누른 것이다. 앵커가 무엇을 담는지는
아래 "앵커"에 있다.

| 입력 | 하는 일 | 앵커 |
|---|---|---|
| CTRL | 그 행을 넣거나 뺀다 | 그 행으로 옮긴다 |
| SHIFT | 앵커부터 그 행까지를 선택으로 삼는다. 왼쪽 열에 그려진 순서로 잰다 | 안 옮긴다 |
| CTRL+SHIFT | 그 범위를 더한다 | 안 옮긴다 |

- 앵커가 왼쪽 열에 안 그려져 있으면(필터, 검색) 그 행 하나만 고른다. 오른쪽 `SelectRangeTo`의 규칙과 같다.
- 지정 모드 중에는 지금처럼 아무것도 안 한다.
- 범위 함수는 `DebindResultPanelMixin`에 둔다. 이 열의 행에 하는 일이라서다(`LayerPanel` 머리 주석이 세 동작을
  그 패널에 둔 이유와 같다).

### 머리글 클릭

**머리글은 그 안의 행 전체다.**

| 입력 | 하는 일 |
|---|---|
| 클릭 | 선택을 그 그룹의 행 전체로 갈아치운다 |
| CTRL | 그룹이 전부 골라져 있으면 전부 빼고, 아니면 전부 넣는다. 다른 그룹의 선택은 그대로다 |
| SHIFT | 앵커부터 그 그룹까지를 선택으로 삼는다. 그룹이 앵커보다 아래면 그룹의 마지막 행을, 위면 첫 행을 누른 것으로 본다. 그래서 그룹이 통째로 들어간다 |
| CTRL+SHIFT | 그 범위를 더한다 |

- CTRL로 머리글을 눌러도 앵커가 그 그룹으로 간다. 행의 CTRL이 앵커를 옮기는 것과 같다.
- **체크박스는 안 단다.** 머리글 클릭이 같은 일을 한다.
- 키 없는 덩어리와 도착분 그룹의 머리글도 같다.
- 우클릭은 지금의 키 그룹 메뉴(`SetupKeyGroupDropdownMenu`) 그대로다.
- 지정 모드 중에는 아무것도 안 한다.

### 앵커

**SHIFT가 재는 기준점을 `_selectedAction`에서 떼어 따로 둔다.** 상태는 셋이다.

| 상태 | 언제 | SHIFT |
|---|---|---|
| 행 | SHIFT 없이 행을 눌렀을 때. 행 앵커를 세우는 길(`SetSelectedAction`, `ToggleActionSelected`, `SelectActions`)이 전부 여기다 | 그 행부터 잰다 |
| 그룹 | SHIFT 없이 머리글을 눌렀을 때. 그룹은 `(key, arrivalID)`로 기억한다 | 누른 것이 그룹보다 아래면 그룹의 첫 행부터, 위면 마지막 행부터 재서 그룹이 통째로 든다. 머리글끼리면 두 그룹을 다 담는다 |
| 없음 | 그룹 앵커가 풀렸을 때 | 누른 것 하나만 고른다. 다음 클릭이 기준점을 새로 세운다 |

- **왜 그룹인가.** 기준점이 행 하나면 머리글을 누른 뒤의 SHIFT가 한쪽 방향에서 그룹의 나머지를 떨군다. 첫 행에 두면
  위쪽으로, 마지막 행에 두면 아래쪽으로 넓힐 때다.
- **왜 떼나.** 그룹 앵커가 풀렸을 때 기준점이 `_selectedAction`으로 떨어지면 사용자가 고른 적 없는 행에서 범위가
  잡힌다. 두 역할을 한 변수에 둔 근거는 "왼쪽 열이 짚는 행(`isCurrent`)이 곧 기준점이라 따로 그릴 것이 없다"였는데,
  이 계획에서 왼쪽 열의 강조는 앵커가 아니라 선택 전체를 그리므로 그 근거는 어차피 없어진다. 그 변수 위 주석을 고친다.
- **그룹 앵커가 풀리는 때.** 가지치기(`PruneSelectionToBinFilter`)가 그 그룹을 선택에서 뺄 때다. 필터와 검색이 가린
  경우이고, 도착분 그룹을 수락해 `(key, arrivalID)`가 없어진 경우도 수락이 가지치기를 지나므로 여기서 같이 풀린다.
- **행 앵커는 가려져도 남는다.** 검색어가 보던 자리를 뺏지 않는다는 지금 규칙 그대로다. 안 그려진 동안의 SHIFT는
  누른 것 하나만 고른다(`SelectRangeTo`).
- **`_selectedAction`은 "지금 이야기 중인 행"으로만 남는다.** 순서 화살표, reveal, 매크로 창이 본다. 머리글을 누르면
  그룹의 첫 행으로 둔다.
- 오른쪽 목록의 SHIFT도 이 기준점을 읽는다. 기준점이 그룹이면 오른쪽 목록에서는 누른 것 하나만 고른다. 그 목록에는
  그룹이 없다.

### 왼쪽 열의 우클릭 메뉴

**오른쪽 목록과 같은 액션 메뉴(`SetupActionDropdownMenu`)를 연다.** 레이어를 넘는 선택에 메뉴가 열릴 자리는 왼쪽
열뿐이다.

- 고른 것 위에서 열면 고른 것 전부를 겨눈다. 고른 것 밖에서 열면 선택을 그 행 하나로 접고 그 행을 겨눈다. 오른쪽
  목록(`DebindLineMixin:OnClick`)과 같다.
- **순서 항목을 더한다.** `Run Sooner`(`ORDER_MOVE_UP`)와 `Run Later`(`ORDER_MOVE_DOWN`)다. 판정과 막힌 사유는 지금
  `SetupOrderDropdownMenu`가 쓰는 `ComputeOrderSwapForAction`과 `ORDER_BLOCKED_*`를 그대로 옮긴다. 겨눈 액션이
  하나가 아니면 막힌 줄로 선다.
- 도착분 하나를 겨누면 순서 항목이 안 선다. 지금 순서 메뉴와 화살표(`UpdateMoveButtons`)가 도착분에서 순서 대신
  수락을 세우는 것과 같은 이유이고, 수락과 거절은 액션 메뉴 맨 위에 이미 있다.
- **ctx에 메뉴가 열린 자리를 싣는다(`ctx.inOrderList`).** 순서 항목은 왼쪽 열에서 열렸을 때만 선다. 오른쪽 목록에서는
  순서를 안 바꾼다.
- `SetupOrderDropdownMenu`는 없어진다. 그 메뉴의 키 항목은 액션 메뉴의 `CreateAssignKeyMenuItem`이 맡는다. 그 메뉴가
  도착분 하나에 쓰던 말(`ACTION_SET_KEY_ACCEPT`, 키를 주는 것이 곧 수락이라는 것)은 액션 메뉴로 옮겨 와서, 이제 두
  목록 다 도착분 하나에 그 말로 선다.
- **뒤집는 규칙이 있다.** 편집 메뉴는 액션이 사는 탭에서 연다는 규칙이다. `DebindOrderLineMixin:OnClick` 머리
  주석, `DebindOrderLineTemplate` XML 주석, `reworking-the-overview.md`에 적혀 있다. 좌클릭이 그 탭으로 데려가는 것은
  그대로 남는다.

### 레이어가 섞인 메뉴의 제목 줄

메뉴의 둘째 제목 줄은 겨눈 액션이 사는 레이어 이름이다(`GetLayerLabel(ctx.layer)`). 레이어가 섞이면
**`<레이어 이름> +N`** 으로 세운다. 예: `Jinseong / 암흑 +3`.

- 앞에 대는 레이어는 `layerID`가 가장 작은 것이다. 일반, 직업, 캐릭터 순이라 공유 레이어가 섞여 있으면 늘 그것이
  앞에 선다. 이 줄은 어디를 건드리는지 말하려고 서 있고, 모르고 건드리면 가장 넓게 번지는 것이 공유 레이어다.
- `+N`은 키 그룹 메뉴 제목(`Charge +1`, `OVERVIEW_KEY_HEADER_MORE`)과 같은 모양이다.
- 그러려면 `ctx.layer` 하나로는 모자란다. 한 레이어면 그 레이어, 섞이면 앞에 댈 레이어와 나머지 개수
  (`ctx.otherLayers`)를 넘긴다(`LayerSpread`).
  이동과 복사의 현재 탭 표시와 막힘은 한 레이어일 때만 건다. 이미 목적지에 있는 것은 `MoveActions`가 건너뛴다.

### 호버

- 왼쪽 열의 행에 커서가 올라가면, 오른쪽 목록에서 같은 액션의 행이 커서를 올렸을 때와 같은 강조를 받는다
  (`FrameHighlight`, `LockHighlight`). 툴팁은 안 띄운다.
- **그 행이 지금 그려져 있을 때만이다. 스크롤은 절대 안 한다.** 다른 레이어의 액션이면 아무것도 안 켜진다.
- 프레임이 아니라 액션을 든다(`_linkedAction`). 오른쪽 행은 그릴 때마다 그 값을 보고 강조를 잠그거나 푼다
  (`DebindLineMixin:Update`). 행은 풀에서 나오므로, 프레임을 들고 있으면 다시 지어진 목록에서 남의 행이 켜진다.

## 고칠 자리

### 선택을 오른쪽 목록에서 읽던 곳

지금은 고른 것이 전부 오른쪽 목록, 곧 지금 레이어 안에 있다고 가정한다. 다른 레이어에서 고른 것은 아래 자리에서
에러 없이 빠진다.

| 자리 | 지금 | 바꿀 것 |
|---|---|---|
| `GetSelectedActions` | 오른쪽 목록을 훑어 모은다 | 왼쪽 열 순서(`BuildKeyboardElements`)로 모은다. 순서가 이름순에서 키와 발동 순서로 바뀌므로, 이동과 복사가 한 키 안에서 발동 순서를 지키며 붙는다 |
| `MoveActions` | 행을 `FindElementDataByActionInfo`로 찾는다 | 레이어를 `FindLayerID`로 찾고, `MoveAction`이 읽는 `layer`와 `index`도 거기서 만든다 |
| `DebindLayerPanelMixin:SelectActions` | 오른쪽 목록에 있는 것만 되살린다 | 왼쪽 열이 그리는 집합(`NarrowedVisibleActions`, nil이면 전부)으로 거른다 |
| `ShowBulkDropdown` | `layer = GetLayerID()` | 위 "제목 줄"의 레이어 값 |
| `SetupActionDropdownMenu`, `CreateMoveCopyMenu` | `ctx.layer`가 늘 한 레이어라고 본다 | 위 "제목 줄" |

같은 가정을 적은 주석: `SetupActionDropdownMenu` 머리("The picked rows all live in one layer"),
`ShowBulkDropdown` 머리, `GetSelectedActions`, `SetTab`.

### 왼쪽 열의 행

- `DebindOrderLineMixin:OnClick`: 좌클릭에 수식키 갈래, 우클릭은 액션 메뉴.
- `DebindOrderLineMixin:OnEnter`, `OnLeave`: 오른쪽 행 강조.
- 행 강조(`SelectedHighlight`)가 `isCurrent`(앵커) 대신 `IsActionSelected`를 본다. 순서 화살표는 지금처럼 앵커 행에
  선다(`UpdateMoveButtons`의 `isCurrent`).
- `ORDER_LINE_TOOLTIP_INSTRUCTION_GOTO`에 CTRL, SHIFT 안내를 넣는다. enUS, koKR, ruRU에 있다.

### 머리글

- `DebindKeyHeaderMixin:OnClick`: 좌클릭이 접기에서 선택으로 바뀌고, 지정 모드 가드가 붙는다.
- 요약: `UpdateSummary`, `LayoutSummary`, `SUMMARY_MIN_WIDTH`, `OnSizeChanged`, XML의 `ActionName`과 `ExtraCount`,
  `OVERVIEW_NO_KEY_COUNT`(enUS, koKR). `OVERVIEW_KEY_HEADER_MORE`는 키 그룹 메뉴 제목과 위의 레이어 제목 줄이 쓰므로
  남는다. 키 그룹 메뉴 머리 주석이 요약을 가리키고 있다.
- `IssueIcon`은 남긴다. 접힌 그룹을 이유로 든 주석은 고친다.
- `allInactive`는 요약 글자를 흐리는 데만 쓰이므로 요약과 같이 빠진다. 그룹이 늘 펼쳐져 있어 행마다 안 나가는 사유가
  제 칸에 선다. 다른 전문화와 전문화 조건은 `ORDER_FLAG_OFFSPEC`, 물어볼 주문이 없는 `known`은
  `ORDER_FLAG_NO_SPELL`, 도착분은 파란 이름과 수락 버튼이다.
- 간격: `InitializeOrderScrollBox`의 요소 팩토리와 높이 계산에 빈 요소. `RevealRow`는 머리글의 자리를 받으므로 빈
  요소가 앞에 끼어도 그대로다.

### 접기를 걷어내는 자리

- `_collapsedKeys`, `KEYLESS_GROUP`, `CollapseKeyFor`
- `BuildKeyboardElements`의 `collapsed` 두 자리와, 접혔을 때 행을 비우는 갈래
- `RefreshKeyboard`에서 reveal이 그룹을 펴는 줄. 스크롤(`RevealRow`)은 남는다.
- `DebindKeyHeaderMixin:Init`의 `UpdateCollapsedState`
- `CollapseButton`을 숨긴다. `LayoutSummary`가 그 폭을 빼던 것은 요약과 같이 빠진다.
- 접기를 전제로 한 주석: `OnClick` 머리("The whole bar is the fold button"), `OnEnter` 머리("Folding is left
  out"), `IssueIcon`(XML 주석과 `BuildKeyboardElements`의 "A collapsed heading summarises only its first action"),
  `BuildKeyboardElements` 머리("접힘은 집합에 안 든다"), `RefreshKeyboard` 머리.
- `reworking-the-overview.md`의 "접기", "reveal", 요약, 머리글 좌클릭, 행 메뉴를 다룬 절에 뒤집혔다는 표시를 달았다.

### 우클릭 메뉴

- `SetupActionDropdownMenu`에 순서 항목과 열린 자리 판정. `SetupOrderDropdownMenu` 삭제.
- 왼쪽 열의 행에서 메뉴를 여는 길. 오른쪽의 `ShowEditDropdown`, `ShowBulkDropdown`이 하는 일과 같다.

## 테스트가 닿는 곳

- **헤드리스(`tests/actionmenutree_spec.lua`).** 액션 메뉴는 헤드리스로 지어진다. 순서 항목이 왼쪽 열에서 열 때만
  서는지, 둘 이상이면 막히는지, 도착분 하나에서는 안 서는지, 도착분 하나의 키 항목이 수락의 말로 서는지.
- **킷(`DebindDev/DebindTest.lua`, "Left column:"으로 시작하는 다섯).**
  - 두 레이어에서 고른 것이 둘 다 골라지고, 메뉴로 둘 다 넘어가고, 탭을 바꿔도 남는다.
  - 행의 SHIFT가 그룹을 넘어 사이의 행을 전부 담고, 다시 누르면 같은 기준점에서 줄어든다.
  - 머리글을 누르면 그 그룹이 골라지고, 그 뒤 위쪽 행과 아래쪽 행에 SHIFT를 해도 그룹이 통째로 남고, CTRL로 빠진다.
  - 머리글을 누르고 검색으로 그 그룹을 가렸다가 지우면 다음 SHIFT가 누른 것 하나만 고른다.
  - 오른쪽 목록이 연결된 액션의 행을 그려져 있을 때만 켜고, 풀면 끈다.
- **킷이 못 닿는 것.**
  - **손으로 누른 CTRL과 SHIFT.** `OnClick`은 클라이언트 전역 `IsControlKeyDown`, `IsShiftKeyDown`을 읽는데 테스트가
    클라이언트 전역을 덮어쓸 수는 없다. 그래서 수식키 갈래는 그 갈래가 부르는 함수로 잰다. 머리글의 그냥 클릭만 실제
    클릭이다.
  - **테스트 레이어 행의 호버, 그냥 클릭, 우클릭.** 셋 다 행의 레이어 이름을 짓거나 그 탭을 여는데, 테스트 레이어의
    id는 어느 탭도 가리키지 않는다. 섞인 레이어의 제목 줄도 같은 이유로 못 잰다.
  - 머리글과 그룹 간격이 어떻게 보이는지.
