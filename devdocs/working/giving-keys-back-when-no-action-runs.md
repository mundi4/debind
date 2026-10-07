# 아무 액션도 안 돌 때 키를 돌려주기 (2026-10-07 계획)

> 상태: 진행 중. G0(8f3ca88)과 G1~G4, 1-1절(1c81ae6)이 들어갔고 G5는 쟀다(b998892). 키를 쥘지와 머리글 색을 방출
> 뒤 한 곳에서 정하는 3-1절의 구조 수정도 들어갔다. 남은 것은 G6(화면 배선과 등급 합치기), G7(문서). 설정 탭은
> 목업(b6e0d1c)이라 그 행들은 아무것도 저장하지 않는다. G6·G7은 한 번 구현했다가 통째로 되돌렸다(6462ec0). 그때 밟은
> 함정이 3절이고, 다시 할 때 먼저 읽는다.
>
> 쓴 세션: `debind-4a` (세션 ID `73ee6c63-8228-430b-9aca-e8140fe8facd`). 3절과 G5 결과를 쓴 세션: `debind-d8`
> (세션 ID `391e6100-a76a-4f2e-987e-6da498724074`). 3-1절의 구조 수정과 G6·G7을 다시 하는 세션: `debind-45`
> (세션 ID `69a358ab-115a-49d9-9681-65106e3c7003`). 셋 다 문의처가 아니다.

## 1. 정한 것 (소유자, 2026-10-06~07)

- **키의 액션이 하나도 안 도는 누름에서는 키를 돌려주는 것이 기본이다.** 근거는 층 구조다. Debind 액션이 아예 없는 키는
  아래 깔린 바인딩(와우 단축키 설정, 다른 애드온, 또는 아무것도)으로 떨어지는데, 액션이 있고 하나도 안 맞는 키는 지금
  죽는다. 층을 내세우면 둘은 같아야 한다(소유자: *"우리가 LAYERED KEYBINDING SYSTEM을 표방하니까"*).
  `handing-the-rest-of-a-key-to-the-game.md` 1절의 "예전처럼 암묵적으로 넘기지는 않는다"(2026-10-04)를 뒤집는다.
- **전역 옵션 `giveBackWhenNoActionRuns`, 기본 켬.** 끄면 지금처럼 쥔다. 4.0이 옵션을 거부한 근거
  (`dropping-the-game-fallback.md` §2) 넷 가운데 셋은 이제 서지 않는다. 루프는 꼬리 때문에 이미 있고, 조합키 구멍은
  2-3이 막았고, 클릭 시점과 루프의 두 벌 판정은 `judgment_spec`이 맞춘다. 남은 "가져온 프로필이 받는 쪽 옵션에 따라
  다르게 돈다"는 옵션이 계정 백업(`OPTION_FIELDS`)에 실려 약해졌다.
- **기본값을 켬으로 둔 까닭** (소유자가 물었고 이 세션이 답함). 꺼짐의 실패는 조건이 안 맞는 순간마다 키가 죽는 것이라
  매일 겪는다. 켬의 실패는 beat가 늦은 사이 와우 바인딩이 대신 나가는 것(드물고 한 beat 안)과, 누르는 동안 동작하는
  키에서 키 주인이 바뀌는 것(특정 설정에서만)이다.
- **기존 사용자도 기본값을 그대로 받는다.** 마이그레이션으로 지금 동작을 지키지 않고, What's New가 알린다(소유자).
- **이동 키 함정은 이 문서의 범위가 아니다** (소유자: 나중에 처리).
- **타입 `UNUSED`는 `GIVEBACK = "giveback"`이 된다.** `"unused"`는 코드에서 "안 쓰는(꺼진) 액션"으로 읽힌다. 라벨은
  이미 "Give Key Back"(a35ec65). `RELEASE`·`YIELD`는 코드에서 다른 것을 가리켜 거뒀다. `GIVE_BACK`은 이름이 값을 따르는
  타입 상수의 꼴(`MACROTEXT = "macrotext"`)과 맞지 않고, `GIVE_BACK_*` 무리의 머리처럼 읽혀 거뒀다. 로케일 키도
  `TYPE_GIVEBACK`, `TYPE_GIVEBACK_DESC`로 바꾼다.
