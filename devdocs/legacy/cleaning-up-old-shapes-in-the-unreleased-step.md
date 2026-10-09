# 옛 저장 모양을 배포 전 단계에서 다 정리하기 (2026-10-10 시작)

> 상태: 다 했다(2026-10-10). 나눔(2절)은 소유자와 정했다(2026-10-09~10). 3절의 0~4단계가 들어갔다.
> `need-fixing.md` 17번에서 자라 나온 일이고, 17번은 이 문서로 옮겼다.
>
> 쓴 세션: `debind-af` (세션 ID `d9fbd825-1a2a-44c4-98fa-a5173c039ed5`).

## 1. 무엇이 문제인가

**읽는 쪽이 옛 판의 저장 모양을 읽는 갈래를 들고 있다.** `Issues.lua`의 `StoredUnitRows`가 하는
`rawget(action, "checkedUnits")`가 그 예다. 바인딩을 짓는 쪽, 이슈 검사, 툴팁에 같은 종류가 여럿 있다.
저장 모양을 옮길 때마다 "사다리가 아직 안 닿은 프로필"을 읽으려고 남긴 것들이다. `checkedUnits`의
경우는 2026-08-20(`bc8bf87`)에 들어갔고, 2026-09-17(`fccc813`)에 `Issues.lua`가 그대로 베꼈다.

**그런 프로필은 읽는 쪽에 오지 않는다.** 사다리는 접속 때 누가 무엇을 읽기 전에 끝까지 돈다. 사다리가
실패하면 애드온은 물러나고 아무것도 읽지 않는다. 그 뒤 들어온 sanitize가 그 이름들을 모든 문에서 지우니,
지금 이 갈래들에는 데이터가 하나도 닿지 않는다.

**남겨 두면 같은 바꾸기가 두 벌이 되고, 두 벌은 이미 갈렸다.** 예를 들어 `unitframe` 행이 없을 때
옛 `frameTypes`를 사다리(6 -> 7 단계)는 끈 행에 넣어 기억하는데, `FillBinding`은 버린다.

**sanitize에도 기준이 없다.** 옛 모양 가운데 스칼라 유닛 행과 행 이름 `hover`는 옮기고, 최상단
`hover`·`reactions`·`checkedUnits`·`frameTypes`는 지운다.

## 2. 정한 것 (소유자, 2026-10-09~10)

- **마이그레이션은 옛 판의 모양을, 그 판이 읽던 뜻대로 다음 판의 모양으로 옮긴다.** 7 -> 8 단계가
  끝나면 8판이 실제로 쓰는 필드만 남는다. 지난 단계들이 처리했어야 하는데 남은 것도 이 단계가 정리한다.
  sanitize가 뒤에서 치워 줄 것을 기대하지 않는다. 서랍은 사다리가 남긴 모양을 그대로 보관하기 때문이다.
  - 이 단계가 그 일을 맡을 수 있는 까닭: 8판은 아직 배포되지 않았다(v4.1.2까지 `DB_VERSION = 7`).
    그래서 지금 있는 모든 사용자 데이터가 이 단계를 꼭 한 번 지난다. 손으로 고친 데이터도 마찬가지다.
- **sanitize는 사다리를 끝낸 8판 데이터만 다룬다.**
  - 8판이 쓰지 않는 이름은 우리가 그 뜻을 알든 모르든 지운다. 옛 판에서 뜻이 있던 이름도 8판에서는 뜻이
    없다. 8판 빌드가 읽은 적이 없으므로 지워도 잃는 조건이 없다.
  - 8판이 쓰는 필드의 틀린 값은 8판 규칙 안에서 바로잡거나 지운다. 범위 밖 마스크 비트 자르기, NaN을
    0으로 두기, 기본값과 빈 표 접기, 번호 다시 매기기, 타입이 깨진 액션을 `"invalid"`로 두기가 그렇다.
  - 다른 판의 모양을 해석하지 않는다.
- **나머지 코드는 8판 모양만 읽는다.** 과거 형식을 읽으려는 갈래는 하나도 남기지 않는다.
  - 남기는 것은 터짐을 막는 가드뿐이다. `UnitConditionForBinding`이 표가 아닌 값을 `false`로 읽는
    갈래가 그것이다. 세션 안에서 `/run`으로 넣은 값은 어느 문도 안 지나고 리빌드에 닿는다. 그런 숫자나
    불리언을 표처럼 읽으면 리빌드가 터진다. `Talents.ListOf`와 `Specs`의 `MaskFor`를 남긴 것과 같은
    까닭이다. 이 가드는 값을 해석하지 않는다.

