# 꼬리 키 박자 줄이기 (2026-10-05 계획)

> 상태: 계획. 소유자와 논의 중이고 코드는 아직 없다. 각 항목에 정한 것(소유자)과 제안(아직 안 정함)을 따로
> 적었다. `handing-the-rest-of-a-key-to-the-game.md` 2-5 끝의 "계산식 스위치를 언제 구하나"와 3절을 이어받는다.
>
> 쓴 세션: `debind-ac` (세션 ID `1361cd24-6aad-48a3-9a06-643d7caa65ad`). 루프를 구현한 세션은 `debind-67`
> (세션 ID `22d40970-4ea2-4333-bb00-f9e7c2f1175a`).

## 1. 왜

꼬리를 든 키가 하나라도 있으면 루프가 박자(~0.2초)마다 돈다. 소유자의 요구는 이 패스를 끝까지 줄이는 것이고,
`handing-the-rest-of-a-key-to-the-game.md`는 3절 전체를 최적화에 쓴다. 이 문서는 그 3절과 2-5의 계산식 스위치
결정을 실제 본문 모양까지 내린다.

## 2. 지금 박자가 하는 일 (커밋 1208119, 코드로 확인)

1. `BuildJudgeSnippet`(`UpdateBindings.lua`)이 생성한 앞 절반이 손으로 켜는 스위치를 뺀 모든 컬럼을 잰다.
   - 계산식 스위치: 아이템이 읽는 것과 그것이 읽는 것을 매번 `SecureCmdOptionParse`로 구한다.
   - `known`: 매번 `SecureCmdOptionParse`, 거짓이고 `knownID`가 있으면 `FindSpellBookSlotBySpellID`도.
   - `unit`: `UnitExists`, `UnitIsDead`/`UnitIsGhost`, `PlayerCanAssist`/`PlayerCanAttack`. `unitgroup`이 있으면
     `UnitPlayerOrPetInRaid`/`UnitPlayerOrPetInParty`도.
   - `role`·`frameType`이나 `unitframe` 유닛이 있으면 `READ_UNITFRAME_SNIPPET`.
   - `petbattle`과 `specialbar`의 보충은 `[petbattle]`을 파싱한다(`STATE_EVAL_EXPRESSIONS`).
   - `judge-<이름>` 깨움은 그 이름의 컬럼만 잰다.
2. 뒤 절반 `JUDGE_BUNDLES_SNIPPET`(`SecureBindings.lua`)은 고정 본문이다. `moved`일 때만 돌고, 돌 때는
   `JudgeBundles` 전부의 `stamp`를 비교한다.
3. `CollectDriverEvents`가 매니저에 거는 이벤트는 각각 그 컬럼이 있을 때만 걸린다. 매니저는 이벤트를 받으면
   `timer = 0`만 하고, 다음 `OnUpdate`에서 **모든 프레임의 모든 드라이버**를 다시 풀고 unit watch를 전부 다시
   돈다(`SecureStateDriver.lua`). 우리 루프만이 아니라 다른 애드온의 드라이버까지 한 번씩 더 돈다.
4. 보안 본문에는 `function`이라는 글자가 어디에도 들어갈 수 없다. 주석과 문자열 안도 마찬가지다
   (`RestrictedExecution.lua`, `BuildRestrictedClosure`). 그래서 본문 안에서 측정을 부를 길은 그 자리에 코드를
   넣는 것과 `RunAttribute`뿐이다.
5. `known` 컬럼으로 남는 것은 `SettleKnown`이 확정하지 못한 것이다. 펫 주문, 덮어쓰기로 바뀌는 주문, 아직 모르는
   주문이 여기 든다. 레벨 업, 새 주문, 특성, 전문화는 리빌드를 부른다.

## 3. 계산식 스위치의 게이트

### 3-1. 그룹마다 따로 본다 (소유자)

