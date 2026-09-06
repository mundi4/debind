# 액션 하나를 바인딩 여럿으로 가르기

> 상태: 들어갔다 (2026-09-06). 근거는 `0-DIARY.md` 2026-09-06에 있고 여기엔 결론과
> 순서만 둔다. `adding-a-hover-unit-option.md`의 커밋 1이 이 구조 위에서 돌므로 **그 문서보다
> 먼저 읽고 먼저 구현한다.** 시작 전에 `action-and-binding-shapes.md`와 `testing-a-change.md`를
> 읽을 것.

## 1. 왜 가르나

지금은 액션 하나가 바인딩 하나다. `GetBindingInfoForAction`이 액션당 표 하나를
`_ActionToBindingCache`에 두고 리빌드마다 제자리에서 다시 채우고, `BuildKeyMap`의
`BindingInfoToActionMap`과 `Placements`가 그 표 하나를 키로 쓴다.

`preferHoverUnit`(hover 조건 없는 액션이 개체창 위에서만 그 개체를 겨눈다)이 그 모양에 안 들어간다.
`units["@"]`는 액션이 겨누는 대상을 가리키는 포인터라, 겨눔이 개체창의 개체로 옮겨가면 그 조건도 그
개체에게 물어야 한다. 그러면 발동 조건이 **(hover 개체가 조건 만족) 또는 (원래 대상이 조건 만족)**이
된다. 액션이 합집합을 가진 적이 없다. 솔버는 조건 집합을 상자 하나로 보고, 두 축의 합집합은 상자가
아니다(`Solver.lua` 머리 주석: 축을 한 컬럼에 접는 것은 곱으로는 되고 합으로는 무너진다).

겨눔만 옮기고 조건은 원래 대상에만 재면 교집합이 되는데, 그건 "안 나감"이 아니라 **엉뚱한 개체에
나감**이라 되돌릴 수 없다.

액션 하나를 바인딩 둘로 파생하면 각각이 상자라 솔버가 그대로 선다. hover 쪽은 "같은 액션에 hover
조건을 켜고 대상을 비운 것"이라 스니펫도 순서 규칙도 손댈 것이 없다. 계획서가 처음 잡았던 "유닛
풀이 한 줄만 바꾼다"는 길은 그래서 접는다. 그 길은 `@`가 없을 때만 맞고, 있을 때는 위의 교집합이다.

**같은 장치를 나중에 쓸 자리가 하나 더 있다.** 전문화가 주문을 정하는 부활
(`adding-spec-resolved-actions.md`)이 대규모와 단일을 클릭 시점 몸통 대신 바인딩 둘의 순서로 풀
수 있다. 그쪽은 "대상이 내 파티나 공격대인가"라는 축이 하나 더 필요하고 **이 문서에서는 정하지
않는다.** 여기서 만드는 것은 가르는 장치까지다.

## 2. 모양

### 2-1. 원본과 파생

액션 하나가 **바인딩 목록**을 낸다. 첫째가 **원본**이고 지금의 바인딩 그대로다. 나머지가 **파생**이다.

```
GetBindingInfoForAction(action)      원본 하나. 지금과 같은 함수, 같은 표, 같은 호출부
GetBindingsForAction(action)         목록. [1]이 원본이고, 그 뒤가 파생. 액션당 배열 하나를 약한
                                     키 표에 두고 리빌드마다 제자리에서 다시 채운다
```

**원본을 받는 자리는 안 바뀐다.** 이슈 검사(`GetBindingIssue`), `MakeOrderRecord`,
`IsConditionalAction`, 매크로 변환(`ConditionsSurviveMacroText`와 그 짝), `MakeRow`의 전문화 조건,
헤드리스 스펙의 `normalize`가 전부 원본에 묻는 것이고, 액션의 답은 원본의 답이다. 목록을 받는 것은
`BuildKeyMap` 하나다.

**파생은 액션에서 만든다, 원본을 복사하지 않는다.** 정규화가 `unit`을 보고 `"@"`를 지우거나
hover를 채워 넣는 순서가 있어서(`action-and-binding-shapes.md` §4), 원본을 복사해 고치면 이미 지워진
`"@"`를 되살릴 길이 없다. 그래서 `GetBindingInfoForAction`의 본문을 **채우기 함수 하나**로 뽑고,
원본과 파생이 그 함수를 다른 인자로 부른다. 인자는 둘이다. 처음에 놓을 `unit`과, `units["hover"]`에
얹을 조건. 원본은 둘 다 액션 것이고, 파생이 그걸 바꾼다.

**파생마다 자기 표.** 원본과 같이 약한 키 표에 살고 제자리 재사용이다. `BuildKeyMap`이 리빌드마다
모든 바인딩을 도는데 예전에는 할당이 없었다. 그 성질을 지킨다.

