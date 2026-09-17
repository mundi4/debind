# `EvaluateIssues`를 다시 짜기 (2026-09-17 시작)

> 상태: **계획. 코드는 안 건드렸다.** 정답표(§4)와 기존 테스트 대조(§5)는 2026-09-17에 지금 코드를
> 헤드리스로 돌려 채웠다. 구현 순서는 §8이다.
>
> 규칙은 `which-action-a-key-runs.md`(S2, S3)가 들고, 이 문서는 이슈 검사가 그 규칙을 어떻게 읽어야
> 하는지와 그것을 재는 표만 든다. 둘이 갈리면 스펙이 맞다.

## 0. 왜 다시 짜나

2026-09-17에 소유자가 게임에서 본 것. 대상을 안 고른 액션(루트 Target이 Disable)에서 Units › Resolved
Unit의 반응을 전부 끄면 세 곳이 빨갛다. Units › Resolved Unit은 맞고, Units › Target과 루트 Target은
틀렸다. 사용자는 그 두 곳에 아무것도 걸지 않았다.

원인을 코드로 따라가 확인한 것.

- `EvaluateIssues`는 액션을 받자마자 `GetBindingInfoForAction(action)`으로 **원본 바인딩 하나**를 만들고,
  유닛 갈래는 그 바인딩의 `unitStates`, `unitGroups`, `unitRole`, `unitFrameTypes`만 읽는다.
- `BuildUnitStates`는 `"@"`를 그 바인딩이 겨누는 유닛 칸에 접는다(`ResolvedUnitOf`). 대상을 안 골랐으면
  `target` 칸이다. `"@"`의 조건과 `target` 줄의 조건이 한 칸에서 만나 0이 되면 **누구 때문인지가 칸에
  안 남는다.** `contributed`와 `target == unit`이 그 빈자리를 짐작으로 메우고, 위의 두 오답이 거기서
  나온다. 툴팁의 Target 줄도 같은 물음(`GetIssue("unit", "@")`)이라 같이 틀린다.
- 원본만 본다. 스펙 S2, S3에서 `"@"`는 **바인딩마다** 그 바인딩이 겨누는 유닛에 묻는다. self 쌍둥이는
  `player`, focus 쌍둥이는 `focus`, hover 쌍둥이는 `H`. 대상 안 고름, `"@"` [우호], `target` [적대]인
  액션은 원본만 못 서고 쌍둥이 셋은 선다. 지금은 `CONDITIONS_NEVER`(ERROR)가 나고, ERROR는
  `BuildKeyMap`이 액션을 통째로 빼므로 멀쩡한 쌍둥이까지 키에서 사라진다.
- 반대로 **쌍둥이만 죽는 경우는 아무도 안 본다.** `"@"` [우호]에 `player` [적대]면 self 쌍둥이의
  `player` 칸이 0인데 원본은 멀쩡하니 이슈가 없고, 그 죽은 쌍둥이가 `KeyMap`에 들어가 솔버와
  `UpdateBindings`까지 간다(§4 R, F, G 줄). `mergeUnitConditions`의 `NEVER`가 그것을 방출 직전에
  걸러서 지금까지 증상이 없었을 뿐이다. 그 함수의 머리 주석이 "여기까지 오는 것 자체가 없다"고
  장담하는 보장은 **원본에만** 서 있었다.
- 솔버는 칸이 0인 상자를 표시도 삭제도 안 한다(`Solver.lua`의 `isCovered` 머리 주석). 지금 그 앞에서
  거르는 것은 `GetBindingIssue`뿐이다.
- 액션 자체는 안 바뀐다. 접기는 전부 바인딩 복사본에서 일어난다. **잘못된 것은 쓰기가 아니라 읽기다.**

## 1. 소유자가 정한 것 (2026-09-17)

- 액션은 저장된 그대로다. 저장되지 않는 임시 필드를 액션 루트에 다는 것까지는 괜찮고, 그 이상 손대지
  않는다.