계산식 스위치의 식은 대괄호 그룹의 OR이고(`[a][b]`), 그룹 안은 `,`로 이은 AND다. 흔한 것은 그룹 하나짜리이고
`[a][b]`는 드물지만 받아들이는 모양이다. 예전 `CollectSwitchGate`(`pre-drop-game-fallback` 태그)는 그룹을 돌면서도
토큰을 한 목록으로 합쳤고, 옮길 수 없는 토큰이 하나라도 있으면 식 전체를 포기했다.

여기서는 그룹을 따로 담는다. 다시 구해야 하는 때는 아래 둘 중 하나다.

- 옮긴 토큰의 컬럼이나 깨움 가운데 하나가 이번 패스에 바뀌었다.
- 옮길 수 없는 토큰이 든 그룹이 있고, 그 그룹의 옮긴 토큰이 **지금 모두 참**이다.

`[combat,pvpcombat]`이면 `combat`이 거짓인 동안에는 `pvpcombat`이 어떻든 그룹이 맞지 않으므로, 다시 구하는 것은
`combat` 컬럼이 바뀐 박자와 `combat`이 참인 동안뿐이다. 포기의 범위가 식 전체에서 그룹 하나로, 그것도 같은 그룹의
나머지가 참인 동안으로 줄어든다.

리빌드가 그룹과 토큰을 컬럼과 마스크로 옮기고, 본문에는 스위치마다 리터럴로 굽힌 조건 하나만 남는다. 컬럼이
이번 패스에 바뀌었는지는 지금은 본문의 로컬 `moved` 하나뿐이라, 컬럼마다 `c.moved = generation`을 남기는 줄이
측정 쪽(`mark`)에 새로 든다. `[combat,pvpcombat]`이면 아래와 같다. 옮긴 토큰이 여럿인 그룹은 그 확인을 `and`로
잇는다.

```lua
c = JudgeColumns[3]
if (c.moved == generation or (2 % (c.cell + c.cell)) >= c.cell) then
	-- due: stamp the bundles reading this switch
end
```

`ParseMacroText`(`MacroText.lua`)는 갈아 끼울 자리를 뽑는 것이지 그룹을 나누지 않으니 이 일에 맞지 않는다.

**토큰을 컬럼에 옮기는 근거는 두 가지가 다 있어야 한다.**
- 매크로 토큰의 답이 바뀔 때마다 그 컬럼도 바뀐다. 하나라도 빠지면 그 스위치가 마지막 답에 얼어붙는다. 이쪽은
  양쪽 방향이 다 맞아야 한다.
- 우리 컬럼이 토큰을 거짓이라 하면 매크로도 거짓이다. 그룹 하나를 건너뛰는 판단(위 둘째 줄)이 이것에 기댄다.

결국 그 토큰과 컬럼이 같은 것을 잰다는 근거(`handing-the-rest-of-a-key-to-the-game.md` 6절의 4처럼)가 있어야 3-2의
✓ 낱말을 게이트에 쓸 수 있다. 아직 구하지 않은 `$s`는 참으로 본다.

### 3-2. 낱말과 보안 환경 API

목록은 warcraft.wiki.gg의 Macro conditionals, API는 `RestrictedEnvironment.lua`다. ✓는 답을 낼 API가 있다는 뜻이고,
매크로 조건과 같은 것을 재는지는 따로 근거가 있어야 한다.

