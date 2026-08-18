# 임포트를 한 덩어리로 되돌리기 (2026-08-18 시작)

> 상태: **1번은 했다.** `Drawer.lua`가 사라졌고 `Import.lua`가 한 덩어리다. 줄 두 함수는
> `Debind/ImportUI.lua`로 갔다. `npm run check` 전부 통과.
>
> **남은 것은 2번(저장 형식) 하나다. 페이로드로 간다** (2026-08-18, 소유자).

## 왜 하나

소유자의 말이 이 문서의 전제다.

> "기본 와우의 특성 로드아웃 내보내기, 다른 애드온들의 설정 내보내기 모두 import<>export의
> 개념이지 중간에 bring이란 개념이 끼지 않아. (…) export와 대충은 import가 되어야 논리적이라고."
>
> "서랍 구조는 일단 보존해야해. 딱히 마땅한 ui가 떠오르지 않으니. 하지만 ui는 코드의 view일뿐이야.
> 개념은 import<>export가 맞다."

**개념은 둘이다. import와 export.** 서랍은 임포트가 여러 번에 걸쳐 일어날 수 있어서 중간 상태를
저장한다는 사실일 뿐, 나란히 설 세 번째 개념이 아니다. **서랍 UI는 그대로 둔다.** 바꾸는 것은
코드가 그것을 개념으로 취급하는 부분이다.

지금 코드는 화면 모양을 개념으로 착각한 자리가 여럿이다.

- 파일 이름이 `Drawer.lua`다. **화면에 있는 것의 이름이고, 이 애드온은 UI를 안 만든다.**
  로케일에 `IMPORT_DRAWER_EMPTY`, `IMPORT_DRAWER_COUNT`, `"Add to drawer"`가 있다. 즉 `drawer`는
  사용자가 읽는 낱말이다.
- `CollectImportLines`의 "line"은 다이얼로그의 체크박스 줄이다. 그 구획 헤더가 스스로
  `-- The lines the reader is offered`라고 적혀 있다.

## 할 일 1 — 파일을 개념대로 (정해졌다)

`DebindStorage/Drawer.lua`(390줄)는 세 구획이다. 구획 주석이 이미 갈라놓았다.

| 구획 | 무엇 | 어디로 |
|---|---|---|
| Source layers | `ForEachPayloadLayer`, `ImportAddress` | `Import.lua`로 |
| The lines the reader is offered | `ImportLineFor`, `CollectImportLines` (83줄) | **`Debind/ImportUI.lua`로** |
| The drawer | `Vars`, `decoded`, `GetBatchPayload`, `AddBatch`, `GetBatches`, `GetBatch`, `DeleteBatch` | `Import.lua`로 |

그리고 `Drawer.lua`는 사라진다.

**`Vars`도 `Import.lua`에 그대로 둔다**(소유자 결정). 따로 빼는 안이 있었는데, 개념 기준으로는
그것도 임포트의 세부다.

**두 함수가 Debind로 가는 이유는 "UI 코드라서"가 아니다.** 그 결정의 나머지 절반이 이미 저쪽에
있다. `ImportUI.lua`의 `LINE_LABELS`가 줄 키를 로케일 키로 옮긴다. 어떤 줄을 내놓을지는 여기서,
그 줄을 뭐라 부를지는 저기서 정하고 있어서, **다이얼로그를 레이어 단위 체크박스로 바꾸면 한
변경이 애드온 둘을 건드린다.** 그중 하나는 LoadOnDemand다.

붙이는 순서는 **두 파일을 그냥 이어 붙이면 된다.** 재배열하면 diff만 커진다. `CommitBatch`가
`BuildAction`과 `GetBatchPayload`를 둘 다 쓰므로 지금도 아래쪽에 있고, 이어 붙이면 "액션 짓기 →
보관 → 커밋" 순서가 되어 그대로 읽힌다. 합친 뒤 약 614줄이고 `Export.lua`가 537줄이라 대칭이다.