- **DB 판은 올리지 않는다.** 판 8은 아직 안 나갔고(v4.1.2가 7), 저장 값의 이름 바꾸기와 `giveBackWhenActionExists` 지우기는
  그 7→8 단계에 얹는다.
- **"Filled buttons only"(`giveBackWhenActionExists`)는 없앤다.** 칸이 나중에 채워지면 다시 읽지 않는 구멍이 있다
  (`giving-keys-back.md`). 켰을 때의 실패가 차량 기술을 키로 못 누르는 것이라, 얻는 것(빈 칸 키에서 내 액션을 계속 씀)보다
  무겁다.
- **설정 섹션의 모양**은 목업(b6e0d1c) 그대로다. Cast Options 다음, 행은 셋이다.
  `When no action runs < Key is given back | Press does nothing >`,
  `Action Button keys < Replaced bars | Pet battles | Replaced bars and pet battles | Never >`, `House Editor keys [x]`.
  Action Button keys의 네 값은 기존 불리언 `giveBackOnReplacedBar`·`giveBackInPetBattle`의 조합이고 새 필드가 아니다.
  라벨과 문구가 어떻게 정해졌는지는 일기의 2026-10-07 절에 있다.

### 1-1. 미리 정해지는 액션, 이슈, ESC (소유자, 2026-10-07)

- **키에 없는 액션은 비활성화된 것뿐이다.** 다른 전문화 레이어의 액션과 "Turn this action off"로 끈 액션이다. 리빌드가
  미리 답을 정해 빼는 액션(다른 전문화 조건, 물을 주문이 없는 `known`, 쓸 수단이 없는 액션, 시전 값을 모두 끈 액션)은
  키에 있고, 조건이 늘 거짓일 뿐이다(소유자: *"그냥 조건이 항상 FALSE로 떨어지는것 뿐이잖아"*). 그래서 그런 액션만
  있는 키는 옵션을 따른다. 켜져 있으면 **처음부터 쥐지 않는다.** 걸었다가 beat가 놓으면 `IsKeyOurs`가 "예"로 남는다.
- **이슈는 그 액션 하나의 일이다.** 이슈가 있는 액션은 `OMIT`으로 건너뛰고, 다음 액션이 없으면 키의 끝(옵션)이 받는다.
  키 전체를 막거나 놓는 이슈는 없다(소유자: *"에러든 warning이든 키 자체를 막을 상황이 보이질 않아"*).
  - 거친 안: 액션이 모두 고장인 키는 쥔다, 고장(없는 매크로 등)과 늘 거짓을 나눠 고장만 쥔다, 고장이 하나라도 있으면
    끝을 BLOCK으로. 모두 같은 마크 밑에서 동작이 갈리거나, 고장과 상관없는 액션 하나가 보호를 켜고 끈다.
  - 대가: 고장 난 액션뿐인 키는 옵션이 켜져 있으면 그 아래 바인딩이 나간다. 행의 마크는 남는다.
- **ERROR와 WARNING은 하나로 합친다** (소유자, 아이콘은 경고 아이콘). 동작이 하나이니 등급은 그 액션이 안 돈다는
  표시일 뿐이다. G6에서 한다.
  - 색은 주황, 순서 칸은 "Needs checking", 마크 툴팁은 "Because of this, the action is sometimes or always
    skipped.", 키 머리글 툴팁은 "Some actions under this heading are sometimes or always skipped." (소유자,
    2026-10-07). "누름"이라고 쓰지 않는 것은 개체창 클릭이 누름으로 안 읽혀서다.
  - **`ROLES_NONE_ON_GROUP_FRAMES`는 KEEP으로 남는다** (소유자). 역할은 파티·공격대 개체창에서만 재니, 다른 개체창
    종류에서는 액션이 그대로 돈다. "sometimes"가 이 코드다.