| 낱말 | 옮기는 곳 | |
|---|---|---|
| `exists` `help` `harm` `dead` | 그 유닛의 `unit` 컬럼 | ✓ |
| `party` `raid` | 그 유닛의 `unitgroup` 컬럼 | ✓ |
| `unithasvehicleui` | `UnitHasVehicleUI` | ✓ 블리자드가 고친 판이라 같은지 따로 봐야 한다 |
| `advflyable` `flyable` `flying` `indoors` `outdoors` `mounted` `stealth` | 같은 이름의 `Is…` | ✓ |
| `swimming` | `IsSubmerged` | ✓ 같이 움직였다(7-1). `IsSwimming`은 물에서 나올 때 어긋난다 |
| `combat` | `PlayerInCombat` | ✓ 같은 것을 잰다(`handing-the-rest-of-a-key-to-the-game.md` 6절의 4) |
| `canexitvehicle` | `CanExitVehicle` | ✓ |
| `channeling` (인자 없음) | `PlayerIsChanneling` | ✓ |
| `channeling:주문` | | ✗ 주문을 읽을 API가 없다 |
| `form` `stance` | `GetShapeshiftForm` | ✓ |
| `group` | `PlayerInGroup` | ✓ |
| `pet` `pet:이름` `pet:계열` | `PlayerPetSummary` (계열과 이름) | ✓ (소유자) |
| `actionbar` `bar` | `GetActionBarPage` | ✓ |
| `bonusbar:n` | `GetBonusBarOffset` | ✓ 인자 없는 `bonusbar`는 오프셋과 다른 것을 묻는다(7-1) |
| `extrabar` `overridebar` `shapeshift` | `Has…ActionBar` | ✓ |
| `mod` `modifier` | `Is…KeyDown`, `IsModifiedClick` | ✓ |
| `spec` | 리빌드 사이에 상수 | 게이트에 걸 것이 없다 |
| `petbattle` | 비보안 쪽이 깨움으로 넣는다 (3-3) | (소유자) |
| `house:editor` | 비보안 쪽이 깨움으로 넣는다 (3-3) | (소유자) |
| `known` `equipped` `worn` `cursor` | | ✗ 전투 중에도 움직인다 |
| `resting` `pvpcombat` `house:inside` `house:plot` `house:neighborhood` | | ✗ API가 없고, 전투 중에 움직이는지 모른다 |
| `button` `btn` | | ? 박자에는 누름이 없다. 루프에서 무엇으로 나오는지 모른다 |
| `possessbar` `vehicleui` | | ? 빙의 중에 둘이 갈린다(`giving-keys-back.md`). 어느 API와 맞는지 모른다 |

`@unit`은 2-5에서 정한 대로 별칭은 `judge-<별칭>`, `@hover`는 `judge-unitframe`, 맨 유닛은 그 유닛의 컬럼에 건다.

### 3-3. 전투 밖에서만 움직이는 것은 비보안 쪽이 넣는다 (소유자)

펫 대전은 전투가 끝나야 시작되고, 집 편집기도 마찬가지다. 그런 값은 보안 쪽이 박자마다 잴 필요가 없다. 비보안
쪽이 이벤트를 받아 `judge-<이름>` 속성에 써 넣으면 우리 깨움이 그 컬럼만 갱신한다.

- `petbattle`: `PET_BATTLE_OPENING_START`·`PET_BATTLE_CLOSE`. 박자에서 `[petbattle]` 파싱이 빠지고,
  `specialbar`의 보충도 받아 둔 값을 읽는다. **값은 이벤트 이름이 정하고, 그 자리에서 상태를 묻지 않는다.**
  `PET_BATTLE_CLOSE`는 두 번 오고 첫 번째에는 클라이언트가 아직 대전 중이라고 답한다. 그때 상태를 읽어 쓰면 대전이
  끝난 뒤에도 참이 남고, 박자가 다시 재지 않으니 다음 대전까지 그대로다.
- 누름은 지금처럼 `STATE_EVAL_EXPRESSIONS.petbattle`을 파싱한다. 그래서 위의 첫 번째 `PET_BATTLE_CLOSE`부터 두
  번째까지는 루프와 누름이 갈린다. 루프는 이미 거짓으로 보고 키를 판정하고, 누름은 아직 참으로 본다.
- `house:editor`: `BindingContexts.lua`가 이미 `HOUSE_EDITOR_MODE_CHANGED`와 `HouseEditor.StateUpdated`를 받아
  `BakeContextKeys`를 부른다. 같은 자리에서 깨움을 쓴다.
- 루프 때문에 매니저에 걸던 `PET_BATTLE_*`는 필요 없어진다. Keys Given Back의 `[petbattle] b` 드라이버는 매니저가
  직접 푸니 그쪽 등록은 그대로다.

