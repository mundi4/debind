# action / binding 모양 바로 세우기

> 상태 (2026-08-20): **§4-2와 §5 전부가 들어갔다. 남은 것은 §4-1과 §4-3뿐이고, 그 둘은 3.3이다.**
>
> 들어간 것: `binding.spellName` 삭제(§5-A), `action._dirty` 삭제(§5-B), 비교자 레코드를
> `Misc.MakeOrderRecord` 하나로(§4-2), 솔버의 인자 이름(§5-C), `GetBindingIssue`의 모양
> 갈아타기(§5-D), `binding.reactions` 삭제(§5-E). 같은 편집에서
> `GetBindingInfoForAction`의 `update` 인자와 `if (true)` 블록이 같이 없어졌고,
> `.zzz/refactor-candidates.md`의 `UnitConditionToRuntimeScalar` 항목도 같이 닫혔다.
>
> 시작은 `checkedUnits`라는 이름이 거슬린다는 것이었는데, **이름은 증상이고 원인은 `binding`이
> 세 가지 일을 겸하는 데 있었다.** 그래서 이 문서는 이름 정리가 아니라 모양 이야기다.
>
> **§4의 2번 하나만이 모델을 고치는 항목이다.** 1번과 3번은 모델을 읽기 좋게 만들 뿐이고,
> 2번은 모델이 성립하게 만든다.
>
> **배정은 §8에서 갈렸다.** 2번은 독립이라 아무 때나 내고, 1번과 3번은 3.3에 커스텀 상태
> 재설계와 한 단계로 간다.

## 1. 지금 서 있는 모양은 둘이 아니라 넷이다

| 모양 | 사는 곳 | 무엇 |
|---|---|---|
| **action** | SavedVariables | 저장 |
| **binding** | `Misc.lua`의 `GetBindingInfoForAction` | 파생 |
| **row** | `Profile.lua`의 `MakeRow` | 순서 + 그리기 |
| **issue category** | `Misc.lua`의 `GetBindingIssue` | 갈래 이름 |

네 번째가 특히 나쁘다. 카테고리는 이 열셋이다.

```
key groups forms bonusbars states target hover reactions frameTypes
unit checkedUnits specialbar petbattle
```

- `hover`와 `reactions`는 **그 이름의 액션 필드가 없다.** `dbver <= 4` 단계가 `checkedUnits.hover`로
  접었는데 카테고리 이름만 남았다.
- `target`은 필드가 없고 뜻도 다르다. 그 갈래가 보는 것은 `GetMissingMacroName` 하나뿐이다.
- `checkedUnits`만 필드와 이름이 같다.

그런데 이 문자열들은 `DropDownMenus.lua`의 `setActionValue`에서 `_action[key]`로 **필드 이름으로도
쓰인다.** 한 네임스페이스가 필드 이름 겸 이슈 카테고리 겸 메뉴 그룹 이름인데, 셋이 이미 따로
놀고 있다.

## 2. 비교자 레코드는 계약 하나에 구현이 셋이다

`Ordering.lua`의 `CompareActionOrder`가 받는 레코드를 만드는 곳이 셋이고, 필드 집합이 다 다르다.

1. `Debind.lua`의 `BuildKeyMap`이 **`binding`에 `layerRank`/`seq`/`isConditional`을 긁어 넣은 것.**
   그 파일 주석이 "binding 테이블이 그대로 레코드 역할을 한다"고 적어놨다.
2. `Profile.lua`의 `MakeRow`. 위에 더해 `specRank`, `index`, `imported`, `issue`, `offWorld`.
3. `Profile.lua`의 `RenumberKeyGroup` 안에서 만드는 인라인 레코드. 제일 짧다.

셋이 섞여서 정렬되는 자리는 없다. 즉 지금 틀린 답을 내고 있지는 않고, **손으로 맞춰서 유지되는
상태다.** 그리고 `priority or DEFAULT_PRIORITY`가 저 셋과 `Misc.lua`, 비교자 자신까지 **네 곳**에서
따로 적용된다.

## 3. 원인: `binding`이 세 가지 일을 겸한다