### 2-2. 첫 파생: `preferHoverUnit`의 hover 쌍둥이

이 문서의 구조는 첫 손님과 같이 들어간다. 옵션의 **필드**는 여기서 정하고(`preferHoverUnit`,
`true`/`nil`, `KEYS_TO_SAVE`와 `Export.lua`의 `ACTION_FIELDS`), 메뉴와 문구와 이슈 등급은
`adding-a-hover-unit-option.md`가 든다. 필드가 먼저 들어가는 것은 헤드리스 스펙이 액션 표에 그 필드를
써서 파생을 일으켜야 해서다. 테스트만을 위한 갈고리를 두지 않는다.

쌍둥이가 만들어지는 조건 넷. **하나라도 아니면 목록은 원본 하나다.**

- `action.preferHoverUnit`이 참
- 타입이 옵션을 받는 여섯 중 하나(`SPELL`, `ITEM`, `USESLOT`, `TARGET`, `FOCUS`, `TOGGLEMENU`,
  `adding-a-hover-unit-option.md` §1). 메뉴가 같은 목록으로 체크박스를 잠그지만, 공유 프로필은 메뉴를
  안 거치므로 여기서도 본다. 목록은 상수 하나로 두고 둘이 같이 읽는다. 이 커밋 시점에는 아직
  `EQUIPSLOT`이고, 개명 커밋이 이름을 따라 바꾼다.
- 원본의 `hover`가 nil. hover 조건이 켜진 액션은 개체창 위에서만 실행되고 그때 유닛이 이미 그
  개체라 결과가 같다. 값은 남기고 읽지 않는다.
- `DebindPrivate.CliqueDetected`가 거짓. 켜져 있으면 쌍둥이는 hover 클릭캐스트 레코드가 되어 Clique와
  같은 자리를 다투고, 이슈 검사는 원본만 봐서 그걸 못 잡는다. 안 만드는 것이 유일하게 맞는 답이다.

쌍둥이의 인자: `unit`은 처음부터 `"hover"`, `units["hover"]`는 빈 조건(모든 개체창, 모든 반응).
`ignoreHoverUnit`은 nil. 나머지는 액션 것 그대로.

`unit`을 처음부터 `"hover"`로 두는 것이 핵심이다. 정규화의 `"@"` 정리가 `unit`이 nil이나 `"none"`이나
`"player"`일 때 `"@"`를 지우는데, 쌍둥이의 `"@"`는 살아서 hover 개체를 가리켜야 한다. 그리고 그
뒤의 `BuildUnitStates`가 `"@"`를 `binding.unit`의 유닛으로 접으니 hover 컬럼이 저절로 좁아지고,
방출부의 유닛 병합도 같은 키로 접는다. 새 코드가 아니라 있던 코드가 맞는 답을 낸다.

### 2-3. 순서: 인접은 규칙이 아니라 구조다

**파생 바인딩은 hover 층에 올라가지 않는다.** 암묵적으로 hover 조건을 가진 것은 hover 조건이
아니다. 쌍둥이를 hover 층에 두면 그 사이에 다른 hover 액션과 원본보다 앞선 비hover 액션이 다
끼어들고, "가려 받고 싶으면 그 앞에 hover 액션을 얹는다"는 규칙이 원본에게만 성립한다.

그래서 `BuildKeyMap`은 **원본만 정렬하고, 정렬이 끝난 뒤 각 원본을 자기 목록으로 펼친다.**

```
KeyMap[key] = { ...정렬된 원본들 }                지금
KeyMap[key] = { 원본1의 파생..., 원본1, 원본2의 파생..., 원본2, ... }   바꾼 뒤
```

- `Placements`는 원본만 키로 든다. `CompareActionOrder`와 `Ordering.lua`는 **한 글자도 안
  바뀐다.** 파생은 비교자에 들어가지 않으므로 같은 placement를 가진 둘을 가르는 부호를 레코드에
  더할 필요가 없고, `sort`가 불안정하다는 문제도 안 만난다.
- 목록 안의 순서는 파생이 낸 순서 그대로다. 파생이 원본 앞이다. 쌍둥이는 좁은 상자라 원본 앞에
  서야 개체창 위에서 먼저 답한다.
- 다른 액션이 같은 목록에 들어올 길이 없으니 인접은 보장이 아니라 사실이다.

### 2-4. 죽는 것

