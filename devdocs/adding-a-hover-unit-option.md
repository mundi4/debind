# 개체창 위에서는 그 개체에게. 그리고 `equipslot`이 `useslot`이 된다

> 상태: **커밋 1(옵션)이 들어갔다 (2026-09-06). 남은 것은 커밋 2, `useslot`과 `dbver` 7.** 다른 세션이 이어받아도 되게 썼다. 근거는 `0-DIARY.md`
> 2026-09-06에 있고 여기엔 결론과 순서만 둔다. 시작 전에 CLAUDE.md, `testing-a-change.md`,
> `writing-user-facing-text.md`, `action-and-binding-shapes.md`, `restricted-environment.md`를 읽을 것.
>
> **같은 날 옵션의 실체가 바뀌었다.** 처음에는 유닛 풀이 한 줄이었는데, `units["@"]`가 따라오면 그
> 길이 교집합이 되어 엉뚱한 개체에 나간다. 그래서 옵션은 **액션 하나에서 바인딩 둘을 파생하는 것**이
> 되었고, 가르는 장치는 `legacy/splitting-an-action-into-bindings.md`가 든다. **그 문서가 먼저다.** 옵션의
> 필드(`preferHoverUnit`)와 쌍둥이 바인딩과 헤드리스의 구조 쪽 테스트는 거기 커밋에 들어가고, 여기
> 커밋 1에 남는 것은 메뉴·문구·이슈 등급·매크로 변환이다.

## 무엇을 하는가

### 1. 액션 옵션 하나

`2`에 회복을 걸어 둔 사람이 개체창 위에서도 그 키를 쓰려면 지금은 hover 조건을 켠 `2`를 하나 더
만들어야 한다. `@hover`가 엄격해서다. 개체창 밖에서는 유닛이 `raid41`(없는 유닛)로 박혀 시전이
실패한다(`SecureBindings.lua`의 `SetUnit`, `COMPOSE_MACROTEXT_SNIPPET`).

새 옵션은 켜진 액션을 **바인딩 둘로 가른다.** 개체창 위에서는 그 개체창의 개체를 겨누는 hover
쌍둥이가, 밖에서는 원래 대상을 겨누는 원본이 답한다. `[@mouseover][@원래대상]`과 같은 뜻이고,
`units["@"]` 조건은 각자 자기가 겨누는 개체에게 묻는다. 가르는 장치와 쌍둥이의 모양은
`legacy/splitting-an-action-into-bindings.md` §2.

- **순서에서는 hover 조건 없는 액션 그대로다.** hover 유닛 조건(반응·죽음·역할)도 없다. 개체창
  위에서 가려 받고 싶으면 그 앞에 hover 조건 액션을 얹는다. 지금 규칙과 같다. 쌍둥이는 hover 층에
  안 올라가고 원본 바로 앞에 붙어 선다(같은 문서 §2-3).
- **hover 조건이 켜진 액션에서는 무시한다.** 그 액션은 개체창 위에서만 실행되고 그때 유닛은 이미 그
  개체다. 결과가 같으니 값은 남기고 읽지 않는다("옵션을 끄면 값은 남긴다"). 메뉴에서는 hover 조건이
  없을 때만 켤 수 있다.
- **Clique가 켜져 있으면 보이되 잠긴다.** 숨기면 사용자는 잘되던 것이 Clique 때문에 안 되는 줄을 알
  길이 없다. 체크박스는 그대로 보이고 켜져 있던 값도 그대로 보이되 `SetEnabled(false)`, 툴팁이 Clique가
  이 자리를 맡고 있다고 말한다. **액션은 빨갛게 되지 않는다.** 액션은 여전히 원래 대상으로 실행되고 개체창
  위 겨눔만 빠지는 것이라 사용 불가(`ISSUE_GRADE_ERROR`, hover 조건이 Clique에 막힐 때의 등급)가 아니다.
  `ISSUE_GRADE_MINOR` 등급의 문제 하나(`BINDING_ISSUE_HOVER_UNIT_WITH_CLIQUE` 같은 이름)를 새로 두어
  주황이나 경고 표시로 목록에 보이게 한다. 값은 남기고 실행에서만 무시. 실행에서 무시한다는 것은
  쌍둥이를 안 만든다는 뜻이다(구조 문서 §2-2의 넷째 조건).
- **대상을 받는 타입에만.** `SPELL`, `ITEM`(장난감 포함), `USESLOT`(아래 2), `TARGET`, `FOCUS`,
  `TOGGLEMENU`. `SETCUSTOM`은 hover 전용이라 제외, `MACROTEXT`는 본문이 `@hover`를 이미 쓸 수 있어
  제외, 나머지는 대상이 없다.
