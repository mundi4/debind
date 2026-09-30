# 목록 행에 공통 base를 둔다

> 상태: **구현됐다** (2026-09-30). 처음에는 base → 아이콘 → large → 최종의 네 단계 계층을 세우려 했고, 따져 본 뒤
> base 하나와 드리프트 정리로 줄였다. 무엇을 뺐고 왜 뺐는지는 5절. 3-4의 스위치 쓰임 행 높이는 구현하다 이유가
> 나와서 안 바꿨다.
>
> 쓴 세션: `debind-d6`, 세션 ID `e4608c6b-67fc-443c-a6d9-05607e0f4897`.

**범위는 메인 창 목록 안의 행 일곱 개다.** 그룹 헤더, 빈 칸(`factory("Frame")`), 스위치 설정 블록, 스펠 피커,
설정 탭, 키 지정 대화상자의 줄(`KeyCapture.lua`)은 안 건드린다.

## 1. 왜 하나

**드리프트를 잡는 것이 목적이다** (소유자). 목록 행을 새로 만들 때마다 기존 행을 베껴 조금씩 다르게 적었고, 최근 한
달 사이 새 목록이 다섯 개(저장소 둘, 스위치 셋) 생기면서 어긋남이 쌓였다. 기준이 되는 base가 없으면 다음 목록도 같은
길을 간다.

**모은 뒤에 이전 커밋의 어느 패널 행 스타일이 더 낫다면, 그 방향으로 모두 함께 고친다** (소유자). base는 그 "한 곳"이다.
그래서 이 작업이 고르는 기본 모양은 최종 결정이 아니다. 지금 가장 많은 행이 쓰는 모양을 고른다.

## 2. 지금의 드리프트

| 템플릿 | 목록 | 높이 | 배경 | 마우스오버 강조 | 선택 표시 |
|---|---|---|---|---|---|
| `DebindLineTemplate` ← `DebindLineVisualTemplate` | 개요 오른쪽 열 | 46 | 있음 | 노랑 | `SelectedHighlight` |
| `DebindSwitchUsageActionTemplate` ← `DebindLineVisualTemplate` | 스위치 오른쪽 열 | 46 | 있음 | 노랑 | (텍스처만 물려받음) |
| `DebindOrderLineTemplate` | 개요 왼쪽 열 | 28 | 있음 | 노랑 | `SelectedHighlight` |
| `DebindStoragePreviewRowTemplate` | 저장소 미리보기 | 28 | **없음** | **퀘스트 제목 강조, x=28부터, 높이 22** | 체크박스 |
| `DebindSwitchRowTemplate` | 스위치 왼쪽 열 | 28 | 있음 | 노랑 | `SelectedHighlight` |
| `DebindSwitchUsageRowTemplate` | 스위치 오른쪽 열 | **24** | 있음 | **없음** | 없음 |
| `DebindStorageEntryRowTemplate` | 저장소 왼쪽 열 | **44** | 있음 | **노랑 빠짐** | `SelectedHighlight` |

배경은 `ClickCastList-ButtonBackground`, 노랑 강조는 `ClickCastList-ButtonHighlight`에 노랑 `Color`, 선택 표시는
`auctionhouse-ui-row-select`다. 같은 선언이 행마다 따로 적혀 있다.

그 밖에:

- **폭.** 행 XML의 `x`(450 / 400 / 300)는 화면에 닿지 않는다. 여섯 목록 모두 `CreateScrollBoxListLinearView`로 만들고
  `SetElementStretchDisabled`를 안 켜므로, 목록이 행을 제 폭으로 늘린다(`ScrollBoxViewUtil.SetPoint`).
