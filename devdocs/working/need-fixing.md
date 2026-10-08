# 고칠 것

> 상태: 미착수. 항목 3, 8, 9. 1(유닛 조건 fold가 갈림)과 2(키트가 방출의 레코드 배치를 따로 베껴 세다 갈림)는
> 2026-10-08에 고쳐서 여기서 뺐다. 둘 다 같은 규칙을 두 곳 이상에 따로 적어 둔 것이 원인이었다. 4(키트의 Tail 시험
> 넷이 beat와 리빌드를 못 가름)도 같은 날 넷 다 `WaitOnBeat`로 바꿔서 뺐다. 6(`macrotext_spec`이 `EmitMacroTextArg`를
> 베껴 잼)도 같은 날 `BuildMacroTextEntries`가 내는 글을 직접 재게 바꾸고 `bakeFixed`를 지워서 뺐다. 이것도 같은 규칙을
> 두 곳에 적어 둔 것이었다. 5(조건끼리 모든 상태를 덮는 키도 beat에 오름)도 같은 날 고쳐서 뺐다. 그대로 두는 길은
> 소유자가 받지 않았다. `IsAlwaysOurs`가 앞선 "우리 것" 항목들을 합쳐서, 판정 아이템 자신의 열로 묻는다. 7(수동
> 스위치의 `[$x]`·`[no$x]` 키도 beat에 오름)도 같은 날 고쳐서 뺐다. 정의된 스위치는 수동이든 계산식이든 읽는 곳에서
> 늘 켜짐 아니면 꺼짐이라, 그 열은 이제 두 칸이다. "설정 안 됨" 칸은 정의 없는 이름에만 남는다.
>
> 쓴 세션: `debind-45` (세션 ID `69a358ab-115a-49d9-9681-65106e3c7003`). 8과 9는 `debind-3e`
> (세션 ID `9c6ce919-05ff-4e0d-aa1f-839f97dff70f`).

다른 일을 하다 찾은 결함이다. 그 일의 범위가 아니라 여기 따로 둔다.

## 3. "Replaced Action Bar" 조건이 애완동물 대전까지 덮는다

찾은 곳: 344519d 뒤의 빈 에이전트 검토(2026-10-08). 키 돌려주기 G6에서 설정 값 이름을 정하던 중이었다.

### 무엇이 다르나

- 조건 `specialbar`("Replaced Action Bar", `CONDITION_SPECIALBAR`)는 `[vehicleui][possessbar][overridebar][shapeshift]`에
  `[petbattle]`까지 읽는다(`ConditionText.lua`의 `specialbar` 갈래).
- 애완동물 대전에는 조건이 따로 있다(`petbattle`). 그래서 대전은 두 조건에 겹쳐 들어간다. 그 겹침 때문에 이슈 검사가
  두 조건의 모순을 따로 본다(`Issues.lua`의 `SpecialBarAgainstPetBattle`). `FillBinding`도 둘 다 켠 액션에서
  `specialbar`를 지운다.
- 설정의 Keys Given Back은 같은 이름 "Replaced Action Bar"를 대전 없이 쓴다(`giveBackOnReplacedBar`). 대전은 옆 값
  "Pet Battles"다. 소유자가 이름을 하나로 정했고(2026-10-08), 이름을 바꿔서는 이 차이가 안 풀린다.
- 조건의 설명(`CONDITION_SPECIALBAR_DESC`)은 "a vehicle, a possession, and the like"라고만 하고 대전을 말하지 않는다.

### 고치는 길

`specialbar`가 대전을 안 덮게 나눈다. 대전은 `petbattle` 조건이 맡는다. 설정 쪽을 합치는 길은 없다. 두 값은 기본값이
달라서(바뀐 단축바 끔, 대전 켬) 하나로 합치면 지금 기본값인 "대전만"을 잃는다.

마이그레이션에서 갈리는 것:

- `specialbar`를 끈 액션(바뀌지 않았을 때)은 정확히 옮겨진다. `specialbar = false`, `petbattle = false`다.
- `specialbar`를 켠 액션은 한 액션으로 못 옮긴다. 조건은 AND라서 `petbattle`을 같이 켜면 둘이 동시에 참일 때만 돈다.
  길은 둘이다. 액션을 둘로 나눠 하나는 `specialbar`, 하나는 `petbattle`로 두면 동작이 그대로이고, 대신 사용자에게 행이
  하나 늘어 보인다. 나누지 않으면 그 액션은 대전에서 안 돈다. 대전에서는 기본으로 행동 단축키가 게임에 돌아가니(Pet
  Battles 켬) 영향받는 액션이 적을 것으로 보지만, 잰 것은 아니다.
