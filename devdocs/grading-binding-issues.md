# 문제에 등급을 매기기 (2026-08-17)

> 상태: **등급표가 섰다. 코드는 아직 하나도 안 건드렸다.** 아래 등급표가 승인 대기고, "무엇을
> 정해야 하나"의 3·4번과 곁가지가 열려 있다.

배경은 `navigating-the-overview.md`다 — 이 작업이 어디서 나왔는지와 지금 머리글이 무슨
색을 왜 쓰는지가 거기 있다.

## 왜 열렸나

오버뷰 키 그룹 머리글에 색을 붙이다 나왔다. 지금 머리글은 세 가지를 말한다.

| | |
|---|---|
| 들어온 것(배지) | 파랑 |
| 키는 걸렸는데 지금 아무것도 안 나가는 그룹 | 회색 |
| 그 밖 | 흰색 |

여기에 **"문제가 있으면 빨강"**을 얹으려다 멈췄다. 얹으면 도달 불가(`UNREACHABLE`) 하나 때문에
멀쩡히 도는 그룹의 머리글이 빨개진다 — 도달 불가는 **그 그룹 안에서 누군가는 이기고 있다**는
뜻이기 때문이다.

소유자가 그 자리에서 물은 것: *"매번 never run인지 체크해서 그걸 회색으로 하드코딩 해야되는지,
지금 그렇게 하고 있는지 조금 신경쓰여."* 그 걱정이 맞다.

## 지금 구조 — `UNREACHABLE`은 신분이 둘이다

**1. 이슈 코드다.** `GetBindingIssue`(`Misc.lua`)가 `"key"` 갈래 안에서 이 코드를 낸다. 그래서
**"이슈가 있나"로 묻는 모든 자리에 자동으로 걸린다.** 대표적으로 `ColoredNameAndIconForAction`
(`DebindUI.lua`)이 `GetBindingIssue(action)`을 그냥 부르므로, 도달 불가인 행은 **지금 이름이
빨갛다.**

**2. 별도 필드이기도 하다.** `MakeRow`(`Profile.lua`)가 `issue`와 나란히 `unreachable`을 따로
싣는다. 오버뷰의 사유 칸(`GetOrderReasonText`)은 `row.issue`가 아니라 그 필드를 먼저 본다.

같은 사실이 두 경로로 흐르고, 한쪽은 "이슈면 빨강"에 휩쓸린다. **지금 하드코딩은 없지만, 색을
바꾸려 드는 순간 시작된다** — 그리는 자리마다 `issue == UNREACHABLE`을 빼는 코드를 심게 된다.

### 얽혀 있는 매듭 하나

`BuildKeyMap`(`Debind.lua`)이 `if (not issue and not yielded)`로 키 맵 진입을 막는다. 그런데
**도달 불가 판정은 그 키 맵에서 나온다.** 지금 구조는 그 순환을 "이슈면 안 넣는다"로 잘라둔
것이고, 이슈에서 `UNREACHABLE`을 빼면 그 매듭이 풀려 나온다.

`ActiveActions[action] = ordinal`은 그 `if` **밖**에 있다. 즉 문제가 있어도 "빌드에 들어갔다"로
센다 — `IsInactiveAction`이 회색을 결정하는 값이 이것이고, 그래서 **문제가 있는 키는 지금 안
흐려진다.**

## 두 길 — **A로 간다** (소유자, 2026-08-17)

| | | |
|---|---|---|
| **A. 이슈에 등급을 붙인다** | **채택** | `BINDING_ISSUE_*`마다 등급을 한 테이블에 적고, 그리는 쪽은 코드가 아니라 등급을 묻는다. 새 코드가 늘면 그 테이블 한 줄만 늘고 색을 정하는 자리는 그대로다. 위 매듭을 안 건드린다 |
| **B. `UNREACHABLE`을 이슈에서 빼고 필드로만 남긴다** | **기각** | 신분을 하나로 줄이는 쪽이라 더 깨끗하기는 하다. 기각 사유는 매듭이다 — 이슈에서 빼면 `BuildKeyMap`의 순환을 먼저 풀어야 하고, 얻는 것(신분 하나)에 비해 건드리는 범위가 크다. **다시 열릴 수 있는 자리**다: 그 순환이 다른 이유로 풀리는 날 이 항목의 근거가 없어진다 |

## 등급을 가르는 기준

**이 행 하나만 보고 판정되면 빨강, 이웃을 봐야 판정되면 회색.**

처음 적었던 문장은 *"고칠 것이 이 행에 있으면 빨강"*이었는데 **틀렸다.** 소유자가 짚었다
(2026-08-17): *"unreachable은 키와 관계가 있지 않나? 다른 키에 들어간다면 말짱해질 액션인데."*
맞는 말이고, 그러면 첫 문장은 도달불가도 빨강이라고 답한다. 고칠 곳은 이 행의 키에 **있다.**

