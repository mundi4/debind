# 보관함 행이 무엇이 들었는지 말하게 하기 (2026-09-28 시작)

> 상태: **계획. 구현 전.** 1절의 열 항목은 소유자가 정했다. 2절은 그 열 항목을 코드에 옮기는
> 방법이고, 3절은 소유자가 맡긴 제목 모양이다. 4절은 이 계획 다음에 붙일 입력 UI다.
>
> 쓴 세션: `debind-02`, 세션 ID `74a57376-a8ec-45da-a9f3-4553ea5bbb45`.

나중에 한 키에 여러 액션을 넣는 빌트인 샘플을 싣게 되는데, 보관함에는 그런 payload가 무엇인지 말할
자리가 없다. 행 제목은 만든 캐릭터의 이름이고, 계정 전체로 만든 행에서는 그 이름이 아무것도 가르지 않는다.
받은 문자열은 언제 만들어졌는지도 모른다. payload에 시각이 실린 적이 한 번도 없기 때문이다.

## 1. 정한 것 (소유자, 2026-09-28)

1. **payload에 `description`을 선택 필드로 둔다.** 이 payload가 무엇인지 설명하는 문장이 들어갈
   자리다. 처음 채울 것은 나중에 추가 버튼 메뉴에 들어갈 빌트인 샘플이다.
2. **행 제목은 누가 만들었는지가 아니라 무엇이 들었는지를 말한다.** 이름(`payload.name`, 9)이 있으면
   그것을 쓰고, 없으면 payload에서 제목을 짓는다(3절). 캐릭터 이름은 제목에 쓰지 않는다. 여기서 만든
   행은 이름이 비어 있으므로 지금은 자동 제목이 선다.
3. **툴팁에 들어 있는 캐릭터와 직업을 보인다.**
4. **생성 시각을 분까지 보인다.**
5. **행의 직업 아이콘을 뗀다.**
6. **payload에 생성 시각을 싣는다.** `entry.received`는 이 목록에 행이 들어온 시각이고, 생성 시각은
   데이터 자체의 사실이라 문자열을 따라가야 한다. 둘은 다른 물음에 답한다.