- 같이 고칠 곳: `SpecialBarAgainstPetBattle`, `FillBinding`의 겹침 처리, beat의 `specialbar` 갈래(`watchSpecialbar`,
  대전을 미는 `SetPetBattle`), 조건 툴팁, 도움말.

### 같이 정할 것

설정의 "Action Button keys" 기본값. 지금은 "Pet Battles"(바뀐 단축바 끔)다. 끈 근거는 `ActionBindings.lua`의 주석이다.
바뀐 단축바는 대개 전투 중이라, 그때 키가 다른 일을 하는 것이 곧 손해다. 켤 근거는 "Filled buttons only"를 없앤 근거와
같다(`giving-keys-back-when-no-action-runs.md` 1절). 끄면 차량 기술을 그 키로 못 누른다. 소유자가 생각해 보기로
했다(2026-10-08).

## 8. 마스크 조건의 범위 밖 비트를 누름과 loop가 다르게 읽는다

찾은 곳: 2125916의 `/code-review high`(2026-10-08). 지적은 `bartakeover`였는데, 같은 모양이 다른 마스크에도 있다.

### 무엇이 다르나

마스크 조건에 그 축이 쓰는 비트 밖의 비트만 있으면(예: `groups = 8`, `bonusbars = 64`, `bartakeover = 8`), 누름과
판정 loop가 서로 다른 답을 낸다.

| 필드 | 누름 (`ConditionText.lua`의 `StateAlternatives`) | loop (`Judgment.lua`의 `constrain`) |
|---|---|---|
| `groups` | 세 비트가 다 없으면 맨 끝 갈래로 가서 `[group:raid]` | `band(8, 7) = 0`, 절대 안 맞음 |
| `bonusbars` | 대안이 빈 `{}`라 제한 없음 | 절대 안 맞음 |
| `bartakeover` | 대안이 빈 `{}`라 제한 없음 | 절대 안 맞음 |
| `forms` | 누름도 `GetShapeshiftForm()`의 비트를 대조하니 절대 안 맞음 | 절대 안 맞음. 갈리지 않는다 |

거르는 곳도 없다. 이슈 검사는 `== 0`만 보고(`Issues.lua`), `FillBinding`은 전체 비트가 다 켜졌을 때만 전체값으로 접는다.
메뉴로는 이런 값이 안 생긴다. 손으로 고친 SavedVariables나 붙여넣은 문자열에서만 온다. 붙여넣기는
`CONDITION_TYPES`가 타입(`"number"`)만 본다.

### 고치는 길

애드온이 안 쓰는 값이니 `INVALID_ACTION`이 맞아 보인다(손으로 만든 데이터는 고쳐 주지 않는다는 결정, 2026-10-08). 걸리는
것이 하나 있다. `normalize_spec`의 "범위를 넘는 마스크는 정규 전체값으로 잘린다"가 `ALL * 2 + 1`을 전체값으로 접는 것을
고정한다. 그 테스트는 위 결정보다 먼저 생겼다. 접기를 남길지, 범위 밖 비트가 하나라도 있으면 `INVALID_ACTION`으로 볼지를
정해야 한다.

## 9. 사다리 단계가 지금 판의 표를 읽는다

찾은 곳: 같은 리뷰. `dbver <= 5` 단계가 무엇이 조건인지를 지금의 `Constants.IsConditionField`에 물었다. 그래서 그 표에서
빠진 `pet`, `frameTypes`, `specialbar`, `petbattle`이 5판 이하 프로필에서 옮겨지지 않고 `CleanUpDB`에 지워졌다. 그 단계는
5판의 이름을 직접 들게 고쳤다. 같은 모양이 다른 단계에 남아 있다.

- `dbver <= 1`: `Constants.BASIC_UNITS`, `Constants.SPECIAL_UNITS` (`Migration.lua`의 `checkUnitExists`·`checkedUnit` 옮기기)
- `Constants.SPEC_RESOLVED_TYPES`를 읽는 단계
- `MigrateSwitches`의 `Constants.IsSwitchName`

이 표들이 바뀌면 옛 프로필의 값이 조용히 다르게 옮겨진다. 각 단계가 자기 판의 값을 직접 들게 할지, 그 표가 그 판 이후로
안 바뀌었다는 것만 확인하고 둘지를 단계마다 정해야 한다.