- 짝이 되는 기존 옵션은 hover 메뉴의 `IGNORE_HOVER_UNIT`("마우스 올린 개체 무시")이다. 그쪽은 hover
  조건이 켜진 액션에서 "개체창 위여도 내 대상에", 이쪽은 hover 조건이 없는 액션에서 "개체창 위면 그
  개체에". **구현 전에 `IGNORE_HOVER_UNIT`이 코드에서 실제로 무엇을 하는지 따라가서**, 같은 자리
  같은 꼴로 세운다.

### 2. `equipslot` → `useslot`, `dbver` 7

옵션이 `EQUIPSLOT`에도 붙으니 예약돼 있던 개명을 이번에 한다(`0-ROADMAP.md` "다음 `dbver` 범프에").
새 이름은 **`useslot`**. 하는 일(`/use 13`, `UseInventoryItem`)을 말하고, `equip`이 안 들어가고,
게임 명령 `/equipslot`과 겹치지 않는다. 사용자 문구는 안 바뀐다. 코드 상수와 저장값만이다.

개명은 `dbver` 단계와 임포트의 옛 이름 수용을 요구하므로 **이번 판이 `dbver` 7**이다. 선택 필드
하나(위 옵션)는 범프 사유가 아니지만(2026-08-27), 개명이 범프를 요구하고 소유자가 지금 하기로
했다. 범프는 호환 경계라 3.6이 마이너를 사는 근거가 된다(`0-ROADMAP.md`).

## 순서

커밋 둘. 각각 `npm run check`를 통과한다. 새 테스트는 고치기 전에 빨간 것을 먼저 본다.

### 커밋 1. 옵션

- **필드와 쌍둥이는 이미 들어와 있다** (`legacy/splitting-an-action-into-bindings.md`). `SecureBindings.lua`와
  `UpdateBindings.lua`는 이 커밋에서 손대지 않고, 골든도 안 바뀐다. 쌍둥이는 hover 조건이 켜진 평범한
  바인딩이라 스니펫이 이미 아는 모양이다.
- **도달 불가의 일부.** `IsUnreachableAction`은 둘 다 죽었을 때만 참이다(구조 문서 §3-1). 쌍둥이만
  죽은 액션(앞의 hover 액션이 개체창을 다 덮은 것)과 원본만 죽은 액션(개체창 위에서만 나가게 된 것)은
  액션이 여전히 어딘가에서 나가므로 빨갛지 않다. `ISSUE_GRADE_MINOR` 코드 둘
  (`UNREACHABLE_OVER_FRAMES`, `UNREACHABLE_OFF_FRAMES`)로 툴팁에 "개체창 위에서는 앞의 항목이
  받는다" 또는 "개체창 밖에서는 앞의 항목이 받는다". 문장 하나에 코드 하나인 것은 툴팁이
  `BINDING_ERROR_<코드>`만 찍기 때문이다. Clique 잠금과 같은 등급인 것은 셋 다 "옵션이 여기선 뜻이
  없고 액션은 나간다"이기 때문이다. `GetBindingIssue`의 `unreachable` 갈래에서 목록을 돌아 답한다.
  원본만 죽는 것은 마우스 버튼에서만 생긴다. 키보드 키에서는 원본이 제일 넓은 상자라 그걸 덮는 것은
  쌍둥이도 덮는다.
- **매크로 변환.** `ConditionsSurviveMacroText`가 옵션이 켜진 액션을 `known`과 같이 거절한다. 옵션은
  매크로 본문으로 옮겨가지 않고, 조용히 떨어뜨리면 변환된 매크로가 개체창 위에서 다른 개체에게 나간다.
  거절이 맞다.
- **메뉴.** `DropDownMenus.lua`. `IGNORE_HOVER_UNIT` 체크박스 옆. 활성 조건은 셋: 타입이 위 여섯 중
  하나, hover 조건 꺼짐, Clique 꺼짐. 안 맞으면 `SetEnabled(false)`, 값은 지우지 않는다.
- **로케일.** `enUS.lua`, `koKR.lua`. 말은 `writing-user-facing-text.md`대로 클라이언트 것 우선.
  개체창은 "개체창", 유닛은 "개체". 툴팁 한 줄에 "개체창 위에서는 그 개체창의 개체에게, 밖에서는 원래
  대상에게"가 들어가면 된다.