1. **정규화된 액션.** 못 갖는 조건을 지우고, 마스크를 `_ALL`로 접고, 호버를 채워 넣는다.
   액션 하나의 순수 함수다.
2. **솔버 입력.** `unitStates`, `unitStatesOpaque`. 1번의 순수 함수다.
3. **순서 레코드.** `layerRank`, `seq`, `isConditional`.

**3번만 액션에서 파생되지 않는다.** 프로필 안에서의 *위치*이기 때문이다. 그래서 밖에서 써넣고,
아무도 안 지우고, `MakeRow`가 같은 것을 또 만든다. 1번과 2번이 "액션의 순수 함수"라는 성질은
지금 규약이지 사실이 아니다.

## 4. 제안하는 모양

```
action        저장. 액션 하나로 닫힌다.
              type value key unit / name icon / seq priority imported /
              keepInBindingContext ignoreHoverUnit
              conditions = { units, frameTypes, groups, forms, bonusbars,
                             specialbar, extrabar, combat, stealth, known,
                             pet, petbattle, $state1..5 }

binding       액션 하나의 순수 파생. 밖에서 아무도 안 쓴다.
              정규화된 conditions + unitStates / unitStatesOpaque + hover

placement     프로필에서의 위치. 액션에서 파생되지 않는 유일한 것.
              layerID layerRank specRank index seq
              CompareActionOrder가 받는 것은 이것 하나
```

### 1. `conditions` 중첩

`KEYS_TO_SAVE` 서른 개 중 **열여덟 개가 조건**이다. 지금은 `unit`이 그 사이에 섞여 앉아 있어서
`Misc.lua`가 예순 줄짜리 주석으로 "이 둘은 한 식구처럼 들리는데 정반대다"를 설명해야 한다.
높이가 갈리면 그 주석이 필요 없어진다.

**`ignoreHoverUnit`은 조건이 아니다.** `Misc.lua`에서 `binding.unit`을 `""`로 만드느냐 `"hover"`로
만드느냐를 가른다. 겨누는 것을 바꾸지 언제 나가는지를 바꾸지 않는다. `conditions` 밖으로 나오면
**지금 아무 주석도 하지 않는 말을 구조가 한다.** 이 문서에서 코드가 아직 어디에도 안 적어둔
사실은 이것 하나다.

접히는 것과 안 접히는 것을 정직하게 세면, "조건 전부"를 손으로 나열한 목록이 아홉 개인데
넷이 접히고 다섯은 안 접힌다. 필드마다 로직이 달라서다(마스크냐 불리언이냐 표냐).

| 목록 | |
|---|---|
| `Profile.lua`의 `KEYS_TO_SAVE` | 접힘 |
| `Export.lua`의 `ACTION_FIELDS` | 접힘 |
| `Misc.lua`의 복사 블록 | 접힘 (루프 하나) |
| `Misc.lua`의 `IsConditionalBinding` | **쉰다섯 줄이 `next(binding.conditions) ~= nil`** |
| `Misc.lua`의 이슈 카테고리 사슬 | 안 접힘 |
| `Solver.lua`의 `FIXED_COLUMNS` | 안 접힘 |
| `UpdateBindings.lua`의 방출 블록 | 안 접힘 |
| `SecureBindings.lua`의 스니펫 판정 | 안 접힘 |
| `DropDownMenus.lua`의 메뉴 구성 | 안 접힘 |

깨지는 것: `tools/check-export-fields.js`는 줄 단위로 `name =`을 매칭해서 읽으므로 여러 줄로
퍼진 값의 안쪽 키를 필드 이름으로 읽는다. 파서를 고쳐야 한다. `Import.lua`의 검증도 한 겹
깊어지는데, 여기는 적대적 입력 표면이다.

그리고 `DropDownMenus.lua`의 `setActionValue`가 `_action[key] = value`라서, 조건 필드는
`_action.conditions[key]`로 가야 한다. 쓰는 길이 두 갈래로 갈리는 것을 같이 결정해야 한다.