- **고정폭 글자.** `DebindLineVisualTemplate`의 FontString 다섯 개가 모두 `Size x="430"`이고 한 점으로만 앵커된다.
  윗줄에서 긴 `Name`과 `InfoText`(`@대상`)가 가로로 겹칠 수 있고, `Name`의 말줄임은 행 끝이 아니라 430에서 걸린다.
  코드를 읽어 내린 결론이다. `DebindStorageEntryRowTemplate`의 `Name`(Lua `SetWidth(335)`/`315`)과 `Counts`(XML
  335)도 고정폭이다.
- **죽은 것.** `SpecialConditionsText`(채우는 코드 없음).

쓰임 액션 행이 `Marks`를 숨기는 것(`DebindSwitchUsageActionMixin:Init`)은 드리프트가 아니다. 그 행을 세운 커밋
(5a6d45a)이 "Picking, drops, menus and the marks stay behind"라고 정했다.

## 3. 할 일

### 3-1. base: `DebindListRowTemplate`

- 배경, 마우스오버 강조, `SelectedHighlight`(숨긴 채). 리전 이름은 지금 행들이 쓰는 그대로(`Background`,
  `FrameHighlight`, `SelectedHighlight`)라서, 그것을 켜고 끄는 Lua는 안 바뀐다.
- 마우스오버 강조는 `HIGHLIGHT` 레이어에 둔다. 엔진이 켜고 끄므로 base에 스크립트가 필요 없다. 템플릿의 스크립트는
  물려받은 같은 핸들러를 덮기 때문에, base가 스크립트를 들면 일곱 행이 모두 그것을 챙겨야 한다. 순서 행에 마우스를
  올리면 개요 행의 같은 액션이 켜지는 링크 강조도 이 레이어를 잠근다(`LockHighlight`, 킷이 `IsHighlightLocked`로 잰다).
- mixin은 없다. 올라갈 동작이 `SelectedHighlight:SetShown` 한 줄뿐이다.
- `<Size>`는 안 적는다. 높이는 각 행이 적는다.

일곱 행이 모두 `inherits`로 받고, 각자의 배경·강조·선택 표시 선언을 지운다. 따라오는 변화:

- 저장소 항목 행: 강조에 노랑이 붙는다.
- 스위치 쓰임 행: 강조가 생긴다. 누를 것이 없는 행이지만 숫자가 있는 행은 툴팁을 연다.
  `DebindSwitchGroupHeaderTemplate`이 강조를 끈 이유("offers a press that does nothing")와 맞닿는 자리라, 모은 뒤 화면에서
  갈린다면 1절 둘째 원칙대로 base 쪽에서 정한다.
- 미리보기 행: 배경이 생기고, 강조가 체크박스까지 행 전체를 덮는다. 자기 `<HighlightTexture>`는 지운다.

### 3-2. 두 줄 액션 행의 고정폭을 푼다

`DebindLineVisualTemplate`(3-5에서 `DebindTwoLineActionRowTemplate`)에서:

- `Name`은 아이콘 오른쪽에서 `InfoText` 왼쪽까지, 양쪽 앵커로 폭을 받는다. `InfoText`는 오른쪽 끝에 한 점으로 붙고 폭은
  글자를 따른다. `InfoText`가 먼저 선언돼야 한다(`check:xml-anchors`가 잡는다).
- 둘째 줄도 같다. `BindingText`는 `InfoText2` 왼쪽까지.
- `SpecialConditionsText`를 지운다.
- `KeyWarning`의 자리는 지금처럼 `BindingText`의 글자 폭으로 잡는다(`FillActionLine`).

`Marks`는 `<Frames>` 안의 프레임이라, `<Layers>`의 글자가 XML에서 그것을 앵커로 잡을 수 없다(레이어가 먼저 만들어진다).
그래서 둘째 줄 글자가 `Marks` 앞에서 멈추게 하는 것은 이 작업에 넣지 않는다. 단축키 글자는 짧아서, 지금까지 마크와
겹쳐 문제가 된 기록이 없다.

### 3-3. 저장소 항목 행의 고정폭을 푼다