7. **툴팁에 출처를 보인다.**
8. **툴팁에 익명화된 payload인지 보인다.**
9. **이름도 `description`처럼 payload에 둔다.** 행에만 붙던 `entry.name`이 `payload.name`으로 옮겨 가
   문자열을 따라간다. 이름을 두는 곳은 한 곳이다. 2026-08-15 결정("이름은 필드를 두되 익스포트가
   지금은 안 채운다")이 원래 이 모양이었다.
10. **payload에 만든 클라이언트의 게임 타입(`gameType`)을 싣는다.** 받는 쪽이 다른 게임 타입에서 온
    문자열을 거절할지 어디까지 받을지 가르려면 이것이 있어야 한다. 가르는 규칙은 이 계획이 아니고,
    이 계획은 싣기만 한다.

**payload의 새 필드 넷(1, 6, 9, 10)은 이번 v3에 같이 싣는다.** `PAYLOAD_VERSION = 3`은 아직 어느 릴리스
태그에도 없으니 번호를 또 올릴 일이 없다. 옛 문자열에는 생성 시각도 게임 타입도 없고, 없는 것은 보일 수 없다(소유자).

`building-export-import.md`의 "전송 포맷에 메타데이터가 없다"가 이미 내보낸 시각을 에폭 정수로 싣자고
했고 지어지지 않았다. 6은 그것을 짓는 일이다. 같은 절이 짚은 **남이 준 텍스트를 그리는 문제**는 1의
`description`과 9의 `name`에 그대로 걸린다.

## 2. 옮기는 방법

### 2-1. payload의 네 필드

- **`created`**: `time()`의 에폭 정수. `received`와 같은 시계라 한 기계 안에서 둘을 비교할 수 있다.
  `NewPayload`에서 찍으면 `BuildExportPayload`와 계정 전체 쪽이 같이 받는다. Clique에서 옮긴 payload는
  우리가 만든 것이 아니므로 찍지 않는다.
- **`description`**: 문자열. 이 계획에서는 채우는 UI가 없고, 읽고 그리는 쪽만 짓는다. 채우는 것은
  4절이다.
- **`name`**: 문자열. 붙여 넣을 때 적는 이름(`ImportEntry`의 `name`)과 Clique 행의 이름
  (`StorePayload`의 `name`)이 `StoreEntry`의 `extra` 대신 payload에 들어간다. 이미 저장된 행의
  `entry.name`은 `payload.name`으로 옮기는 단계를 `Vars()`에 둔다. 보관함에서 이동이 돌 수 있는 곳은
  그곳뿐이다(`Vars` 위 주석).
- **`gameType`**: TOC의 `AllowLoadGameType`이 쓰는 값 그대로(`"standard"`, `"camelot"`). 이름도 그
  공식 낱말을 따른다. **`WOW_PROJECT_ID`로는 못 가른다**: 카멜롯도 `WOW_PROJECT_MAINLINE`(1)을 낸다
  (`preparing-the-code-for-camelot.md` 3번, 2026-09-23 프로브). 게임 타입을 돌려주는 런타임 함수도
  API 문서에 없다(`C_GameRules.GetActiveGameMode`는 Plunderstorm 같은 모드를 가르는 다른 축이다).
  그래서 값은 TOC 조건으로 실리는 파일이 정한다. `Debind.toc`가 이미 `SpecSpells_Mainline.lua`와
  `SpecSpells_Camelot.lua`를 그 조건으로 가르므로 같은 두 조건을 쓴다(`[AllowLoadGameType standard]`,
  `[AllowLoadGameType camelot] [ExcludeLoadGameType standard]`. 둘째 조건이 빠지면 `camelot`을 모르는
  정식 서비스도 그 파일을 싣는다). 상수는 `Constants.GAME_TYPE`으로 두고, **payload에 실을 값이지
  동작을 가르는 데 쓰지 않는다**고 선언부에 적는다. `shipping-on-the-camelot-client.md` 2절이
  `IS_CAMELOT` 같은 갈래 상수를 두지 않기로 했고, 이 상수는 그 대용이 되면 안 된다. 헤드리스에서는
  `tests/run.lua`의 파일 목록과 shim의 `resetWorld(client)`가 이 값을 알아야 한다. 옛 문자열에는 없으니
  nil은 "모름"이다. Clique에서 옮긴 payload 가운데 디스크에서 읽은 프로필은 이 클라이언트의 값을 싣고,
  Clique 공유 코드에서 온 것은 어느 클라이언트에서 왔는지 모르므로 싣지 않는다(`StorePayload`가 두
  경로를 다 받는다).
- **최상위 필드를 손으로 옮겨 적는 두 곳에 추가한다.** `FilterPayload`(`Export.lua`의 `out = { v, dbver,
  source, layers }`)와 `AnonymizePayload`가 새 표를 짓는다. 여기 빠지면 네 필드는 문자열로 나가는
  순간 조용히 사라진다.
- **들어올 때 타입이 틀리면 그 필드만 버린다.** 문자열 전체를 거절하지 않는다. 설명이 이상하다고
  멀쩡한 액션까지 못 받게 할 이유가 없다. `created`는 NaN과 무한대도 버린다.
- **`name`과 `description`은 그리기 전에 와우 마크업을 막고 길이를 자른다.** `|c`, `|H`, `|T`, `|n`이 그대로
  들어가면 행 하나가 색을 바꾸고 링크를 흉내내고 목록을 덮는다. payload는 받은 그대로 저장되므로
  (`StoreEntry`) 막는 자리는 그리는 쪽이다.
- `IDENTITY_FIELDS`나 `ACTION_FIELDS`처럼 최상위 필드를 거르는 표는 없다. `check:export-fields`도
  최상위를 보지 않는다.

### 2-2. 행

- `EntrySender`에서 `entry.character`로 제목을 짓는 분기를 뺀다. 순서는 `payload.name`, 그다음
  payload에서 지은 제목(3절)이다. `EntryLabel`(삭제 확인창)은 `EntrySender`를 부르므로 따라간다.
- **`entry.character`, `realm`, `guid`는 남긴다.** 제목에만 안 쓴다. 이 셋은 "이 행이 내 백업인가"를
  가르고(`CreateEntry` 위 주석) 자동 백업의 이름을 짓는다. wire에는 그 둘을 가를 것이 없다.
- `ClassIcon`과 그것을 부르는 곳을 걷는다. 직업 색은 이 항목이 말하지 않았으니 둔다.

### 2-3. 툴팁

`DebindStorageEntryRowMixin:OnEnter`에 넣는다.

- **들어 있는 캐릭터와 직업.** 캐릭터는 `CharacterName`이 이미 `characters`의 이름을 읽고, 없으면
  `STORAGE_ADD_CHARACTER_UNNAMED`로 번호를 낸다. 직업은 `ForEachPayloadLayer`의 칸 키다.
- **익명화 여부.** 표시는 따로 없고 판별만 된다. `characters`에 항목이 없는 캐릭터 칸이 있으면
  익명화된 것이다(`AnonymizePayload` 주석). 위 캐릭터 목록이 번호로 나오는 것이 이미 그 말이므로,
  따로 줄을 세울지는 목록 모양을 보고 정한다. 캐릭터 칸이 없는 payload는 가릴 이름이 없으니 따질 것도
  없다.
- **생성 시각, 분까지.** `created`가 있을 때. 지금의 `EntryDate`는 `FormatShortDate`로 날짜만 낸다.
- **출처.** 지금 첫 줄이 `entry.character`로 `STORAGE_ENTRY_MADE`와 `STORAGE_ENTRY_RECEIVED`를 가른다.
  Clique에서 온 것은 `payload.source`로 가를 수 있다.
- **`description`.** 있을 때.

### 2-4. 거짓이 되는 주석

구현하면 아래 주석이 틀린 말이 된다. 같은 변경에서 영어로 다시 쓴다.

- `StorageUI.lua`: `EntryDate`, `ClassIcon`, `EntrySender`("the icon is where the class lives", "Only a
  paste the reader named and a Clique profile carry one"), `OnEnter`("a string carries no date of its
  own (7절)").
- `Import.lua`: `StoreEntry`의 `received` 주석("which a string does not carry").
- `Export.lua`: `FilterPayload`("The fields an entry carries about the row do not travel")와
  `AnonymizePayload`가 무엇을 옮기는지.

### 2-5. 시험

헤드리스(`export_spec`, `import_spec`):

- 만든 payload에 `created`가 찍히고, `gameType`은 shim 세계의 게임 타입을 싣는다(두 세계 모두).
- `FilterPayload`와 `AnonymizePayload`를 거쳐도 `created`, `gameType`, `name`, `description`이 남는다.
- 타입이 틀린 필드는 버려지고 문자열은 받아진다.
- 인코딩과 디코딩을 한 바퀴 돌아도 넷이 남는다.
- 붙여 넣을 때 적은 이름이 `payload.name`에 들어가고, 옛 `entry.name`은 `Vars()`에서 옮겨진다.

제목 짓기와 마크업 막기는 순수 함수로 떼어 헤드리스에서 잰다. 툴팁 배선은 재지 않는다.

## 3. payload에서 짓는 제목

모양은 소유자가 맡겼다("surprise me"). **작은 payload는 담긴 것 자체로, 큰 payload는 닿는 범위로
부른다.** 키 묶음 바로가기로 만든 행은 무엇인지가 한 단어로 서고, 백업은 누구의 무엇까지
들었는지가 그 행을 다른 행과 가른다.

위에서부터 처음 맞는 것을 쓴다.

1. **액션이 하나**: 그 액션의 이름(`DebindUI.NameAndIconForAction`).
2. **키가 하나**: 그 키(`DebindPrivate.GetKeyDisplayText`). 키가 없는 액션만 있으면 이 줄을
   건너뛴다.
3. **그 밖**: 들어 있는 범위를 넓은 쪽부터 `LIST_DELIMITER`로 잇는다. 일반 층이 있으면 일반, 직업은
   하나면 그 이름이고 여럿이면 개수, 캐릭터도 하나면 이름(익명화된 것은 번호)이고 여럿이면 개수.
4. 액션이 하나도 없으면 지금처럼 날짜(`EntryTitle`의 대체).

개수를 말하는 문구는 새 로케일 문자열이 필요하다. 지을 때 `writing-user-facing-text.md`를 따른다.

## 4. 다음에 붙일 것: 이름과 설명 입력 (소유자, 2026-09-28)

보관함에서 행을 골라 이름과 설명을 적는다. 적은 것은 `payload.name`과 `payload.description`에 들어가
그 행으로 만드는 문자열에 실린다. **받은 행도 똑같이 고칠 수 있다.** 두 필드가 한 곳에만 있으니 고친
것이 다음 문자열에 그대로 실린다.

내보내는 순간에 입력을 받지 않으므로 2026-08-15 결정이 막은 수고(내보낼 때마다 무언가를 채우게 하는
것)와 부딪히지 않는다. 이 계획이 필드, 옮겨 적기, 제목 순서를 먼저 세워 두므로 4절은 입력 UI만 더하면
된다.