### 2. `binding`에서 순서 필드를 뺀다 — **들어갔다 (2026-08-20)**

`Misc.MakeOrderRecord`가 그 레코드를 만드는 한 자리다. `BuildKeyMap`은 그것을 바인딩 **옆**의
약한 키 표(`Placements`)에 두고, `MakeRow`는 그 위에 그리기 필드를 얹고, `RenumberKeyGroup`은
그대로 쓴다. `binding.priority`도 같이 나갔다. `/debtest`의 `Binding carries no ordering fields`가
되돌아가는 것을 잡는다 - 되돌아가도 순서는 맞아서 화면에는 아무것도 안 나온다.

**이것 하나만이 모델을 고친다.** `BuildKeyMap`이 바인딩에 긁어 넣는 대신 placement를 만들고,
`CompareActionOrder`는 placement만 받는다. 레코드 구현이 셋에서 하나가 되고, `priority` 기본값도
한 곳이 된다. 그리고 바인딩이 "액션의 순수 함수"라는 성질이 규약이 아니라 사실이 된다.

저장 형식을 안 건드린다. `layerRank`도 `specRank`도 원래 저장되지 않는다.

### 3. 이슈 카테고리를 필드 이름과 분리한다

카테고리는 **어느 컨트롤을 빨갛게 칠할지**의 이름이지 필드 이름이 아니다. 이미 `hover`,
`reactions`, `target` 셋에서 깨져 있다.

같이 고칠 것: 카테고리 `"target"`은 오분류다. `Misc.lua`가 그 자리에서 **"여기서 `"target"`은
갈래를 끄기 위한 이름"**이라고 자백하고 있고, 보는 것은 `GetMissingMacroName` 하나다. `"macro"`가
맞는 이름이다.

## 5. 조사에서 나온 것들

모양이 무너진 자리를 가리키는 증거다. 각각은 따로 고칠 수도 있다.

**A. `binding`은 재사용되는데 wipe를 안 한다.** — **닫혔다 (2026-08-20). 필드를 지웠다.**

캐시에서 꺼내 제자리에서 덮어쓰는데, 조건부로만
쓰는 필드는 안 지워진다. `binding.spellName`이 그것이다(`type == SPELL`일 때만 대입, `else` 없음).
주문을 아이템으로 바꾸면 옛 주문 이름이 남는다.

**그런데 `binding.spellName`을 읽는 코드가 하나도 없다.** 매크로 본문도 UI도 각자
`GetSpellNameAndIconID`를 따로 부른다. `Misc.lua`의 필드 목록은 "resolved name, for display and
macro text"라고 적어뒀는데, **없는 소비자를 설명하는 문서가 달린 죽은 필드**다. 살아 있었으면
위가 버그였을 자리다.

**B. 무효화 프로토콜이 도착지에서 꺼져 있다.** — **닫혔다 (2026-08-20). 지우는 쪽으로 갔다.**

`action._dirty`를 **열한 곳이 쓰고 영 곳이 읽는다**
(DebindUI 일곱, Profile 셋, DropDownMenus 하나). `Misc.lua`에 읽는 줄이 주석 처리돼 있고 다음
줄이 지워버린다. `update` 인자도 같이 죽었다(`if (true)`). 그래서 모든 호출이 전부 다시 만든다.
`C_Spell.GetSpellInfo` 포함해서.

파생 캐시라는 개념이 호출부에는 남아 있고 도착지에서만 사라진 상태다. **지금은 둘 다 아닌 것이
제일 나쁘다.** 지우든 읽는 줄을 되살리든 하나를 골라야 한다.

→ 지웠다. 되살리는 쪽은 열한 곳이 정확한지 먼저 감사해야 하는데 그건 실행된 적 없는 코드였고,
그 감사는 §4-2와 아무 상관이 없다. `update` 인자와 `if (true)`도 같이 없어졌다.

**C. 솔버가 binding을 `action`이라고 부른다.** — **닫혔다 (2026-08-20). 이름을 바꿨다.**

`FIXED_COLUMNS`의 `make`, `makeUnitFlags`/`makeKnownFlags`/`makeCustomStateFlags`,
`buildConditionSet`이 전부 `binding`을 받는다.

