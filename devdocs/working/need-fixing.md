# 고칠 것

> 상태: 미착수. 항목 1~5.
>
> 쓴 세션: `debind-45` (세션 ID `69a358ab-115a-49d9-9681-65106e3c7003`). 항목 4와 5를 쓴 세션: `debind-76` (세션 ID
> `44a4417a-2abe-44e5-b0f9-4cbfb7431e9e`).

다른 일을 하다 찾은 결함이다. 그 일의 범위가 아니라 여기 따로 둔다.

## 1. 유닛 조건을 접는 두 곳이 role과 frameTypes에서 갈린다

찾은 곳: ee05ce9의 리뷰(2026-10-08). 키 돌려주기 3-1절 작업 중이었다(`giving-keys-back-when-no-action-runs.md`).

### 무엇이 갈리나

유닛 조건은 두 곳에서 접힌다. 솔버 쪽은 `Units.lua`의 `BuildUnitStates`이고, 방출 쪽은 `UpdateBindings.lua`의
`mergeUnitConditions`다.

- `BuildUnitStates`는 role과 frameTypes를 `unitframe` 행에서만 읽는다(`narrowRole`, `narrowFrameTypes`).
  다른 유닛 행의 두 값은 무시한다.
- `mergeUnitConditions`는 유닛을 가리지 않는다. 같은 유닛에 떨어진 두 행의 frameTypes가 겹치지 않으면 `NEVER`를
  낸다. role도 겹치지 않으면 `NEVER`다. 다만 두 행 다 role을 하나 이상 골랐을 때만이다.
- group은 두 쪽 다 모든 유닛에서 읽으므로 갈리지 않는다.

### 재현 조건

- 한 액션의 유닛 조건 두 행이 `unitframe`이 아닌 같은 유닛에 떨어진다. 보기는 대상 없는 액션의 `"@"`(target으로
  풀린다)와 `target` 행이다.
- 두 행의 role이 겹치지 않는다. 보기는 `"@"`에 TANK, `target`에 HEALER다. frameTypes가 겹치지 않아도 같다.
- `"@"` 행의 role과 frameTypes는 메뉴로 넣을 수 있다. `"@"` 하위 메뉴는 액션이 무엇을 겨누든 그 둘을 내준다
  (`ActionMenuNodes.lua`의 `pointedFrame`). `target` 행에는 메뉴가 그 둘을 안 내준다. 그래서 두 행이 다 갖는 모양은
  손으로 고친 프로필이나, 그런 값을 담은 가져오기 문자열로만 들어온다.

### 무슨 일이 일어나나

- 솔버는 바인딩을 살려 둔다. `dead`도 아니고 opaque도 아니다. 그래서 이슈도 없다.
- 방출은 그 바인딩을 버린다. 접으면 `NEVER`이니 `PrepareKeyBindings`가 빼고 레코드가 안 나간다.
- 솔버는 이 바인딩을 덮개로 쓴다. 이 바인딩의 상자(target이 있는 상태)에 완전히 덮이는 아래 바인딩은 솔버가 지운다.
  그러면 둘 다 안 나가고, 그 상태의 누름에서 아무 액션도 안 돈다.
- 아래 바인딩이 완전히 덮이지 않으면 그것은 나가고, 누름에서 그것이 돈다. 위 바인딩은 레코드가 없다.
- 키에 다른 레코드가 없으면 키는 옵션(`giveBackWhenNoActionRuns`)대로 처리된다.
- 창은 위 액션에 아무것도 표시하지 않는다. 완전히 덮인 아래 액션의 행에는 "Never runs"(`BINDING_ERROR_UNREACHABLE`)가
  붙는다. 그 원인으로 읽히는 위 액션은 실제로 나가지 않는다.

누름에서 아무 액션도 안 도는 것은 3-1절 작업 전(6bbe915)에도 같았다. 그때는 `BuildKeyRecord`가 nil을 내고 레코드를
건너뛰었다. 키를 쥐는 쪽은 달랐다. 그때는 키를 끝 레코드만으로 묶어 우리 것으로 읽었고, 개체창 전용 마우스 버튼은 빈
목록을 등록했다(a31ab92 메시지).

### 같이 고칠 주석