`Name`과 `Counts`가 `DeleteButton` 앞에서 멈추게 양쪽 앵커로 받는다. `DebindStorageEntryRowMixin:Init`의
`SetWidth(335)`/`SetWidth(315)`를 지운다. 출처 아이콘이 있을 때 `Name`의 왼쪽 점만 옮기는 코드는 남는다.

### 3-4. 높이 두 곳

저장소 항목 행 44 → 46. XML `<Size y>`와 Lua 상수(`ENTRY_ROW_HEIGHT`)를 같이 바꾼다.

**스위치 쓰임 행의 24는 둔다.** `USAGE_ROW_HEIGHT`에 이유가 적혀 있었다. 누르는 줄이 아니라 훑어 읽는 줄이고, 수가
아주 많을 수 있다는 것이다. 쓰임 액션 행의 `Marks` 숨김처럼 일부러 정한 값이지 베끼다 어긋난 것이 아니다.

### 3-5. 폭 값과 이름

- 행 XML의 `<Size x>`를 지우고 `y`만 남긴다.
- `DebindLineTemplate` / `DebindLineMixin` → `DebindLayerRowTemplate` / `DebindLayerRowMixin`. 이 행이 사는 열이
  `DebindLayerPanel`이다.
- `DebindLineVisualTemplate` → `DebindTwoLineActionRowTemplate`. 다른 액션 행(순서, 미리보기)과 이 모양을 가르는 것이
  두 줄이다. `DebindActionCardTemplate`도 후보였는데, "card"는 주석에만 있는 말이라 이름만 보고는 무엇인지 모른다.
- `DebindUI.FillActionLine` → `DebindUI.FillTwoLineActionRow`. 채우는 대상이 그 템플릿의 리전이다.

바뀌는 이름이 닿는 곳: `Debind/`의 XML·Lua, `.luacheckrc` 전역 목록, `DebindDev/DebindTest.lua`,
`Debind/Locales/enUS.lua`, `Debind/Menus/ActionMenuItems.lua`의 주석. `devdocs/legacy/`는 그때의 기록이라 안 고친다.

### 3-6. 주석

건드리는 템플릿에서 바로 아래 XML을 다시 읽어 주는 주석("같은 아트를 쓴다", "이 칸은 어디에 붙는다")과 틀린 주석은
고치지 않고 지운다. 틀린 것은 넷이다. `DebindLineTemplate`을 "왼쪽 목록"이라 부르는 둘(`DebindOrderLineTemplate` 위,
`DebindSpellPickerRowTemplate` 위. 이 템플릿은 개요의 오른쪽 열이다), 순서 행에 없는 "아래줄"을 말하는 하나, 없는
`DebindLineMixin:LayoutName`을 가리키는 하나. 새로 다는 주석은 base의 강조가 왜 `HIGHLIGHT` 레이어여야 하는가
하나다. 앵커와 간격에는 달지 않는다.

## 4. 순서

1. base (3-1)
2. 고정폭 (3-2, 3-3)
3. 높이 (3-4)
4. 폭 값, 이름, 주석 (3-5, 3-6)
5. 목록 행이 base를 물려받는지 보는 정적 검사 (6절)

`breaking-up-debindui.md`의 C(오버뷰 두 열을 파일로 떼기)와 같은 파일을 만진다. 그 문서의 "같이 하게 되는 것"에 있던
행 템플릿 항목 셋은 이 문서가 넘겨받았다.

## 5. 뺀 것과 이유

다시 열 때는 여기 적은 이유가 아직 서 있는지부터 본다.

- **아이콘 / large 단계.** 소유자가 처음 부른 계층이다. 각 단계를 쓰는 행이 둘씩(아이콘: 순서, 미리보기 / large: 개요,
  쓰임 액션)이라 줄어드는 중복이 작다. 반대로 새 복잡도가 생긴다. XML은 물려받은 리전의 크기나 앵커를 고칠 수 없어서,
  large가 아이콘 단계를 물려받지 못하고 같은 이름의 리전을 따로 적는 형제가 되어야 한다. 그 이름 규약은 확인하는 검사가
  없다. 아이콘이 있는 목록이 셋 이상으로 늘면 다시 잴 만하다.