- **설정 섹션 드롭다운 값은 클라이언트 드롭다운처럼 낱말마다 대문자다** (소유자, "Quest Objectives and Mouseover"를
  보이며): Key Is Given Back / Press Does Nothing, Replaced Bars / Pet Battles / Replaced Bars and Pet Battles /
  Never. "Pet Battles"는 클라이언트 문자열 `SHOW_PET_BATTLES_ON_MAP_TEXT`다. 머리글은 기존 `GIVE_BACK_KEYS`
  ("Keys Given Back")다. 도움말 세션이 이 값을 인용하므로 바꾸면 그쪽에 알린다.
- **ESC는 키로 남기지 않는다.** 키 지정 창이 받지 않으니, 있다면 옛 프로필이나 손으로 고친 문자열이다. 프로필을 읽을 때
  (`CleanUpDB`)와 가져올 때(`BringPayloadDataForward`, 미리보기도 같은 값을 보게) 키를 비우고, `BuildKeyMap`도 ESC를 키
  없는 것으로 읽는다(다른 길로 들어온 것에 대한 가드). 액션은 키 없이 남는다. 그래서 게임 메뉴 키 이슈와 결과 등급
  `RELEASE`가 없어졌다. 판 7→8 단계가 아니라 매번 읽을 때인 것은, 이미 판 8인 프로필에도 있을 수 있어서다.
- **키 머리글.** 옵션이 켜진 상태에서 돌 액션이 없는 키는 쥐지 않으니 회색이다(`IsKeyHandled` 거짓). 마크는 그대로다.
- **값이 잘못된 액션과 게임에서 할 게 없는 액션을 가른다** (소유자). 이 캐릭터가 모르는 주문을 시전하는 액션은 그대로
  돌고 게임이 처리한다. 그와 같이, 칸이 다 빈 플라이아웃과 이 캐릭터에 없는 태세 버튼은 **돈다**(속성 없는 버튼,
  `Inert`). 누르면 아무 일도 없고 아래 액션은 안 돈다. 반대로 이 클라이언트에 없는 소환수 명령과 행동 단축키를 누르지
  않는 명령 이름은 값이 잘못된 것이라 이슈(`UNKNOWN_PET_COMMAND`, `UNKNOWN_ACTION_BUTTON`, 결과 `OMIT`)로 건너뛴다.
  전에는 넷 다 방출 단계에서 조용히 빠져 아래 액션이 받았다.
- **키를 쥘지와 머리글 색은 `UpdateBindingsMap`의 키 루프가 정한다.** `PrepareKeyBindings`가 걸 수단이 없는 바인딩을
  버린 뒤라야 키에 나갈 바인딩이 남았는지 안다. 옵션이 켜져 있으면 키를 쥐는 바인딩이 남은 키만 묶는다. 꺼져 있으면
  `KeysOnLiveLayers`(`BuildKeyMap`이 채움, 살아 있는 레이어의 액션이 선 키, 개체창으로만 받는 마우스 버튼은 뺀다)도
  묶는다. `HandledKeys`는 실제로 키를 묶은 줄과 `ClickCastKeys`를 쓴 줄에서 채운다. 위 둘로 "버튼을 못 만드는" 경우가
  이슈나 `Inert`로 미리 갈리니, `PrepareKeyBindings`의 빼기는 이슈가 놓친 경우의 안전망이다.

## 2. 구현 순서

### G0. 이름 바꾸기