### 3-4. 파싱을 컬럼 계산으로 바꾼다 (제안)

모든 토큰을 옮길 수 있는 그룹은 우리 컬럼으로 참과 거짓을 바로 셀 수 있다. 그런 그룹 하나가 지금 참이면 답은
파싱 없이 참이고, 모든 그룹이 그러면 그 스위치는 파싱하지 않는다. 남는 파싱은 옮길 수 없는 토큰이 든 그룹을
실제로 판가름해야 할 때뿐이다.

근거의 조건은 3-1과 같다. 같은 것을 잰다는 근거가 있는 토큰만 쓴다.

### 3-5. 스위치가 다른 스위치를 읽으면 게이트를 합친다 (제안)

`$c`가 `$s1`을 읽으면 `$c`의 게이트는 `$s1`의 게이트에 자기 것을 더한 것이다. `$s1`이 아직 구해지지 않았으면
"`$s1`이 바뀌었다"를 알 수 없기 때문이다. `handing-the-rest-of-a-key-to-the-game.md` 2-5 끝의 "`judge-$s1` 깨움에
`$c`도 선다"도 이것으로 풀린다.

**`$c`를 구하는 코드는 `$s1`이 `due`면 `$s1`부터 구한다.** 지금 `COMPUTE_SWITCHES_SNIPPET`이 `$s1`을 새 값으로 두는
것은 `ComputedSwitches` 순서로 다 구하기 때문이다. 필요할 때 재기에서는 `$s1`의 확인에 닿는 묶음이 없으면 `$s1`이
`due`인 채로 남는다. 그 상태로 `$c`를 조립하면 `$s1`의 옛 값으로 파싱한다. `SwitchesToWorkOut`의 순서대로 `$c`의
측정 앞에 의존하는 스위치의 `due` 확인을 넣는다.

## 4. 필요할 때 재기

### 4-1. 정한 것 (소유자, 2-5)

게이트로 걸러진 뒤에도 결과를 못 바꾸는 스위치는 구하지 않는다. 판정이 그 확인에 닿았을 때만 구한다.

### 4-2. 게이트가 열리면 그 스위치를 읽는 묶음에 `stamp`를 찍는다 (제안)

2-5의 스케치는 "다시 필요해졌을 때 새로 구해 묵은 값과 비교하고, 바뀌었으면 읽는 묶음을 다시 판정한다"였다.
그것만으로는 놓치는 경우가 있다. 묶음이 `[$s] → 놓음; 나머지 → 우리`이고 `$s = [mounted]`이면, 탈것에 타서 게이트가
열려도 그 묶음이 읽는 다른 컬럼이 없어 다시 판정될 계기가 없다. 키는 넘어가지 않는다.

그래서 게이트가 열리면 그 스위치를 `due`로 두고 그 스위치를 읽는 묶음에 `stamp`를 찍는다. 다시 판정된 묶음이 그
확인에 닿으면 그때 구하고, 닿지 않으면 `due`인 채 남는다. 읽는 묶음은 이미 모두 `stamp`가 찍혀 있으므로 "구한 뒤
비교해 다시 판정"하는 단계는 필요 없다.

### 4-3. `known`은 게이트 없이 필요할 때 잰다 (제안)

`known`의 답은 전투 중 펫 교체 등으로 움직이고, 그 계기를 컬럼으로 다 옮길 수 없다. 그래서 박자마다 그 컬럼을
읽는 묶음에 `stamp`를 찍고, 파싱은 판정이 닿았을 때만 한다. 다시 판정하는 비용은 저장된 값 몇 번 비교하는 것이다.
옮길 수 없는 토큰만 남아 3-1로도 줄지 않는 계산식 스위치도 같다.

한 항목 안에서는 리빌드가 싼 컬럼의 확인을 앞에, 파싱하는 컬럼의 확인을 뒤에 둔다.

### 4-4. `unit` 컬럼은 박자 첫머리에서 잰다 (제안)

