# 액션을 sanitize 함수 하나로 바로잡기

> 상태: 되감기를 했다(3-4). 7절은 7번(5절의 값들을 다시 넣어 보기)만 남았다. 5번은 2·3번에서 같이 됐다. 2절은 2026-10-09에 소유자가 정했고, 같은 날 검토에서
> 소유자가 더 정한 것(대기 액션, 계정 전체 페이로드는 사본만, 서랍, 클라이언트마다 다른 답)을 2-1·2-2에 넣었다. 2절에서
> `debind-1b`가 덧붙인 줄에는 "(덧붙임)"을 달았다. 6절의 정답표도 다 정했다.
> `checking-pasted-strings-and-keeping-actions-canonical.md`의 설계(가져오기 관문만 엄하게 하고, 접속 때는 아무것도 고치지
> 않는다)를 이 문서가 뒤집는다. 그 문서는 되감기로 트리에서 빠졌고, `backup/before-sanitize-rewind` 브랜치에 남아 있다.
>
> 쓴 세션: `debind-1b` (세션 ID `2c1db7a6-0e14-4331-bdf0-6ec31eeda180`). 검토에서 정한 것, 3-3의 되감기 사실, 되감기와 6절은
> `debind-4b` (세션 ID `606704f4-0b90-4e5a-93e4-cdefc063f074`).

## 1. 왜 바꾸나

앞 설계의 목표는 단순하게 가는 것이었다. 그런데 일을 할수록 결정할 거리가 늘었다.

- **관문을 엄하게 하니 깊이마다 표가 생겼다.** `units` 행의 축, 특성 목록 이름, 유닛 이름 목록이 그렇다. 이 표들은 메뉴가
  쓰는 것을 따로 베낀 사본이라, 리뷰를 돌릴 때마다 "작성기와 묶여 있지 않다"는 지적이 나왔다.
- **관문이 엄해진 만큼 다른 곳도 손봐야 했다.** 스펙 픽스처 50곳을 고쳤고, 서랍의 옛 항목을 치우는 마이그레이션을 붙였다.
- **내 프로필로 만든 백업이 열리지 않는 경우가 생겼다.** 프로필에 손 값이 하나라도 있으면 그렇다.

관문을 엄하게 한 까닭은 하나였다. 잘못된 값이 한번 들어오면 그 뒤에 치울 곳이 없다는 것이다. 치우는 함수를 두면 그 까닭이
사라진다.

## 2. 정한 것 (2026-10-09, 소유자)

### 2-1. 함수

- **액션을 sanitize하는 함수를 하나 둔다.** 액션의 모든 자리를 본다.
- **복구할 수 있는 것은 복구하고, 안 되는 것은 문제가 되는 필드를 날린다.**
  - 범위 밖 비트가 든 마스크는 `band(value, ALL)`로 좁힌다. 0이 되면 "아무것도 안 고름"으로 읽혀 키에 오르지 않는다.
    좁아지는 쪽이라 안전하다.
  - 마스크의 NaN은 0으로 둔다. (덧붙임: 소유자의 말은 "NaN 같은 건 0으로 둔다"였고, 마스크 이야기 바로 뒤였다. 범위를
    마스크로 좁혀 읽은 것은 `debind-1b`다. 마스크 밖의 NaN은 6절이 타입이 틀린 값과 같이 다룬다.)
  - 그 밖의 필드도 같은 원칙으로 정한다. `priority`가 틀리면 날려서 nil, 곧 기본값이 된다. 원칙으로 답이 나오는 것은
    소유자에게 묻지 않는다. 필드마다의 답은 6절(초안)이다.
- **답은 클라이언트마다 달라도 된다** (소유자). 예를 들어 `specs`를 그 클라이언트의 전문화로 좁히면, retail에서 온 값이
  camelot에서 깎인다. 서랍은 넣을 때 sanitize를 거치니(2-2) 깎인 값이 서랍에 남고, 그 항목을 다시 내보내면 깎인 채 나간다.
  지금 정답표(6절)에는 클라이언트마다 답이 다른 줄이 없다. `specs`를 좁히는 줄은 뺐다(6-6의 6번).

### 2-2. 어디서 쓰나

**페이로드인지 프로필인지 가리지 않는다.** 마이그레이션 사다리를 지난 뒤에 이 함수를 한 번 돌린다.

- **프로필을 불러올 때:** 이 캐릭터와 관련된 레이어의 액션. **대기 액션도 UI에 뜨니 대상이다** (소유자). 이 캐릭터의 대기
  액션은 `MergePendingActions`가 레이어로 들이므로, 그 뒤에 돈다. `LoadProfile`이 그보다 먼저 돌아서, 그 안에 두면 대기
  액션을 놓친다. 다른 캐릭터의 대기 액션은 UI에 개수만 나오고, 그 캐릭터로 접속할 때 레이어로 들어와 여기를 지난다.
- **액션이 바뀔 때마다.**
- **계정 전체 페이로드를 만들 때마다:** 계정의 모든 액션. **페이로드에 담을 사본만 고친다** (소유자). 다른 캐릭터의 액션은
  UI에 그려지지 않으니 저장된 칸을 고쳐도 얻는 것이 없고, sanitize가 틀렸을 때 피해가 백업 하나에 그친다. 그래서 이 판이
  나온 뒤 접속하지 않은 캐릭터의 저장된 칸은 그 캐릭터로 접속할 때 처음 고쳐진다. 비싸지 않으니 매번 돈다(재 보지는 않았다).
- **로그아웃할 때:** 현재 캐릭터와 관련된 레이어를 다시. SavedVariables 파일 말고도, 게임 중에 `/run` 같은 것으로 전역
  `DebindVars`를 사용자가 고칠 가능성이 0은 아니기 때문이다. 메모리에서 다른 캐릭터의 칸을 고친 경우는 그 캐릭터로
  접속할 때 걸러진다.
- **가져올 때:** 사다리 뒤에. **서랍은 넣을 때 sanitize를 거치고, 꺼낼 때 또 거친다** (소유자). 미리보기, 개수 세기, 다시
  내보내기가 서랍의 항목을 그대로 읽기 때문이다.
- **저장할 때:** 위의 로그아웃할 때와 같은 순간이다. SavedVariables는 로그아웃과 /reload 때만 쓰인다.

### 2-3. `seq`

- **액션 하나만 보는 함수로는 번호가 겹쳤는지 알 수 없다.** 같은 레이어의 다른 액션을 봐야 한다.
- **레이어에 실제로 들어가는 자리에서 고친다.** 묶음(키와 `arrivalID`)마다 번호를 다시 매긴다. 레이어가 다르면 번호를 따로
  1부터 매기니 겹쳐도 정상이다.
- **겹친 번호는 원래 순서를 알 길이 없다.** DEBUG 메시지를 띄우고 레이어에 저장된 순서대로 매긴다. 같은 번호끼리는 정렬이
  불안정해서 리빌드할 때마다 순서가 바뀔 수 있다.
- **키 없는 액션의 `seq`를 지우는 것**은 액션 하나로 되니 2-1의 함수가 맡는다. (덧붙임)
- **가져올 때는 따로 할 일이 없다.** (덧붙임. 같은 날 소유자도 같은 답을 냈다.) 들어오는 액션은 서랍에서 꺼낼 때 이미 sanitize를 거쳤다. `PlaceArrivedActions`는 도착
  번호에 들어온 번호를 더해 넣고, 다 넣은 뒤 묶음마다 다시 매긴다. 들어온 번호끼리 겹쳐도 거기서 풀린다.

## 3. 커밋을 어떻게 되돌리나

### 3-1. 사실

- **앞 설계는 `35813f9`(계획 문서)에서 시작했다.** 그 뒤 코드 커밋은 `9129ccd`, `42eef0e`, `209ab8b`, `ff0463e` 넷이다.
  여기에 커밋하지 않은 `checking-pasted-strings-and-keeping-actions-canonical.md` 3절 6번(가져오기 관문, 서랍의 옛 항목 정리,
  왕복 확인, 픽스처 수정)이 더해진다.
- **아무것도 푸시하지 않았다.** `origin/main`은 `7e5f43d` 바로 앞이고, 그 뒤 커밋은 모두 이 컴퓨터에만 있다.
- **사이에 설계와 상관없는 커밋이 끼어 있다.**
  - `b9e6291`: 세션 시작 훅
  - `a29529b`: `need-fixing.md` 3번을 줄임
  - `25a919e`: `CLAUDE.md`의 금지 명령 절
  - 일기 커밋 아홉. 그 가운데 `009b30a`는 다른 세션이 썼다.