### 버린 안

- **sanitize가 "우리가 뜻을 아는" 옛 이름을 옮긴다** (2026-10-09에 잠깐 정했다가 버림). 같은 바꾸기가
  사다리와 sanitize에 두 벌이 된다. 그리고 "뜻을 안다"에 "어느 판에서"가 빠져 있었다. 옛 이름의 뜻은 그
  이름을 쓰던 판에서 정해지므로, 그 뜻대로 옮기는 것은 사다리의 일이다. 다시 볼 계기: 배포된 8판 데이터에
  옛 이름이 섞여 들어오는 경로가 생길 때.
- **읽는 쪽의 옛 갈래를 가드로 남긴다** (`need-fixing.md` 17번의 처음 글). 그런 데이터가 오지 않으니
  가드가 막을 것이 없고, 남기면 같은 바꾸기의 둘째 벌이 된다.
- **옛 필드와 오늘 자리가 함께 있을 때 둘을 합치거나 옛 것을 살린다.** 배포된 어느 빌드도 그런 모양을
  만들지 않았다. 그리고 오늘 자리가 차 있으면 7판 빌드도 옛 것을 읽지 않았다. 예를 들어 `checkedUnits`는
  `conditions.units`가 있으면 읽히지 않았다. 그러니 옛 것은 지운다.

## 3. 할 일 (순서대로)

**단계마다 테스트를 먼저 쓰고, 지금 코드에서 빨간 것을 본 뒤 고친다.**

### 0. 문서를 2절에 맞춘다

`sanitizing-actions-with-one-function.md`에 2026-10-09에 넣은 "우리가 뜻을 아는 옛 이름은 옮긴다"(6-1,
머리말, 6-6의 1번)를 걷는다. "표에 없는 이름은 우리가 그 뜻을 알든 모르든 지운다. 옛 모양을 옮기는 것은
사다리의 일이다"로 바꾼다. 6-5의 두 줄(스칼라 행을 편다, 행 이름 `hover`를 옮긴다)의 "지운다"는 정답표가
코드를 따라야 하므로 2단계에서 코드와 같이 바꾼다.

했다(2026-10-10, `debind-af`). 6-5의 두 줄에는 "6-1의 규칙에 따라 지우게 바뀐다"만 붙였다.

### 1. 7 -> 8 단계가 옛 모양을 다 정리한다

`MigrateLayer`의 `dbver <= 7` 단계, 마지막 패스에서 한다.

1. **효력이 있던 옛 모양을 옮긴다.** 대상은 최상단 `hover`·`reactions`·`checkedUnits`·`frameTypes`,
   `conditions.frameTypes`, 행 이름 `hover`, 스칼라 유닛 행, 대상 칸의 `unit = "hover"`다.
   - 7판 빌드는 이것들을 바인딩 쪽 갈래로 실제 조건으로 읽었다. 그러니 7판이 읽던 뜻대로 옮긴다. 그 뜻은
     v4.1.2의 읽는 쪽을 git으로 꺼내 읽고, 단계 안에 7판의 값으로 적는다(`MigrateLayer` 머리주석의 규칙).
   - 오늘 자리가 차 있어서 7판이 옛 것을 읽지 않았던 경우는 옮기지 않고 지운다.
2. **그다음 8판이 쓰지 않는 이름을 모두 지운다.** 액션 최상단, `conditions`, `casting`, 유닛 행 안이
   대상이다. 목록은 단계 안에 8판의 값으로 적는다(`_AT_8`). 오늘의 `KEYS_TO_SAVE`는 앞으로 바뀌므로 읽지
   않는다.
3. **두 번 돌아도 결과가 같아야 한다.** 서랍 항목은 제자리에서 올라가므로 이 단계를 두 번 만날 수 있다.
4. **받은 문자열도 이 단계를 탄다.** 타입이 틀린 값에서 터지면 안 된다.
5. 마지막 패스 머리주석의 "손으로 만든 값은 `SanitizeAction`의 몫"을 고친다. 이 패스는 8판 이전에 남은
   것을 손 편집까지 모두 정리한다.