`BindingInfoToActionMap`과 `GetKeyMap`을 지운다. `GetKeyMap`은 호출부가 없고(`Debind/`,
`DebindDev/`, `tests/` 전부), 역방향 표는 그 함수만 먹였다. 바인딩에서 액션으로 되돌아가는 길이
필요해지면 그때 만든다. 지금 만들면 파생마다 같은 액션을 가리키는 표가 되고, 쓰는 데가 없는 표는
낡아도 아무도 모른다.

## 3. 따라오는 것

### 3-1. 솔버

`CheckUnreachableBindings`는 정렬된 배열을 받고 바인딩마다 상자를 세운다. 펼친 배열을 그대로 준다.
**바뀌는 것이 없다.** 쌍둥이(작은 상자)는 원본(큰 상자)을 못 덮고 원본은 자기 뒤에 있는 쌍둥이를
덮을 수 없으니 둘 다 선다. 원본 뒤에 놓인 다른 hover 액션이 쌍둥이에 덮여 떨어지는 것은 맞는
답이고, 그게 화면에 도달 불가로 보이는 것도 맞다. 개체창 위에서는 쌍둥이가 받는다고 사용자가
정한 것이다.

`IsUnreachableAction(action)`은 **목록 전부가 도달 불가일 때만** 참이다. 지금은 원본 하나를
묻는데, 쌍둥이만 죽은 액션은 원래 대상으로 여전히 나가니 그 액션이 죽었다고 하면 거짓말이다.
`row.unreachable`(`MakeRow`)과 툴팁(`GetBindingIssue`의 `UNREACHABLE`)이 둘 다 이 함수를 보므로
한 자리만 고치면 둘이 같이 맞는다. 일부만 죽은 경우를 무엇으로 보일지는 옵션 문서의 것이다
(`adding-a-hover-unit-option.md`, MINOR 등급 하나).

### 3-2. 방출

`UpdateBindingsMap`은 `KeyMap[key]`를 돌며 바인딩마다 레코드를 굽는다. 펼친 배열이 그대로 들어가고
**바뀌는 것이 없다.** `PrepareKeyBindings`가 쓰는 `isClickCast`와 `holdsKey`는 바인딩마다 붙는
값이라 쌍둥이도 자기 것을 받는다.

마우스 버튼 키가 저절로 맞게 갈린다. 쌍둥이는 `hover`가 참이라 클릭캐스트 레코드(개체창의 버튼)가
되고 원본은 키를 든다. `BuildUnitStates`가 마우스 버튼 키의 hover 없는 바인딩을 "hover 없음"으로
좁혀 두므로 두 상자가 겹치지도 않는다. 키보드 키에서는 둘 다 키 레코드다.

`SecureBindings.lua`는 안 건드린다. 쌍둥이는 hover 조건이 켜진 평범한 바인딩이라 `raid41` 엄격함이
닿는 상황(개체창 밖)에서는 실행되지 않는다. 골든도 안 바뀐다.

### 3-3. 화면

**액션당 한 줄.** 사용자가 놓은 것은 옵션 하나 켠 액션 하나고, 순서도 그 단위로 서고, 목록이
이어져 있으니 한 줄이 틈 없이 그 자리다. 둘째 줄을 그리면 그 줄은 조건도 순서도 자기 것이 없고
지울 수도 없어서 클릭할 곳이 없는 줄이 된다. 그 줄이 가진 정보는 "개체창 위에서 도달하느냐"
하나라 툴팁 한 문장으로 끝난다.

카드에 두 줄을 그리는 형태는 접었지 버린 것이 아니다. 파생 바인딩이 자기만의 상태를 가질 때(부활의
대규모와 단일처럼 주문이 다르고 하나는 못 배웠을 수 있는 경우) 꺼낸다.

화면 쪽에서 터질 수 있는 자리를 따라간 결과. 전부 **액션 단위**라 파생을 안 본다.

| 자리 | 읽는 것 | 판정 |
|---|---|---|
| `MakeRow`, `CollectActionsForKey` | 액션, 원본 바인딩, `IsUnreachableAction` | 안 바뀜. 도달 불가만 3-1의 뜻으로 |
| `ActionTooltip` | `GetBindingIssue(action)` | 안 바뀜. 같은 함수가 행과 툴팁에 답한다 |
| 순서 화살표, `ComputeOrderSwap`, `RenumberKeyGroup`, `GetDecidingOrderAxis` | 행과 `MakeOrderRecord` | 안 바뀜. 파생은 레코드가 없다 |
| `ActiveActions`, `IsInactiveAction` | 액션 | 안 바뀜 |
| `IsKeyInvalidForAction` | 원본의 `hover` | 안 바뀜. 마우스 버튼에 hover 클릭캐스트가 얹히는 것은 hover 액션이 늘 하던 일 |
| 메뉴의 hover 체크박스(`IGNORE_HOVER_UNIT`) | `action.conditions.units.hover` | 안 바뀜. 쌍둥이의 hover는 바인딩에만 있다 |
| 매크로 변환 | 원본 | 옵션이 매크로 본문으로 안 옮겨간다. 어떻게 할지는 옵션 문서 |
| `DebindDev`의 `GetNthBinding(key, n)` | `KeyMap` 자리 | 옵션 켠 액션이 있는 키만 번호가 밀린다. 기존 테스트는 그런 액션이 없다 |