다음으로 시험한 *"이 행이 안 나가면 빨강"*도 틀렸다 — 도달불가도 안 나간다.

살아남은 것이 위 문장이고, **코드가 그대로 그렇다.** 빨강 12개는 `GetBindingIssue`가 그 액션의
필드만 보고 낸다. `UNREACHABLE` 하나만 `CheckUnreachableBindings(bindings)`가 **정렬된 배열
통째**를 받아야 나온다(`Solver.lua`의 `UnreachableBindingCache`). 처방이 두 행에 걸쳐 있는 유일한
코드이기도 하다 — 이 행의 키를 바꿔도, 이웃의 조건을 좁혀도, 이웃을 지워도 낫는다. 그래서 이 행만
빨갛게 칠하면 **절반만 가리키는 것**이 된다.

### 같은 답이 코드에서 한 번 더 나온다

`BuildKeyMap`(`Debind.lua`)이 `ClearUnreachableBindingCache()`를 부른 **뒤에** `GetBindingIssue`를
부르고, `CheckUnreachableBindings`는 그 루프가 **끝난 뒤**에 돈다. 그래서 빌드 시점에는
`IsUnreachableAction`이 늘 nil이고, **`UNREACHABLE`은 `not issue` 게이트를 절대 못 건드린다.**

| | |
|---|---|
| **빨강 12개** | 이 코드가 붙으면 `KeyMap`에 못 들어간다. 그 액션은 아무 일도 안 한다 |
| **회색 1개** | 들어갔고, 정렬에서 졌다. 그 키는 잘 나간다 — 다른 행이 |

기준과 이 사실이 13개 전부에서 일치한다. 서로 다른 두 곳에서 같은 선이 나온 셈이다.

## 등급표 — 승인 대기

`Constants.lua`의 선언 순서 그대로. "내는 자리"는 전부 `Misc.lua`의 `GetBindingIssue`(또는 그것이
부르는 `IsKeyInvalidForAction`)다.

| 코드 | 등급 | 근거 |
|---|---|---|
| `NOT_SUPPORTED_GAMEMENU_KEY` | **빨강** | 이 행의 키가 게임 메뉴 키다 |
| `NOT_SUPPORTED_MOUSE_BUTTON` | **빨강** | 이 행의 키 + hover 조합 |
| `NOT_SUPPORTED_HOVER_CLICK_COMMAND` | **빨강** | 이 행의 타입 + 키 |
| `CONDITIONS_NEVER` | **빨강** | 사용자가 이 행에 만든 모순. 유닛 마스크 0과 specialbar/petbattle 모순 두 갈래가 같은 코드를 낸다 |
| `UNREACHABLE` | **회색** | 판정에 이웃이 필요한 유일한 코드 |
| `CLIQUE_DETECTED` | — | **등급 대상이 아니다.** 아래 참조 |
| `CANNOT_USE_HOVER_WITH_CLIQUE` | **빨강** | 아래 참조 |
| `FORMS_NONE_SELECTED` | **빨강** | `forms == 0` |
| `BONUSBARS_NONE_SELECTED` | **빨강** | `bonusbars == 0` |
| `GROUPS_NONE_SELECTED` | **빨강** | `groups == 0` |
| `HOVER_NONE_SELECTED` | **빨강** | `reactions == 0` 또는 `frameTypes == 0`. 세 갈래(hover/reactions/frameTypes)가 같은 코드를 낸다 |
| `UNDEFINED_STATE` | **빨강** | 이 행의 매크로 본문에 적힌 오타 |
| `MISSING_MACRO` | **빨강** | 이 행이 가리키는 이름이 없다 |

**살아 있는 12개 중 회색은 `UNREACHABLE` 하나다.** 회색이 하나뿐인 것이 결과이지 목표는 아니었다 —
기준을 두 번 갈아엎고도 같은 하나가 남았다.

### `CLIQUE_DETECTED`는 아무도 안 낸다

`Constants.lua`의 선언 한 줄이 저장소 안의 전부다. `git grep`으로 초기 커밋(`ed170bd`)과 `b09efb2`
양쪽을 확인했고, **역사 전체에서 대입된 적이 없다.** 로케일 짝(`BINDING_ERROR_`/`ORDER_FLAG_`)도
처음부터 없다.

소유자가 이 코드에 빨강을 제안한 근거는 *"해당 액션 자체가 무시된다"*였는데, 그 동작을 실제로
내는 것은 `CANNOT_USE_HOVER_WITH_CLIQUE`다(그쪽이 빨강이다). 등급표에 한 줄 넣으면 **죽은 코드가
산 것처럼 보인다.** `check:locales`도 이건 못 잡는다 — 코드가 안 나오니 짝이 없어도 조용하다.