- `Constants.UNUSED = "unused"` → `Constants.GIVEBACK = "giveback"`. 이 글자는 `Constants.lua`에만 있고 나머지는 상수를 쓴다.
- **7→8 단계는 상수가 아니라 글자 `"unused"`, `"command"`로 옛 값을 찾는다.** 단계는 판 7이 무엇을 뜻했는지 말하는 것이라
  상수를 따라 움직이면 안 된다(같은 파일이 이미 적은 규칙). 지금은 `Constants.UNUSED`를 쓰고 있어, 상수만 바꾸면 판 7에서
  올라오는 사용자의 `"unused"`를 못 찾는다.
- 로케일 키는 세 파일에서 이름만 바꾼다(ruRU의 번역문은 그대로).
- `DevSeed.lua`를 고친다. `tests/v3.5.2/`는 옛 판의 사본이라 둔다.
- 대가: 꼬리 기능이 들어온 뒤 개발 빌드로 넣은 꼬리는 이미 판 8에 `"unused"`로 저장돼 이 단계를 다시 지나지 않는다.
  실사용자에게는 없는 데이터다.

### G1. 옵션을 읽는 자리

`DebindPrivate.GiveBackWhenNoActionRuns()`: `Options().giveBackWhenNoActionRuns ~= false`. 화면 배선은 G6이다.

### G2. 끝을 BLOCK 대신 GIVEBACK으로

- 리빌드는 키를 쥐는 키마다 맨 끝에 BLOCK을 늘 붙인다(`WithBlocks`의 마지막 줄). 옵션이 켜져 있으면 그 자리에 공용 GIVEBACK
  레코드를 붙인다. 바인딩으로는 BLOCK이고 `tail = GIVEBACK`이다. 저장된 꼬리가 바인딩에서 BLOCK이 되는 꼴과 같다
  (`ActionBindings.lua`).
- self/focus 층 끝의 BLOCK 둘은 그대로다(꼬리는 그 층에 서지 않는다, 2-1).
- `JudgmentEntryFor`가 이 레코드를 `RELEASE`로 읽는다. 원본과 hover 쌍둥이가 함께 쓰는 맨 누름 층이 놓기로 끝난다.
- 누름이 여기 닿아도(beat가 아직 키를 못 놓은 사이) BLOCK이라 아무것도 안 한다. 이 레코드는 클릭 갈래가 아니라 개체창
  클릭은 지금처럼 프레임으로 간다.

### G3. 루프에 넣는 조건

- `hasTail`을 없애고 키를 쥐는 키는 모두 `Judgment.Build`를 돌린다. 결과가 늘 "우리 것"인 아이템(항목 없음,
  `rest = OURS`)은 버린다.
- "마지막 액션에 조건이 없다"로 고르지 않는 까닭: 조건은 없어도 맨 누름에서는 안 나가는 액션이 있다(개체창 위에서만
  나가는 `normalCast = false`, 시전 값을 다 끈 액션). `RecordsItem`이 늘 맞는 상자에서 `rest`를 정하고 뒤를 잘라 내니,
  아이템이 그것을 이미 정확히 안다.
- 조합 키는 "기본 키에 아이템이 없으면 조합 키도 늘 우리 것"이라는 지금 규칙을 따른다.

### G4. 헤드리스 시험

모두 고치기 전 코드, 또는 일부러 틀린 코드에서 실패하는 것을 먼저 본다.

| 경우 | 기대 | 실패를 볼 코드 |
|---|---|---|
| `[combat]` 액션 하나, 전투 밖 | 놓음 | 지금 코드 |
| 같은 키, 옵션 끔 | 쥠 | 옵션을 안 읽는 코드 |
| 조건 없는 액션으로 끝나는 키 | 아이템 없음, beat 없음 | 모든 키에 아이템을 남기는 코드 |
| 끝에 조건 없는 Nothing | 쥠 | 같은 코드 |
| 끝에 조건부 Nothing, 조건 거짓 | 놓음 | 지금 코드 |
| 개체창 위에서만 나가는 액션 | 맨 누름은 놓고, 가리킨 누름은 쥠 | 지금 코드 |
| 조합 키, focus 쌍둥이가 맞을 때와 안 맞을 때 | 맞으면 `ALT-X` 쥠, 아니면 `X`를 따라 놓음 | 지금 코드 |