- **헤드리스.** 구조 쪽(목록, 인접, 왕복)은 구조 문서의 커밋이 들었다. 여기서는 `issue_spec.lua`와
  `grade_spec.lua`에 쌍둥이만 죽은 액션과 원본만 죽은 액션이 MINOR 문장 각각을 내고 빨갛지 않은 것,
  둘 다 죽으면 `UNREACHABLE`인 것. `macrotext_spec.lua`에 옵션 켠 액션의 변환이 거절되는 것.
  `MACROTEXT`·`SETCUSTOM`에 옵션이 있어도 쌍둥이가 안 생기는 것은 타입 제한이 메뉴에만 있으면 안
  되므로 파생 조건에도 있어야 하고, 그것은 `normalize_spec.lua`에.
- **`/debtest`.** 구조 문서의 커밋에 등록돼 있다. 여기서 더할 것은 없다.

### 커밋 2. `useslot`과 `dbver` 7

- `Constants.lua`: `Constants.EQUIPSLOT = "equipslot"`을 `Constants.USESLOT = "useslot"`으로. 코드
  전체의 `EQUIPSLOT`을 따라 바꾼다(`grep -rn "EQUIPSLOT\|equipslot" Debind DebindDev tests tools`).
  로케일 키에 `EQUIPSLOT`이 들어 있으면 키만 바꾸고 문구는 그대로.
- `Constants.DB_VERSION = 7`. `Profile.lua`의 `MigrateLayer`에 `if (dbver <= 6) then` 단계 하나. 액션의
  `type == "equipslot"`을 `"useslot"`으로. **`<=`로, 다른 단계와 같이.** `npm run check:dbver`가
  사다리 셋(`check-dbver.js`가 보는 곳)과 맞는지 잡는다. 세 곳 다 올린다.
- **임포트가 옛 이름을 받는다.** 3.5 이하가 내보낸 문자열엔 `equipslot`이 그대로 실려 온다. 페이로드의
  `dbver`가 6 이하면 같은 단계를 지나게 한다(`OLDEST_PAYLOAD_DBVER`와 페이로드 사다리를 볼 것).
- **되돌림 방어.** `profileIsNewer`(3.5로 내려간 사람이 7짜리 프로필을 만나는 경우)는 이미 있는
  장치다. 손댈 것은 없고, 테스트가 7에서도 서는지만 본다.
- `0-ROADMAP.md`: "다음 `dbver` 범프에" 줄을 "3.6에 들어갔다"로. `action-and-binding-shapes.md`의
  `equipslot` 언급을 `useslot`으로.
- **헤드리스.** `tests/migration_spec.lua`에 6→7 단계(액션 타입 개명, 다른 타입은 그대로),
  `tests/import_spec.lua`에 `dbver` 6 페이로드의 `equipslot`이 `useslot`으로 들어오는 것. 둘 다 지금
  코드에서 빨갛다.

### 문서 (커밋 2에 같이)

- `CHANGELOG.md` 3.6 절에 옵션 한 문단. 개명은 사용자에게 보이지 않으니 노트에 안 쓴다.
- 이 문서를 `devdocs/legacy/`로.
- **`0-DIARY.md`의 2026-09-06 치는 이미 써 있다**(이 문서와 같은 시점에, 커밋 전). 커밋 1에 같이
  태운다. 구현 중 소유자와 새로 갈린 것이 있으면 그 밑에 덧붙인다.

## 하지 말 것

- 옵션에 hover 유닛 조건(반응·죽음·역할)을 싣지 않는다. 그건 hover 조건 액션의 것이다.
- 순서 규칙("hover가 먼저")을 건드리지 않는다. 이 옵션의 액션은 평범한 액션이다.
- `@hover` 대상의 엄격함(`raid41`)은 그대로 둔다. 개체창 밖에서 절대 안 나가게 하려고 그걸 고른 사람이
  있다.
- 옵션 켜기를 자동으로 하지 않는다. 가져오기도 이 옵션을 켜지 않는다.
- 푸시하지 않는다.

## 커버리지

헤드리스가 드는 것: 도달 불가의 세 갈래(쌍둥이만, 원본만, 둘 다)와 그 등급, 매크로 변환 거절, 타입
제한, 6에서 7로의 마이그레이션과 옛 페이로드 수용. 목록·인접·왕복·마우스 버튼 갈림은 구조 문서의
커밋이 든다.

`/debtest`가 드는 것: 실제 프레임 위에서 유닛 속성이 갈리는 것(구조 문서의 커밋에 등록).

닿지 못하는 것: Clique가 켜진 화면에서 체크박스가 잠기고 툴팁이 이유를 말하는 것. 킷은 Clique 없이 돈다.
