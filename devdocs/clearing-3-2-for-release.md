# 3.2를 내보내도 되는지 (2026-08-19 검토)

> 상태 (2026-08-20): **막는 것 없음. 다만 "막는 것이 없다"를 처음 답했을 때 클릭 시점 평가를
> 안 읽고 답했고, 그건 이 릴리스에서 모든 키에 닿는 변경이었다. 지금은 읽었고 아래에 있다.**
>
> **범위를 줄여서 깊이를 지켰다.** 아래 "본 것"이 실제로 코드 경로를 따라간 자리고, "안 본 것"이
> 다음 세션 몫이다. 안 본 자리를 통과로 읽으면 이 문서는 없는 것만 못하다.
>
> 다 닫히면 이 문서는 그냥 지운다. 릴리스가 나가면 남길 것이 `CHANGELOG.md`라 `legacy/`로 옮길
> 것이 없다.

`v3.1.6..HEAD`는 커밋 217개, 파일 112개다. 트랙은 익스포트/임포트(`building-export-import.md`)이고
그 아래로 오버뷰 손보기, 오프스펙 액션 노출, 키 그룹 재번호, 유닛 축 재설계가 같이 들어 있다.

---

## 본 것

| 자리 | 어디까지 |
|---|---|
| 릴리스 절차 | `CHANGELOG.md`, `.pkgmeta`, TOC 다섯 개, 로드 순서, `@debug@` 제거, 루트 파일 |
| 임포트 데이터 안전 | `AddBatch` → `PayloadIsImpossible` → `PlanImport` → `PlaceImportedActions`까지 전 경로 |
| 익스포트 | `BuildExportPayload`, `CopyFields`, `NormalizeAction`, 무엇이 문자열에 실리나 |
| 마이그레이션 | `dbver` 4 → 5 (유닛 조건 축 분리), `KEYS_TO_SAVE`, `CleanUpDB` |
| 발동 순서 | `CompareActionOrder`에 `specRank`가 낀 것이 기존 사용자에게 무엇을 하나 |
| 클릭 시점 평가 | 배선·매칭 루프·먹히는 창까지. 아래 자기 절에 |
| 열린 항목 | `fixing-what-the-review-found.md`의 둘 |

`npm run check`는 통과한다. 스펙 475개, luacheck, XML 11개, 로케일 서식 대조, 스니펫 46개 파싱과
골든 바이트, 익스포트 필드 27개 대조, `method=` 74개, 앵커. 전부 초록이다.

## 안 본 것 (다음 세션)

읽지 않았다는 뜻이지 문제가 있다는 뜻이 아니다. 크기 순으로 적는다.

1. **UI 전체.** `DebindUI.lua` +3273, `DropDownMenus.lua` +1055, 새 파일 `ExportUI`/`ImportUI`/
   `KeyCapture` 약 2600줄. 여기가 이번 변경의 절반이고 `npm run check`가 가장 못 보는 자리다.
2. **`Snippets.lua` +264와 `SecureBindings.lua`의 나머지.** 클릭 시점 경로는 따라갔고 자기 절에
   있다. 남은 것은 나머지 스니펫들이다. 골든은 **드리프트**를 막지 틀린 것을 막지 않는다 —
   굽는 바이트가 골든과 같다는 말은 지난번과 같다는 말뿐이다.
   `restricted-environment.md`를 먼저 읽어야 하는 자리.
3. **`UpdateBindings.lua` +748.** 비보안 쪽 어트리뷰트 조립.
4. **`Misc.lua` +803.** `UnitConditionForBinding`, `HoverConditionFromLegacy` 같은 유닛 조건 접기.
   **마이그레이션 스펙이 이 함수들을 통과시켜서 전후를 비교하므로, 양방향으로 똑같이 틀린 버그는
   그 스펙이 못 잡는다.** 이 자리를 안 본 것이 4번인 이유다.
5. **`Solver.lua` +377.** 스펙은 통과하지만 헤더가 지키라는 축 불변식을 다시 따라가지 않았다.
6. **`enUS.lua` +828.** 새 문자열을 `writing-user-facing-text.md` 기준으로 훑는 일.
7. `FrameRegistry.lua` +237, `Events.lua`, `ActionCatalog.lua`, `Constants.lua`.

---

## 막는 것

### ~~1. `CHANGELOG.md`에 3.2 절이 없다~~ 썼다