유닛 확인은 대개 꼬리 키를 둔 이유가 되는 조건이라 판정이 거의 늘 거기 닿는다. 필요할 때 재기로 돌리면 그
컬럼을 읽는 묶음을 박자마다 판정하는 비용만 붙는다.

### 4-5. 판정하는 절반도 생성한다 (제안)

필요할 때 재려면 확인하는 자리에 측정 코드가 있어야 한다. 본문에서는 함수를 만들 수 없고(2의 4), `RunAttribute`를
박자마다 부르는 것은 막혔다. 생성하면 마스크가 리터럴로 굽혀 `entry[c+1]` 읽기와 안쪽 루프가 빠진다. 첫 일치에서
나가는 것은 `repeat … until true`와 `break`다. 조합 키가 기본 키에 기대는 것도 빌드 때 상수가 된다.

측정 코드를 넣는 방식은 둘이다.

- (a) 확인하는 자리마다 그대로 넣는다. 실행 비용이 없다. 본문은 측정 코드 길이 × 그 컬럼을 읽는 묶음 수만큼
  커진다. 조합식 스위치의 측정은 25줄쯤이다.
- (b) 필요한 컬럼을 표시하고 멈춘 뒤, 한 번에 재고 멈춘 묶음만 다시 판정한다. 측정 코드는 한 벌이고, 그런 박자마다
  판정을 한 번 더 돈다.

제안은 (a)다. 커지는 것은 리빌드 때 한 번 치르는 비용이다.

### 4-6. 묶음 훑기는 그대로 둔다 (제안)

`stamp` 비교는 묶음 수만큼이고 무언가 움직인 박자(그리고 4-3의 묶음이 있는 박자)에만 든다. 작업 목록을 두면
`stamp`마다 넣는 비용이 대신 생긴다.

## 5. 매니저 이벤트 (제안)

이벤트 하나는 매니저의 전체 패스 한 번이다(2의 3). 이벤트마다 얼마나 자주 오는지와 늦으면 무엇이 틀리는지를
견준다.

- `SPELLS_CHANGED`는 뺀다. `known`은 박자에서 다시 판정되므로 얻는 것은 0.2초 안의 지연뿐이다. 자주 오는지는 재지
  않았다.
- `PET_BATTLE_*`은 3-3으로 루프 몫이 없어진다.
- 나머지는 하나씩 같은 기준으로 본다.

## 6. 그대로 두는 것

- 박자의 속성을 0으로 되돌리는 것. unit watch가 다시 쓰게 하려면 필요하다.
- `handing-the-rest-of-a-key-to-the-game.md` 3절의 4(교집합으로 먼저 쳐내기)는 같은 문서 6절의 3을 잰 뒤에 정한다.

## 7. 모르는 것

1. `button`·`btn`이 박자에서 무엇으로 나오는지.
2. `possessbar`·`vehicleui`가 어느 API와 맞는지.
3. `resting`, `pvpcombat`, `house:inside`·`house:plot`·`house:neighborhood`가 전투 중에 움직이는지. 움직이지 않으면
   3-3으로 간다.
4. 3-2의 ✓ 낱말 가운데 `combat` 말고는 매크로 조건과 같은 것을 잰다는 근거가 없다. 근거가 없는 낱말은 3-1에도
   3-4에도 못 쓴다. `Probe_GateWords.lua`가 낱말마다 매크로 쪽과 API 쪽을 매 프레임 견준다. 한쪽만 움직인 횟수와
   서로 다른 답이 이어진 가장 긴 프레임 수를 낸다. `button`(7의 1)과 `possessbar`·`vehicleui`(7의 2)의 후보 API도
   같이 기록한다.
5. 박자 한 번의 비용(`handing-the-rest-of-a-key-to-the-game.md` 6절의 3).

### 7-1. 측정: 낱말과 API (2026-10-05, 소유자, xptr 120105, 흑마법사, `Probe_GateWords.lua`)

약 250초, 36000프레임.