### G5. 비용

- 리빌드: 키마다 `Judgment.Build`가 돈다. 키 수에 따른 리빌드 시간을 잰다.
- beat: 조건부 키가 있는 프로필은 이제 beat가 선다. `--bench-beat`의 합성 프로필에 꼬리 없는 조건부 키를 넣어 잰다.

**잰 것 (2026-10-07, `--bench-beat`, 헤드리스 lua5.1).** 리빌드는 같은 프로필을 일곱 번 지어 첫 번을 버린 중앙값이고,
Windows의 `os.clock`이 1 ms 단위라 작은 쪽은 그만큼 거칠다.

| | 옵션 켬 | 옵션 끔 |
|---|---|---|
| 리빌드, 꼬리 없는 조건부 키 12 / 30 / 60 / 120개 | 4 / 7 / 11 / 28 ms | 1 / 5 / 8 / 19 ms |
| 리빌드, 소유자 모양(30키 × 액션 10 × 조건 5) 꼬리 없음 | 90 ms | 93 ms |
| beat, 꼬리 없는 키 4 / 12 / 30개, 조용할 때 | 9.35 / 9.44 / 9.44 µs | beat 없음 |
| beat, 같은 키, 전투·탈것이 뒤집힐 때 | 10.13 / 10.70 / 11.39 µs | beat 없음 |

- 리빌드에 더해지는 것은 키 120개에서 약 9 ms이고 키 수에 비례한다. 소유자 모양에서는 솔버 몫에 묻혀 차이가 측정 오차
  안이다(꼬리를 단 같은 모양이 98 ms).
- beat는 꼬리 키 프로필과 같은 값이다(꼬리 키 12개 9.44 µs). 키가 늘어도 조용한 beat는 그대로이고, 움직일 때만 판정한
  묶음 수만큼 는다. 새로 생기는 비용은 값이 아니라 **beat가 서는 프로필이 늘어난다**는 것 하나다. 꼬리 없이 조건부 키 하나만
  있어도 이제 beat가 선다.
- 그래서 깎을 것은 없다. 다시 볼 조건은 `keeping-only-the-records-form.md`가 이미 적은 0.5 ms/s 그대로다.

### G6. 화면 배선

- 목업을 실제 저장으로 바꾼다. `OPTION_FIELDS`에 `giveBackWhenNoActionRuns = "boolean"`, `ResetToDefaults`, 로케일 키.
  `check:export-fields`가 둘을 맞춘다.
- `giveBackWhenActionExists`를 지운다. 7→8 단계에서 저장 값, `OPTION_FIELDS`, `ResetToDefaults`,
  `DebindPrivate.GiveBackWhenActionExists`, 스니펫의 `GiveBack.onlyWithAction`이 대상이다. 옛 계정 백업의 그 필드는
  가져올 때 `OPTION_FIELDS`에 없어서 버려진다.
- 게임 안 키트: 조건부 액션 하나뿐인 키가 조건 밖에서 놓이고 조건 안에서 다시 잡히는지를 등록한다.

### G7. 문서와 문구

- `handing-the-rest-of-a-key-to-the-game.md` 1절과 2-2 표의 "아무것도 안 맞음 → 우리 것".
- `which-action-a-key-runs.md`의 정답표와 그 행에 묶인 시험.
- What's New.
- **도움말은 이 문서의 범위가 아니다** (소유자: 한 세션을 통째로 쓰는 일이다). `ordering.md`의 "The key does nothing"이
  이 변경으로 틀린 말이 된다.

## 3. 함정 (2026-10-07, 되돌린 G6·G7에서)