맨 위가 `# 3.1.6`이었고, `.pkgmeta`가 `manual-changelog`라 그대로 두면 3.2 자리에 3.1.6 노트가
올라갈 참이었다.

**노트의 범위를 정할 때 주의한 것 하나를 남긴다.** 3.1.4/3.1.5/3.1.6은 릴리스 라인에서 나간
핫픽스라 `v3.1.6..HEAD`에 그 작업이 섞여 들어온다. 반대로 **유닛 축 재설계와 클릭 시점
평가(2026-08-11 ~ 08-13)는 main에 있으면서 아직 한 번도 안 나갔다.** 커밋 범위만 보고 노트를
쓰면 이미 나간 것을 다시 싣고 처음 나가는 것을 빠뜨린다. 기준은 `CHANGELOG.md`에 이미 절이
있느냐다.

---

## 소유자가 답한 것

> *"migration 가능하게 해야지"*, *"export/import 기능을 3.3까지 기다리는건 너무 늦어"*

**3.2는 공유를 싣고 지금 나간다. 대신 3.2로 만들어진 문자열은 3.3에서 읽을 수 있어야 한다.**
아래 2번이 그 답이 3.2 코드에 요구하는 것이고, 3번은 같은 요구가 서랍 쪽에 남긴 몫이다.

`0-DECISION-LOG.md`에는 안 적었다. 내가 물었고 소유자가 답한 자리지 서로 다른 주장이 부딪힌
자리가 아니고, 3.3 배정(`0-ROADMAP.md`)은 그대로 서 있다. 그 파일의 기준으로는 좁히거나 고친
쪽이다.

### 2. 3.2로 공유한 문자열은 3.3에서 죽는다

`SCHEMA_VERSION`은 1이고, `DecodeExportString`은 `payload.v < SCHEMA_VERSION`을
`SCHEMA_TOO_OLD`로 **거절한다.** 읽는 사람에게 나가는 문장도 "할 수 있는 것이 없다"는 쪽이다.
그리고 3.3이 커스텀 상태를 이름으로 갈면 `SCHEMA_VERSION`이 올라간다(`0-ROADMAP.md`,
`0-DECISION-LOG.md` 2026-08-18).

그러니 3.2가 나가는 순간부터 3.3이 나가기 전까지 만들어진 문자열은, 공략글에 붙었든 메모에
남았든 3.3에서 전부 못 읽는 것이 된다. **이 기능의 요점이 남이 붙여넣을 문자열을 만드는
것이므로 값이 작지 않다.**

**답은 나왔다. 3.3은 v1 리더를 쓴다.** 그러면 3.2가 지금 지켜야 할 것은 둘뿐이고, 둘 다
확인했다.

- **페이로드가 자기 버전을 들고 다닌다.** `payload.v`가 문자열에도 실리고 서랍에 저장되는
  페이로드에도 그대로 남는다. 3.3이 v1을 알아볼 근거가 이미 디스크에 있다.
- **v1이 3.3으로 올라갈 만큼의 정보를 든다.** 3.3이 커스텀 상태를 이름으로 가는데, v1은 이미
  상태를 **이름으로** 싣는다(`setstate = {mode, state = "$state3"}`, 그리고 `states` 매니페스트가
  정의까지 든다). 번호가 아니라 이름이라 옮길 자리가 있다.

**그래서 3.2 쪽에 남는 일은 3번 하나다.**

### ~~3. 서랍에 쌓인 배치는 스키마 검사를 안 지난다~~ 고쳤다

붙여넣을 때는 `DecodeExportString`이 `payload.v`를 보지만, **서랍에서 열 때 도는
`GetBatchPayload`는 `payload.v`를 안 본다.** `PayloadIsImpossible` 하나만 지난다.
`Vars()`가 찍는 `vars.version`도 주석이 적어둔 대로 아무도 되읽지 않는다.

3.2 안에서는 아무 일도 없다. 스키마가 하나뿐이다. **3.3에서 갈린다.** 그때 서랍에 남아 있던
v1 배치가 아무 검사도 없이 새 코드의 `BuildAction`과 `PlanImport`를 지난다. 붙여넣는 쪽만
마이그레이션을 얹으면 **서랍에 쌓여 있던 것만 조용히 새 코드로 들어간다.**

**이것이 2번의 답이 3.2에 남긴 일이었다.** 두 문은 이미 `PayloadIsImpossible`을 같이 지나기로
정해져 있었고(2026-08-18), 버전만 한쪽 문에 없었다.