- 접는 것은 바인딩의 일이다. 액션의 이슈를 접힌 바인딩으로 판정하지 않는다.
- 바인딩 전부가 못 설 때만 문제다. 일부만 못 서면 이슈도 경고도 아니다. 그 바인딩만 키에서 빠진다.
- 루트 Target이 Disable인데 에러가 나오는 것은 말이 안 된다.
- `if` 사슬을 하나 더 얹는 식으로 고치지 않는다. 고칠 자리마다 짐작이 붙는 것은 함수를 뜯어고칠
  때라는 신호다.
- 전부 헤드리스로 잰다.

## 2. 설계

### 2-1. 물음이 둘이고, 둘은 다른 것을 읽는다

**액션 이슈**는 저장된 값만 읽는다. 바인딩을 만들지 않는다.

| 갈래 | 읽는 것 | 코드 | 칠하는 곳 |
|---|---|---|---|
| `key` | `action.key` | `NOT_SUPPORTED_GAMEMENU_KEY` | KEY |
| `groups` | `conditions.groups == 0` | `GROUPS_NONE_SELECTED` | CONDITION_GROUP |
| `specs` | `conditions.specs`가 빈 표 | `SPECS_NONE_SELECTED` | CONDITION_SPEC |
| `forms`, `bonusbars` | 0 | `*_NONE_SELECTED` | 각 묶음 |
| `known` | 이름에 `,`나 `]` | `KNOWN_NAME_UNPARSABLE` | CONDITION_KNOWN |
| `states` | `SETSTATE_MODES`인데 `value`가 문자열이 아님, `GetUndefinedSwitch` | `SWITCH_NONE_SELECTED`, `UNDEFINED_STATE` | CONDITION_CUSTOM_STATES |
| `macro` | `GetMissingMacroName` | `MISSING_MACRO` | TYPE_MACRO |
| `specialbar`, `petbattle` | 둘이 어긋남 | `CONDITIONS_NEVER` | 양쪽 |
| `skyriding`, `bonusbars` | 둘이 어긋남 | `CONDITIONS_NEVER` | 양쪽 |
| `units` | **스스로 빈 유닛 줄**: 저장된 줄의 `reaction == 0`, `group == 0`, 그리고 `unitframe` 줄(대상이 `unitframe`이면 `"@"` 줄도)의 `role == 0`, `frameTypes == 0` | 지금 코드와 같은 코드(`CONDITIONS_NEVER`, `UNITGROUPS_NONE_SELECTED`, `HOVER_NONE_SELECTED`) | CONDITION_UNITS. 짚어 물으면 그 줄만. 루트 Target은 안 칠한다 |

스스로 빈 줄은 접기 전에 이미 아무 유닛도 못 맞는 값이라 액션 이슈다. 그 줄을 묻는 바인딩은 전부
못 서지만 그 판정에 바인딩이 필요 없다. 역할과 프레임 종류는 개체창을 가리킬 때만 잴 수 있고 못 재면
맞음이라(S2), `unitframe` 자리에 걸린 0만 빈 줄이다. 지금 `BuildUnitStates`가 역할을 접는 조건과
같다.

**바인딩 이슈**는 `GetBindingsForAction(action)`이 만드는 목록 전부를 읽는다.

- 목록이 비면 `CASTING_NONE_LEFT`, 수식키 없는 왼클릭·오른클릭에 Hover Cast가 Skip이면
  `CASTING_BARE_CLICK_SKIPPED`. 지금 `casting` 갈래가 `normalCast == false`, `TwinUnitFor`,
  `KeyTakesCastKeyTwins`로 다시 계산하는 조건은 `GetBindingsForAction`이 빈 목록을 돌려주는 조건과
  글자만 다른 같은 식이다. 한 규칙을 두 번 적은 것이라 목록의 길이로 바꾼다.