→ **등급이 아니라 삭제 후보다.** 결정은 아래 5번.

### `CANNOT_USE_HOVER_WITH_CLIQUE`가 빨강인 이유

원인이 프로필 밖에 있는 유일한 코드다. 사용자가 이 행에 잘못 적은 것이 없고, 다른 애드온이 깔려
있을 뿐이다. 소유자의 판정(2026-08-17): **이슈가 맞다. 고칠 것이 있다** — Clique를 쓴다면 이
바인딩은 Clique로 옮겨야 한다는 것이 권장 동작이고, 그것을 우리가 알려주지는 않는다.

회색을 검토했다가 접었다. 두 오판의 값이 다르다:

- 도달불가를 빨강으로 두면 → **멀쩡히 도는 그룹이 빨개진다.** 거짓 경보.
- Clique를 회색으로 두면 → **동작하던 바인딩이 죽었는데 화면이 조용해진다.** 놓친 경보.

키바인딩 애드온에서 이 둘은 값이 같지 않다. `GetUndefinedCustomState`의 머리주석이 같은 논리를
이미 쓴다 — *"바인딩이 안 멈추는 게 아니라 사방에서 나가기 시작한다. 키바인딩 애드온에서 그건
최악의 방향."* 조용히 틀리는 쪽을 피하는 같은 기준이다.

## 등급은 색만 정한다 — 갈래는 안 건드린다

`UNREACHABLE`은 `"key"` 갈래 안에서 나온다. 한때 **그 배치가 틀렸다(키는 멀쩡하다)**고 적으려
했는데, 위 기준 항목의 소유자 지적이 그것도 같이 꺾었다. 처방이 실제로 키에 있으므로 ⚠가 가리키는
칸도 맞다. 갈래는 그대로 두고 등급이 **색과 세기만** 정한다.

| 자리 (`DebindUI.lua`) | 지금 | 회색 등급일 때 |
|---|---|---|
| 단축키 글자 (`DebindLineMixin:Update`) | `ERROR_COLOR` | 안 칠함 |
| ⚠ `KeyWarning` | 그대로 뜸 | **뜨되 desaturate** |
| 툴팁 KEY 줄 (`ShowLineTooltip`) | 빨간 에러 줄 | 보통 줄 + 회색 괄호 |
| 이름 (`ColoredNameAndIconForAction`) | 빨강 | 회색 |

⚠를 남기는 이유는 그 자리의 주석이 이미 적어둔 것이다 — *색만으로는 색맹에 안 걸리고 어느 칸인지도
안 말해준다.* desaturate는 같은 함수가 `QuestionMark`에 이미 쓰는 관용이다.

## 무엇을 정해야 하나

1. ~~A인가 B인가~~ — **A로 정해졌다.**
2. **코드별 등급** — 위 등급표. **승인 대기.**
3. **머리글에 빨강을 얹을 것인가.** 얹는다면 "하나라도"인지 "전부"인지도.
   - **제안: 하나라도.** 회색과 대칭이 아니어야 한다. 회색은 *"이 그룹은 아무 일도 안 한다"*는
     그룹의 상태 서술이라 전부일 때만 참이지만, 빨강은 *"여기 고칠 것이 있다"*는 안내라 하나면
     성립한다.
   - **결정적인 것은 접힘이다.** 접힌 그룹의 요약은 **첫 액션 하나**만 보여준다
     (`navigating-the-overview.md`). "전부일 때만" 규칙이면 한 행만 망가진 그룹은 접힌 채로
     아무 표시가 없고, 그 행은 요약에도 안 뜬다.
   - 같이 정할 것: **색이 겹칠 때의 순서.** 지금 파랑(배지)이 있고 회색이 있는데 빨강이 셋째로
     들어온다. 머리글은 한 색뿐이다.
4. **문제가 있는 키를 흐리게 할 것인가.** 지금은 안 흐려진다.
   - 배경 문서가 회색의 판정을 *"빌드에 들어갔는가"*(`IsInactiveAction`)라고 적어뒀는데, 실제로 재고
     있는 것은 **키 맵 진입을 시도했는가**다. `ActiveActions[action] = ordinal`이 `not issue` 게이트
     **밖**에 있기 때문이다(`Debind.lua`).
   - 그래서 **머리글 회색은 자기 정의를 절반만 지킨다.** 전부 이슈로 죽은 그룹은 아무것도 안 도는데
     흰색이다. 3번을 "하나라도 빨강"으로 정하면 그 그룹은 빨강으로 덮이므로 이 구멍이 화면에서는
     닫힌다 — **고치는 것이 아니라 가려지는 것**이라 여기 적어둔다.