`mergeUnitConditions` 위의 `NEVER IS UNREACHABLE` 주석은 `NEVER`로 가는 길을 셋만 적는다. 모두
`binding.unitStates`의 0 마스크다. 실제로는 role, frameTypes, group의 셋이 더 있다. 이 셋은 솔버의 다른 칸
(`unitRole`, `unitFrameTypes`, `unitGroups`)에 들어간다. 그리고 `unitframe` 밖의 role과 frameTypes는 그 칸에도
안 들어가서, "닿지 않는다"는 말이 그 경우에 틀렸다.

`EmitRecord`의 role 주석("The menu cannot make that shape")도 틀렸다. 위에 적은 대로 `"@"` 행에는 메뉴가 role을
넣는다.

### 고치는 길 (정하지 않았다)

- **접기에서 `unitframe` 밖의 role과 frameTypes를 무시한다.** 방출은 이미 role을 `unitframe`에만 내보낸다
  (`EmitRecord`). 그러니 접기도 같은 규칙을 따르면 세 곳이 맞는다. 대가는 손으로 넣은 그 값이 조용히 무시되는 것이다.
- **솔버가 모든 유닛에서 두 값을 읽는다.** 그러면 바인딩이 `dead`가 되고 이슈가 뜬다. 대가는 런타임이 재지 않는
  값(target의 role)을 솔버가 조건으로 다루는 것이다. 역할은 파티·공격대 개체창에서만 잰다.
- **읽을 때 그 값을 지운다.** ESC를 `CleanUpDB`와 `BringPayloadDataForward`에서 지우는 것과 같은 꼴이다. 데이터에서
  갈림의 원인이 사라진다. 대가는 저장 데이터를 고치는 길이 하나 더 생기는 것이다.

어느 쪽이든 고치기 전에 시험을 먼저 세운다. `loopoff_spec`의 "makes no record" 두 경우가 이 갈림을
`ResolvedUnitOf`를 바꿔서 흉내 낸다. 진짜 갈림(role 두 행)으로 같은 결과를 내는 경우를 세우면 고친 뒤의 기대를
거기에 걸 수 있다.

## 2. 키트의 `BindingIndexForEmitted`가 실제 방출과 다르게 센다

찾은 곳: f9af1bf의 리뷰(2026-10-08). 키 돌려주기 3-1절 작업 중이었다.

### 무엇이 다르나

`DebindTest.lua`의 `BindingIndexForEmitted`는 내보낸 레코드 번호를 `KeyMap`의 바인딩 번호로 되돌린다.
`BindingIndexForRecord`를 거쳐 `probeReports`가 이것을 쓴다. 그런데 방출과 두 가지가 다르다.

- self 블록과 focus 블록이 늘 있다고 본다. `WithBlocks`는 `SelfCastEnabled()`·`FocusCastEnabled()`가 참일 때만 그
  블록을 넣는다. 테스터가 설정에서 Self Cast Key나 Focus Cast Key를 끄면(`options.selfCast == false`,
  `options.focusCast == false`) 그 블록이 없다.
- `KeyMap`의 바인딩을 다 센다. `PrepareKeyBindings`가 버린 바인딩은 레코드가 안 나가는데도 센다.

### 무슨 일이 일어나나

그런 키에서 프로브 보고가 이긴 레코드를 엉뚱한 바인딩이나 블록으로 적는다. 키의 동작에는 영향이 없다.

이 함수 위의 주석("Every key bound to us gets the blocks")도 self·focus 블록에 대해서는 틀렸다.

### 고치는 길

같은 셈을 키트에 한 벌 더 두면 방출과 또 갈린다. 방출하는 쪽(`UpdateBindingsMap`)이 키마다 몇 번째 레코드가 어느
바인딩이나 블록이었는지를 DEBUG에서만 남기고, 이 함수가 그것을 읽게 한다.

## 3. "Replaced Action Bar" 조건이 애완동물 대전까지 덮는다

찾은 곳: 344519d 뒤의 빈 에이전트 검토(2026-10-08). 키 돌려주기 G6에서 설정 값 이름을 정하던 중이었다.

### 무엇이 다르나

- 조건 `specialbar`("Replaced Action Bar", `CONDITION_SPECIALBAR`)는 `[vehicleui][possessbar][overridebar][shapeshift]`에
  `[petbattle]`까지 읽는다(`UpdateBindings.lua`의 `specialbar` 갈래).
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

