# Replaced Action Bar 조건을 Bar Takeover로 바꾸기

> 상태: 구현했다(2026-10-08). 남은 것은 도움말 하나다. `keys-given-back.md` 4번 항목이 "druid forms and skyriding do not
> count"라고만 해서 은신이 빠져 있다. 도움말은 손대기 전에 범위를 소유자에게 묻는 것이 규칙이라 물어 둔 상태다.
>
> 쓴 세션: `debind-3e` (세션 ID `9c6ce919-05ff-4e0d-aa1f-839f97dff70f`). 2026-10-08.

`need-fixing.md` 3번 항목에서 나온 계획이다. 이 계획을 끝내고 `legacy/`로 옮길 때 그 항목을 `need-fixing.md`에서
지운다. 다만 그 항목의 "같이 정할 것"(Action Button keys의 기본값)은 이 계획 밖이다. 그때까지 정해지지 않았으면
그 부분만 남긴다.

## 왜

조건 "Replaced Action Bar"(`specialbar`)는 애완동물 대전까지 덮는다(`ConditionText.lua`의 `specialbar` 갈래가
`[petbattle]`까지 쓴다). 그런데 설정의 Keys Given Back에서 같은 이름의 값은 대전을 뺀 뜻이다. 대전은 옆 값
"Pet Battles"가 따로 맡는다. 한 이름이 두 곳에서 다른 것을 가리킨다.

조건을 둘로 나누는 길은 막혀 있다. 조건끼리는 AND로만 묶인다. 그래서 바뀐 바 조건과 대전 조건을 따로 두면
"바뀐 바일 때 또는 대전일 때"를 액션 하나에 쓸 수 없다. 지금 `specialbar`를 켠 액션이 바로 그 뜻이다.

그래서 축 하나 안에서 칸끼리 OR가 되는 마스크로 바꾼다. `forms`, `bonusbars`, `groups`와 같은 꼴이다.

설정 쪽을 하나로 합치는 길도 따져 봤다. 합치면 기본값도 하나여야 한다. 지금은 바뀐 바 끔, 대전 켬이라
"대전만"이라는 지금 기본값을 잃는다. 그래서 이 길은 버렸다.

## 정한 것

모두 소유자가 2026-10-08에 정했다.

1. **따로 있던 `petbattle` 조건은 이 축에 합친다.** 남겨 두면 대전이 두 조건에 걸친다. 그러면 지금과 같은 모순
   검사가 남고, 솔버가 같은 축을 두 열로 본다.
2. **지금 죽어 있는 "바 켬 + 대전 끔" 액션은 살린다.** 아래 결함 때문에 지금 안 돈다. 옮기면 Replaced Action
   Bar 칸 하나가 되고, 사용자가 처음 뜻한 대로 돌기 시작한다. 지금 동작을 지키려면 빈 마스크로 옮겨 사용자가 쓴
   조건을 지워야 한다. 조건이 칸을 고르는 꼴이 되니, 결함을 데이터로 옮겨 적을 까닭이 없다.
3. **필드 이름은 `bartakeover`로 바꾼다.** 어차피 저장된 값을 모두 고쳐 쓰는 단계라 사용자 쪽 비용은 없다. 옛
   불리언과 새 마스크가 같은 이름을 나눠 쓰지 않으니, 이미 옮겼는지를 필드가 있느냐로 가릴 수 있다. 코드 이름도
   메뉴 이름과 맞는다. `extrabar`, `bonusbars`처럼 소문자를 붙여 쓰는 꼴이다. 열 종류, 이슈 범주, 메뉴 노드,
   상수, locale 키도 같은 이름을 따른다.
4. **결함만 먼저 따로 고치지 않는다.** 이 계획과 함께 고친다. 사용자는 나간 판만 본다. 이 계획이 다음 판보다
   먼저 들어오면 따로 고친 커밋은 사용자에게 아무것도 더 주지 않고, 고칠 테스트만 두 번이 된다. 이 계획 없이
   판이 하나 나가게 되면 그때 다시 본다.

## 지금 있는 결함

`Issues.lua`의 `SpecialBarAgainstPetBattle` 첫 갈래는 "바 켬 + 대전 끔"을 절대 안 도는 조합으로 본다. 하지만
그 조건문은 `[vehicleui,nopetbattle]`처럼 나오고, 대전 밖에서 차량을 타면 참이다. 그래서 "차량에서만, 대전은
빼고"라는 정상 액션이 경고를 받고 키에서 빠진다. 이 계획이 들어가면 그 검사 자체가 없어진다.