이미 8판이 된 개발 프로필은 이 단계를 다시 돌지 않는다. 거기 남은 옛 이름은 sanitize가 지운다. 배포 전의
개발 데이터라 그것으로 충분하다.

했다(2026-10-10, `debind-af`).
- 7판이 읽던 뜻은 v4.1.2의 `FillBinding`과 `Units.lua`에서 읽었다. 짝 접기는 5판의 것과 줄마다 같아서
  `UnitFrameConditionAt5`를 그대로 부른다. 행은 `UnitConditionAt7`로 읽는다.
- **스칼라 넷이 아닌, 표도 아닌 행 값은 그대로 둔다.** 옛 모양이 아니라 8판이 쓰는 이름 밑의 깨진 값이고,
  `combat`이 불리언이 아닌 것과 같은 경우라 sanitize의 몫이다. 처음에는 지웠는데, "dbver 5 does not change
  what an unknown value means"가 빨개져서 다시 봤다.
- 8판 이름 목록은 `Migration.lua` 맨 위의 `_AT_8` 표들이다. 마지막 패스가 따로 지우던 `checkUnitExists`,
  `checkedUnit`, `checkedUnitValue`, `reactions`는 이 표에 없는 이름이라 거르기에 들어갔다.
- `orderupgrade_spec`의 코퍼스가 액션에 제 필드(`shapeName`)를 붙여 두고 있었다. 거르기가 그것을 지워서, 액션
  옆의 표로 옮겼다.

### 2. sanitize가 8판 모양만 다루게 한다

- 스칼라 유닛 행과 행 이름 `hover`를 옮기던 일을 걷고, 지우게 한다. sanitize 문서 6-5의 두 줄도 같이
  "지운다"로 바꾼다.
- **픽스처를 같이 8판 모양으로 고친다.** 스펙 픽스처 가운데 옛 스칼라 행(`units = { target = true }`
  같은 것)을 쓰는 줄이 많다. sanitize를 만들 때 199줄이었다. 지금은 sanitize가 펴 주는 데 기대고 있어서,
  sanitize만 바꾸면 조건이 말없이 사라져 테스트가 엉뚱하게 지나거나 빨개진다.

했다(2026-10-10, `debind-af`).
- **픽스처를 찾는 데 확인 장치(`tests/canonical.lua`)를 넓혔다.** 이제 유닛 행도 본다. 행 이름이 메뉴의 유닛
  목록이나 `"@"`에 있는지, 행이 표인지, 행 안의 이름과 타입이 `UNIT_CONDITION_FIELDS`에 맞는지다. 넓히자 저장된
  액션으로 들어가는 픽스처 19곳이 걸렸다. 18곳은 `false` 스칼라 행이었고, 하나는 옛 행 이름 `hover`였다.
- `false` 행을 `{ exists = false }`로 바꿨다. `answer_rows`, `convert_spec`, `display_spec`, `emit_fixture`,
  `eval_spec`, `hovertwin_spec`, `issue_spec`, `keymap_spec`, `plan_spec`이다. 옛 행 이름을 쓰던 `display_spec`의
  테스트는 3단계에서 걷을 것을 앞당겨 걷었다.
- 확인 장치는 행에 모드(`exists`나 `disabled`)가 없는 것은 보지 않는다. 그런 픽스처가 많고, 8판도 모드 없는 행을
  "있을 때"로 읽으므로 옛 모양이 아니다.
- 바인딩 모양을 직접 만드는 픽스처(`solver_spec`, `bench.lua`)의 `false`는 바인딩 모양 그대로라 두었다. 그쪽의
  `true`·`"help"` 같은 스칼라는 3단계에서 스칼라 읽기를 걷을 때 바꾼다.

### 3. 과거 형식을 읽는 코드를 다 걷는다

- `need-fixing.md` 17번에 적혀 있던 것: `FillBinding`과 `StoredUnitRows`의 `rawget(action, "checkedUnits")`,
  `action.hover` 갈래와 `UnitFrameConditionFromLegacy`, `legacyFrameTypes`, 행 이름 `hover`와 대상 `"hover"`
  바꾸기(`FillBinding`, `StoredUnitFrameCondition`, `RowUnitName`, 툴팁), 스칼라 갈래(`UnitConditionForBinding`,
  `UnitConditionToState`).