### 3-2. 정한 것

- **작은 변경 셋(`b9e6291`, `a29529b`, `25a919e`)은 백업해 두었다가, 되감은 뒤 그대로 다시 적용한다** (소유자).
- **`96c0dbc`로 되감는다.** `35813f9` 바로 앞이다. 계획 문서도 뒤집는 설계를 적은 것이라 같이 걷는다.
- **설계 커밋 가운데 셋을 살린다.** 새 설계와 부딪히지 않는다.
  - `9129ccd`의 DevSeed 수정: 설계와 상관없이 맞는 것이다.
  - `42eef0e`의 쓰는 쪽 수정(메뉴, 타입 바꾸기, 매크로 바꾸기, 특성)과 확인 장치(`tests/canonical.lua`): 바른 모양을 쓰는
    것은 새 설계에서도 맞다.
  - `209ab8b`의 7→8 단계 정리: 접속 때 sanitize가 같은 것을 치우니 겹치지만, 남겨도 틀리지는 않다.
  - 정면으로 부딪히는 것은 `ff0463e`(접속·로그아웃 때 아무것도 안 고침)와 커밋하지 않은 3절 6번이다. 이 둘은 버린다.
- 위 둘은 소유자에게 묻지 않고 정했다. 어느 자리로 되감든, 무엇을 꺼내 오든 끝에 남는 코드는 새 설계가 정한다.
- **도구:** `tools/measure-shipped-payloads.js`는 커밋하지 않은 채 그 자리에 둔다(소유자). 나간 판이 만든 페이로드를 지금
  코드에 넣어 보는 도구라 어느 설계에서든 쓸 수 있다. 5절을 잰 스크립트는 `debind-1b`의 스크래치에서
  `.zzz/sanitize-harness/`로 옮겼다. 정답표를 짠 뒤 같은 값들을 다시 넣어 볼 때 쓴다. 돌리는 법은 `breaks.lua` 머리주석과
  `lua5.1 breaks.lua <저장소 루트> <breaks_spec.lua 경로>`다.

### 3-3. 같이 챙길 것

- **일기:** 되감기 전에 `0-DIARY.md`를 지금 모양 그대로 백업했다가, 되감은 뒤 돌려놓는다.
- **두 문서의 기록:** 작업 문서와 `need-fixing.md`는 설계 커밋들이 같이 고쳤으니 되감으면 계획 단계 모양으로 돌아간다.
  그 사이의 기록 가운데 살릴 것은 아래 셋이고, 모두 이 문서로 옮겼으니 되감을 때 따로 챙길 것이 없다.
  - **`need-fixing.md` 14번**(읽는 쪽 가드가 "공유 문자열이 넣을 수 있다"를 근거로 듦, 툴팁의 유닛 줄은 `UNIT_INFO`에 없는
    유닛에서 터짐): sanitize가 그 값들을 불러올 때와 가져올 때 치우니(6-4, 6-5) 새 설계에 들어간다. 읽는 쪽 가드를 남길지는
    구현할 때 정한다.
  - **`need-fixing.md` 15번**(목록의 표 아닌 원소를 말없이 건너뜀): 액션 하나만 보는 함수로는 못 하는 일이라 2-3의 `seq`처럼
    목록을 걷는 쪽이 한다. 레이어와 페이로드의 목록에서 표가 아닌 원소는 뺀다. 프로필에서는 그런 원소가 계정을 걷는 자리마다
    터진다.
  - **나간 판 측정**: v3.2~v4.1.2 14개 태그가 만든 페이로드(판마다 34~68개)를 지금 사다리에 넣었을 때, 사다리는 하나도
    거절하지 않았다. 관문이 거절한 것은 옛 `export_spec`이 일부러 심은 값뿐이었다. 도구는 `tools/measure-shipped-payloads.js`다.
- **되돌아가는 파일은 두 문서만이 아니다.** 설계 커밋들이 `0-IDEAS.md`, `which-action-a-key-runs.md`,
  `reshaping-stored-layers.md`, `giving-keys-back-when-no-action-runs.md`와 `tools/check-dbver.js`,
  `tools/check-export-fields.js`도 고쳤다.
- **버릴 커밋에 이름을 걸어 둔다.** 되감기 전에 지금 `HEAD`에 브랜치나 태그를 건다. 안 걸면 4절에서 살릴 것을 꺼내 올
  `9129ccd`·`42eef0e`·`209ab8b`가 reflog에만 남는다.
- **다시 적용할 커밋은 작은 변경 셋과 일기다.** 그 사이 커밋마다 고친 파일을 봤다. 설계와 상관없는 것은 세션 시작 훅
  (`b9e6291`), `CLAUDE.md`(`25a919e`), `need-fixing.md` 3번(`a29529b`)과 일기 커밋들뿐이고, 일기 커밋은 `0-DIARY.md` 말고는
  고치지 않았다.
- **`a29529b`는 그대로 다시 적용되지 않는다.** `need-fixing.md` 머리말에서 충돌한다. `9129ccd`가 같은 머리말을 고쳤기
  때문이다(드라이런으로 확인).
- **같은 트리를 쓰는 다른 세션:** 되감기는 그 세션들이 보는 브랜치도 같이 움직인다. 되감기 직전에 커밋하지 않은 변경이 이
  세션 것뿐인지 다시 본다.

### 3-4. 한 것 (2026-10-09, `debind-4b`)

- 커밋하지 않은 변경 29개가 모두 `debind-1b`의 앞 설계 작업이고 버려도 된다는 것을 그 세션에 확인했다.
- 되감기 전 `HEAD`(`5ce690a`)에 `backup/before-sanitize-rewind` 브랜치를 걸었다. 태그가 아니라 브랜치인 것은 태그를 푸시하면
  배포되기 때문이다.
- `96c0dbc`로 되감고, 설계와 상관없는 커밋 열셋(작은 변경 셋과 일기 열)을 원래 순서대로 다시 적용했다. `a29529b`의
  `need-fixing.md` 머리말은 손으로 맞췄다. 그 시점에는 8번이 아직 열려 있어 "항목 3, 8, 9"다. 훅, `CLAUDE.md`, 일기는 백업
  브랜치와 같다.
- 3-2의 세 커밋에서 살릴 것을 꺼내 와 이 문서와 함께 한 커밋에 넣었다. `9129ccd`의 `DevSeed.lua`, 그리고 `42eef0e`와 `209ab8b`는
  통째로 가져왔다. 두 커밋이 앞 설계의 계획 문서에 쓴 기록은 버렸다. `need-fixing.md`의 10~12번은 살렸다.
- 그 상태에서 `npm test`(2090 + 1723)와 정적 검사가 모두 지난다. `check:help`만 실패하는데, Help 파일 둘이 원본과 다른 것으로
  이 작업 전부터 그랬다.
- **꺼내 온 코드가 지운 계획 문서를 가리킨다.** `Profile.lua`, `DebindStorage/Import.lua`, `tests/canonical.lua`,
  `tests/import_spec.lua`, `need-fixing.md`의 10~12번이다. sanitize를 짜면서 이 문서를 가리키게 고친다.
- 그 상태의 `CleanUpDB`는 아직 접속 때 이름 걷기, 타입 검사, `seq` 그물을 한다. 그 자리를 sanitize가 맡는다.

## 4. 아직 정하지 않은 것

- 없다. 정답표도 다 정했다.
- **앞 설계가 sanitize를 버린 까닭**("우리 표가 필드를 빠뜨리면 모든 사용자의 데이터를 말없이 지운다",
  `checking-pasted-strings-and-keeping-actions-canonical.md` 5절)에는 6-6의 1번이 답한다. 날리는 기준이 저장 목록 그 자체이고,
  그 목록을 쓰는 쪽과 묶는다.

## 5. 확인한 것: 프로필을 고장 내는 값 (2026-10-09, 헤드리스)

2-1에서 무엇을 날릴지 정할 때의 자료다. 72가지 값을 커밋, 승인, 리빌드, 다음 접속, 목록 한 줄, 툴팁, 백업 만들기에 차례로
통과시켰다. 창 전체를 그려 보지는 못했고, 게임 안에서 잰 것도 아니다.

- **넣는 도중에 터진다.**
  - `key = {}`
  - `seq`가 표나 문자열
  - `conditions`·`units`가 표가 아님
  - `groups = {}`
  - `units` 행의 `reaction`·`group`이 숫자가 아님