원래 적어둔 것: `buildLayout`은 `binding`이라 쓰는데, 바로 아래
`buildConditionSet(action, dest)`와 `FIXED_COLUMNS`의 모든 `make = function(action)`은 `action`이라
쓴다. `makeUnitFlags`가 읽는 `action.unitStates`는 바인딩만 가진 필드다. 한 파일 안에서 같은
것을 두 이름으로 부르고 있고, 하필 불변식에 쉰 줄 쓰는 그 파일이다.

**D. `GetBindingIssue`가 함수 중간에 모양을 갈아탄다.** — **닫혔다 (2026-08-20).**

바인딩을 함수 첫머리에서 한 번 잡고, `groups`/`forms`/`bonusbars`도 거기서 읽는다. 어느 읽기가
**반드시** 바인딩이어야 하고 어느 것이 선택이었는지는 그 함수 머리 주석에 적었다.

원래 적어둔 것: `groups`/`forms`/`bonusbars`는 액션에서
읽고, `local binding = ...` 뒤로 `hover`/`reactions`/`frameTypes`는 바인딩에서 읽는다. 그런데
**어느 쪽은 필수고 어느 쪽은 임의다.** `binding.frameTypes`는 호버가 아니면 nil이 되니 반드시
바인딩이어야 하고, `groups`는 `_ALL` 접기 말고는 차이가 없어서 아무 쪽이나 된다. 무엇이 어느
쪽인지 표시가 없다.

**E. 호버가 바인딩 위에 세 겹으로 있다.** — **닫혔다 (2026-08-20). 두 겹이 됐다.**