**`BringPayloadForward`로 묶었다.** `DecodeExportString`에 있던 두 거절이 그 함수로 나갔고,
`GetBatchPayload`가 `PayloadIsImpossible`보다 **먼저** 그것을 지난다. 순서가 그런 이유는
`PayloadIsImpossible`이 읽는 필드의 뜻을 스키마가 정하기 때문이다. 3.3은 "거절"을
"마이그레이션"으로 바꾸는 일을 **한 군데서** 하게 된다.

`batch_spec`에 세 케이스를 붙였다(더 새 스키마 · 옛 스키마 · 버전이 숫자가 아닌 것). **고치기
전에 셋 다 빨간 것을 보고 넣었다.** 사유 코드는 그대로라 `REASON_TEXT`는 안 건드렸다.
헤드리스 480개 통과, `npm run check` 통과.

---

## 고친 것

### ~~6. `UpdateSummary`의 머리말이 코드와 반대다~~ 고쳤다

`fixing-what-the-review-found.md`의 2번이었다. 머리말이 *"접혔을 때만 안을 요약한다"*,
*"펼쳐져 있으면 아무것도 안 붙인다"*라고 말하는데, 열두 줄 아래 같은 함수 안 주석이
*"Folded or not, the heading says the same thing"*이고 코드가 그쪽이었다.

**머리말을 다시 쓰고 함수 안 주석은 지웠다** — 같은 이유가 두 군데 설 이유가 없다. 그리고
**한 자리가 아니었다.** 그 동작을 바꾼 편집이 "접혔을 때의 요약"이라는 말을 세 군데 더
남겨놨고(`OpenKeyGroupMenu`, 목록을 짓는 두 자리) 같이 훑었다. 편집한 주석은 규칙대로 통째로
영어로 다시 썼다. `Export.lua`의 `SCHEMA_VERSION` 머리말도 같은 이유로 고쳤다 — *"밖에 나간
v1 문자열이 없다"*는 문장이 **3.2가 나가는 날 저절로 거짓이 된다.**

**여기서 소유자가 규칙 하나를 세웠다.** 관리 못할 주석은 가치가 마이너스이고, 코드를 바꾸면
그것을 말하는 주석을 **같은 편집에서** 훑는다. 검사가 못 보는 종류라 방법은 개념 이름으로
grep 하는 것뿐이고, 리포에 한국어와 영어 주석이 섞여 있으니 **두 언어 다** 봐야 한다.

---

## 이번 검토가 새로 찾은 것

### ~~7. `GetBatchPayload`는 `payload`가 표가 아니면 던진다~~ 고쳤다

`PayloadIsImpossible(payload)`가 `payload.class`를 바로 읽는다. **같은 파일의 `CountBatch`는
`if (not batch.payload)`로 그 경우를 막고 있다** — 한쪽은 있을 수 있다고 보고 다른 쪽은 안 본다.

내보내는 빌드에서 그런 배치는 안 생긴다. `DebindStorage`가 이번에 처음 나가므로 `AddBatch`를
안 지난 배치가 남의 디스크에 있을 수 없다. **닿는 것은 개발용 `DebindStorageVars` 하나다.**
문자열 대신 페이로드를 저장하기로 바뀌기 전에 만들어진 배치가 있으면, 서랍 행은 멀쩡히 그려지고
열 때 터진다.

**3번을 고치면서 문이 하나로 모였으므로 그 자리에서 같이 닫았다.** `BringPayloadForward`가
"이게 페이로드이긴 하냐"를 먼저 묻고 `BAD_PAYLOAD`로 돌려보낸다. `DecodeExportString`이 따로
묻던 것도 그리로 접었다. 던지는 것을 재현하는 케이스를 먼저 빨갛게 만들어 넣었다.

**그리고 `GetBatchPayload` 머리말의 한 문장이 거짓이었다.** *"Everything reading a payload comes
through here"*라고 적혀 있는데 `CountBatch`와 `BatchClassText`(`ImportUI.lua`)가 `batch.payload`를
직접 읽는다. 둘 다 **행을 그리는** 쪽이고, 문이 거절한 배치도 행은 그려져야 한다(지우는 버튼이
그 행에 있다). 그 사정을 적는 것으로 문장을 고쳤다.

### 8. `ImportUI.lua`의 `skipped`가 두 가지를 든다