그 갈래를 지금 고정해 둔 테스트가 둘 있다: `keymap_spec.lua:126`, `issue_spec.lua:1050`.

## 모양

```
Action Bars
├ Stance Bar
├ Bar Takeover
│   ( ) Off
│   [ ] None
│   [ ] Replaced Action Bar
│   [ ] Pet Battles
└ Extra Action Button
```

- Off는 칸이 아니다. 조건이 없는 상태(`nil`)이고, `forms`와 `bonusbars`의 Off와 같다.
- 제목 "Bar Takeover"는 우리가 지은 말이다. 클라이언트에는 이 셋을 묶는 말이 없다. "Action Bar 1"도
  따져 봤지만 버렸다. 폼 바는 페이지가 1일 때만 뜨고(`ActionBarController.lua:161`), 나중에 페이지 조건이
  들어오면 그것도 Action Bar 1의 상태가 된다. 그러면 이 메뉴 하나만 그 이름을 가질 까닭이 없다.
- "None"은 클라이언트의 `NONE`을 쓴다. "Normal"은 변신 중인 사용자를 망설이게 하고, "Default"는
  기본값으로 읽혀서 버렸다.
- "Replaced Action Bar"는 지금 `CONDITION_SPECIALBAR`의 값 그대로다. 설정 값도 같은 키를 읽는다. 이제 뜻도
  같아진다.
- "Pet Battles"는 설정 값 `GIVE_BACK_PET_BATTLES`와 같은 `SHOW_PET_BATTLES_ON_MAP_TEXT`다.
- vehicle, override, possess로 더 나누지 않는다. 사용자가 이름을 모르는 것도 있지만, 그보다 어느 전투가
  어느 바를 쓰는지 화면으로는 가를 수 없다. 칸을 나눠 줘도 고를 근거가 없다.

Replaced Action Bar 칸의 툴팁:

> While a vehicle, a possession or a quest replaces your whole action bar. What *Stance Bar* covers — forms,
> stealth, skyriding — is not included.

설정 쪽 `GIVE_BACK_REPLACED_BAR_DESC`도 같이 고친다. 지금 "Forms and skyriding are not included"에서 은신이
빠져 있다. 설정 창에는 Stance Bar 메뉴가 없으니 거기서는 예 셋을 그대로 적는다.

## 비트와 조건문

| 칸 | 비트 | 조건문 |
|---|---|---|
| None | 1 | `[nopetbattle,novehicleui,nopossessbar,nooverridebar,noshapeshift]` |
| Replaced Action Bar | 2 | `[nopetbattle,vehicleui]` `[nopetbattle,possessbar]` `[nopetbattle,overridebar]` `[nopetbattle,shapeshift]` |
| Pet Battles | 4 | `[petbattle]` |

- 대전을 먼저 묻는 순서 덕분에 상태 하나가 칸 하나에만 들어간다. `groups`가 레이드를 파티보다 먼저 묻는 것과
  같은 까닭이다(`Constants.STATE_EVAL_EXPRESSIONS`의 `groups` 주석). 차량 바와 대전이 함께 켜지는지는 잰 적이
  없지만, 이 순서면 그 답이 무엇이든 칸이 겹치지 않는다.
- 칸 둘을 고른 마스크는 더 짧게 쓸 수 있다. None+Replaced는 `[nopetbattle]`, Replaced+Pet Battles는 지금
  `specialbar = true`가 쓰는 글 그대로다.
- 빈 마스크는 `BONUSBARS_NONE_SELECTED`처럼 이슈로 띄우고 액션을 뺀다.

## 옮기기

`DB_VERSION` 8은 아직 나가지 않았다. v4.1.2는 7이다. 그래서 새 단계를 두지 않고 `MigrateLayer`의
`dbver <= 7` 단계("The unreleased step")에 얹는다. 받은 붙여넣기도 같은 사다리를 타니, 그 단계는 입력의
타입부터 확인해야 한다.

옛 필드 `specialbar`, `petbattle`은 둘 다 지우고 `bartakeover` 하나를 쓴다.