- **그 목록 밖도 찾는다.** `Migration.lua`와 `Sanitize.lua` 밖에서 옛 이름을 읽는 곳을 찾는다. `off`,
  `setstate_*`, `specialbar`, `petbattle`, `pinRank`, `"usual"`, `"command"`, `"unused"` 같은 이름이다.
  다른 까닭으로 남겨야 하는 것이 나오면 걷기 전에 소유자에게 말한다.
- `UnitConditionIsUnreadable`은 표가 아닌 값을 모두 못 읽는 값으로 친다. 지금은 스칼라 넷을 읽을 수 있는
  값으로 친다. 그대로 두면 `/run`으로 넣은 `true`가 "유닛 없을 때"로 읽혀 키에 오른다.
- 옛 갈래를 위해 있던 테스트를 걷는다. `convert_spec`의 "마이그레이션 전 모양은 못 바꾼다"와
  `display_spec`의 "a unit frame condition saved under the old name still draws its line"이다.
  뒤의 것은 `InitDB`를 거쳐 sanitize가 먼저 이름을 옮기므로, 이름과 달리 툴팁에 닿지 않는다.

했다(2026-10-10, `debind-af`).
- 걷은 것: `FillBinding`의 `aimedUnit == "hover"`·`checkedUnits`·행 이름 `hover`·`action.hover`·
  `legacyFrameTypes`, `ActionUnitFrameIsOn`의 `action.hover`, `Units.lua`의 `UnitFrameConditionFromLegacy`와
  스칼라 표(`UNIT_SCALAR_TO_STATE`), `StoredUnitFrameCondition`의 `units.hover`, `UnitConditionToState`의 스칼라
  갈래, `Issues.lua`의 `checkedUnits`·`RowUnitName`·`action.hover`, 툴팁의 `hover` 줄.
- **목록 밖에서 하나 더 나왔다.** `MacroText.lua`의 `AimedUnitKeyForMacroText`가 "바인딩은 살아 있는 `"@"`를
  드는데 저장된 `conditions.units`에는 없다"는 경우를 따로 들고, 그때 변환을 거절했다. 그 경우는 바인딩이 평평한
  `checkedUnits`를 읽을 때만 생겼다. 그 갈래와 주석을 걷었다.
- 옛 이름(`off`, `setstate_*`, `specialbar`, `petbattle`, `pinRank`, `"usual"`, `"unused"`)으로 찾은 나머지는
  옛 모양을 읽는 곳이 아니었다. 오늘의 값이거나(`"usual"`은 Self Cast Key·Focus Cast Key 줄의 값이고 Hover Cast의
  선택 이름이다), 게임이 읽는 조건 이름이거나(`[petbattle]`), 페이로드의 사다리(`Export.lua`의
  `BringPayloadForward`)였다. Hover Cast에 저장된 `"usual"`을 설명하던 주석 둘은 걷었다. 7 -> 8 단계가 그 값을
  지우므로 설명할 데이터가 없다.
- `UnitConditionIsUnreadable`은 이제 표가 아닌 값을 모두 못 읽는 값으로 친다.
- 테스트 정리. 옛 모양을 읽는 쪽에 바로 넣던 픽스처는 8판 모양으로 바꿨다. `issue_spec`과 `normalize_spec`은
  스칼라를 이름으로 쓰던 자리를 `Row` 도우미로 받아 행을 쓴다. `solver_spec`은 바인딩 모양을 직접 만드므로
  `{}`·`{ reaction = ... }`로 바꿨다. 옛 읽기 자체를 묻던 테스트는 걷었다. 옛 `hover` 짝과 옛 대상 이름,
  "옛 스칼라도 여전히 읽힌다", 사다리 전 모양을 바인딩에 넣어 사다리 뒤와 맞대던 두 테스트(`migration_spec`)가
  그것이다. 사다리 뒤의 짝은 남아서 같은 리터럴을 계속 묻는다.

### 4. 테스트