`DebindBringFrameMixin:Accept`에서 `CommitBatch`의 둘째 반환값을 `skipped`로 받는데, 성공하면
개수고 실패하면 사유 코드다. `REASON_TEXT[skipped]`와 `skipped > 0`이 한 함수 안에 같이 서 있다.
동작은 맞다. 실패면 `placed`가 nil이라 먼저 돌아간다.

### 9. 문자열에 사용자가 쓴 글이 실린다

**신원은 안 실린다.** `payload`가 드는 것은 `class` 하나고, 이름도 서버도 guid도 없다. 캐릭터
레이어는 스펙 번호만 남는다. 매크로는 이름만 나가고 본문은 안 나간다(2026-08-18 결정).

**다만 사용자가 직접 쓴 글 둘은 실려 나간다.** `MACROTEXT` 액션의 본문과, 참조된 커스텀 상태의
`displayMessage`/`expr`이다. 둘 다 애드온 안에서 쓴 글이라 나가는 것이 설계고 주석도 그렇게
적고 있다. 공개 채널에 붙일 문자열이라 **알고 내는 것과 모르고 내는 것이 다르다**는 뜻으로만
적는다.

### 10. 안 보이는 레이어에 착지한 것을 말하는 자리가 없다

드루이드가 메이지 문자열을 받으면 `shared.classes.MAGE`에 들어간다. 착지는 성공이고 화면은
"N개 가져왔다"고 말하는데, **그 N개는 메이지로 접속하기 전까지 어느 화면에도 안 나온다.**
`CollectImportedActions`가 `LayerArray`에서 멈추는 것이 의도이므로 [모두 받기]도 안 닿는다.

`building-export-import.md`의 "남은 것"에 *"안 보이는 레이어에 남는 배지를 어디서 말할지"*로
이미 서 있다. 새 발견이 아니라 **내는 시점에 알고 있어야 할 한계**로 여기 옮겨 적는다.

---

### 11. `CLICK_TIME_EVAL`이 이번에 처음 켜진 채로 나간다

`Constants.CLICK_TIME_EVAL`은 3.1.x 내내 `false`였고 2026-08-11에 `true`가 됐다(커밋
"Pick the action at the click by default"). 그 커밋 메시지가 *"Game verification of that path has
not been walked yet"*라고 적고 있다. 그 뒤에 `/debtest` 쪽 커버가 붙긴 했다.

**이번 릴리스에서 모든 기존 사용자의 모든 키에 닿는 변경은 마이그레이션 말고 이것이다.** 키를
누른 순간 스니펫이 액션을 고르는 경로로 전부 넘어간다. 저 상수 하나가 되돌리는 레버라고
주석이 적어두고 있으니, **릴리스 뒤에 "키가 안 나간다"는 보고가 오면 여기부터 뒤집어 볼 것.**

막는 항목으로 세우지 않는다. 켜진 뒤로 여드레 동안 그 경로에 킷 항목이 붙었고
(`clicktime_spec`, 우리 프레임과 블리자드 프레임 양쪽의 클릭캐스트 검사) 그동안 개발 클라이언트가
이 경로로 돌았다. 다만 **"안 본 것"의 2번이 하필 이 경로**라, 이번 검토가 그것을 안 봤다는
사실과 같이 읽혀야 한다.

---

## 클릭 시점 평가 (2026-08-20에 따라갔다)

**이 릴리스에서 모든 기존 사용자의 모든 키에 닿는 변경이다.** `Constants.CLICK_TIME_EVAL`이
3.1.x 내내 `false`였고 2026-08-11에 `true`가 됐다. 처음에는 "안 본 것"에 넣고 넘어갔는데,
**키가 나가느냐를 정하는 경로를 안 보고 내보내도 된다고 답한 것이 잘못이었다.** 아래는 코드
경로를 따라간 결과다.

### 키가 영구히 죽는 길은 막혀 있다

- **이름 등록과 배선이 갈라질 수 없다.** `ClickTimeKeys[<버튼이름>]=bindings`와
  `SetBindingClick(…)`이 같은 블록에서 붙어 나가는 두 줄이고 한 스니펫으로 같이 실행된다
  (`UpdateBindings.lua`의 `clickTime and not first` 블록). 걸려 있는데 아무도 응답 안 하는
  버튼 이름이 생길 자리가 없다.