같이 할 것:

- `DebindStorage.toc`에서 `Drawer.lua` 줄 삭제
- **`drawer`라는 낱말을 `DebindStorage/` 주석에서 걷는다.** `Export.lua`에 두 군데 있다.
  `Debind/`와 로케일에는 그대로 둔다. 거기서는 화면 이야기라 맞다.
- `tests/drawer_spec.lua` 이름과 `tests/run.lua`의 등록. **그 스펙이 검사하는 것은 대부분 서랍이
  아니라 `ImportAddress`/`ImportLineFor`/`CollectImportLines`다.**
- `CLAUDE.md`의 `DebindStorage` 줄이 "the strings and the drawer"라고 적혀 있다.

**이름은 안 건드린다.** `CommitBatch`가 진짜 임포트이고 `AddBatch`는 시작해서 세워두는 것이라
개념 기준으로는 어긋나 있는데, 화면 문자열(`IMPORT_COMMIT`)과 얽혀 있어서 따로 볼 일이다.

### 하면서 나온 것 두 개 (위 계획에 없던 것)

- **`PlanImport`가 `ImportLineFor`를 부른다.** 줄이 `Debind`로 가면 저장 애드온에서 부를 길이
  없어진다. 그래서 두 함수는 `ImportUI.lua`의 파일 지역이 아니라 `DebindPrivate.ImportLineFor` /
  `DebindPrivate.CollectImportLines`로 섰다. 저장 애드온은 `Constants`, `NextSyntheticKey`,
  `PlaceImportedActions`를 이미 그 통로로 읽으므로 새로 뚫은 통로가 아니고, 방향도 계획대로다.
  줄이 무엇인지는 `Debind`가 정하고 저장 애드온은 물어보기만 한다.
- **헤드리스 스펙이 `Debind/ImportUI.lua`를 읽는다.** `CollectImportLines` 케이스 여덟 개가 거기
  걸려 있고, 이 파일은 읽힐 때 프레임을 안 만들어서 셤에 그대로 들어간다. `tests/run.lua`가
  `DebindPrivate.Store`도 같이 세운다(게임에서는 `DebindStorage.lua`가 하는 일).
  `devdocs/testing-a-change.md`의 로드 목록도 같이 고쳤다.

`EnsureLineButtons`가 첫 열기까지 미루던 이유가 "그 숫자는 저장 애드온만 안다"였는데 이제
아니다. 미루는 것 자체는 그대로 뒀고(임포트 탭을 안 여는 사람은 프레임 넷을 안 만든다) 주석만
다시 썼다.

## 할 일 2 — 무엇을 저장하나 (**페이로드로 정해졌다**)

지금은 **원문 문자열**을 저장한다. `batch.text`다. 붙여넣을 때 한 번 역직렬화해서 읽을 수 없는
것을 거절하고, **그 결과는 버린다.** 목록을 그리려고 그 결과에서 뽑은 `class`, `groupCount`,
`actionCount`를 배치 레코드에 따로 저장한다. `decoded`는 파일 지역 테이블이라 메모리 캐시다.

즉 디스크에 원본과 그 파생값이 둘 다 있다.

**페이로드를 그대로 저장한다.** 문자열을 저장할 이유를 찾다가 넷을 댔고 넷 다 죽었다. 다시
세우지 않도록 근거를 적어둔다.

- **되돌리기** — 문자열이 필요 없다. 페이로드로 다시 커밋하면 된다.
- **도로 복사해 나가기** — `Vars` 밑 주석이 그렇게 적어놨는데 **그 통로가 없다.** `batch.text`를
  복사 창에 넘기는 코드가 리포에 없다.
- **나중에 새 디코더로 다시 읽기** — 못 읽는 문자열은 애초에 서랍에 못 들어간다. `AddBatch`가
  저장 전에 디코드해서 안 되면 거절한다. **서랍에 있는 것은 전부 우리가 완전히 이해한 것이다.**