## 4. 키트의 Tail 시험 넷이 "beat가 옮겼다"를 리빌드와 가르지 못한다

찾은 곳: 2611118의 리뷰(2026-10-08). 키 돌려주기 G6의 키트를 고치던 중이었다.

### 무엇이 빠졌나

`DebindTest.lua`의 Tail 시험들은 `MockBody`나 유닛 별칭으로 값을 옮긴 뒤 `WaitUntil`로 2초까지 키가 바뀌기를
기다린다. 그 사이에 리빌드가 돌면 리빌드가 키를 스스로 판정해 건다. 그러면 beat가 고장 나 있어도 시험이 통과한다.

리뷰가 짚은 두 시험("Tail: the beat takes the key and hands it back to the command", "Key given back: a lone
conditional action lets its key go and takes it back")은 `WaitOnBeat`로 고쳤다. 리빌드 횟수를 세어, 기다리는 동안
리빌드가 돌았으면 실패로 낸다. 남은 것은 같은 꼴의 넷이다.

- "Tail: the watch follows two state words one after the other"
- "Tail: the units' watch follows a token and a life"
- "Tail: the form moves the key by the call"
- "Tail: flyable in combat waits behind nocombat"

### 재현 조건

beat가 판정 아이템을 안 도는 회귀가 있고, 시험이 기다리는 2초 안에 다른 이벤트가 `QueueUpdateBindings`를 부른다.
그 리빌드가 바뀐 값으로 키를 걸어 기다림이 풀린다.

### 고치는 길

그 넷의 `WaitUntil`을 `WaitOnBeat`로 바꾼다. 조용한 beat를 세는 `WaitTicks` 자리는 키가 안 움직이는 것을 보므로 그대로
둔다.

## 5. 조건끼리 모든 상태를 덮는 키도 beat에 오른다

찾은 곳: 키 돌려주기 3-1절 작업(2026-10-08, `giving-keys-back-when-no-action-runs.md` 3-1절 끝에서 옮겨 왔다).

### 무엇이 낭비인가

`giveBackWhenNoActionRuns`가 켜져 있으면 키를 쥐는 키마다 끝에 `GIVEBACK_END`가 붙는다. `UpdateBindingsMap`은
"우리 것"밖에 답할 수 없는 키에 판정 아이템을 안 만든다. 그 판별이 둘이다.

- 키의 레코드를 순서대로 보다가 제약 없는 "우리 것"을 다른 결과보다 먼저 만나면 아이템을 안 만든다(`answersOther`).
- 만든 아이템도 `Judgment.IsAlwaysOurs`가 참이면 버린다. 이 함수는 항목이 0개일 때만 참이다.

조건이 있는 액션 여럿이 합쳐서 모든 상태를 덮는 키는 둘 다 지나간다. 레코드마다 제약이 있고, 아이템에 항목이
남는다. 그래서 아이템이 생기고 beat에 오른다. 답은 어느 상태에서나 "우리 것"이라 키는 한 번도 안 놓인다. 동작은
맞고, beat의 일만 는다.

### 재현 조건

키 `X`에 `[combat]` 액션 하나와 `[nocombat]` 액션 하나만 있다. `giveBackWhenNoActionRuns`는 켜져 있다(기본).
`DebindPrivate.JudgmentItems["X"]`가 있고, 다른 조건부 키나 꼬리가 없는 프로필에서도 beat가 선다.

### 얼마나 드나

조용한 beat는 키 수와 상관없이 약 9.4µs다. 이런 키만 있는 프로필은 beat가 아예 없어도 될 것을 세운다. 전투가
바뀔 때마다 이 키도 판정하지만 바인딩은 안 바뀐다(`giving-keys-back-when-no-action-runs.md` G5).

### 고치는 길 (정하지 않았다)

- **아이템을 만들 때 앞의 "우리 것" 항목들이 모든 점을 덮는지 본다.** 덮으면 아이템을 안 만든다. 주의할 것: 판정
  아이템의 제약은 솔버의 바인딩 열과 일대일이 아니다. 그래서 솔버의 덮임 판정을 그대로 가져다 쓰면, 놓아야 할 키를
  쥘 수 있다. 판정 아이템의 열로 따로 세어야 한다.
- **그대로 둔다.** 동작은 맞고, 비용은 위의 값이다.

할지는 소유자가 정하지 않았다.