- **`IsKeyAlwaysOurs`는 한쪽으로만 틀린다.** 축이 없는 레코드도 예산 초과도 전부 "안 덮임"으로
  세므로 거짓 예가 안 나온다. 놓아줘야 할 키를 영영 붙들고 있는 경우가 없다는 뜻이다.
- **걸 수단이 없는 레코드는 배선 전에 떨어진다.** 빈 플라이아웃이나 모르는 펫 명령이 예전에
  **키를 통째로 먹던** 자리이고, 지금은 그 자리에서 `isClick`/`isNonClick`을 꺼 버린다.
- **`PROBE.*`는 구울 때 사라진다.** 릴리스에 그 토큰이 남으면 클릭마다 던져서 모든 키가 죽는데,
  치환 후 남은 토큰이 있으면 `applyProbes`가 assert로 잡고 골든이 바이트를 잠근다.

### 대신 누른 것이 한 번 먹히는 창이 있다 (의도된 것)

`alwaysOurs`가 아닌 clickTime 키에서, 상태 루프가 **묵은 값**으로 키를 걸어둔 뒤 누르는 순간
live로는 아무 레코드도 안 맞으면 래퍼가 `false`를 낸다. 아무것도 안 나가고, **와우 자기
바인딩으로도 안 넘어간다** — 제한 환경에 `RunBinding`이 없고 입력은 이미 소비됐다. 다음 폴링
틱에 상태 루프가 놓아준다.

3.1.6에서는 같은 창에서 **묵은 액션이 틀리게 나갔다.** 그러니 바뀐 것은 "틀린 것이 나감"에서
"아무것도 안 나감"이고, 그 판단과 근거가 래퍼 옆에 적혀 있다.

### ~~찾은 것: 폴과 프레스가 갈리는 것을 막는 가드가 DEBUG 전용이다~~ 정적 검사로 옮겼다

구운 `EVAL_SNIPPET`에 `Constants.STATE_EVAL_EXPRESSIONS`의 측정식이 그대로 들어 있는지 로드
시점에 assert 한다. 그 자리 주석이 이렇게 적어놨다 — *"Drift here is the worst kind of quiet: the
poll and the press would answer differently for the same state, and nothing downstream could tell
which one was wrong."*

**그 assert가 `if (DebindPrivate.DEBUG)` 안에 있다.** 사용자 빌드에서 안 도는 것은 맞다. 빌드
시점 속성이지 사용자마다 다를 일이 아니다. 문제는 **그러면 그것을 도는 곳이 개발 클라이언트
로그인밖에 없다는 것**이다. `npm run check`는 못 본다 — `check:snippets`는 파싱만 보고
`check:snippet-golden`은 드리프트만 본다 — 헤드리스 스펙은 `SecureBindings.lua`를 아예 안 읽는다.
게임을 안 켜고 둘 중 하나를 고친 사람은 아무 소리도 못 듣는다.

**3.2를 막지는 않는다.** 이 경로가 8월 11일부터 개발 클라이언트의 기본값이었으므로 그 assert는
그동안 로그인마다 돌았다. 막는 것은 다음번이고, 옮길 자리는 정적 검사다.

**옮겼다 (2026-08-20).** `npm run check:state-eval`이 `EVAL_SNIPPET`을 구워서 표와 대조한다.
로드 시점 assert는 지웠다. 굽는 자리를 `tools/lib/bake.js`가 이미 들고 있었으므로 새로 만든 것은
**`Constants.lua`를 진짜로 올린 두 번째 fengari 상태**뿐이다. 표가 들고 있는 것이 숫자를 이미
끼운 문자열이라 `CONSTANTS.*`까지 치환한 형태라야 대조가 성립하는데, 골든은 그 자리를 값이 아니라
토큰으로 박제해야 해서 두 상태를 겸할 수가 없었다.

붙이면서 하나 나왔다. **fengari는 5.3이라 `2 ^ 2`가 실수다** - `BakeSnippet`의 `tostring`이
"4.0"을 내놓는데 게임에서는 "4"다. 도구가 굽는 것은 곧 게임에 들어가는 바이트라야 하므로 5.1의
숫자 서식(`%.14g`)을 `bake.js`에 되돌려 놨다. 애드온 쪽 결함은 아니다.

### 읽어서는 못 답하는 것

