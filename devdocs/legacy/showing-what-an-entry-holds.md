# 보관함 행이 무엇이 들었는지 말하게 하기 (2026-09-28 시작)

> 상태: **전부 구현됨 (2026-09-28).** 1절의 열 항목은 소유자가 정했다. 2절은 그 열 항목을 코드에
> 옮긴 방법이다. 3절의 제목 규칙은 첫 판이 구현됐다가 3-2로 바뀌었다. 4절은 이름과 설명 입력, 5절은
> 나머지 손본 것이다.
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
  익명화된 것이다(`AnonymizePayload` 주석). 판별은 `DescribePayload`의 `anonymous`이고, 툴팁은 캐릭터
  목록 아래에 `STORAGE_ENTRY_ANONYMOUS` 한 줄을 세운다. 캐릭터 칸이 없는 payload는 가릴 이름이 없으니
  따질 것도 없다.
- **생성 시각, 분까지.** `STORAGE_ENTRY_MADE`는 `created`를 쓰고, 여기서 만든 행에 `created`가 없으면
  `received`를 쓴다(그 행은 둘이 같은 순간이다). 여기서 만들지 않은 행은 `STORAGE_ENTRY_RECEIVED`가
  따로 선다. 둘 다 `DateTimeText`로 분까지 낸다. 행의 둘째 줄은 날짜만 그대로다.
- **출처.** 첫 줄: 여기서 만든 행은 만든 캐릭터(`STORAGE_ENTRY_SOURCE_MADE`), Clique 변환은
  `STORAGE_ENTRY_SOURCE_CLIQUE`, 나머지는 붙여 넣은 문자열(`STORAGE_ENTRY_SOURCE_PASTED`).
- **`description`.** 있을 때 제목 바로 아래 흰 글씨로.

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

제목 짓기의 재료(`DescribePayload`)와 마크업 막기(`PlainText`)는 `DebindStorage`의 순수 함수라
`entry_spec`이 잰다. `clique_spec`은 공유 코드에 게임 타입이 안 붙는 것을, `client_spec`은 두 세계에서
`Constants.GAME_TYPE`과 payload의 값을 잰다. 툴팁과 제목의 배선(`StorageUI.lua`)은 헤드리스 목록에
없고 재지 않는다. 클라이언트가 TOC 조건대로 `GameType_*.lua` 하나를 싣는지는 게임만 답하므로
인게임 킷의 "Game type: this client's own file loads"가 잰다.

3~5절에서 더한 것 가운데 `entry_spec`이 재는 것은 `DescribePayload`의 `only`(범위가 겹칠 때만 선다),
`SetEntryText`(자르고, 빈 것은 nil, 받은 행도 덮는다), `PlainText`의 여러 줄이다. 우클릭 메뉴, 입력
팝업, Clique 아이콘, 서버명 규칙, 제목 색은 `StorageUI.lua`의 배선이라 재지 않는다.

## 3. payload에서 짓는 제목

모양은 소유자가 맡겼다("surprise me"). **작은 payload는 담긴 것 자체로, 큰 payload는 닿는 범위로
부른다.** 키 묶음 바로가기로 만든 행은 무엇인지가 한 단어로 서고, 백업은 누구의 무엇까지
들었는지가 그 행을 다른 행과 가른다.

위에서부터 처음 맞는 것을 쓴다.

1. **액션이 하나**: 그 액션의 이름(`DebindUI.NameAndIconForAction`).
2. **키가 하나**: 그 키(`DebindPrivate.GetKeyDisplayText`). 키가 없는 액션만 있으면 이 줄을
   건너뛴다.
3. **그 밖**: 범위 하나. 아래 3-2.
4. 액션이 하나도 없으면 날짜(`EntryTitle`의 대체).

**지어낸 제목은 저장하지 않는다** (소유자, 2026-09-28). 위 규칙은 그릴 때만 돌고 `payload.name`에는
사람이 붙인 이름만 들어간다. 이름이 없다는 것 자체가 정보이고, 채워 넣으면 사람이 붙인 이름과 가를
수 없게 된다. 보이는 방식은 저장된 것을 건드리지 않고 언제든 바꿀 수 있다.

### 3-1. 첫 판 (구현됨, 3-2로 바뀜)

범위를 넓은 쪽부터 `LIST_DELIMITER`로 이었다. 일반, 직업(하나면 이름, 여럿이면 개수), 캐릭터(하나면
이름, 여럿이면 개수). 캐릭터에서 만든 행은 늘 "General, Warlock, 이름"처럼 셋이 다 붙었다.

### 3-2. 가장 좁은 범위 하나 (소유자, 2026-09-28)

**범위는 겹겹이다.** 캐릭터의 층이 있으면 그 직업과 일반은 그 캐릭터가 닿는 범위라 따라온다. 그러니
가장 좁은 것 하나만 쓰고, **직업은 색이 말한다.**

- 캐릭터가 하나이고 직업 층이 그 캐릭터의 직업뿐: 캐릭터 이름을 그 직업 색으로.
- 캐릭터가 없고 직업이 하나: 직업 이름을 그 직업 색으로.
- 직업 층도 캐릭터 층도 없이 일반만: "General"을 `DebindUI.ACCOUNT_COLOR`로.
- 그 밖(여럿이 섞인 계정 전체 백업 따위): 개수(`STORAGE_TITLE_CLASSES`, `STORAGE_TITLE_CHARACTERS`).

캐릭터 이름은 5-2의 서버명 규칙을 따른다.

### 3-3. Clique 행의 제목