- **mixin 층** (`DebindListRowMixin`, `DebindIconRowMixin`, `DebindActionRowMixin` …). 올라갈 동작이 한두 줄짜리다.
  개요 행 하나가 다섯 mixin을 섞게 되면, 행 하나를 읽으려고 파일 서너 곳을 오가야 한다. 공유할 코드는 지금의
  `FillActionLine`처럼 함수로 둔다.
- **순서 행의 이유 칸과 미리보기 행의 키 칸을 하나로** (`SetTrailingText`). 같은 일을 하지만 합치려면 두 행이 같은
  아이콘 단계에 서야 하고, 그 단계를 뺐다.
- **높이를 XML에서만 읽기.** 목록 뷰에 높이 계산 함수를 안 주면 Blizzard 목록이 템플릿 높이를 XML에서 읽는다
  (`ScrollBoxListLinearViewMixin:CalculateFrameExtent`). 그런데 `C_XMLUtil.GetTemplateInfo`가 `inherits`로 물려받은
  `<Size>`까지 풀어 주는지는 엔진 함수라 코드로 알 수 없다. 빈 칸마다 템플릿도 세워야 한다. 상수는 거의 안 바뀌고, 3-4로
  지금 어긋난 곳은 없어진다.
- **`GetElementData()`로 데이터 잡는 방식 통일.** 지금 행들은 네 가지 방식으로 데이터를 잡는다. 모으면 행 코드와 킷의
  행 찾기가 다 흔들리는데 화면에서 얻는 것이 없다.
- **메뉴 대상 표시를 메뉴 여는 행 넷 모두에.** 지금은 개요 행만 표시한다. 정리가 아니라 새 동작이다. 메뉴가 닫힐 때를
  행마다 추적해야 하고, 순서·미리보기·저장소 항목 행은 `MenuUtil.CreateContextMenu`를 쓰므로 개요 행의 방식을 그대로
  못 쓴다.
- **미리보기 행의 체크박스 자리.** 아이콘 단계가 없으면 체크박스가 아이콘을 밀어내는 것이 다른 행과 부딪히지 않는다.

## 6. 검증

**정적 검사가 잡는 것.** `check:xml-anchors`는 한 템플릿 안에서 뒤에 선언된 형제를 가리키는 앵커를 잡는다(3-2의
선언 순서). `check:xml-methods`는 `inherits`를 따라 `method=`를 본다. lint는 바뀐 mixin 이름을 본다.

**`check:list-rows`.** 목록의 `factory(...)`/`SetElementInitializer`가 넘기는 템플릿이 `inherits` 사슬에서
`DebindListRowTemplate`에 닿는지 본다. 새 행이 base 없이 들어오는 것이 이 작업이 되돌아가는 길이다. 행이 아닌 것(그룹
헤더, 빈 칸, 스위치 설정 블록, 스펠 피커의 격자)은 `NOT_ROWS`에 이유와 함께 이름으로 빼고, 아무 목록도 안 만드는
이름이 거기 남으면 그것도 실패다. 이 작업 전의 트리(`git archive HEAD`)에 돌려 일곱 행이 모두 빨개지는 것을 봤다.

**킷이 이미 재는 것.** 링크 강조(`IsHighlightLocked`), 순서 행의 이동 버튼과 수락, 스위치 행 찾기, 쓰임 액션 행을
눌러 그 액션으로 가기. 이 작업은 이 테스트들이 행을 찾는 필드를 안 건드린다.

**킷이 원리상 못 재는 것.** 강조가 어떻게 보이는지, 글자가 겹치는지. 픽셀을 판정하지 않는다.