- **같이 움직였고 어긋난 적이 없다:** `combat`(3번), `mounted`(9), `flying`(15), `indoors`·`outdoors`(3),
  `overridebar`(3), `bar`(5), `mod`·`mod:alt`·`mod:ctrl`, 유닛 낱말 `exists`·`help`·`harm`·`dead`(`@target`,
  `@focus`, `@mouseover`, `@pet`. `@mouseover,exists`만 121번).
- **`bonusbar`도 같이 움직였다**(탈것을 탈 때 5, 내릴 때 0). 요약에 어긋남으로 나온 것은 프로브가 오프셋 0을
  `[bonusbar:0]`으로 물은 탓이다. 보너스 바가 없을 때 그 절은 맞지 않는다.
- **`swimming`은 `IsSwimming()`과 어긋난다.** 물에 들 때는 매크로가 1프레임 먼저 참이 되고, 나올 때는 API가
  13~14프레임 먼저 거짓이 된다(네 번 모두). 나오는 쪽이 문제다. 그 틈에 박자가 들면 API가 바뀐 박자에 스위치를
  다시 구하는데 매크로는 아직 참이고, 13프레임 뒤 매크로가 거짓이 될 때는 컬럼이 안 움직여 게이트가 안 열린다.
  `IsSwimming()`으로는 게이트를 못 건다.
- **`[swimming]`은 `IsSubmerged()`와 맞는다** (같은 날 두 번째 측정, 약 15초). 물에 들고 나기 세 번 모두 같은
  프레임에 움직였다. `IsSwimming()`은 이번에도 나올 때 13프레임 먼저 거짓이 됐다.
- **맨 `[bonusbar]`는 오프셋과 같은 질문이 아니다** (두 번째 측정). 날고 있는 동안 리로드한 직후
  `GetBonusBarOffset()`은 5, `HasBonusActionBar()`는 참이었는데 `[nobonusbar]`도 참이었다. 첫 측정의 `[bonusbar:5]`는
  오프셋과 같이 움직였다. 그래서 인자 있는 `bonusbar:n`만 오프셋에 옮긴다. 내린 뒤 오프셋이 0이 된 것은 `mounted`가
  거짓이 되고 42프레임 뒤였다.
- **`pet`의 API 쪽만 세 번 움직였다.** 소환 직후 이름이 `Unknown`이었다가 0.1~0.2초 뒤 진짜 이름이 된다. 게이트가
  한 번 더 열릴 뿐이다.
- **`btn`은 누름이 없는 박자에 `1`로 답했다.**
- **처음 값에서 한 번도 안 움직여 잰 것이 아니다:** `advflyable`, `flyable`, `stealth`, `form`, `shapeshift`,
  `group`, `extrabar`, `channeling`, `canexitvehicle`, `mod:shift`, 유닛 낱말 `party`·`raid`·`unithasvehicleui`,
  `vehicleui`, `possessbar`(참이 된 적이 없다).

## 8. 테스트

- 헤드리스(`restricted.lua`로 박자를 돌린다). 상태를 바꿔 가며 박자마다, 게이트와 필요할 때 재기를 거친 키의
  바인딩이 모든 계산식 스위치와 `known`을 매 박자 파싱해 얻은 바인딩과 같아야 한다. 4-2의 `[$s] → 놓음` 묶음,
  `[combat,pvpcombat]`, `[a][b]`, 그리고 `$s1`의 확인에 닿는 묶음이 없는 채 `$s1`을 읽는 `$c`(3-5)를 따로 둔다.
- 3-4는 같은 상태에서 컬럼 계산의 답과 파싱의 답이 같아야 한다. 헤드리스의 파싱은 목이라, 매크로 조건과 같은
  것을 잰다는 근거(7의 4)는 여기서 안 나온다.
- 3-3의 깨움은 게임 안에서 펫 대전과 집 편집기를 열고 닫아 바인딩을 본다. 펫 대전은 두 번째
  `PET_BATTLE_CLOSE` 뒤에 `petbattle`이 거짓인지를 본다.