- **리빌드가 터진다.** 넣은 순간과 그 뒤 접속할 때마다 모든 키가 죽는다.
  - `value`가 표나 불리언 (목록 한 줄도 터짐)
  - `key`가 숫자
  - `forms`·`bonusbars`·`bartakeover`가 숫자가 아님
  - `known`이 표
  - `unitframe` 행의 `role`·`frameTypes`가 숫자가 아님
  - NaN `value`, NaN `key`
- **목록 한 줄이나 툴팁만 터진다.**
  - `priority`가 표: 툴팁
  - `talents`가 표가 아님: 툴팁
  - `UNIT_INFO`에 없는 유닛 이름: 툴팁
  - 값 없는 `worldmarker`: 목록 한 줄과 툴팁
- **아무 데서도 안 터진다.**
  - 모르는 필드·조건·축·casting 이름
  - `specs`·`talents` 안의 틀린 값
  - 스칼라 유닛 행, `type`이 표나 숫자, 모르는 타입
  - 숫자 든 매크로, 모르는 액션 버튼 명령
  - 다른 자리의 NaN

## 6. 정답표 (2026-10-09, `debind-4b`)

> `debind-4b`가 채우고 소유자와 논의해 정했다. 논의한 것은 6-6에 있다.

### 6-1. 무엇을 문제로 보나

- **문제가 되는 값은 넷이다.** Lua 타입이 틀린 값, NaN, 표에 없는 이름, 이 타입이 가질 수 없는 필드다.
- **타입이 맞는 값의 내용은 보지 않는다.** 모르는 주문·전문화·특성 ID, 모르는 `casting` 철자, `UNIT_INFO`에 없는 `unit`
  문자열, 범위 밖 `priority`가 그렇다. 정상 데이터에서도 생기는 값이고, 어디서도 터지지 않는다(5절).
- **마스크는 날리지 않고 0으로 둔다.** 0이면 메뉴에 "아무것도 안 고름"이 칠해지고 이슈로 키에서 빠진다. 사용자가 어디가
  틀렸는지 본다. 범위 밖 비트는 `band(value, ALL)`로 좁힌다(2-1).
- **기본값과 빈 표는 접는다.** 복구할 수 있는 것이다. 빈 `conditions`는 조건부로 읽혀 발동 순서가 바뀌니 접어야 한다.
- **이름 목록은 `KEYS_TO_SAVE`에 `untranslated`를 더한 것이다.** `untranslated`는 Clique 페이로드가 레이어에 놓이기 전까지
  드는 필드다. 함수가 페이로드와 프로필을 가리지 않으니 둘 다 받는다. 레이어에서는 읽는 쪽이 `true`만 물어 해가 없다.
- **순서:** 이름 → 타입 → 타입별 규칙(`DropFieldsTheTypeCannotHold`) → 기본값 접기 → 빈 표 접기 → 키 없는 액션의 `seq`.
  지금의 `FoldIntoStoredShape`는 이 함수 안으로 들어온다.

### 6-2. 액션 최상위

| 자리 | 문제 | 하는 일 |
|---|---|---|
| 표에 없는 이름 | | 날린다 |
| `type` | 문자열이 아님, 모르는 타입 | `"invalid"`로 바꾸고 원래 `type`·`value`를 `formerly`에 옮긴다(6-6의 2번) |
| `value` | 그 타입의 모양(`VALUE_SHAPES`)과 다름, NaN | 위와 같다 |
| `formerly` | `type`이 `"invalid"`가 아님 | 날린다 |
| `formerly` | 표가 아님, 안에 `type`·`value` 말고 다른 이름, 문자열·숫자가 아닌 값, NaN | 표가 아니면 날리고, 안쪽은 그 칸만 날린다 |
| `key` | 문자열이 아님, NaN, `ESCAPE` | 날린다. 키 없는 액션으로 남는다 |
| `seq` | 숫자가 아님, NaN, 키 없는 액션 | 날린다. 키가 있으면 레이어에 들어갈 때 번호를 받는다(2-3) |
| `name` | 문자열이 아님 | 날린다 |
| `icon` | 숫자·문자열이 아님, NaN | 날린다 |
| `unit` | 문자열이 아님 | 날린다 |
| `unit` | 대상을 못 받는 액션(`ActionTakesUnit`) | 날린다. `"invalid"`는 남긴다. 원래 것이 대상을 받았을 수 있고, [바꾸기]로 그런 타입이 되면 대상도 돌아온다 |
| `priority` | 숫자가 아님, NaN | 날린다 |
| `priority` | 기본값 | nil로 접는다 |
| `disabled` | 불리언이 아님 | 날린다 |
| `disabled` | `false` | nil로 접는다 |
| `skipWhenUnusable` | 불리언이 아님, 전문화 파생 타입이 아님, `false` | 날린다 |
| `pinnedSpell` | 숫자·문자열이 아님, NaN, 주문이 아님 | 날린다 |
| `resolvedSpellID` | 숫자가 아님, NaN, 이름으로 든 주문이 아님 | 날린다 |
| `noTargetMassRez`, `battleRezOutOfCombat` | 불리언이 아님, 부활이 아님 | 날린다 |
| `arrivalID` | 숫자가 아님, NaN | 액션을 지운다 |
| `untranslated` | 표가 아님 | 날린다 |
| `casting` | 표가 아님 | 날린다 |
| `conditions` | 표가 아님 | 날린다 |

### 6-3. `casting` 안

| 자리 | 문제 | 하는 일 |
|---|---|---|
| 표에 없는 이름 | | 날린다 |
| `selfCastKey`, `focusCastKey`, `hoverCast`, `hoverCastMode` | 문자열이 아님 | 날린다 |
| `normalCast`, `auto*` 넷 | 불리언이 아님 | 날린다 |
| `normalCast` | `true` | 날린다. 쓰는 쪽은 `false`나 nil만 쓴다 |
| 빈 `casting` | | nil로 접는다 |

### 6-4. `conditions` 안

| 자리 | 문제 | 하는 일 |
|---|---|---|
| 표에 없는 이름, 문자열이 아닌 키 | | 날린다 |
| `$` 이름 | 불리언이 아님 | 날린다 |
| `combat` 등 불리언 조건 | 불리언이 아님 | 날린다 |
| `groups`, `forms`, `bonusbars`, `bartakeover` | 숫자가 아님, NaN, 정수가 아니거나 음수 | 0으로 둔다 |
| 같은 넷 | 범위 밖 비트 | `band(value, ALL)` |
| `known` | 불리언·숫자·문자열이 아님, NaN, `false` | 날린다 |
| `known` | 주문도 전문화 파생 타입도 아닌 액션 | 날린다 |
| `known` | 전문화 파생 타입의 `true` | 날리고 `skipWhenUnusable = true` |
| `specs` | 표가 아님 | `{}`로 둔다 |
| `specs`의 칸 | 키가 숫자가 아님 | 그 칸을 날린다 |
| `specs`의 칸 | 값이 숫자가 아님, NaN, 정수가 아니거나 음수 | 0으로 둔다 |
| `specs`의 칸 | 어느 클라이언트에도 없는 비트(전문화 번호 1~`INITIAL_SPEC_INDEX` 밖) | 그 다섯 비트로 `band`. 클라이언트와 상관없는 고정값이다 |
| `specs`의 칸 | 0 | 그 칸을 날린다. 메뉴가 쓰는 모양이다. 다 날아가도 `{}`는 남긴다 |
| `talents` | 표가 아님 | 날린다 |
| `talents`의 칸 | 키가 숫자가 아님, 값이 표가 아님 | 그 칸을 날린다 |
| `talents`의 칸 안 | `taken`·`notTaken` 말고 다른 이름, 목록이 표가 아님 | 날린다 |
| 특성 목록 | 숫자가 아닌 항목, NaN | 그 항목을 날린다 |
| 특성 목록 | 빈 목록, 둘 다 빈 칸, 빈 `talents` | 접는다(`Talents.Prune`) |
| `units` | 표가 아님 | 날린다 |
| 빈 `conditions` | | nil로 접는다 |

### 6-5. `units`의 행

