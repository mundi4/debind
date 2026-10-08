# 고칠 것

> 상태: 미착수. 항목 3과 7. 1(유닛 조건 fold가 갈림)과 2(키트가 방출의 레코드 배치를 따로 베껴 세다 갈림)는
> 2026-10-08에 고쳐서 여기서 뺐다. 둘 다 같은 규칙을 두 곳 이상에 따로 적어 둔 것이 원인이었다. 4(키트의 Tail 시험
> 넷이 beat와 리빌드를 못 가름)도 같은 날 넷 다 `WaitOnBeat`로 바꿔서 뺐다. 6(`macrotext_spec`이 `EmitMacroTextArg`를
> 베껴 잼)도 같은 날 `BuildMacroTextEntries`가 내는 글을 직접 재게 바꾸고 `bakeFixed`를 지워서 뺐다. 이것도 같은 규칙을
> 두 곳에 적어 둔 것이었다. 5(조건끼리 모든 상태를 덮는 키도 beat에 오름)도 같은 날 고쳐서 뺐다. 그대로 두는 길은
> 소유자가 받지 않았다. `IsAlwaysOurs`가 앞선 "우리 것" 항목들을 합쳐서, 판정 아이템 자신의 열로 묻는다.
>
> 쓴 세션: `debind-45` (세션 ID `69a358ab-115a-49d9-9681-65106e3c7003`). 항목 7을 쓴 세션: `debind-a1` (세션 ID
> `de09907b-7408-4ae2-ac15-00b166056b03`).

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

## 7. 수동 스위치의 `[$x]`와 `[no$x]`로 모든 상태를 덮는 키도 beat에 오른다

찾은 곳: 5를 고친 변경의 두 번째 리뷰(2026-10-08).

### 무엇이 낭비인가

판정 아이템의 스위치 열은 칸이 셋이다. 켜짐, 꺼짐, 그리고 아무도 값을 쓰지 않은 칸(`JUDGMENT_SWITCH_UNSET`)이다.
`[$x]` 액션과 `[no$x]` 액션만 있는 키는 셋째 칸을 덮지 못한다. 그래서 `IsAlwaysOurs`가 거짓이고, 아이템이 남아 beat에
오른다.

수동 스위치는 그 칸에 닿지 않는 것으로 읽힌다. 리빌드는 계산식이 아닌 스위치마다 `SetSwitch`로 값을 넣는다
(`BuildSwitchesSnippet`). 그 값은 `GetSwitchValue`에서 오고, 이 함수는 nil을 내지 않는다(`or false`). 여기까지는 코드를
읽은 것이다. 다른 경로로 `States`의 그 이름이 비는 때가 있는지는 재지 않았다.

### 재현 조건

수동 스위치 `$x`를 정의하고, 키 `X`에 `[$x]` 액션과 `[no$x]` 액션만 둔다. `giveBackWhenNoActionRuns`는 켜져 있다(기본).
`DebindPrivate.JudgmentItems["X"]`가 있다.

### 고치는 길 (정하지 않았다)

- **수동 스위치의 열을 켜짐과 꺼짐 두 칸으로 만든다.** `States`의 그 이름이 nil일 수 없다는 것을 먼저 확인해야 한다.
  nil일 수 있는데 칸을 빼면, 그 상태에서 놓아야 할 키를 쥔다.
- **그대로 둔다.** 동작은 맞고, 그런 키가 있는 프로필에 beat가 선다.