| 저장된 값 | 지금 하는 일 | `bartakeover` |
|---|---|---|
| 바 켬, 대전 없음 | 바뀐 바 또는 대전 | Replaced + Pet Battles (6) |
| 바 끔, 대전 없음 | 바뀌지 않고 대전도 아님 | None (1) |
| 바 없음, 대전 켬 | 대전 | Pet Battles (4) |
| 바 없음, 대전 끔 | 대전 아님 | None + Replaced (3) |
| 바 켬, 대전 켬 | 대전 (`FillBinding`이 바를 지움) | Pet Battles (4) |
| 바 켬, 대전 끔 | 결함 때문에 안 돎 | Replaced (2). 돌기 시작한다 (정한 것 2번) |
| 바 끔, 대전 켬 | 진짜 모순이라 안 돎 | 빈 마스크(0). 이슈로 계속 안 돎 |
| 바 끔, 대전 끔 | 바뀌지 않음 | None (1) |

- 액션을 둘로 나눠야 하는 경우는 없다.
- 발동 순서는 그대로다. `CompareActionOrder`는 조건이 있느냐만 묻는다. 위 표에서 조건이 있던 액션은 모두
  `nil`이 아닌 값을 받는다.
- 다시 돌려도 안전하다. 옮긴 뒤에는 옛 필드 둘이 남지 않는다.
- 불리언이 아닌 옛 값은 손으로 만든 데이터다. 고쳐 주지 않는다.

## 고칠 곳

**저장과 상수**
- `Constants.lua`: `bartakeover`의 비트 셋과 `ALL`. `CONDITION_FIELDS`와 `BINDING_ISSUE_CATEGORIES`에서
  `specialbar`, `petbattle`을 `bartakeover` 하나로. `MEASURED_BY`, `STATE_EVAL_EXPRESSIONS`의 두 줄과 그 주석
  ("`specialbar` folds it in")을 다시 본다. 새 이슈 코드 `BARTAKEOVER_NONE_SELECTED`와 그 결과
  (`ISSUE_OUTCOME_OMIT`).
- `DebindStorage/Export.lua`: 필드 타입 표의 두 줄을 `bartakeover = "number"` 하나로(`check:export-fields`).
- `Migration.lua`: 위 표.