`debind-d8`이 G6·G7을 구현하고 리뷰를 여섯 번 돌린 끝에 통째로 되돌렸다(6462ec0). 리뷰마다 결함이 나왔고, 대부분 아래
꼴이었다. 되돌린 커밋(3388a85, 9780f2e, e845de6, 435ecf1, 9317497, 5bf80e7)은 `git show`로 읽을 수 있다. 참고는
하되 그대로 다시 적용하지 않는다.

### 3-1. 구조: 요구가 바뀌면 옛 구조도 고친다

- **키를 쥘지와 머리글 색은 한 곳에서, 바인딩이 실제로 나갈 수 있는지 안 뒤에 정한다.** 1c81ae6은 `BuildKeyMap`에서
  `PrepareKeyBindings`가 바인딩을 버리기 전에 `KeysToHold`·`HandledKeys`를 정했다. 그래서 쥐는 바인딩이 다 버려진
  키는 루프에서는 늘 돌려지는데 머리글은 흰색이었다. 5bf80e7은 `UpdateBindingsMap`에 분기를 덧대 결정이 두 곳이 됐고,
  개체창 클릭으로만 답하던 마우스 버튼(애초에 `KeysToHold`에 없었다)을 빠뜨려 곧바로 어긋났다.
- **실제로 내보낸 기록이 이미 있었다.** `ClickTimeKeys`(키를 묶는 줄에서 채움, `IsKeyOurs`)와 방출된 `ClickCastKeys`다.
  그래서 미리 정하는 단계를 없애고 `HandledKeys`를 그 두 줄에서 채운다(1-1절 끝). `loopoff_spec`의 "builder refuses"
  두 경우가 고치기 전 코드에서 실패했다.
- `BuildKeyMap`만 불러 보는 스펙(context, keygroup, role, specid, emit)은 `KeyMap`만 묻는다.
- **조건끼리 모든 상태를 덮는 키**(`[combat]`과 `[nocombat]` 둘)도 아이템을 만들어 beat에 오른다. `IsAlwaysOurs`가
  항목 0개만 알아보기 때문이다. 동작은 맞고 낭비다. 판정 아이템의 제약은 솔버의 바인딩 열과 일대일이 아니라, 솔버의
  덮임 판정을 그대로 가져다 쓰면 놓아야 할 키를 쥘 수 있다. 할지는 소유자가 정하지 않았다.

### 3-2. 등급 합치기: 빨강은 생각보다 많은 곳에 있다

- 색과 그리기가 흩어져 있다. `Issues.lua`의 `GetIssueColor`·`IsIssueError`·`IsIssueWarning`·`GetGroupIssueGrade`,
  `Constants.lua`의 등급 표, `DebindUI.lua`의 마크 종류·순서 칸·키 글자색, `ActionTooltip.lua`의 이슈 줄 함수 둘과
  `addErrorLine`·`addLabelLine`의 빨강 갈래·"아무것도 안 고름" 값 줄, 없는 스위치·없는 매크로 줄, `MenuKit.lua`의
  `SetErrorTooltip`과 `BuildNode`의 대체값, `ActionMenuItems.lua`의 스위치 하위 메뉴, `SwitchesUI.lua`의 툴팁과 식
  입력칸 글자색.
- **게임 안 키트도 색을 잰다.** "Switches tab: an expression left naming a deleted switch goes red"는 입력칸을
  `ERROR_COLOR`와 비교한다. 입력칸을 주황으로 바꾸면 이 시험이 깨진다.
- **사용자 문구:** `SWITCH_DELETE_CHOICES`가 "marked in red"라고 말한다(koKR도). 뜻이 바뀐 koKR 키는 번역하지 말고
  지운다(`writing-user-facing-text.md`).