| 자리 | 문제 | 하는 일 |
|---|---|---|
| 행 이름 | `"@"`도 메뉴의 유닛 목록(`SORTED_UNIT_LIST`에서 `none`을 뺀 것)에도 없음 | 그 행을 날린다 |
| 행 | 옛 스칼라 넷(`true`, `false`, `"help"`, `"harm"`) | 그 행으로 옮긴다(`{ exists = true }` 등). 읽는 쪽이 아직 그 뜻으로 읽고(`UnitConditionForBinding`), 날리면 넓어진다. 옮기는 법은 사다리 4·6단계의 것이다 |
| 행 | 그 밖의, 표가 아닌 값 | 그 행을 날린다 |
| 행 이름 | 옛 이름 `hover` | `unitframe`으로 옮긴다. 둘 다 있으면 `unitframe`이 이긴다(사다리 6단계와 같다) |
| 행 안 | 표에 없는 이름 | 날린다 |
| `disabled`, `exists`, `dead` | 불리언이 아님 | 날린다 |
| `disabled` | `false` | nil로 접는다 |
| `disabled = true`인 행 | `exists`가 있음 | 날린다. 기억하는 축이 없으면 행을 날린다. 메뉴가 쓰는 모양이다(`WriteUnitConditionMode`) |
| 표시 없는 행 | `disabled`도 `exists`도 없음 | `exists = true`. 읽는 쪽이 "있을 때"로 읽는다(`UnitConditionForBinding`). 날리면 넓어진다 |
| `reaction`, `group`, `role`, `frameTypes` | 숫자가 아님, NaN, 정수가 아니거나 음수 | 0으로 둔다. `role`도 같다(6-6의 4번) |
| 같은 넷 | 범위 밖 비트 | 각자의 ALL로 `band` |
| 같은 넷 | ALL | nil로 접는다. 메뉴가 쓰는 모양이다 |
| 빈 `units` | | 날린다 |

### 6-6. 논의한 것

줄마다 두 세션의 의견을 단다. `debind-4b`가 이 표를 쓴 세션이고, `debind-1b`가 1~5절을 쓴 세션이다.

1. **표에 없는 이름을 날리나.** 정했다: 날린다. `units` 행 안의 이름도 날린다(소유자: 제안대로). 행 안의 이름을 담은 목록은
   새로 세워 쓰는 쪽과 묶는다. 그 묶음이 4절의 위험에 대한 답이다.
   - `debind-4b`: 날린다. 앞 설계가 sanitize를 버린 까닭(4절)에 대한 답이기도 하다. 표는 새로 만드는 것이 아니라 저장 목록
     `KEYS_TO_SAVE` 그 자체다. `check:export-fields`가 그것을 내보내기 목록과 묶는다. `96c0dbc`의 `CleanUpDB`도 접속할 때마다
     이 목록으로 이름을 걷었다.
   - `debind-1b`: 최상위·`conditions`·`casting`은 같은 답이다. **`units` 행 안의 이름은 다르다.** 그 이름을 담은 목록은 어디에도
     없다. 앞 설계의 3절 6번이 `UNIT_CONDITION_TYPES`(`Export.lua`)로 새로 만들었는데 되감으면 사라지고, 작성기와 묶는 검사도
     없다. 그래서 이 자리는 4절의 위험이 그대로 남는다. 덧붙여 `IsConditionalBinding`은 `conditions`에 무엇이든 있으면
     조건부로 본다(코드로 확인). 모르는 조건 이름이 유일한 조건이었다면, 날린 순간 그 액션의 발동 순서가 바뀐다.