- 목록의 바인딩이 **하나도 못 서면** `CONDITIONS_NEVER`. 못 선다는 것은 §2-2의 `dead`이거나
  `normalCast == false`다. 하나라도 서면 이슈가 아니고, 못 서는 것만 `BuildKeyMap`이 뺀다(§2-3).
- 칠하는 곳은 §2-4.

### 2-2. 바인딩이 서는가는 `FillBinding`이 적는다

`BuildUnitStates` 뒤에 `binding.dead`를 세운다. 참인 조건은 넷이고 전부 지금 `EvaluateIssues`가 원본에
대고 묻는 것 그대로다.

1. `unitStates[u] == 0`인 `u`가 있다.
2. `unitGroups[u] == 0`인 `u`가 있다.
3. `unitRole == 0`이거나 `unitFrameTypes == 0`이다.
4. 혼자일 때만(`groups`에 `GROUP_NONE`뿐)인데 `UNITS_ABSENT_WHEN_SOLO`인 유닛의 마스크에
   `UNITSTATE_NONE`이 없거나, `unitRole`에 `ROLE_NONE`이 없다.

`groups == 0` 같은 고정 컬럼의 0은 여기 안 든다. 액션 이슈가 ERROR로 잡아 액션이 키에서 빠지므로
바인딩까지 안 온다.

`dead`는 바인딩 하나의 순수 파생이라 `FillBinding`의 다른 필드와 같은 자리에 선다. 이슈 검사, `BuildKeyMap`,
`IsUnreachableAction`이 같은 필드를 읽는다.

### 2-3. 못 서는 바인딩은 `BuildKeyMap`이 뺀다

- `UnrollIntoTiers`가 `binding.dead`를 건너뛴다. 지금 `normalCast == false`를 4층에서 건너뛰는 자리다.
  탐침(`spellbook`)은 조건이 같아 `dead`도 같으므로 같이 빠진다.
- `IsUnreachableAction`은 `dead`인 것을 세지 않는다. "전부 덮였다"는 서는 것 전부가 덮였다는 뜻이고,
  서는 것이 없으면 거짓이다(빈 목록과 같다).
- 이것으로 **0인 칸을 든 상자는 솔버에도 `UpdateBindings`에도 안 간다**가 원본이 아니라 바인딩마다의
  보장이 된다. `mergeUnitConditions`의 `NEVER`는 그대로 두되 머리 주석을 이 문서대로 고친다. 갈리는 날
  알아채는 백스톱이고 값이라 비용이 없다는 결론은 그대로다. `MergeKeyUnitConditions`,
  `Solver.lua`의 `isCovered` 머리 주석, `Constants.lua`의 `UNITGROUPS_NONE_SELECTED` 주석,
  `tests/record_spec.lua`, `solver_spec.lua`, `normalize_spec.lua`의 같은 문장도 같이 고친다.

### 2-4. 칠할 줄은 `BuildUnitStates`가 출처로 적는다

`narrow(unit, mask, source)`. 출처는 비트다.

| 출처 | 언제 |
|---|---|
| `SOURCE_ROW` | 그 유닛의 저장된 줄 |
| `SOURCE_AT` | `"@"`가 이 바인딩에서 그 유닛으로 풀림 |
| `SOURCE_KEY` | 마우스 버튼 키의 규칙([`unitframe` 없음]) |
| `SOURCE_SKIP` | Hover Cast Skip이 원본에 얹는 [모드의 유닛 없음](`skipsPointedUnit`) |
| `SOURCE_TWIN` | hover 쌍둥이가 스스로 얹는 [`H` 있음](`UNIT_IS_THERE`) |