**판정**
- `ActionBindings.lua`: `FillBinding`의 겹침 처리(485행)를 뺀다.
- `Solver.lua`: 두 불리언 열을 `bartakeover` 마스크 열 하나로. 머리말의 `bonusbars` 줄("those are
  `specialbar`")도 고친다.
- `Judgment.lua`: `BOOL_FIELDS`의 두 줄을 빼고 `MASK_FIELDS`에 `bartakeover`.
- `Issues.lua`: `SpecialBarAgainstPetBattle`과 그 두 줄을 빼고, 빈 마스크 검사를 넣는다.
- `Rebuild/ConditionText.lua`: 위 비트 표대로 쓴다. 지금 102행 주석은 까닭을 거꾸로 적고 있고, 있지도 않은
  키 `GIVE_BACK_PET_BATTLE`을 든다. 새로 쓴다.
- `Rebuild/KeyRecords.lua`: 두 필드를 `bartakeover` 하나로.
- `Rebuild/JudgeLoop.lua`: `bartakeover` 열의 칸을 `J.petBattle`이면 4, 아니면 바뀐 바 파싱으로 2 또는 1로 낸다.
  `specialbar`·`petbattle` 갈래들(`JudgmentWakesOf`, `JudgedOnBeat`, `otherCell`, `JUDGED_BOOL_STATES`,
  `StateCellClauses`의 예외, `NegatedGroups`의 주석, `watchSpecialbar`)을 정리한다. 깨우는 쪽은 그대로 `petbattle`이다.
- `UpdateBindings.lua`: `CollectDriverEvents`의 `judged.specialbar`를 `judged.bartakeover`로.
- `SecureBindings.lua`의 `SetPetBattle`은 그대로다. 주석의 "`petbattle` and `specialbar`"만 다시 본다.

**화면**
- `Menus/ActionMenuNodes.lua`: `SPECIALBAR` 노드를 `BARTAKEOVER`로, `Disable` + `Checkboxes`로. "그 밖" 묶음에서
  `PETBATTLE` 줄을 뺀다(859, 902, 909행). `ACTIONBAR`의 `isActive`도 새 필드를 본다.
- `ActionTooltip.lua`: 불리언 줄 둘(818, 820행)을 마스크 줄 하나로, 빈 마스크 이슈 줄도 넣는다. 940행 목록의
  `CONDITION_PETBATTLE`도 다시 본다.
- `SettingsTab.lua`: 설정 값이 칸과 같은 키를 읽으니, 키 이름이 바뀌면 따라 바꾼다.
- `Locales/*.lua`: 제목 키(Bar Takeover), 칸 셋, 칸 툴팁, 빈 마스크 이슈 문장. 쓰지 않게 된
  `CONDITION_SPECIALBAR_YES/_NO/_DESC`, `CONDITION_PETBATTLE*`는 지운다. `GIVE_BACK_REPLACED_BAR_DESC`에 은신.
  koKR, ruRU도 같이. 1191, 1197행의 주석이 `CONDITION_SPECIALBAR`를 이름으로 드니 같이 고친다.
  koKR("특수 단축바")와 ruRU("Специальная панель")의 `CONDITION_SPECIALBAR`는 enUS의 "Replaced Action Bar"와
  뜻이 다르다. 이 값은 설정 쪽(`SettingsTab.lua:276`, `281`)에도 나오니 두 언어도 "바뀐 바"라는 뜻으로 다시 쓴다.
- 도움말: `docs/ingamehelp/*/keys-given-back.md`와 조건을 설명하는 쪽. `help-pages` 스킬을 따른다.

**테스트**
- 헤드리스: `eval_spec`(477행 "plus pet battle"), `judgment_spec`(243행의 상태 모형, 1698·1850행), `keymap_spec`
  (126행), `issue_spec`(1050행), `normalize_spec`(607행), `solver_spec`(795행), `import_spec`(403행),
  `plan_spec`(383행), `menukit_spec`(236–262행), `emit_fixture`, `bench`, `beatbench`. 옮기기 표의 여덟 줄은
  마이그레이션 스펙에 한 줄씩 둔다.
- 키트: `DebindTest.lua` 8694행의 `SetPetBattle` 시험은 `[petbattle]`과 `[nospecialbar]`를 쓴다. 새 칸으로
  바꾼다. `DevSeed.lua` 185–195행의 "`petbattle` and `specialbar` cannot share an action"도 다시 쓴다.
- `tests/v3.5.2/`는 옛 판의 사본이라 손대지 않는다.

## 구현하며 정한 것

- **대전만 묻는 열은 beat가 안 잰다.** 옛 `petbattle` 열은 밀어 넣는 값이라 beat가 없었다. `bartakeover`를 비트 열로만 바꾸면
  대전만 묻는 키도 beat마다 바를 파싱하게 된다. 그래서 `bartakeover`를 칸 묶기(`ColumnGroups`) 대상에 넣었다. 어떤 검사도
  None과 Replaced를 가르지 않으면 파싱할 글이 없고 beat에서 빠진다(`JudgeLoop.lua`의 `BarTakeoverCells`). `plan_spec`이
  이것을 본다.
- **칸 목록은 한 벌이다.** 툴팁과 메뉴가 같은 `BARTAKEOVER_CELLS`를 읽는다(`ActionTooltip.lua`).
- **설정 값과 같은 문자열이 키 이름을 따라갔다.** "Replaced Action Bar"는 이제 `CONDITION_BARTAKEOVER_REPLACED`이고, 설정 탭도
  그 키를 읽는다. koKR와 ruRU의 옛 키는 지웠다. 두 언어에는 아직 새 키가 없어 영어로 나간다.
- **문구.** 메뉴 행 설명 `CONDITION_BARTAKEOVER_DESC`는 "What has taken over your main action bar, if anything.", 빈 마스크 이슈
  문장은 "No action bar state is selected."로 썼다. 칸 툴팁은 Stance Bar를 `%s`로 받는다. 다른 컨트롤의 이름을 문장에 다시
  치지 않는다는 규칙 때문이다.
- **`STATE_EVAL_EXPRESSIONS`의 `bartakeover`도 파싱이다.** 제한 환경에는 대전과 possess bar를 답하는 함수가 없다.

## 이 계획 밖

- 설정 "Action Button keys"의 기본값. 지금은 Pet Battles만 켬이다. `need-fixing.md` 3번의 "같이 정할 것"에
  남아 있다.
- 페이지 조건(`[actionbar:n]`). 들어오면 Action Bars 아래 Stance Bar 옆에 선다. 하나 확인할 것이 있다. 페이지
  2에서 차량을 타거나 변신했을 때 `GetActionBarPage()`가 계속 2를 답하는지는 잰 적이 없다.
  `Probe_ActionBars.lua`의 기록(xptr #1, 2026-09-14·19)에는 페이지 1에서 들어간 표본만 있다.