- **디스크에서 읽은 프로필**: 프로필 이름(`profile.name`) 그대로를 `payload.name`에 넣는다.
  `STORAGE_CLIQUE_ENTRY_NAME`("Imported Clique Profile (%s)")의 포장은 걷고 그 문자열은 지운다. Clique에서
  왔다는 말은 5-3의 아이콘과 툴팁 출처 줄이 한다.
- **공유 코드**: Clique의 `GetExportString`은 `addon.db.profile.bindings`만 싣는다(CL01, CL02 같다).
  프로필 이름도 캐릭터도 없다. 붙여 넣을 때 이름을 안 적었으면 `payload.name`은 nil이고, 제목은
  **임시로** "Unnamed Profile"이다. 우리 행은 이름이 없으면 3-2의 자동 제목인데 Clique 행만 고정 문구라
  규칙이 둘로 갈린다. 무엇을 보일지는 나중에 따로 생각하기로 했다(소유자).

## 4. 이름과 설명 입력 (소유자, 2026-09-28)

**행 우클릭, 드롭다운, 항목 하나, 팝업 하나.** 팝업에 한 줄짜리 제목 칸과 여러 줄짜리 설명 칸이 같이
있고 둘 다 선택이다. 이름 따로 설명 따로 두지 않는다. 텍스트 입력 팝업은 스위치 이름을 받는 것이 이미
있으니 그것을 본뜬다. 여러 줄 칸은 붙여 넣기 창의 것을 본뜬다.

- 열 때 지금 값이 채워져 있다.
- **저장할 때 앞뒤 공백을 자르고, 빈 글이면 nil**로 둔다. 공백만 적은 것은 없는 것과 같다.
- 두 칸의 `SetMaxLetters`는 그리는 쪽의 상한(`NAME_MAX_CHARS`, `DESCRIPTION_MAX_CHARS`)과 같게 둔다.
  다르면 저장은 다 되고 화면에서 말없이 잘린다.
- 적은 것은 `payload.name`, `payload.description`에 들어가 그 행으로 만드는 문자열에 실린다.
- **받은 행도 똑같이 고친다.** 필드가 한 곳뿐이라 보낸 사람이 붙인 이름과 설명은 고치는 순간
  사라진다. 받은 것도 받은 순간부터 내 복사본이라는 모델 그대로이고 의도한 것이다. 코드에도 그렇게
  적는다.
- **설명은 줄바꿈을 살린다.** 지금의 `PlainText`는 제어 문자를 모두 공백으로 바꾼다. 이름은 한 줄로
  접고, 설명은 줄바꿈을 두고 나머지만 접는다. `|`를 두 겹으로 막는 것은 둘 다 같다.

내보내는 순간에 입력을 받지 않으므로 2026-08-15 결정이 막은 수고(내보낼 때마다 무언가를 채우게 하는
것)와 부딪히지 않는다.

**오버뷰보다 편집이 많아지는 것은 아니다.** 보관함에서 전문화 레이어 같은 단위를 따로 걷어 내는
편집은 그 걱정 때문에 안 넣었다(소유자). 레이어 체크와 삭제로 이미 되기도 한다. 이 팝업은 액션을
건드리지 않고, 이름과 설명은 이 창 말고 적을 곳이 없다.

## 5. 나머지 손볼 것 (소유자, 2026-09-28)

### 5-1. 툴팁의 "Made on"을 뺀다

만든 캐릭터는 담긴 것에 이미 드러난다. 캐릭터에서 만든 항목의 내용은 그 캐릭터가 닿는 층이라 툴팁의
직업 줄과 캐릭터 줄이 같은 말을 하고, 계정 전체로 만든 항목은 어느 캐릭터에서 만들어도 같다. 출처는
여기서 만든 것, 붙여 넣은 문자열, Clique 셋만 가른다. `STORAGE_ENTRY_SOURCE_MADE`의 `%s`를 걷는다.

### 5-2. 서버명은 내 서버와 다를 때만

`NameWithRealm`이 늘 "이름-서버"로 붙이던 것을 `Ambiguate(fullName, "none")`처럼 내 서버면 떼고
다르면 붙인다. 클라이언트의 방식이고, 포에버는 서버가 하나라 저절로 전부 떨어진다. 서버명에 룰셋이
들어가는지는 확인되지 않았지만(70009에서 잰 것은 "Pitt"뿐), 이 규칙은 서버명 문자열이 무엇이든 같게
돈다.

### 5-3. Clique 행에 아이콘

**글자가 아니라 행 템플릿의 자리**에 둔다. 우리 애드온에서 나온 행은 숨긴다. 제목과 출처가 다른
필드(`payload.name`, `payload.source`)에서 오므로 이름을 붙여도 아이콘은 남는다.

- 아이콘은 `C_AddOns.GetAddOnMetadata("Clique", "IconTexture")`로 묻는다. Clique는 게임 텍스처가 아니라
  자기 폴더의 `images\icon_square_64.tga`를 쓰므로 Clique가 없으면 그려지지 않는다. 경로를 박지 않으면
  Clique가 바꿔도 따라간다.
- 답이 없으면 `Constants.QUESTION_MARK_ICON`. 클라이언트의 애드온 목록이 아이콘을 안 적은 애드온을
  이미 그 물음표로 보이므로 읽는 사람에게 낯설지 않다. 이렇게 하면 Clique 행에는 늘 아이콘이 있다.
- 그 이미지를 우리 패키지에 복사하지는 않는다. 남의 애드온 파일이다.