`binding.unitSources[unit]`에 `bor`로 쌓는다. 표는 바인딩이 갖고 리필마다 `wipe`한다. 쌍둥이의
[`H` 있음]은 `FillBinding`이 `conditions.units[pointedUnit]`에 써넣으므로 `BuildUnitStates`는 그것을
줄과 못 가른다. `FillBinding`이 `twinCondition == UNIT_IS_THERE`일 때 `binding.twinOwnUnit = pointedUnit`을
적고, `BuildUnitStates`가 그 유닛은 `SOURCE_TWIN`으로 센다(`UNIT_IS_THERE`의 선언을 `FillBinding` 위로
올린다). 사용자 줄에 좁혀 들어간 쌍둥이(`existing`)는 `SOURCE_ROW`다.

**"대상 고름"은 따로 적지 않는다.** `ActionHasPickedUnit(action)`이면 `"@"`는 고른 유닛에 풀리므로
`SOURCE_AT`가 곧 대상 고름이다. 대상을 안 골라 `target`으로 풀린 `"@"`는 `SOURCE_AT`이되 대상 고름이
아니다. 그래서 루트 Target은 **고른 유닛이 있고 그 유닛의 0에 `SOURCE_AT`가 있을 때만** 칠한다.

바인딩 이슈가 `CONDITIONS_NEVER`일 때(서는 바인딩이 없고 `dead`인 것이 있을 때), 못 서는 바인딩마다
못 서는 유닛 `u`(0인 칸, 또는 혼자 규칙의 유닛)와 그 출처로:

| 물음 | 칠하는 조건 |
|---|---|
| `units`, `arg = U` (Units › 유닛 줄) | 어느 바인딩의 `u == U`에 `SOURCE_ROW` |
| `units`, `arg = "@"` (Units › Resolved Unit) | 어느 바인딩의 `u`에 `SOURCE_AT` |
| `units`, arg 없음 (Units 묶음) | 위 둘 중 하나 |
| `unit` (루트 Target, 툴팁 Target 줄) | `ActionHasPickedUnit(action)`이고 `u`가 그 유닛이고 `SOURCE_AT` |
| `groups` | 혼자 규칙으로 못 서는 것이 있음. 지금과 같다 |

`SOURCE_KEY`, `SOURCE_SKIP`, `SOURCE_TWIN`만으로 0이 되는 일은 없다. 셋은 서로 만나지 않고 각각은
축의 반쪽이라, 0에는 언제나 줄이나 `"@"`가 함께 있다. 출처에 스스로 빈 줄(§2-1)이 있는 `u`는
건너뛴다. 액션 이슈가 그 줄을 이미 잡았고, 여기서 또 칠하면 `"@"`가 풀린 자리로 빈 줄의 0이 번진다.

`arg`가 유닛이 아닌 값(`unit`이 문자열이 아닌 바인딩, `unitStatesOpaque`)은 지금처럼 아무것도 안 묻는다.
`unitStatesOpaque`인 바인딩은 `dead`가 아니다.

### 2-5. `EvaluateIssues`의 새 모양

`Report`, `TakeIssue`, `LookingForWorse`, `collected`는 그대로 둔다. 갈래는 둘이 된다.

- **액션 갈래 표.** `{ category, label, check = function(action) return code, arg end }`의 배열을 돈다.
  `Looking()`과 `category`/`notCategory` 가드가 루프 한 자리에 선다. `units`의 스스로 빈 줄 검사는
  `arg`를 봐야 하므로 `check(action, arg)`로 받는다. 두 묶음을 칠하는 쌍(`specialbar`/`petbattle`,
  `skyriding`/`bonusbars`)은 표에 두 줄이다. 지금 코드가 그 둘을 따로 적고 있는 것과 같다.
- **바인딩 갈래 함수 하나.** `category`가 nil, `units`, `unit`, `groups`, `casting` 중 하나일 때만 돈다.
  `GetBindingsForAction(action)`을 한 번 부르고 §2-1의 빈 목록 검사와 §2-4의 칠하기를 한다.
  `notCategory`가 `units`면 유닛 부분을, `casting`이면 빈 목록 부분을, `groups`면 혼자 부분을 건너뛴다.