- **주석 약 50곳**이 이슈를 "red", "reddens", "빨강", ERROR, WARNING, grade로 말한다. 코드, 키트, `DevSeed.lua`,
  XML 주석, `which-action-a-key-runs.md` S5 표의 행까지다. 낱말 뿌리(`redd`, `redden`, `빨`)와 등급 낱말까지 넓혀
  찾는다. 실제 빨강(막힌 이동 화살표, General 문구, Nothing의 X 아이콘, 시험 실패)은 남긴다. "모르는 주문은 빨갛다"
  같은 문장은 확인 없이 남기지 말고 코드로 확인한다(이름은 회색과 파랑만 쓴다).
- 공용 함수로 옮길 때 기본값이 바뀌는지 본다. `GameTooltip_AddErrorLine`은 줄바꿈하고, `wrap or false`는 안 한다.

### 3-3. 설정 배선

- `Options().x = (not value) and false or nil`은 늘 nil이다. if/else로 쓴다.
- 클라이언트 `NEVER`는 koKR이 "표시 안 함"이라 쓰지 않는다.
- `giveBackWhenActionExists`를 지우면 스니펫(`UpdateGivenBackKeys`)에서 페이지 계산도 같이 빠지고, 두 골든이 그만큼
  움직인다. 7→8 단계에서 저장 값을 지우는 마이그레이션 시험은 고치기 전 코드에서 빨간 것을 봤다.

### 3-4. 키트

- 기본값(옵션 켬)에서 꼬리 없는 조건부 키는 돌려진다. 그 전제로 짠 "The driver is off Blizzard's beat"는
  `HoldUnmatchedKeys()` 없이는 "the key did not bind"로 실패한다. 다른 시험도 같은 전제를 찾는다.
- 키트 여러 곳이 아무 `"CLICK "`이나 우리 것으로 본다. 키를 놓으면 테스터의 다른 애드온 바인딩이 보이므로,
  `DefaultClickFrame` 이름까지 맞춰 보는 함수 하나를 두고 모두 그것을 쓴다(남의 엔진 프레임을 보는 한 곳은 예외).

### 3-5. 명세 문서

- **승자 없는 조합 키(Self/Focus Cast Key 층)는 맨 키를 따른다**(`JudgmentEntryFor`의 `BASE`, `SecureBindings.lua`의
  `base` 풀이). 맨 키가 우리 것이면 아무 일도 안 하고, 돌려진 것이든 `COMMAND` 꼬리든 우리 것이 아니면 조합 키를
  놓는다. 바뀐 단축바·애완동물 대전·집 편집기로 맨 키를 돌려주는 동안엔 조합 키도 같이 넘어간다
  (`UpdateGivenBackKeys`). "옵션과 상관없이 아무 일도 안 한다"는 두 번 다 틀렸다.
- 다른 세션이 같은 문서(§3·§6)에 조합 키 문단을 미커밋으로 쓰고 있다.

### 3-6. 진행

- **다른 세션의 미커밋 작업이 같은 파일에 있다**(`UpdateBindings.lua`, `SecureBindings.lua`, `DebindTest.lua`,
  `which-action-a-key-runs.md`, 골든). 제 hunk만 커밋한다. 문맥 없는(`-U0`) 패치는 순수 삽입을 줄 번호로 붙여 엉뚱한
  자리에 넣은 적이 있다. 문맥 있는 패치로 넣고, 커밋할 상태만 임시 worktree에 꺼내 시험한다.
- **리뷰 범위는 커밋 해시로 적는다.** 이 저장소의 `/code-review`는 범위를 스스로 잡는데, 미커밋 변경은 다른 세션 것으로
  빼고 커밋 범위는 다른 세션 커밋까지 넓게 잡았다. 리뷰할 것은 먼저 커밋하고, 그 해시만 보라고 적는다.
- 결과를 보고할 때 도구·지시문·소유자 탓으로 돌리지 않는다. 확인하지 않은 도구 동작을 사실처럼 말하지 않는다.
