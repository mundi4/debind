# 개체창 위에서는 그 개체에게. 그리고 `equipslot`이 `useslot`이 된다

> 상태: 계획 확정, 착수 전 (2026-09-06). 다른 세션이 이어받아도 되게 썼다. 근거는 `0-DIARY.md`
> 2026-09-06에 있고 여기엔 결론과 순서만 둔다. 시작 전에 CLAUDE.md, `testing-a-change.md`,
> `writing-user-facing-text.md`, `action-and-binding-shapes.md`, `restricted-environment.md`를 읽을 것.

## 무엇을 하는가

### 1. 액션 옵션 하나

`2`에 회복을 걸어 둔 사람이 개체창 위에서도 그 키를 쓰려면 지금은 hover 조건을 켠 `2`를 하나 더
만들어야 한다. `@hover`가 엄격해서다. 개체창 밖에서는 유닛이 `raid41`(없는 유닛)로 박혀 시전이
실패한다(`SecureBindings.lua`의 `SetUnit`, `COMPOSE_MACROTEXT_SNIPPET`).

새 옵션은 **유닛 풀이 한 줄만 바꾼다.** 켜진 액션은 개체창 위에서는 그 개체창의 개체를, 밖에서는
액션의 원래 대상을 겨눈다. `[@mouseover][@원래대상]`과 같은 뜻.

- **순서에서는 hover 조건 없는 액션 그대로다.** hover 유닛 조건(반응·죽음·역할)도 없다. 개체창
  위에서 가려 받고 싶으면 그 앞에 hover 조건 액션을 얹는다. 지금 규칙과 같다. 솔버가 볼 것이 새로
  없고, 유닛만 실행 시점에 갈린다.
- **hover 조건이 켜진 액션에서는 무시한다.** 그 액션은 개체창 위에서만 실행되고 그때 유닛은 이미 그
  개체다. 결과가 같으니 값은 남기고 읽지 않는다("옵션을 끄면 값은 남긴다"). 메뉴에서는 hover 조건이
  없을 때만 켤 수 있다.
- **Clique가 켜져 있으면 보이되 잠긴다.** 숨기면 사용자는 잘되던 것이 Clique 때문에 안 되는 줄을 알
  길이 없다. 체크박스는 그대로 보이고 켜져 있던 값도 그대로 보이되 `SetEnabled(false)`, 툴팁이 Clique가
  이 자리를 맡고 있다고 말한다. **액션은 빨갛게 되지 않는다.** 액션은 여전히 원래 대상으로 실행되고 개체창
  위 겨눔만 빠지는 것이라 사용 불가(`ISSUE_GRADE_ERROR`, hover 조건이 Clique에 막힐 때의 등급)가 아니다.
  `ISSUE_GRADE_MINOR` 등급의 문제 하나(`BINDING_ISSUE_HOVER_UNIT_WITH_CLIQUE` 같은 이름)를 새로 두어
  주황이나 경고 표시로 목록에 보이게 한다. 값은 남기고 실행에서만 무시.
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

- **필드.** `action-and-binding-shapes.md`를 읽고 액션 필드 하나를 정한다. 이름은 코드 안에서 정하되
  "hover 유닛으로 겨눈다"가 읽히는 것. `true`/`nil`. `ignoreHoverUnit`이 어떻게 저장·전송·정규화되는지
  따라가서 같은 길을 탄다. `npm run check:export-fields`가 페이로드에 실리는지 잡는다.
- **유닛 풀이.** `SecureBindings.lua`의 두 자리. `COMPOSE_MACROTEXT_SNIPPET`에서 `arg.unit == "hover"`일
  때 `hoverAlias or "raid41"`인 것을, 이 옵션이 켜진 바인딩은 `hoverAlias or 원래 대상`으로. `SetUnit`의
  delegate `unit or "raid41"`도 같은 갈래. **"원래 대상"은 바인딩의 `unit`이고 `none`이면 유닛 속성을
  비운다**(게임의 기본 대상 지정). 옵션을 어떻게 스니펫에 넘기는지는 `ignoreHoverUnit`이 넘어가는 길을
  본다. 스니펫 본문이 바뀌니 골든 둘을 다시 뜨고(`node tools/check-snippet-golden.js --update`,
  `lua5.1 tests/run.lua --update-golden`) diff에서 그 갈래만 바뀌었는지 읽는다.
- **바인딩 준비.** `UpdateBindings.lua`에서 옵션이 켜진 액션은 hover 유닛을 읽는 바인딩으로 표시한다
  (`readsHoverUnit`이 `SETCUSTOM`에 하는 것과 같은 이유. hover 슬롯이 채워져야 풀 유닛이 있다). hover
  조건이 켜져 있으면 표시하지 않는다(무시 규칙).
- **메뉴.** `DropDownMenus.lua`. `IGNORE_HOVER_UNIT` 체크박스 옆. 활성 조건은 셋: 타입이 위 여섯 중
  하나, hover 조건 꺼짐, Clique 꺼짐. 안 맞으면 `SetEnabled(false)`, 값은 지우지 않는다.
- **로케일.** `enUS.lua`, `koKR.lua`. 말은 `writing-user-facing-text.md`대로 클라이언트 것 우선.
  개체창은 "개체창", 유닛은 "개체". 툴팁 한 줄에 "개체창 위에서는 그 개체창의 개체에게, 밖에서는 원래
  대상에게"가 들어가면 된다.
- **헤드리스 (`tests/hover_spec.lua`).** 옵션 켠 `SPELL`이 hover 중엔 hover 유닛으로, 아니면 원래
  대상으로 풀리는 것(대상 `none`과 대상 `focus` 둘 다). hover 조건이 켜진 액션에서는 옵션이 값이
  있어도 유닛이 달라지지 않는 것. `MACROTEXT`·`SETCUSTOM`에는 옵션이 있어도 풀이가 안 바뀌는 것.
  익스포트·임포트 왕복에 필드가 남는 것.
- **`/debtest`.** 옵션 켠 액션을 등록된 테스트 프레임 위에서 hover 상태로 두고 유닛 속성이 그
  프레임의 유닛인지, hover를 풀면 원래 대상인지. 등록만 하고 언급하지 않는다.

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

헤드리스가 드는 것: 유닛 풀이 세 갈래(hover 중, hover 아님, hover 조건 켜짐), 타입 제한, 왕복, 6→7
마이그레이션과 옛 페이로드 수용, 골든.

`/debtest`가 드는 것: 실제 프레임 위에서 유닛 속성이 갈리는 것.

닿지 못하는 것: Clique가 켜진 화면에서 체크박스가 잠기고 툴팁이 이유를 말하는 것. 킷은 Clique 없이 돈다.