`BINDING_ISSUE_CATEGORIES`는 안 바뀐다. 호출자(`ActionMenuModel.issueForKey`, `ActionMenuNodes.FirstUnitIssue`,
`ActionMenuItems`의 Hover Cast 줄, `ActionTooltip.GetIssue`, `DebindUI`의 행, `Profile.MakeRow`)도 안 바뀐다.
`unit` 갈래는 `arg`를 무시한다. 툴팁이 `"@"`를 넘기지만 물음은 루트 Target과 같다.

## 3. 검토한 방향과 결론

| 방향 | 결론 | 이유 |
|---|---|---|
| 액션 이슈와 바인딩 이슈를 따로 구한다 | **택함** | 소유자의 둘째, 셋째 결정이 이 분리 자체다. 스스로 빈 줄과 `groups == 0`은 바인딩 없이 답이 나오고, "전부 못 설 때만"은 목록 전부를 봐야 답이 나온다 |
| 칠할 줄: `BuildUnitStates`가 좁힐 때 출처를 적는다 | **택함** | 0을 만든 자리가 곧 출처를 아는 자리다. 비트 하나라 할당이 없고, 좁히는 줄이 늘면 출처도 그 줄에서 는다 |
| 칠할 줄: 액션 사본에서 그 부분을 빼고 다시 파생해 서는지 본다 | 버림 | 메뉴 종류마다 무엇을 뺄지 나열해야 하고, 나열이 `BuildUnitStates`의 입력 목록과 따로 산다. 파생을 묶음마다 다시 하니 비용도 묶음 수 배다 |
| 0인 칸의 정의를 솔버와 공유한다 | 버림 | 공유할 것이 "0이면 빈 상자" 한 줄뿐이고, 그 상자를 드는 필드 넷(`unitStates`, `unitGroups`, `unitRole`, `unitFrameTypes`)은 이미 `BuildUnitStates`가 만들고 솔버가 읽는 공유 어휘다. 솔버의 컬럼 규칙은 **한 키에 어느 컬럼을 세우나**이지 상자 하나가 비었나가 아니고, 혼자 규칙은 컬럼 둘의 상관이라 어차피 솔버 밖이다. 솔버 쪽에 함수를 두면 `UNITS_ABSENT_WHEN_SOLO`까지 그쪽이 읽어야 한다. 대신 `Solver.lua` 머리에 "0인 상자는 이제 `BuildKeyMap`이 안 넘긴다"를 적는다 |
| 갈래를 표로 둔다 | 액션 갈래만 **택함** | 액션 갈래는 모양이 전부 같다(값 하나 읽고 코드 하나). 바인딩 갈래는 목록 하나를 놓고 여러 물음에 답하는 것이라 표의 행이 못 된다 |

## 4. 정답표

한 줄이 헤드리스 테스트 하나다. 따로 적지 않은 것은 기본값(대상 안 고름, 키보드 키, Cast Options
기본, 설정 탭 두 조합키 켬). 줄 이름은 Units 하위 줄이고, `Target`은 루트 Target(`unit` 갈래),
`Units`는 묶음, `KeyMap`은 `BuildKeyMap` 뒤 그 키의 레코드 수(탐침 없는 타입). "지금"은 2026-09-17의
코드가 낸 답이고, 비어 있으면 기대와 같다.