- **마이그레이션 면제** — 반대다. `DecodeExportString`이 `payload.v ~= SCHEMA_VERSION`이면 거절하므로
  **스키마를 한 번 올리면 서랍의 모든 배치가 죽는다.** 그 자리 주석이 그 결과를 이미 적어놨다.
  마이그레이션을 면제받는 게 아니라 **마이그레이션할 방법이 봉쇄된다.** 페이로드를 들고 있으면
  프로필이 `dbver`로 하는 것과 같이 옮길 수 있다.

**정보는 같다.** `DecodeExportString`은 `LibSerialize:Deserialize`가 낸 테이블을 손대지 않고
그대로 돌려준다. `payload.v`만 보고 반환한다. 화이트리스트는 커밋할 때 `BuildAction`이 하는 일이라,
서랍에 앉는 페이로드에는 문자열에 들어 있던 것이 전부 들어 있다. 버전도 `payload.v`로 같이 간다.
문자열 바깥의 봉투 버전은 **바이트를 어떻게 쌌나**를 말하므로 푼 다음에는 쓸 데가 없다.

**남은 차이는 디스크 크기 하나고, 그걸로 결정을 뒤집지 않는다.** 문자열은 압축돼 있고(주석에
300액션이 약 1.4KB) 페이로드는 펼쳐진 Lua 테이블로 앉는다. 그런데 **작지만 못 읽는 것을 들고 있는
쪽이 나쁘다.** 스키마가 한 번 오르면 서랍의 모든 배치가 죽고 마이그레이션을 붙일 자리가 없다.
크기를 재서 "작으니까 그냥 두자"가 되면 그 상태를 고른 것이 된다.

바꾸면 딸려 오는 것:

- `class`, `groupCount`, `actionCount`가 필요 없어진다. 페이로드에서 읽는다
- 목록을 그리는 데 압축 라이브러리가 필요 없어진다(지금은 `Bring`이 다시 디코드한다)
- `STORE_VERSION` 밑에 마이그레이션 단계가 생긴다
- 이미 저장된 배치(문자열)를 한 번 읽어 옮기는 단계가 필요하다

## 확인해둔 것 (다시 세지 말 것)

- `Export.lua`는 `Drawer.lua`의 어느 것도 안 쓴다. `ForEachPayloadLayer`, `ImportAddress`,
  `AddBatch`, `GetBatch`, `DeleteBatch` 참조가 0이다. **배치는 받는 쪽에만 있는 개념이다.**
- 디스크에 닿는 곳은 `Vars()` 하나다. `_G.DebindStorageVars`를 만지는 줄이 그 안 세 줄뿐이다.
- **임포트 목록은 디코드하지 않는다.** 행이 그리는 것은 `BatchTitle`(= `batch.source`),
  `batch.groupCount`, `batch.actionCount`, `batch.received`, `batch.committed`로 전부 저장된 값이다.
  `GetBatchPayload`를 부르는 곳은 둘뿐이고 `ImportUI.lua`의 `Bring`과 `CommitBatch`다.
- `CommitBatch`는 배치를 안 지운다. `batch.committed = time()`만 찍는다. 지우는 통로는 사용자가
  누르는 삭제 버튼 하나다.
- `DebindStorage/`에 UI 호출이 0이다. 프레임도 `GameTooltip`도 로케일 참조도 없다.

## 검증

파일을 옮기는 일이라 `npm run check`가 대부분 잡는다. `check:xml-methods`와 `check:locales`까지
같이 돈다. 그 위에:

- `tests/drawer_spec.lua`(이름이 바뀌든 말든)가 그대로 통과해야 한다. 옮기기만 하는 변경이다
- **2번을 하면 저장 데이터가 바뀌므로 `/debtest`가 필요하다.** 그리고 옛 배치가 든 프로필로
  한 번은 로그인해봐야 한다