2. **`type`이나 `value`가 틀린 액션을 지우나.** 정했다: 지우지 않고 **`type`을 `"invalid"`로 바꾼다**(소유자가 낸 셋째
   방향, `debind-4b`도 같은 답). 프로필이든 가져오기든 같다.
   - **원래 무엇이었는지 `formerly = { type, value }`에 담는다**(소유자가 낸 안, 이름은 `debind-4b`). 목록의 이름은 대부분
     `type`과 `value`로 그때그때 만들고(`ActionDisplay.lua`), 저장된 `name`을 쓰는 타입은 몇 안 된다. 그래서 이름만으로는 원래
     것을 보여 줄 수 없다. 원래 값을 `value`에 그대로 두지 않는 것은, 타입을 묻지 않고 `value`를 읽는 자리가 깨진 값을 실행할
     값으로 읽지 않게 하려는 것이다. `formerly` 안에는 문자열이나 숫자만 남긴다. 표 같은 값을 남기면 그것을 읽는 자리가 다시
     터진다. `data`·`original`처럼 다른 뜻으로도 읽힐 이름은 피했다.
   - **키에서는 빠진다.** 이슈(`INVALID_ACTION`)로 경고 마크가 붙고 키에 오르지 않는다.
   - **무엇을 할지는 사용자가 정한다.** 이름을 보고 [바꾸기]로 제대로 된 액션으로 바꾸거나, 지우거나, 그냥 둔다. 그냥 두면
     지운 것과 효과가 같다. [바꾸기]는 `type`·`value`·`name`·`icon`만 덮고(`SetActionEntry`) 키, 키 안의 자리, 조건,
     중요도, `casting`은 남기니, 그 줄에 걸린 설정을 잃지 않고 되살린다. `formerly`는 `type`이 `"invalid"`가 아니게 되면
     `DropFieldsTheTypeCannotHold`가 지운다.
   - **내보내기는 다른 액션과 같다.** 받는 쪽에서도 `"invalid"`는 아는 타입이라 같은 모양으로 남는다.
   - **함수가 돌려주는 것은 "이 액션을 지워라" 하나뿐이다.** 액션이 표가 아니거나 `arrivalID`가 틀린 때(3번)이고,
     부르는 쪽은 늘 지운다. 아래 "어떻게 가르나"의 갈래는 필요 없어졌다. 2026-08-18 규칙("만들 수 없는
     액션이 하나면 문자열 전체를 거절한다")도 이것으로 대체된다.
   - 그 앞의 두 의견은 아래와 같았다.
   - `debind-4b`: 지운다. 그 액션은 아무것도 할 수 없다. `value`만 날리면 값 없는 액션이 되는데, 값 없는 `worldmarker`는
     목록 한 줄과 툴팁에서 터진다(5절). 대신 액션 하나가 말없이 사라진다.
   - `debind-1b`: 프로필에서는 같은 답이다. 가져오기에서는 2026-08-18 규칙("만들 수 없는 액션이 하나면 문자열 전체를
     거절한다")과 부딪힌다. 그 규칙이 남는지는 안 정해졌다. 남는다면 가져올 때는 지우지 않고 문자열째 거절하게 되니, 두 경우를
     갈라 적어야 한다.
   - 어떻게 가르나(`debind-4b`): 함수에 자리를 알리는 인자를 두지 않는다. 함수는 살릴 수 없는 액션에 `false`를 돌려주고,
     지울지 문자열째 거절할지는 부르는 쪽이 정한다. 함수가 하는 일은 어디서나 같다.
3. **`arrivalID`가 틀린 액션을 지우나.** 정했다: 지운다(소유자: 도착 번호는 그리 중요하지 않다).
   - `debind-4b`: 지운다. 날리기만 하면 승인하지 않은 도착 액션이 승인 없이 키에 오른다.
   - `debind-1b`: 지우기보다 새 도착 번호(`NextArrivalID`)를 준다. 2-1의 "복구할 수 있으면 복구"다. 배지가 남아 키에 오르지
     않고, 사용자가 보고 승인하거나 지울 수 있다. 말없이 사라지지도, 넓어지지도 않는다. 그렇게 실제로 도는지는 확인하지
     않았다.
4. **숫자가 아닌 마스크를 0으로 두나, 날리나.** 정했다: 0이다. `role`도 0이다(소유자: 그 경우에도 액션에 경고 마크가
   붙는다).
   - `debind-4b`: 0이다. 날리면 제한이 없어지고, 0이면 그 메뉴에 칠해져 사용자가 본다. NaN을 0으로 두는 것(2-1)과 같은
     까닭이다.
   - `debind-1b`: 같은 답이다. 다만 `groups` 말고 다른 축의 0도 칠해지는지는 확인하지 않았다. 칠해지지 않는 축이 있다면 그
     축에서는 "사용자가 본다"는 까닭이 서지 않는다.
   - 확인(`debind-4b`, 헤드리스): 최상위 넷은 0이면 각자의 "아무것도 안 고름" 이슈가 뜨고 키에서 빠진다(`Issues.lua`). 툴팁과
     메뉴에도 칠해진다. `units` 행의 `reaction`·`group`·`frameTypes`도 0이면 각자의 이슈로 키에서 빠진다. **`role`만 다르다.**
     파티·공격대 프레임 옆에서는 0이 `ROLES_NONE_ON_GROUP_FRAMES`라 키에 남고, 그 밖의 프레임에서 발동한다. 그 프레임이 없으면
     이슈가 뜨지 않는다.
5. **표가 아닌 `specs`를 `{}`로 두나, 날리나.** 정했다: `{}`다. 두 세션의 답이 같다.
   - `debind-4b`: `{}`다. 4번과 같은 까닭이다. `{}`는 `SPECS_NONE_SELECTED`로 칠해지고 키에서 빠진다.
   - `debind-1b`: 같은 답이다. 툴팁이 `SpecSetIsEmpty`로 `SPECS_NONE_SELECTED`를 그린다.
6. **`specs` 칸의 비트를 이 클라이언트의 전문화로 좁히나.** 닫았다: 이 클라이언트의 전문화로는 좁히지 않는다(2026-10-09, 소유자). 6-4에서 그 줄을 뺐다.
   이로써 정답표에 클라이언트마다 답이 다른 줄이 없고, 함수에 인자도 단계도 두지 않는다. 서랍에 넣을 때 sanitize를 거쳐도
   다른 클라이언트의 값이 깎이지 않는다. **어느 클라이언트에서도 틀린 비트는 깎는다**(소유자: 그걸 처리해 주는 게
   sanitize다). 저장 모양이 담는 전문화 번호는 1~`INITIAL_SPEC_INDEX`(5)뿐이라, 그 밖의 비트는 클라이언트와 상관없이 틀린
   값이다. 다른 마스크의 `band(value, ALL)`과 같은 줄이 되었다(6-4). 직업 ID는 보지 않는다. 직업은 게임 패치로 늘어서, 지금
   모르는 ID가 틀린 값인지 이 애드온이 가를 수 없다. 두 의견은 아래와 같았다.
   - `debind-1b`: 좁히지 않는다. 6-1의 "타입이 맞는 값의 내용은 보지 않는다"와 어긋난다. 문자열은 클라이언트를 건너다닌다.
     받는 클라이언트의 표로 좁히면 다른 클라이언트에서는 맞는 비트를 지운다. 이 클라이언트가 모르는 직업이면 칸이 통째로
     날아간다. 지금 코드도 일부러 그대로 둔다(`Export.lua`의 `CONDITION_TYPES.specs` 주석: 없는 전문화 비트는 아무것에도 안
     맞으니 덜 자주 참이 될 뿐이다).
   - `debind-4b`: `debind-1b`의 말이 맞다고 본다. 소유자는 답이 클라이언트마다 달라도 된다고 했지만(2-1), 달라야 한다고 하지는
     않았다. 이 줄은 좁혀서 얻는 것이 없다. 그런 비트는 이미 아무것에도 맞지 않는다. 6-4의 그 줄은 빼는 쪽을 권한다.
   - 그 사이 소유자가 "문자열을 페이로드로 바꿀 때는 원본을 보존하고, 프로필에 넣을 때 클라이언트에 맞게 깎는다"를 냈다가,
     선택이 늘어나는 것을 피해 거두었다. 인자로 단계를 나누면 같은 값에 답이 둘이 되고, 정답표에 단계마다 열이 붙는다.

## 7. 할 일 (순서대로)

1. **함수와 `"invalid"` 타입.** 6절 표대로 액션 하나를 고치는 함수를 세운다. 지금의 `FoldIntoStoredShape`와
   `DropFieldsTheTypeCannotHold`는 그 안으로 들어온다. `"invalid"` 타입, 원래 타입을 담는 필드, 이슈, 목록에 보일 이름을 함께
   더한다. 표의 줄마다 헤드리스 테스트를 두고, 고치기 전 코드에서 빨개지는 것을 본 뒤에 넘긴다.

   했다(2026-10-09, `debind-4b`).
   - **함수는 `Sanitize.lua`의 `SanitizeAction`이다.** `tests/sanitize_spec.lua`가 6절의 줄마다 넣은 값과 나와야 할 값을
     든다. 함수가 없을 때 모두 빨갰고, 함수를 몇 군데 일부러 망가뜨려 해당 줄이 빨개지는 것도 봤다.
   - **표는 Debind에 한 벌씩이다.** `KEYS_TO_SAVE`와 `Constants.CONDITION_FIELDS`가 값으로 타입을 들고,
     `Constants.CASTING_FIELDS`, `UNIT_CONDITION_FIELDS`, `VALUE_SHAPES`, `CONDITION_MASKS`, `UNIT_CONDITION_MASKS`,
     `SPEC_INDEX_ALL`을 새로 두었다. `DebindStorage`의 `CONDITION_TYPES`·`CASTING_TYPES`·`VALUE_SHAPES`는 이제 그것을 그대로
     읽고, Judgment의 마스크 표와 메뉴의 `UnitConditionRemembersAxis`도 그쪽으로 옮겼다. 내보내기의 `ACTION_FIELDS`는
     `KEYS_TO_SAVE`에서 `arrivalID`를 빼고 `untranslated`를 더해 만든다. 그래서 `check:export-fields`는 옵션 목록만 비교한다.
   - **`FoldIntoStoredShape`는 없앴다.** 부르던 두 곳(`CleanUpDB`, 가져오기의 `BuildAction`)이 `SanitizeAction`을 부른다.
     그래서 접속·로그아웃 때의 `CleanUpDB`가 이미 이 함수를 돈다(3번에서 자리를 다시 본다).
   - **가져오기는 복사해서 `SanitizeAction`에 넘기기만 한다.** 앞에 따로 거르던 필터(`FieldAllowed`, `ConditionAllowed`)가
     sanitize보다 먼저 값을 떼어, 같은 값이 붙여넣기와 불러오기에서 반대로 처리됐다(리뷰). 관문(`PayloadIsImpossible`)은
     NaN 키만 거절한다. sanitize 전에 개수를 세는 쪽이 그 키를 표 키로 써서 터지기 때문이다. 키 없는 액션의 `seq`를
     지우는 줄은 가져오기의 `Build`에서 걷었고, `CleanUpDB`의 것은 5번에서 걷는다.
   - **`"invalid"`**: 이슈는 `INVALID_ACTION`이 맡고, 그 문장이 [바꾸기]를 가리킨다. 목록에는 "원래 타입 값 (깨진 행동)"으로
     보인다.
   - **구현하며 정답표를 고친 것.** 처음 표대로 옛 유닛 행 스칼라를 날렸더니 스펙 열일곱 건이 빨개졌다. 픽스처 199줄이 그 모양을
     쓰고, 읽는 쪽도 아직 그 뜻으로 읽는다. 날리면 조건이 사라져 넓어지니 "복구할 수 있는 것은 복구"대로 옮기게 고쳤다(6-5).
     `hover` 행 이름도 같다. `"invalid"`는 대상(`unit`)을 남긴다(6-2).
   - **옛 결정을 옮겨 적던 테스트를 고쳤다.** 숫자 키 둘(키를 아직 안 정한 묶음, 사다리가 지우고 이제 만드는 곳이 없다),
     읽을 수 없는 유닛 행 셋(이제 불러올 때 지워지니, 같은 성질을 `"invalid"` 액션으로 옮겨 묻는다), 문자열째 거절 일곱
     (2026-08-18 규칙. `"invalid"`로 들어오는지를 묻게 바꿨고, 모르는 액션 버튼 명령은 그대로 들어와 표시되는지를 묻는다).
     손으로 만든 모양이던 픽스처 셋(숫자인 유닛 행, 메뉴에 없는 유닛 이름, 배포된 적 없는 전문화 ID 집합)은 메뉴가 쓰는
     모양으로 바꿨다. 역할 전체값 테스트는 sanitize를 거치지 않은 액션으로 읽는 쪽을 그대로 묻는다.
2. **목록을 걷는 일.** 표가 아닌 원소 빼기(3-3의 15번)와 묶음마다 `seq` 다시 매기기(2-3). 액션 하나로는 못 하는 일이다.

   했다(2026-10-09, `debind-6c`, 세션 ID `21c5d56d-a7ef-49e7-b1df-24fc109c27b2`).
   - **함수는 둘이다.** `SanitizeActionList`는 어느 목록이든 받는다. 목록의 자리(1..n)만 목록으로 보고, 구멍과 이름 붙은
     원소는 뺀 채 자리 순서대로 메운다. `SanitizeAction`이 지우라고 한 원소도 뺀다. 페이로드의 `seq`는 건드리지 않는다.
     `SanitizeLayerActions`는 그 위에 묶음(키, `arrivalID`)마다 1부터 다시 매긴다. 레이어의 목록에만 쓴다.
   - **목록의 구멍도 이것이 메운다.** 앞의 `CleanUpDB`는 `for i = #actions, 1, -1`로 돌아서, 구멍 너머에 있는 원소를 놓쳤다
     (`1dd02f1` 리뷰).
   - **순위는 저장된 `seq`로만 매긴다**(`debind-4b`가 정했다. 2-3을 따른 것이라 소유자에게는 묻지 않았다). 리뷰는
     `RenumberKeyGroup`의 비교자로 매기라고 했다. 그래야 중요도나 조건과 어긋난 번호가 바로잡힌다는 것이다.
     - 택하지 않은 까닭은 셋이다. 첫째, 2-3이 요구하는 것은 빠진 번호와 겹친 번호를 메우는 것이고, 번호를 비교자와 맞추는
       것은 아니다. 둘째, 어긋난 묶음은 손으로 고친 파일에서만 생긴다. 편집은 모두 비교자로 다시 매기기 때문이다. 그런 묶음이
       남아도 터지는 곳은 없고, 나중에 밴드를 넘겨 옮길 때 반대쪽 끝에 놓이는 것이 전부다. 셋째, 비교자는 바인딩을
       읽는다(`MakeOrderRecord`, `FillBinding`). 이 함수는 ADDON_LOADED와 로그아웃 때 도니, 거기서 하나라도 터지면 불러오기나
       저장이 멈춘다.
     - `seq`는 비교자의 마지막 단계다. 그래서 `seq`로만 매겨도 발동 순서는 그대로다. 이 까닭은 함수 머리주석에도 적었다.
   - **번호 없는 액션은 묶음 맨 뒤로 간다.** 앞 그물의 결정을 이어받았다. 맨 앞에 두면 원래 먼저 발동하던 것의 자리를 뺏는다.
     겹친 번호와 번호 없는 액션끼리는 저장된 순서대로 매긴다. 겹친 번호는 DEBUG에서만 대화창에 한 줄 띄운다.
   - **`CleanUpDB`의 `seq` 그물을 이것으로 바꿨다.** 그물에 있던 키 없는 액션의 `seq` 지우기도 같이 걷혔다. 그 일은
     `SanitizeAction`이 한다. `CleanUpDB`에는 레이어마다 `SanitizeLayerActions`와 `ArmAction`, 끝의 `AttachCharacterTables`만
     남았다. 부르는 자리를 옮기는 것은 3번이다.
   - **앞 그물과 답이 달라진 곳.** 겹친 번호를 그물은 뒤에 만난 쪽을 맨 뒤로 보냈고, 이제는 바로 뒤에 선다. 띄엄띄엄한 번호
     (3, 7)는 그물이 그대로 두었고, 이제는 1, 2가 된다. 둘 다 발동 순서는 바뀌지 않는다.
   - **테스트.** `sanitize_spec`에 목록 열넷을 더했다. 함수가 없을 때 모두 빨갰고, 번호 없는 액션을 맨 앞으로 보내게 망가뜨리면
     넷이 빨개진다. `migration_spec`의 그물 테스트 둘은 새 답을 묻게 고쳤다. 띄엄띄엄한 번호를 불러온 뒤 그 값을 그대로 묻던
     픽스처 셋(`identity_spec`, `export_spec`, `renumber_spec`)은 같은 성질을 액션 자체로 묻거나, 번호를 불러온 뒤에 심게 고쳤다.
   - **이 단계의 리뷰(`/code-review high`)에서 고친 것.**
     - 묶음을 `key .. "/" .. tostring(arrivalID)` 문자열이 아니라 키와 `arrivalID`의 두 겹 표로 가른다. `tostring`은 유효숫자
       14자리에서 자르니, 그 뒤만 다른 두 도착 번호가 한 묶음이 될 수 있었다.
     - DEBUG 메시지가 겹친 번호를 다 적는다. 전에는 마지막 하나만 적었다.
     - 입력이 이미 답과 같던 테스트(`{2, 1}` → `2 1`)를 `{5, 3}` → `2 1`로 바꿨다.
     - `migration_spec`에서 지운 그물의 알고리즘("nil을 먼저 채우고 겹침을 본다")을 설명하던 주석을 고쳤다.
     - 택하지 않은 것: 접속과 로그아웃마다 모든 묶음을 정렬하는 비용. 앞 그물은 일부러 게으르게 짰다. 키 있는 액션마다 기록
       하나, 묶음마다 정렬 한 번이고, 한 세션에 두 번 돈다.
3. **부르는 자리.** 불러올 때(`MergePendingActions` 뒤, Legacy 가져오기 뒤), 로그아웃할 때, 계정 전체 페이로드의 사본,
   서랍에 넣을 때와 꺼낼 때(Clique 변환 포함), 레이어에 놓기 전. 로그아웃에서는 sanitize가 에러를 내도 저장 정리
   (`StowPendingActions`, `AttachCharacterTables`)가 돌아야 한다.
   - **서랍 미리보기가 sanitize 안 된 페이로드를 그린다**(`1dd02f1` 리뷰, 그 커밋이 만든 회귀). `StorageUI`의
     `SortLayerActions`, `BuildPreviewKeyGroups`(`sortName`), `DebindStoragePreviewRowMixin:Init`/`OnEnter`가 원본 표에
     `NameAndIconForAction`·`AddActionToTooltip`을 부른다. `1dd02f1`이 `PayloadIsImpossible`을 NaN 키만 거절하게 좁혀서, 깨진
     액션이 거기까지 온다. 값 없는 `worldmarker`는 `"WORLD_MARKER" .. nil`에서 터진다. `setcustom`도 같다.
     `{ type = "command", value = {} }`는 `"BINDING_NAME_" .. {}`에서 터진다. `GetEntryPayload`의 주석("이 줄을 지나면 우리
     것이다")도 이제 틀렸다. 고치는 길은 위의 "서랍에 넣을 때와 꺼낼 때"다. `DescribePayload`의 `out.action`도 같이 본다.

   했다(2026-10-09, `debind-6c`).
   - **불러올 때.** `SanitizeLoadedLayers`(`Profile.lua`)가 불러온 레이어마다 `SanitizeLayerActions`를 돌리고 `ArmAction`을
     건다. `InitDB`에서는 `CleanUpDB`가 이것을 부르고, `CleanUpDB`는 `MergePendingActions` 뒤에 돈다. 순서는 원래 맞았고,
     거꾸로 돌리면 빨개지는 테스트를 더했다. PLAYER_LOGIN의 Legacy 가져오기는 `LoadProfile` 바로 뒤에서 한 번 더 부른다.
   - **로그아웃.** `PLAYER_LOGOUT`은 `SettleForLogout`(`Profile.lua`)을 부른다. 순서는 sanitize(`SanitizeLoadedLayers`),
     stow(`StowPendingActions`), attach(`AttachCharacterTables`)다. 앞의 둘은 각자 `pcall` 안에서 돌고, 에러는
     `geterrorhandler`로 알린다. attach는 언제나 돈다.
     - sanitize가 터져도 대기 액션이 공용 레이어에 남지 않는다.
     - stow가 터져도 이번 세션에 만든 캐릭터 칸이 파일에 들어간다. 캐릭터의 표는 attach 때만 파일에 들어가기 때문이다.
     - stow 끝에 있던 attach는 여기로 옮겼다. stow를 부르는 곳은 로그아웃뿐이다.
     - 앞의 `CleanUpDB`는 attach를 stow 앞에서 한 번 더 했다. 그 attach가 stow가 터질 때를 받쳐 주고 있었는데, 리뷰가
       그것을 짚었다.
   - **계정 전체 페이로드.** `TakeAction`이 사본을 `SanitizeAction`에 넘기고, 지우라는 답이면 담지 않는다. 프로필은
     건드리지 않는다. 스위치를 모으는 `BuildSwitchCells`가 사본을 읽기 때문에 담는 자리에서 고친다. 다른 캐릭터의 목록에서
     표가 아닌 원소는 건너뛴다. 전에는 표가 아닌 `conditions`에서 `pairs`가, 숫자 원소에서 `IsExportable`이 터졌다.
     `BuildExportPayload`도 `TakeAction`을 쓰니 같이 sanitize된다. 이 캐릭터의 레이어라 바뀌는 것은 없다.
   - **서랍.** `SanitizePayload`(`Import.lua`)가 페이로드의 목록마다 도착 번호를 떼고 `SanitizeActionList`를 돌린다.
     부르는 자리는 셋이다. 넣을 때(`StoreEntry`, 붙여넣기·Clique 변환·다른 애드온 변환·여기서 만든 것이 다 지난다), 꺼낼
     때(`GetEntryPayload`), 서랍을 처음 읽을 때(`Vars`, 올리기에 성공한 항목만, 항목마다 `pcall`)다. 도착 번호를 먼저 떼는
     것은 `BuildAction`과 같은 까닭이다. 페이로드에는 도착 번호가 없어야 하고, `SanitizeAction`은 틀린 도착 번호를 "액션을
     지워라"로 읽는다.
   - **위의 미리보기 회귀는 이것으로 닫혔다.** 미리보기는 `GetEntryPayload`로 읽고, 서랍의 항목은 `Vars`가 이미 고쳐 둔다.
     `DescribePayload`의 `out.action`은 그리는 쪽이 없다. 읽는 것은 `entry_spec` 하나다.
   - **붙여넣는 문.** `DecodeExportString`이 `BringPayloadForward`를 `pcall`로 부르고, 터지면 `BAD_PAYLOAD`로 답한다.
     에러는 `geterrorhandler`로 알린다. 사다리가 터지는 것은 받은 값이 무엇이든 우리 코드가 고칠 일이다.
   - **레이어에 놓기 전**은 1번에서 이미 됐다(`BuildAction`).
   - **테스트.** 열하나를 더했다(`pending_spec` 셋, `migration_spec` 하나, `entry_spec` 넷, `export_spec` 셋). 아홉은 고치기
     전 코드에서 빨갰다. 나머지 둘(불러올 때 대기 액션, 로그아웃 때 stow하는 것)은 원래 순서가 맞아서 통과했다. 그 둘은
     순서를 거꾸로 돌리면 각각 빨개지는 것을 봤다. 리뷰 뒤에 둘을 더했다. stow가 터져도 attach가 도는지, 붙여넣는 문이
     에러를 알리는지다. 둘 다 고치기 전 모양에서 빨갰다.
   - **이 단계의 리뷰(`/code-review high`)에서 고친 것.**
     - stow가 터지면 attach도 안 돌던 것. 위의 로그아웃 순서로 고쳤다.
     - `tests/canonical.lua`의 그물이 `CleanUpDB` 대신 `SanitizeLoadedLayers` 앞에 선다. 그래야 로그아웃과 Legacy 가져오기도
       그물에 걸린다.
     - `BuildExportPayload` 머리주석의 "아무것도 고치지 않는다"를 고쳤다. 이제 사본이 sanitize를 지난다.
     - attach를 `CleanUpDB`로 부르던 주석 여섯 군데를 `AttachCharacterTables`로 고쳤다. 로그아웃 때 `CleanUpDB`가 돈다던
       주석 셋(`Profile.lua`, `Events.lua`, `migration_spec`)도 고쳤다.
     - 아래 줄이 하는 일을 되풀이하던 `BringEntryForward`의 주석을 지웠다.
     - 택하지 않은 것: `GetEntryPayload`의 sanitize를 `pcall`로 감싸라는 것. `SanitizeAction`은 무엇이든 받는 함수이고,
       불러올 때도 감싸지 않는다. 거기서 터지는 것은 거절할 까닭이 아니라 고칠 버그다.
     - 택하지 않은 것: 꺼낼 때마다 다시 sanitize하는 비용. 꺼낼 때 또 거치는 것은 소유자가 정했다(2-2). 여기서 만든 항목이
       두 번 지나는 것(`TakeAction`과 `StoreEntry`)은 만들 때 한 번이다.
   - **이 단계 밖이라 넘긴 것.** `debind-4b`가 `need-fixing.md`에 넣었다.
     - PLAYER_LOGIN의 Legacy 가져오기(`MergeLayers`)가 이 캐릭터의 목록을 통째로 바꾼다. 그래서 `InitDB`가 그 목록에 이미
       넣어 둔 대기 액션이 사라진다. 이 변경 전부터 그랬다.
     - 다른 캐릭터의 칸을 걷는 `ForEachStoredList`·`ForEachStoredAction`·`ForEachPendingAction`은 표가 아닌 목록과 원소를
       거르지 않는다. 계정 전체 페이로드는 원소만 거른다.
4. **"액션이 바뀔 때마다".** 지금은 액션을 쓰는 자리가 열네 곳쯤 흩어져 있다. 입구 하나를 세워 모은다.

   했다(2026-10-09, `debind-6c`. 모양은 `debind-4b`와 정했다).
   - **입구는 `ActionsChanged(actions)`다**(`Profile.lua`). 넘겨받은 액션을 `SanitizeWrittenActions`에 넘기고, 리빌드를 한 번
     한다. `SanitizeWrittenActions`는 액션마다 `SanitizeAction`을 돌리고, 지우라는 답이면 그 액션을 레이어에서 뺀다.
   - **번호 다시 매기기는 쓰는 쪽에 남겼다.** 액션이 어느 묶음에서 빠졌는지는 쓰는 쪽만 안다. `MoveAction`이 떠난 묶음이
     그렇다.
   - **창의 쓰는 자리는 자기 `UpdateBindings` 대신 이것을 부른다.** 메뉴의 `OnActionsChanged`, `MoveAction`,
     `ApproveArrivedActions`, `ReplaceActions`, `OnReceiveDrag`, `ApplyOrderSwap`, `CancelBindMode`, `SetActionKey`,
     `RebuildAfterKeyGroupChange`(키 묶음 옮기기와 [키 풀기]), 매크로 `Save`가 그렇다. 자리를 비킨 액션도 넘긴다. "theirs"
     답의 점유자와 [키 풀기]로 옮긴 점유자다. 아이콘 편집기와 `AddNewAction`은 리빌드를 안 했는데 이제 한다.
     `AddNewAction`에서는 `props`로 키가 들어온 액션도 그 자리에서 바인딩된다.
   - **지우기 둘은 그대로 `UpdateBindings`를 부른다.** 쓴 액션이 없다.
   - **창 밖의 둘은 리빌드 없이 `SanitizeWrittenActions`만 부른다.** `PlaceArrivedActions`와 스위치 이름 바꾸기·합치기
     (`RenameSwitchEverywhere`)다. 손댄 것 가운데 불러온 레이어에 있는 것만 넘긴다. 다른 캐릭터의 칸은 그 캐릭터가
     접속할 때 고쳐진다. `RenameSwitchInAction`은 이제 무언가 썼는지를 돌려준다. 리빌드는 그 둘을 부른 쪽이 원래 한다.
   - **헤드리스의 그물(`tests/canonical.lua`)이 `SanitizeWrittenActions`가 받은 것을 sanitize 전에 본다**(`debind-4b`). 입구가
     먼저 고치면 리빌드 앞의 그물은 고친 것만 보게 되고, 쓰는 쪽이 저장 모양이 아닌 것을 남겨도 지나간다. 그래서
     sanitize는 쓰는 쪽이 만든 것에 대해 아무것도 바꾸지 않는다. 쓰는 쪽이 저장 모양을 지키고, 입구는 그 밑의 그물이다.
   - **그물이 쓰는 쪽의 실수를 하나 잡았다.** 메뉴의 [끄기] 상자가 끈 상태를 `disabled = false`로 썼다. 저장 모양은
     nil이다(6-2). `MenuKit.TOGGLE`은 끈 상자를 `false`로 쓰고, 액션 쪽 `Set`이 그것을 접지 않았다. `ActionValues.Set`이
     `disabled`의 `false`를 nil로 접게 고쳤다. 그물에도 `disabled = false` 줄을 더했다. 이것이 빠져 있어서 지금까지 못
     잡았다. `actionmenu_spec`의 두 테스트는 `false`를 묻고 있었는데 저장 모양(nil)을 묻게 고쳤다.
   - **`check:menu-ctx`의 오탐을 고쳤다.** 위의 접기 줄에 있는 `key == "disabled"`를 `ActionValues` 표의 `key =` 필드로
     읽었다. 비교(`==`)는 필드로 치지 않게 했다. `ctx` 없는 data 표는 여전히 잡는 것을 봤다.
   - **테스트가 가진 것.** 헤드리스 넷을 더했다. 메뉴 줄 하나(실제 메뉴를 세워 누른다), `PlaceArrivedActions`, 스위치
     이름 바꾸기와 합치기다. 각각 저장하지 않는 필드를 심은 액션을 쓰게 하고 그 필드가 사라지는지 묻는다. 고치기 전에
     모두 빨갰다. 이름 바꾸기와 합치기는 다른 캐릭터의 칸을 건드리지 않는지도 묻는다. 그 밖에 헤드리스가 모는 쓰는 자리는
     모두 그물을 지난다.
   - **테스트가 닿지 않는 것과 그 까닭.** `DebindUI.lua`는 헤드리스 러너가 싣지 않는다(`tests/run.lua`의 목록). 그래서 창의
     쓰는 자리가 입구를 부르는지는 헤드리스로 물을 수 없다. 킷 테스트도 두지 않았다. 한 번 맞으면 그대로인 배선이라서다
     (소유자의 규칙, `debind-4b`). 이 자리들은 코드 리뷰가 본다.
   - **이 단계의 리뷰(`/code-review high`)에서 고친 것.**
     - `UpdateBindings`를 부른다고 적은 주석 셋을 `ActionsChanged`로 고쳤다(`MoveAction`, `ApplyOrderSwap`,
       `ApproveArrivedActions`의 필터 주석).
     - 점유자를 붙이는 같은 반복문 두 벌을 `WithOccupants` 하나로 모았다.
     - `PlaceArrivedActions`와 이름 바꾸기가 불러온 레이어를 `LayerArray`가 아니라 `EnumerateAllProfileLayers`로 묻는다.
       인게임 킷이 레이어를 세우는 이음매가 그쪽이다.
     - 택하지 않은 것: 쓰는 쪽이 번호를 다시 매긴 이웃 액션도 입구에 넘기라는 것. 다시 매기기가 쓰는 것은 `seq` 하나이고,
       그 번호는 `RenumberKeyGroup`이 매긴다. sanitize가 거기서 바꿀 것이 없다. 이웃은 리빌드 앞의 그물이 본다.
     - 택하지 않은 것: 입구가 액션을 지울 때 묶음 번호와 선택을 정리하라는 것. 지우라는 답은 표가 아니거나 도착 번호가
       틀렸을 때뿐이고, 쓰는 쪽은 그런 것을 넘기지 않는다. 넘기면 그물이 먼저 잡는다.
     - 택하지 않은 것: 여러 개를 옮길 때 리빌드가 개수만큼 도는 것. 전에도 `MoveAction`마다 `UpdateBindings`를 불렀다.
     - 택하지 않은 것: 아이콘 편집기와 `AddNewAction`이 리빌드를 얻는 것. `debind-4b`와 정한 모양이다.
     - 택하지 않은 것: `disabled`를 이름으로 접지 말고 토글 전체를 접으라는 것. 이 묶음의 토글은 `disabled` 하나다. `Set`은
       토글의 `false`와 예·아니오 줄의 `false`를 가를 수 없다.
   - 이 단계의 픽스처 정리: `talents_spec`이 메뉴에 넘기는 키 있는 액션 넷에 `seq`가 없었다. 그물이 입구에서 그것을 잡아,
     저장된 액션처럼 `seq = 1`을 줬다. Legacy 가져오기 테스트는 일부러 심은 값을 가져오기가 복사하므로, 불러온 액션에
     `HandMade`를 거는 자리를 테스트 안에 두었다.
5. **`CleanUpDB`의 정리를 걷는다.** sanitize가 그 일을 맡는다. 남는 것은 `ArmAction`과 `AttachCharacterTables`다.

   2번과 3번에서 이미 그 모양이 됐다. `CleanUpDB`는 `SanitizeLoadedLayers`(sanitize와 `ArmAction`)와 `AttachCharacterTables`
   뿐이고, 불러올 때만 쓴다.
6. **지운 계획 문서를 가리키는 주석과 문서를 고친다**(3-4).

   했다(2026-10-09, `debind-6c`). 아래 8번과 한 커밋이다.
   - 3-4가 꼽은 파일 가운데 `Profile.lua`, `DebindStorage/Import.lua`, `tests/canonical.lua`, `need-fixing.md`는 그 사이의
     커밋이 이미 고쳐 두었다. 남은 셋을 고쳤다. `Migration.lua`의 7 -> 8 단계 주석, `import_spec`의 접기 테스트 주석,
     `giving-keys-back-when-no-action-runs.md`의 한 줄이다. 마지막 것은 이미 판 8인 개발 프로필의 옵션 값을 "손댄 데이터라
     따지지 않는다"로 지운 문서의 2-1을 들었는데, 그 규칙은 뒤집혔다. 옵션은 sanitize하지 않고, 그 값을 읽는 곳이 없다는 것을
     까닭으로 바꿔 적었다.
   - 이 문서 안의 언급(머리말, 3-1, 4절)은 되감기의 기록이라 그대로 둔다.
7. **5절의 값들을 다시 넣어 본다**(`.zzz/sanitize-harness/`). 어디서도 터지지 않아야 한다.
8. **`1dd02f1` 리뷰에서 나온 작은 것들.** 다른 번호에 속하지 않는다.

   했다(2026-10-09, `debind-6c`).
   - **지운 함수를 가리키는 주석.** 넷을 고쳤고, 같은 이름을 든 테스트 주석 셋(`import_spec`, `normalize_spec`,
     `talents_spec`)도 고쳤다. `Talents.ListOf`와 `Specs`의 `MaskFor`는 읽는 쪽 가드다. 3-3이 "남길지는 구현할 때 정한다"고
     한 것이다. 남겼다. 모든 문이 sanitize를 거치지만, 세션 안에서 `/run`으로 고친 값은 어느 문도 지나지 않고 리빌드에
     닿는다. 거기서 터지면 키 맵이 이미 비워진 뒤다. 주석에 그 까닭을 적었다.
   - **깨진 행의 이름.** `PlainText`를 `DebindStorage/Import.lua`에서 `Debind/Misc.lua`로 옮겼다(`DebindPrivate.PlainText`).
     서랍과 `ActionDisplay`가 같은 함수를 쓴다. 깨진 행은 옛 타입의 철자와 값을 그것으로 그리고, 48자로 자른다. 서랍
     목록이 보낸 이름에 주는 폭과 같다. `display_spec`에 테스트를 더했고, 고치기 전에 빨갰다.
   - **같은 물음을 두 번 적은 것.** 조건 이름이 어떤 타입으로 저장되는지를 `Constants.ConditionFieldType` 하나가 답한다.
     스위치 이름은 불리언 조건이라는 규칙이 거기 있고, `IsConditionField`도 그것을 읽는다. `Sanitize.lua`의 `IsScalar`는
     지우고 `Fits("number|string", ...)`를 쓴다. 스위치 타입을 빼면 `sanitize_spec`이 빨개지는 것을 봤다.
   - **Escape.** `BringPayloadDataForward`의 Escape 줄을 걷었다. 이 판의 문자열은 서랍의 문(`SanitizePayload`)이 키를
     뗀다. `import_spec`의 테스트는 `StorePayload`로 묻게 바꿨고, 넣을 때의 sanitize를 빼면 빨개지는 것을 봤다.
   - **죽은 검사.** `PayloadIsImpossible`의 `luatype(source) == "table"`을 걷었다. `ForEachPayloadLayer`가 이미 표인 원소만
     넘긴다.
   - **이 단계의 리뷰(`/code-review high`)에서 고친 것.** Escape를 `BringPayloadDataForward`가 뗀다고 적은 주석 셋
     (`Constants.lua`, `Debind.lua`, `Issues.lua`)을 `SanitizeAction`으로 고쳤다. `CONDITION_FIELDS` 머리주석이
     `ConditionFieldType`도 가리키게 했다. `Specs`의 가드 주석이 sanitize가 0을 남긴다고 했는데 그 칸을 지운다. 그렇게
     고쳤다. 깨진 행의 길이 한도가 서랍 목록의 상수를 베꼈다고 적었던 것을, 행 자체의 까닭으로 바꿨다.
   - **택하지 않은 것: 목록 검색이 깨진 행의 잘린 이름으로 찾는 것.** 검색은 행에 그려진 이름을 읽는다. 잘린 뒤의 글은
     화면에도 없다.
   - **넘긴 것.** 깨진 행이 아닌 다른 갈래도 붙여넣은 글을 그대로 그린다. 찾지 못한 매크로의 이름, 이름으로 든 주문과
     아이템, 명령의 값, `name`이 그렇다. 이 번호의 범위가 아니라 `need-fixing.md` 15번으로 갔다(`debind-4b`).
   - **택하지 않은 지적.** 옛 빌드로 되돌리면 새 타입이 `INVALID`가 되거나, 로그아웃 때 새 축이 지워진다는 것이다. 되돌리기는
     설계하지 않았다(소유자). 필드나 타입이 늘 때 `dbver`를 올려 옛 빌드가 물러서게 하는 것을 규칙으로 둘지는 소유자와
     아직 정하지 않았다.