위는 전부 코드를 따라간 결과지 게임에서 본 것이 아니다. 이 경로를 볼 수 있는 층은 `/debtest`
하나이고(`testing-a-change.md`), 거기에 이 경로를 직접 겨눈 항목이 여덟 개 있다. 클릭 시점 키가
상태에 맞는 레코드를 고르는지, 일곱 개 중 정확한 하나를 고르는지, **틈이 있는 키에서 폴과
프레스가 같은 답을 내는지**, 배선 갈래 셋, 클릭캐스트 셋. 그것이 초록인지는 `npm run check`가
답할 수 있는 물음이 아니다.

---

## 따라가서 깨끗한 자리

무엇을 근거로 깨끗하다고 말하는지 같이 적는다.

**마이그레이션 `dbver` 4 → 5.** 유닛 조건이 스칼라에서 축별 표로 갈렸고 `hover`/`reactions`가
`checkedUnits.hover`로 접혔다. **전 사용자의 저장 데이터를 건드리는 이번 릴리스 최대 위험이고,
`savedvars_spec`이 그 자리에 서 있다** — 얼려둔 실제 SavedVariables 두 벌, 액션 92개를 다시
태워서 생김새가 아니라 **뜻**을 대조한다(솔버가 보는 마스크와 스니펫에 내려가는 스칼라).
재실행 안전성도 같이 본다. 이 리포에서 그 스펙은 0건이 아니라 92건으로 돌고 있다.
`hover`/`reactions`는 `KEYS_TO_SAVE`에서 빠졌으므로 `CleanUpDB`가 남은 것을 지운다.

**발동 순서.** `CompareActionOrder`에 `specRank`가 `seq` 앞으로 들어갔다. **실제로 발동하는
것은 전부 활성 레이어라 그 단계에서 언제나 동률이다.** 저장 데이터 그대로인데 순서가 조용히
바뀌는 일은 안 일어난다. `IsRowInOrder`가 배지 달린 행과 오프스펙 행을 한 자리에서 답하고,
`ComputeOrderSwap`이 그것을 먼저 묻는다.

**임포트가 프로필에 닿는 경로.** 문이 **붙여넣는 순간(`AddBatch`)과 서랍에서 여는
순간(`GetBatchPayload`) 양쪽에** 서 있다. 2026-08-18 결정이 요구한 자리 그대로다. 필드는 이름과
타입 둘 다 `ACTION_FIELDS`를 지나고, 모르는 클래스와 범위 밖 스펙과 NaN 키는
`ImportAddress`/`PayloadIsImpossible`이 돌려보낸다. 착지한 것은 전부 배지를 달고
`BuildKeyMap`이 건너뛰므로 **커밋이 어떤 키의 동작도 안 바꾼다.** 합성 키는 `LayerArray`가 아니라
저장소 전체에서 세므로 안 보이는 레이어의 번호와 안 부딪힌다.

`fixing-what-the-review-found.md`의 1번은 **문서가 제안한 모양으로는 안 만들어졌다.** `BuildAction`은
여전히 화이트리스트 루프 뒤에 `action.value`를 손으로 쓴다(`setstate` 갈래). 다만 그 자리에서
더해지는 둘이 내부 상수표에서 나온 수뿐이고 결과를 `IsUsableAction`이 다시 보므로, 문서가 노리던
보호는 `PayloadIsImpossible`이 대신 들고 있다. **막는 항목은 아니다.** 그 문서의 머리말이
"둘 남았다"인 것은 자기 안의 "여기까지 만들었다" 표시보다 낡았다.

**`DebindStorage`가 꺼져 있거나 지워진 경우.** `EnsureStore`가 `IsAddOnLoaded`가 아니라
**넘겨받기가 일어났는지**를 묻고, 아니면 탭이 `MissingPanel`을 세운다.

**임포트 실패 사유.** `DecodeExportString`이 내는 아홉 개와 `IMPOSSIBLE_PAYLOAD`,
`NOTHING_TO_PLACE`가 전부 `REASON_TEXT`에 있고, 세 호출부 모두 폴백이 붙어 있다.

**꾸리기.** `Debind/*.lua` 스물셋이 전부 로드 순서에 있다. `.pkgmeta`의 `move-folders`가 새
`DebindStorage`를 덮고, `DevStamp.lua`는 TOC의 `#@debug@` 안에 있으면서 `ignore`에도 있다.
`Constants.DEBUG`는 `--@debug@` 안이고, 코드에 남은 `print` 둘은 모두 `Constants.DEBUG` 뒤에
있다. `docs`/`devdocs`/`tests`/`tools`/`DebindTest`는 `ignore`에 있다.