## 4. 순서

커밋 하나. `npm run check`를 통과한다. 새 테스트는 고치기 전에 빨간 것을 먼저 본다.

- **`Misc.lua`.** `GetBindingInfoForAction`의 본문을 채우기 함수로 뽑는다. `GetBindingsForAction`을
  더한다. 쌍둥이 조건 셋과 인자는 §2-2. `IsUnreachableAction`은 `Solver.lua`에 있고 목록을 돈다.
- **`Profile.lua`, `Export.lua`.** `preferHoverUnit`을 `KEYS_TO_SAVE`와 `ACTION_FIELDS`에.
  `npm run check:export-fields`가 한쪽만 넣은 것을 잡는다.
- **`Debind.lua`.** `BuildKeyMap`이 원본을 정렬한 뒤 펼친다(§2-3). `BindingInfoToActionMap`과
  `GetKeyMap`을 지운다(§2-4).
- **`action-and-binding-shapes.md`.** 표준 문서라 같은 커밋에서 §4를 고친다. "액션 하나의 순수
  파생"은 그대로 참이고 **"하나"가 "목록"이 된다.** 원본과 파생, 원본을 받는 자리와 목록을 받는
  자리, 인접이 구조라는 것을 거기 적는다. 이 문서는 `legacy/`로 가므로 규칙은 저쪽에 남아야 한다.
- **헤드리스.**
  - `normalize_spec.lua`: 옵션 없는 액션의 목록은 길이 1이고 `[1]`이 `GetBindingInfoForAction`과
    같은 표다. 옵션 켠 액션은 길이 2, `[2]`가 원본, `[1]`의 `unit`이 `"hover"`이고 `hover`가 참이고
    `"@"` 조건이 `unitStates.hover`로 접혀 있다. hover 조건이 켜진 액션, `CliqueDetected`가 참인
    경우, 여섯 타입 밖(`MACROTEXT`, `SETCUSTOM`)은 길이 1.
  - `keymap_spec.lua`: 같은 키에 hover 액션 H, 비hover 액션 C, 옵션 켠 액션 A를 C가 A보다 앞에
    오도록 놓으면 `KeyMap`이 `H, C, A쌍둥이, A`다. **쌍둥이가 H 뒤이고 C 뒤인 것**이 이 테스트의
    전부다. 마우스 버튼 키에서 쌍둥이의 `isClickCast`가 참이고 원본의 `holdsKey`가 참인 것.
  - `suppression_spec.lua`: 쌍둥이만 덮인 액션은 `IsUnreachableAction`이 거짓, 둘 다 덮이면 참.
  - `emit_spec.lua`: 키 수 37 그대로.
  - `export_spec.lua`: 왕복에 필드가 남는 것.
- **`/debtest`.** 옵션 켠 액션을 등록된 테스트 프레임 위에서 hover 상태로 두고 키를 누르면 유닛 속성이
  그 프레임의 유닛인지, hover를 풀면 원래 대상인지. 등록만 하고 언급하지 않는다.

그다음이 `adding-a-hover-unit-option.md`의 커밋 1(메뉴·문구·이슈 등급)과 커밋 2(`useslot`)다.

## 하지 말 것

- `Ordering.lua`를 건드리지 않는다. 파생을 비교자에 넣으려는 순간 이 문서의 §2-3이 무너진다.
- 파생에 자기 placement를 주지 않는다.
- 바인딩에서 액션으로 되돌아가는 표를 새로 두지 않는다. 쓰는 데가 생기면 그때.
- 테스트만을 위한 파생 갈고리를 두지 않는다. 첫 손님의 필드가 그 자리다.

## 커버리지

헤드리스가 드는 것: 목록의 길이와 순서, 쌍둥이의 모양(`unit`, `hover`, `"@"`의 접힘), 만들지 않는
조건 셋, `KeyMap`의 인접, 마우스 버튼에서의 갈림, 도달 불가의 새 뜻, 방출 키 수, 왕복.

`/debtest`가 드는 것: 실제 프레임 위에서 유닛 속성이 갈리는 것.

닿지 못하는 것: Clique가 실제로 켜진 클라이언트. 킷은 Clique 없이 돌고, 헤드리스는 플래그만
세운다.