`binding.reactions`가 없어졌다. 읽던 곳은 이슈 검사 둘뿐이었고 지금은 `HoverReactionMask`가
조건에서 바로 읽는다. `binding.hover`는 남는다 - 발동 순서·클릭 경로·솔버 컬럼·키 유효성이
전부 그것을 읽는다. §9에 이 항목이 미결로 적혀 있던 근거("솔버 스펙이 이 필드를 손으로
넣는다")는 틀렸었다.

원래 적어둔 것: `conditions.units.hover` -> `binding.checkedUnits.hover`
-> `binding.hover` + `binding.reactions`. `dbver <= 4`가 없앤 것이 정확히 "한 유닛을 두 컬럼이
설명하는" 모양인데, **파생 쪽에 그대로 살아남았다.** `Misc.lua`가 대는 이유의 절반은 "솔버
스펙이 손으로 만든 바인딩"이다. 테스트 편의가 프로덕션 모양을 정하고 있다.

## 6. dbver는 올려야 한다 (2026-08-20에 뒤집힘)

**이 절이 기대던 창은 닫혔다.** `v3.2`가 2026-08-20에 나갔고 `DB_VERSION = 5`를 넣은 커밋
(`Give each unit condition axis its own field`)이 그 태그 안에 들어 있다(`git tag --contains`).
dbver 5는 정상 배포본이다.

그래서 **§4-1은 새 `dbver 6` 단계를 세운다.** 기존 `dbver <= 4` 단계에 얹는 안은 없어졌고,
"이미 5로 올라간 설치본이 게이트에 막힌다"는 대가도 없어졌다. `tests/migration_spec.lua`의
`"dbver 5 ..."` 이름도 안 고친다 — 이 리포는 단계를 **목적지 버전**으로 부르고 있어서
(`dbver <= 4` 단계 = "dbver 5") 지금이 맞다.

**배정은 안 바뀐다.** 근거만 줄어든다. 커스텀 상태 재설계가
`$state1..5`를 이름으로 갈면 저장 필드가 바뀌어 `dbver`가 올라가고, 전송 포맷이 그 이름을 그대로
싣고 있어 `SCHEMA_VERSION`도 올라간다(`0-ROADMAP.md`). 3.3이 어차피 치르는 값이므로 §4-1을
거기 얹으면 추가 비용이 없다.

**미루는 값이 공짜가 아니라는 것은 짚어둔다.** `DecodeExportString`이 `payload.v < SCHEMA_VERSION`을
`SCHEMA_TOO_OLD`로 거절하므로, 범프는 그 판으로 공유된 문자열을 전부 죽인다. 서랍에 쌓인 배치까지.
3.3이 그 값을 이미 치르기로 되어 있어서 얹는 것이지, 범프 자체가 싸서가 아니다.

## 7. 기각: `action.unit` -> `action.target`

**못 쓴다.** `"target"`이 이 리포에서 이미 넷이다.

| | |
|---|---|
| `Constants.lua` | `Constants.TARGET = "target"` 액션 **타입** |
| 여러 스펙 | `action.unit = "target"` 유닛 **토큰 값** |
| `FrameRegistry.lua` | `target = { type = "target" }` 프레임 타입 |
| `Misc.lua` | 이슈 **카테고리** (뜻은 "매크로 이름이 가리키는 것이 없다") |

`action.target = "target"`인데 `action.type`도 `"target"`일 수 있는 상태가 된다. 정리가 아니라
겹치기다.

**`unit`은 그대로 두고 `conditions.units`로 층을 가르는 것으로 대신한다.** 값 자체는 열일곱 줄에
제한 환경 노출이 영이라 싸긴 했다. 싸다는 것이 근거가 못 된 경우다.

기각 이유가 사라지려면 위 네 자리 중 최소한 카테고리 쪽이 `"macro"`로 옮겨져야 하는데, 그때도
타입과 유닛 토큰 값 둘이 남는다. **이 문은 다시 열릴 일이 없다고 본다.**

## 8. 언제 무엇을 내나 (2026-08-19에 정해짐)

| | |
|---|---|
| **§4-2** 순서 필드를 `binding`에서 빼기 | 독립. 저장·전송·마이그레이션을 안 건드린다. **아무 때나** |
| **§4-1** `conditions` 중첩 + **§4-3** 이슈 카테고리 | **3.3에, 커스텀 상태 재설계와 한 단계로** |

§4-1이 3.3에 붙는 이유는 §6에 있다. 둘이 **같은 필드를 옮기고**, 3.3이 `dbver`와
`SCHEMA_VERSION` 범프를 어차피 치른다.

그리고 `CleanUpDB`의 `$` 탈출구가 둘의 공유 부품이다. `redesigning-custom-states.md`의 ⚑1에
따르면 이름 붙은 상태(`action["$pvpzone"]`)가 가지치기에서 살아남는 유일한 이유가 저것인데,
§4-1이 조건을 중첩하면 가지치기가 한 겹만 훑으므로 탈출구도 같이 내려가야 한다. 따로 내면 같은
가드를 두 번 고친다.

**대가 하나.** 3.3의 마이그레이션 단계가 두 가지 일을 한 번에 하게 된다. `dbver <= 1` 단계가
이미 여럿을 하므로 형태 자체는 문제가 아니지만, 그 릴리스의 동결본은 그만큼 더 중요해진다
(`setting-up-a-dev-profile.md`).

## 9. 안 정한 것

- ~~**`_dirty`를 지울지 되살릴지.**~~ — **지우는 쪽으로 정해졌다 (2026-08-20, 소유자).** 되살리는
  쪽은 열한 곳이 정확한지 먼저 감사해야 하는데, 그건 한 번도 실행된 적 없는 코드였다. 성능이
  실제로 문제로 잡히면 그때 무효화 지점을 근거를 갖고 다시 세운다.
- ~~**`binding.reactions`를 없앨지.**~~ — **미결이 아니었다 (2026-08-20).** 여기 적힌 근거가
  틀렸다. `tests/solver_spec.lua`에 `reactions`가 없다. 스펙이 손으로 쓰는 것은 `checkedUnits`고
  이 필드는 `BuildUnitStates`가 파생시킨다. 실제로 읽는 곳은 `Misc.GetBindingIssue`의 두 갈래와
  `DebindTest` 하나뿐이라, 세 겹을 두 겹으로 줄이는 것은 그냥 하면 되는 항목이다.