| # | 액션 | 액션 전체 | Units | 짚은 줄 | Target | groups | casting | KeyMap | 지금 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `"@"` 반응 0 (소유자 사례) | NEVER | NEVER | `"@"` NEVER, `target` nil | nil | | | 0 | `target` NEVER, Target NEVER |
| 2 | `"@"` [우호], `target` [적대] | nil | nil | 둘 다 nil | nil | | | 3 (hover, focus, self) | NEVER, KeyMap 0 |
| 3 | 2에 설정 탭 두 조합키 끔 | nil | nil | nil | nil | | | 1 (hover) | NEVER, KeyMap 0 |
| 4 | 대상 `focus`, `"@"` [우호], `focus` [적대] | NEVER | NEVER | `"@"`, `focus` NEVER | NEVER | | | 0 | |
| 5 | `target` 줄 반응 0 | NEVER | NEVER | `target` NEVER, `"@"` nil | nil | | | 0 | `"@"` NEVER |
| 6 | 대상 `unitframe`, `"@"` [있음], `unitframe` [없음] | NEVER | NEVER | `"@"`, `unitframe` NEVER | NEVER | | | 0 | |
| 7 | 대상 `unitframe`, `unitframe` 반응 0 | NEVER | NEVER | `unitframe` NEVER | nil | | | 0 | |
| 8 | `tank` [있음], 혼자일 때만 | NEVER | NEVER | `tank` NEVER, `target` nil | nil | NEVER | | 0 | |
| 9 | 대상 `tank`, `"@"` [있음], 혼자일 때만 | NEVER | NEVER | `"@"` NEVER | NEVER | NEVER | | 0 | Target nil |
| 10 | Hover Cast Skip, `unitframe` [적대] (S5 #9) | nil | nil | nil | nil | | nil | 2 (focus, self) | |
| 11 | BUTTON3, `"@"` [우호], `unitframe` [적대] | nil | nil | nil | nil | | | 1 (원본) | KeyMap 2 |
| 12 | BUTTON1, `"@"` [우호], `unitframe` [적대] | NEVER | NEVER | `"@"`, `unitframe` NEVER | nil | | nil | 0 | nil, KeyMap 1 |
| 13 | `"@"` [우호], `player` [적대] | nil | nil | nil | nil | | | 3 (hover, focus, 원본) | KeyMap 4 |
| 14 | `"@"` [우호], `target`·`player`·`focus`·`unitframe` 전부 [적대] | NEVER | NEVER | 다섯 줄 전부 NEVER | nil | | | 0 | `player`, `focus`, `unitframe` nil |
| 15 | `"@"` [없음] | nil | nil | nil | nil | | | 3 (focus, self, 원본) | KeyMap 4 |
| 16 | BUTTON3, 대상 `unitframe`, `"@"` [있음] (마우스 버튼 키 규칙) | nil | nil | nil | nil | | | 1 (hover) | NEVER, KeyMap 0 |
| 17 | 넷 다 끔 | NONE_LEFT | nil | nil | nil | | NONE_LEFT | 0 | |
| 18 | 17에 `"@"` 반응 0 | NEVER | NEVER | `"@"` NEVER | nil | | NONE_LEFT | 0 | |
| 19 | Hover Cast Skip, 설정 탭 두 조합키 끔, `unitframe` [적대] | NONE_LEFT | nil | nil | nil | | NONE_LEFT | 0 | |
| 20 | BUTTON1, Hover Cast Skip (S5 #47) | BARE_CLICK_SKIPPED | nil | nil | nil | | BARE_CLICK_SKIPPED | 0 | |
| 21 | Normal Cast 끔, `"@"` [우호], `target` [적대] | nil | nil | nil | nil | | nil | 3 | NEVER, KeyMap 0 |
| 22 | `focus` 소속 0, `target` [있음] | UNITGROUPS | UNITGROUPS | `focus` UNITGROUPS, `target` nil | nil | | | 0 | |
| 23 | `unitframe` 역할 0 | NEVER | NEVER | `unitframe` NEVER | nil | | | 0 | |
| 24 | `unitframe` 역할 탱커, 혼자일 때만 | NEVER | NEVER | `unitframe` NEVER, `"@"`·`target` nil | nil | NEVER | | 0 | `"@"`, `target` NEVER |
| 25 | `target` 줄 값을 못 읽음(`unitStatesOpaque`) | nil | nil | nil | nil | | | 4 | |
| 26 | `target` 줄 역할 0 (`unitframe` 자리가 아님) | nil | nil | nil | nil | | | 4 | |
| 27 | `"@"` [없음], `target`·`player`·`focus` [있음] | NEVER | NEVER | `"@"`, `target`, `player`, `focus` NEVER, `unitframe` nil | nil | | | 0 | Target NEVER, `player`·`focus` nil |

27에서 hover 쌍둥이의 `unitframe` 0은 `"@"`와 쌍둥이 자신의 [있음]이 만든 것이라 `"@"` 줄은 칠하고
`unitframe` 줄은 안 칠한다. 18은 두 코드를 `GetBindingIssues`가 다 낸다. 19는 원본이 Skip과 조건이 안 만나 `normalCast == false`로
빠지고 쌍둥이가 없어 목록이 비므로 지금처럼 `CASTING_NONE_LEFT`다(`hovertwin_spec`의 "쌍둥이가 설
자리가 없는 액션도 같은 경고를 받는다"와 같은 규칙). 12는 수식키 없는 왼클릭이라 원본이 없고 hover
쌍둥이만 있는데 그것이 못 서므로 ERROR다. 스펙 #47과 달리 사용자가 건 조건끼리 어긋난 것이라
WARNING이 아니다.

## 5. 기존 테스트와의 대조

지금 헤드리스가 쥔 답을 정답표와 맞댔다. **갈리는 줄은 없다.** 바뀌는 답은 전부 §4의 "지금" 열에 있고,
그 어느 것도 지금 테스트가 단언하는 값이 아니다.

| 파일 | 지금 쥔 답 | 정답표 |
|---|---|---|
| `issue_spec.lua` | `issueFor`(대상 `target`, `"@"`와 `target` 줄): 모순 여섯 NEVER, 포섭·같은 값 nil. `hoverAction`(대상 `unitframe`, 옛 `hover`/`reactions`) 넷. `hoverTargetConflict` 넷(액션, `units`, `unit`, `"@"`). `targetUnitConflict` 셋. 빈 반응·빈 소속으로 Target 안 칠함. 빈 소속의 짚어 묻기 셋. `"@"`가 못 풀릴 때 nil 둘. 혼자 규칙 넷. 나머지 갈래는 유닛 무관 | 같다. 대상을 고른 액션은 바인딩 넷이 다 그 유닛에 묻고 다 죽는다(#4, #6). 빈 반응·빈 소속은 액션 이슈(#7, #22) |
| `hovertwin_spec.lua` | 반만 덮인 액션 nil, Skip과 조건이 안 만나면 nil(#10), 넷 다 끔 NONE_LEFT(#17), 쌍둥이 자리 없음 NONE_LEFT, 하나 남으면 nil | 같다 |
| `role_spec.lua` | 역할 0 NEVER와 `units`(#23), 전부 켬 nil, 탱커+혼자 NEVER(#24), `unknown`+혼자 nil, 파티 허용 nil | 같다 |
| `keymap_spec.lua` | 미정의 스위치 UNDEFINED_STATE, BUTTON1 개체창 전용 nil, Mouseover BUTTON1 nil. 레코드 수를 재는 케이스 아홉 | 같다. 그 아홉에 죽는 쌍둥이가 든 키는 없다 |
| `eval_spec.lua` | #9 nil, #41 NONE_LEFT, #44·#46 nil, #47 BARE_CLICK_SKIPPED | 같다 |
| `display_spec.lua` | `focus` 반응 0이 `player` 생사 줄을 안 칠함, 넷 다 끔이 주황, BUTTON1 Skip이 제 문구 | 같다(#7의 짚어 묻기) |
| `grade_spec.lua` | 등급표 | 코드도 등급도 안 는다 |
| `loopoff_spec.lua`, `specid_spec.lua`, `switch_spec.lua`, `import_spec.lua` | `key`, `specs`, `states` 갈래 | 액션 갈래 그대로 |
| `record_spec.lua`, `solver_spec.lua`(898, 1007), `normalize_spec.lua`(676) | 단언은 무관. 주석이 "`GetBindingIssue`가 0을 잡아 `KeyMap`에서 뺀다"고 적음 | 주석을 §2-3대로 고친다 |
| `emit_spec.lua` | 골든 | 죽는 쌍둥이는 지금도 `MergeKeyUnitConditions`가 방출 직전에 떨어뜨리므로 바이트가 안 움직여야 한다. 움직이면 그 diff가 픽스처에 든 죽은 바인딩을 말하는 것이니 읽고 판단한다 |

## 6. 비용

이슈 검사는 목록을 그릴 때 행마다 불린다. 지금 한 행에 `FillBinding`이 도는 횟수와 뒤의 횟수.

| 부르는 자리 | 지금 | 뒤 |
|---|---|---|
| `DebindLineMixin:Update`: `GetBindingIssue(action)` | 1 | 0, 또는 목록 길이(최대 4, 탐침 타입 8) |
| 같은 자리: `GetBindingIssue(action, "key")` | 1 (`key` 갈래도 바인딩을 만들고 안 읽는다) | 0 |
| `MakeRow` | 1 | 0, 또는 목록 길이 |
| 툴팁 `hasIssues` | 1 | 0, 또는 목록 길이 |

바인딩 갈래는 `action.conditions.units`도 `action.casting`도 없으면 안 돈다. 그 둘이 없으면 목록은 비지
않고 어느 바인딩도 `dead`가 아니다. 혼자 규칙과 마우스 버튼 규칙과 Skip이 0을 만들려면 유닛 줄이나
`casting`이 있어야 한다. 그래서 유닛 조건이 없는 행(대부분)은 0회가 되어 지금(2회)보다 싸고, 유닛 조건이
있는 행은 2회에서 최대 4회(탐침 타입 8회)가 된다. `FillBinding`은 표를 재사용하고 할당이 없다. 새로
드는 것은 `unitSources` 표 하나로, 바인딩마다 한 번 만들고 `wipe`한다.

## 7. 커버리지

헤드리스가 재는 것: §4의 표 전부. 액션 전체와 갈래마다의 코드, 짚어 물은 줄, 루트 Target, `KeyMap`의
레코드 수, `IsUnreachableAction`이 `dead`를 안 세는 것, `GetBindingIssues`가 두 코드를 다 내는 것.

못 재는 것: 메뉴 줄과 툴팁 줄이 그 코드를 어느 색으로 그리나. 색은 등급이 정하고(`grade_spec`), 어느
줄이 어느 갈래를 묻는지는 한 번 보면 끝나는 배선이라 재지 않는다.

## 8. 구현 순서

1. **테스트부터.** §4의 표를 `tests/issue_spec.lua`(코드와 칠할 줄)와 `tests/keymap_spec.lua`(레코드 수,
   `IsUnreachableAction`)에 세운다. 돌려서 빨간 줄이 §4의 "지금" 열과 **정확히** 일치하는지 본다. 더
   빨갛거나 덜 빨가면 표나 테스트가 틀린 것이다.
2. `FillBinding`: `UNIT_IS_THERE` 선언을 위로, `twinOwnUnit`, `unitSources`, `dead`. `UnrollIntoTiers`가
   `dead`를 건너뛰고 `IsUnreachableAction`이 `dead`를 안 센다. `KeyMap` 줄이 초록이 되고 이슈 줄은
   아직 빨갛다.
3. `EvaluateIssues`를 §2-5로 다시 쓴다. 전부 초록.
4. §2-3의 주석 여섯 자리를 고친다. `Constants.lua`의 `BINDING_ISSUE_UNITGROUPS_NONE_SELECTED` 주석은
   "위 순회가 찾는다"가 아니라 저장된 줄을 읽는다고 적는다.
5. `npm run check`. 골든이 움직이면 §5의 `emit_spec` 줄대로 읽는다.
6. 이 문서를 `legacy/`로 옮긴다.