- `migration_spec`: 옛 모양마다 7판 액션을 8판으로 올려, 7판이 읽던 조건이 그대로인지 묻는다.
- `migration_spec`: 사다리의 결과가 sanitize를 거치기 전에 이미 8판 필드만 갖는지 묻는다. 입력은 옛 판
  개발 시드와 옛 판 문자열이고, 검사는 `tests/canonical.lua`의 확인 장치로 한다.
- `sanitize_spec`: 스칼라 행과 행 이름 `hover`가 지워지는지 묻게 고친다.
- `npm run check`.

했다(2026-10-10, `debind-af`). 테스트가 가진 것과 못 닿는 것은 이렇다.
- **7 -> 8 단계:** `migration_spec`의 "The 7 -> 8 step's last pass: old shapes a version 7 profile still held"
  묶음이 옛 모양마다 결과 모양을 통째로 묻는다. 짝 접기 열 가지, 행 마스크 여덟 가지, 두 번 돌리기, 타입이
  틀린 입력이 들어 있다. 모두 고치기 전 코드에서 빨간 것을 봤다. 타입이 틀린 입력의 테스트는 처음에는 접을
  행이 없어서 아무것도 재지 못했다. 가드 하나를 일부러 망가뜨려도 초록이었다. 행이 있는 입력을 더해서, 망가뜨리면
  빨개지는 것을 봤다.