5. **`CLIQUE_DETECTED`를 지울 것인가.** 등급표에 안 넣기로 하면 남는 선택은 삭제뿐이다. 남기려면
   내는 자리와 로케일 짝 둘 다 만들어야 하는데, 그 자리는 이미
   `CANNOT_USE_HOVER_WITH_CLIQUE`가 갖고 있다.

## 곁가지 — Clique를 켠 순간 알리기 (등급과 별개)

소유자가 물었다(2026-08-17): *"사용자가 어느날 갑자기 clique를 켰을 때 이거 강하게 경고를
해줘야한다는 느낌도 있다."* **등급이 할 수 있는 일이 아니라서 갈라 적는다** — 빨강은 이미 최대
세기고, 그 세기는 창을 연 사람에게만 있다.

- **그 순간은 언제나 로그인이다.** `DebindPrivate.CliqueDetected`는 `Debind.lua`가 파일 로드
  시점에 `C_AddOns.IsAddOnLoaded("Clique")`를 한 번 읽고 끝이다. 세션 중에 안 바뀐다. 감시 장치도
  새 이벤트도 필요 없고, **자리가 이미 거기 있다**(`Events.lua`의 `WARNING_MESSAGE_CLIQUE_DETECTED`).
- **지금 그 줄의 문제는 세기가 아니라 내용이다.** Clique가 켜져 있으면 무조건 뜬다 — 호버 바인딩이
  하나도 없는 사람에게도. 12개가 죽은 사람에게도 같은 문장이다. 그리고 "일부 기능"은 코드를 아는
  사람의 말이고, 사용자가 잃은 것은 기능이 아니라 자기가 걸어둔 키다.
- **제안: 세는 줄로 바꾼다.** 이 이슈가 붙은 액션이 N개면 그 수를 말하고, 0이면 안 띄운다. 숫자가
  들어가면 그 자체로 강해지고 동시에 무관한 사람에게 안 뜬다. 공짜는 아니다 — 로그인 시점에 그 줄이
  나가는 자리는 `UpdateBindings`가 도는 다음 틱보다 앞이라, 메시지를 미루거나 세기만 따로 돌아야 한다.
- **오버레이/팝업은 반대.** `Events.lua`의 주석이 이미 선을 그어뒀다 — 답해야 하는 것은 창이
  오버레이로 받는다. 옛 애드온 충돌은 **우리가 답을 요구하는** 것이고, Clique는 사용자의 선택이라
  우리가 요구할 것이 없다. 프레임 등록도 Clique가 있으면 우리가 물러나면서(`FrameRegistry.lua`)
  팝업으로 붙잡는 것은 태도가 안 맞는다.
- 창 쪽은 이미 절반 있다: 대상 메뉴의 hover 항목이 Clique면 빨간 줄을 단다(`DebindUI.lua`의
  `UNIT_INFO.hover.tooltipWarning`). **새로 만들려는 사람은 이미 막힌다.** 없는 것은 이미 만들어둔
  사람에게 알리는 길이다.

## 손대는 자리

- `Misc.lua` — `GetBindingIssue`, 등급 테이블이 서는 곳
- `Constants.lua` — `BINDING_ISSUE_*` 목록 (5번을 지우기로 하면 여기)
- `Debind.lua` — `BuildKeyMap`의 `if (not issue ...)`, B로 갈 때만
- `Profile.lua` — `MakeRow`의 `issue` / `unreachable`
- `DebindUI.lua` — `ColoredNameAndIconForAction`, `DebindLineMixin:Update`, `ShowLineTooltip`,
  `GetOrderReasonText`, `DebindKeyHeaderMixin:Init`

**곁다리 하나:** `DebindLineMixin:Update`가 `?` 색칠을 정하면서 `GetBindingIssue`에 없는 갈래 네 개
(`combat`/`known`/`stealth`/`pet`)를 묻고 있다. 항상 nil이라 증상은 없다. 이 작업과 무관하므로
`.zzz/refactor-candidates.md` 40번으로 뺐다.

## 확인 방법

`npm run check`가 색을 못 본다. 등급이 바뀌면 **리로드해서 눈으로** 봐야 하고, 도달 불가는 같은
키에 조건 없는 액션을 둘 이상 걸어야 재현된다. `devdocs/testing-a-change.md`를 먼저 읽을 것.

빨강 12개 중 재현이 제일 싼 것은 `GROUPS_NONE_SELECTED`(그룹 조건에서 전부 해제)와
`UNDEFINED_STATE`(매크로 본문에 `[$없는이름]`)다. `CANNOT_USE_HOVER_WITH_CLIQUE`는
`DebindCliqueFake`가 아니라 **진짜 Clique**가 있어야 한다 — 우리 쪽 더미는 `CliqueDetected`를
안 켠다.