- **사다리를 지난 데이터가 8판 모양인지:** 확인 장치가 이제 유닛 행도 본다. 장치는 `InitDB`마다
  `SanitizeLoadedLayers` 앞에서 돌기 때문에, 개발 시드 5·6·7을 실제 `InitDB`로 올리는 테스트("every development
  seed rides the ladder to the end")가 사다리의 결과를 sanitize 전에 검사한다. 다만 그 시드들에는 이번 단계가
  옮기는 손 편집 모양이 없다. 앞 단계들이 이미 옮겼기 때문이다. 그래서 7 -> 8 단계의 옮기기를 증명하는 것은 위의
  직접 테스트이고, 시드 검사가 아니다(옮기기를 꺼 보니 시드 검사는 초록이고 직접 테스트만 빨갰다). 옛 판 문자열은
  따로 넣어 보지 않았다.
- **sanitize:** `sanitize_spec`의 6-5 줄들. 고치기 전 코드에서 다섯 줄이 빨갰다.
- **`/run`으로 넣은 옛 스칼라:** `issue_spec`의 "an old scalar row is marked invalid"와 `normalize_spec`의
  "표가 아닌 행은 바인딩에 false로만 온다", "유닛 조건 읽기 - 모르는 스칼라는 좁은 쪽으로"가 묻는다.
- `npm run check`가 지난다(두 판의 스펙 2261 + 1894, 린트, 정적 검사).

### 5. 마무리

- 이 문서의 상태 머리말을 고치고, 다 되면 `legacy/`로 옮긴다.
- `/code-review high` 명령을 대상까지 채워 소유자에게 건넨다.

### 리뷰에서 고친 것 (2026-10-10, `/code-review high` 네 번)

**넷째 리뷰**는 깨진 값의 조합을 빼고 보라고 범위를 적어 돌렸다. 단계 안의 지적은 하나였다. 꺼진 `unitframe` 행
옆의 `hover` 행을 지우고 있었다. 7판은 조건으로 읽히는 행만 바인딩에 실었으므로, 그 경우 `hover` 행이 살아 있는
조건이었다. 이제 `unitframe` 행이 조건으로 읽히지 않을 때(없거나 꺼졌을 때) `hover` 행을 옮긴다. 테스트는 고치기
전 코드에서 빨간 것을 봤다. 나머지 다섯은 받은 문자열의 깨진 값에서 6 -> 7 단계가 터진다는 지적이었다. 이 일의
diff 밖이라 `need-fixing.md` 18번으로 옮겼다. 같은 지적이 되풀이되지 않게, `Migration.lua` 머리에 이 파일이
하는 일과 하지 않는 일을 적었다(소유자의 제안).

**쓰레기 값은 이 단계의 일이 아니다** (소유자, 2026-10-10: *"손으로 고치는 쓰레기 값을 고치려고 sanitize가
있는거잖아"*, *"sanitize가 이 쓰레기 값을 다 갖다버리는게 목표야"*). 7 -> 8 단계는 뜻을 아는 옛 모양만 옮기고,
깨진 값에는 판단을 얹지 않는다. 받은 문자열이 이 단계를 타므로 깨진 값 때문에 터지지만 않게 한다. 세 번의 리뷰
가운데 앞의 둘에서 나는 깨진 값의 조합을 하나씩 다루는 갈래를 단계에 더했고, 리뷰는 그때마다 새 조합을 찾았다.
그 갈래들은 셋째 리뷰 뒤에 걷었다. 아래에 무엇이 남았는지 적는다.

- **남은 가드 하나.** 옛 짝을 접을 행의 `reaction`이 숫자가 아니면 접지 않는다. 접으면 `band`가 터진다. 첫 리뷰가
  짚었고, 테스트는 이 가드를 일부러 망가뜨리면 빨개지는 것을 봤다. 행이 표가 아니면 접을 곳이 없으므로
  `UnitConditionAt7`로 읽지 않는다.
- **둘째 리뷰가 짚은 첫 리뷰의 틀린 수정.** 첫 리뷰의 "깨진 스칼라 행을 짝이 덮는다"를 받아 짝을 버리게 했는데,
  sanitize는 표가 아닌 행을 지우므로(6-5) 오히려 넓어졌다. 깨진 값에 대한 결과를 단계에서 정하려 한 것이 잘못이었다.
- **깨진 값의 결과를 못 박던 테스트는 걷었다.** 꺼진 행의 숫자 아닌 `reaction`, 깨진 행 위의 짝, `units = false`
  옆의 `checkedUnits` 같은 것이다. 그 입력들은 "7 -> 8 does not raise on old shapes beside broken values"
  하나에 모아 터지지 않는지만 묻는다.
- **받아서 고친 것.**
  - 첫 리뷰: `KeepOnly`가 술어 대신 이름 표를 받는다. 옛 모양 반복문에만 있던 `luatype(action)` 가드를 걷었다.
  - 둘째 리뷰: 호출하는 쪽의 `reactions == 7` 검사와 `hover ~= false` 변환을 걷었다(`UnitFrameConditionAt5`가
    한다). `MigrateLayer` 머리주석의 "마지막 패스가 유일한 예외"를 "마지막 두 패스"로 고쳤다.
  - 셋째 리뷰: 접은 결과를 필드마다 다시 옮겨 적지 않고 그대로 쓴다. 지운 `UnitFrameConditionFromLegacy`를 살아
    있는 함수처럼 부르던 주석을 고쳤다. "모든 프로필이 이 단계를 한 번 지난다"를 "배포판이 쓴 프로필은 모두"로
    고쳤다. 이미 8판이 된 개발 프로필은 이 단계를 다시 돌지 않는다.
- **택하지 않은 것.**
  - 깨진 값의 조합에 대한 지적 전부(위의 원칙). 셋째 리뷰의 넷이 그랬다. 표가 아닌 `units` 옆의 `checkedUnits`,
    깨진 `unitframe` 옆의 `hover` 행, 불리언이 아닌 `disabled`, 최상단 `frameTypes = false`다.
  - 메뉴에 없는 유닛 이름의 행(`arena1` 등)을 지우지 말라는 지적. 8판에는 그 행을 둘 자리가 없고, sanitize도
    6-5대로 같은 행을 지운다.
  - 6 -> 7 단계와 같은 줄을 함수 하나로 묶으라는 지적. 7 -> 8의 줄은 7판의 읽는 쪽이 한 일이고 6 -> 7 단계는
    그 단계가 한 일로 얼어 있어서, 묶으면 한쪽을 고칠 때 다른 쪽이 따라 움직인다. 스위치 이름 검사를 6판의 것과
    묶으라는 지적도 같은 까닭이다. 둘 다 그 자리에 주석으로 적었다.
  - 툴팁이 `UNIT_INFO`에 없는 행 이름에서 터진다는 지적. 그 이름은 모든 문에서 sanitize가 지우므로 `/run`만 닿고,
    `hover`가 아닌 다른 이름은 전부터 그랬다(`sanitizing-actions-with-one-function.md` 5절). 그 줄에 까닭을
    적었다. `UnitConditionForBinding`의 "`/run`만 여기 온다"도 리뷰가 사다리와 sanitize 사이에 읽는 자리가 있다고
    읽었는데, 그런 자리는 없다. 그 순서를 주석에 적었다.
