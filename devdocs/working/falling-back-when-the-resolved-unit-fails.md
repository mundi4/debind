# Resolved Unit 조건이 안 맞을 때 평소처럼 쓰는 옵션 (2026-10-11 계획)

> 상태: 동작은 소유자와 정했다(2026-10-11, 3절). 만들지 말지는 아직 정하지 않았다(10절).
> 구현은 시작하지 않았다.
>
> 처음 쓴 세션: `debind-34` (세션 ID `234b5878-2331-48a6-a0a8-d3efd3c8f925`). 그 초안을 검토하고 소유자와 정한 내용으로 다시 쓴
> 세션: `debind-be` (세션 ID `3a899c61-4355-4585-abc2-ac37f68d40a7`). 초안의 검토 기록은 `.zzz/reviewing-the-resolved-unit-fallback-2026-10-11.md`에
> 있다. 그 파일은 결정이 오가는 동안 쓴 것이라, 이 문서와 갈리면 이 문서가 맞다.

## 0. 이 문서에서 쓰는 말

**평소처럼 쓴다.** 유닛을 지정하지 않고 쓰는 것이다. 매크로의 `[]`가 이것이다. 그 액션을 Target을 비워 둔 채 지금 그냥 누를 때와
똑같이 나간다. 유닛을 싣지 않는 것까지가 우리 일이고, 그다음은 게임의 일이다. 이 문서는 게임이 그다음 무엇을 하는지 말하지 않는다.
우리가 알아낼 수도 정할 수도 없는 것이다(소유자. `targeting.md`의 작성 주석에 있는 "What the game does with it is not ours to say"와
같은 규칙).

**옵션.** 이 문서가 만들자는 체크박스다. Resolved Unit 메뉴 안에 둔다.

## 1. 왜

디스코드의 한 사용자가 `/cast [@mouseover,help,nodead] [] Lesser Heal`을 Debind 액션으로 옮기는 법을 물었다. 지금은 액션 둘로
옮긴다. 도움말 "One key for a friend and an enemy"(`setting-keys-up.md`)와 같은, 거르는 액션을 위에 두고 조건 없는 액션을 아래에
두는 모양이다. 그 도움말이 가르치는 것은 다른 예(위에 Resolved Unit [적대]를 건 공격, 아래에 Resolved Unit 조건 없는 치유)다.

1. Lesser Heal. Hover Cast를 Cast on pointed unit, 모드 Mouseover. `mouseover` 유닛 조건에 [우호], [생존].
2. Lesser Heal, 아무것도 안 바꿈.

액션 하나로 하려고 Hover Cast를 Cast on pointed unit으로 두고 Resolved Unit에 [우호], [생존]을 걸면 안 된다. Resolved Unit 조건은
그 액션의 모든 바인딩에 걸린다. 마우스를 올린 유닛에게 쓰는 바인딩에서는 그 유닛을 보고, 그냥 누를 때의 바인딩에서는 현재 대상을
본다(`Conditions/Units.lua`의 `ResolvedUnitOf`, `which-action-a-key-runs.md` S3). 그래서 현재 대상이 적이거나 죽었거나 없으면 그냥
누를 때의 바인딩도 건너뛰어지고, 매크로의 `[]`에 해당하는 것, 즉 유닛 없이 쓰는 것이 나가지 않는다.

**이 옵션은 그 `[]` 하나를 액션 하나로 만들 수 없어서 나왔다** (2026-10-11, 소유자). 아래의 모든 결정이 이것에서 나온다.

## 2. 이미 한 번 접은 안

`0-DIARY.md` 2026-09-15의 두 절이 이 자리다.

- **"대상 없는 `@`는 하루에 두 번 정해졌다."** 한때 Target을 비워 둔 액션은 그냥 누를 때 Resolved Unit 조건을 안 봤다. 그것을
  조건 표에서 지우는 식으로 해서, 행의 조건 표시와 실행 순서가 그 액션을 조건 없는 것으로 읽었다. 소유자가 되돌렸다. 근거는 둘이었다.
  조건이 사라지면 순서와 표시가 틀린다. 그리고 `@.harm` 공격 뒤에 `@.help` 치유를 둔 키에서, 그냥 누를 때 조건을 안 보면 우호 대상을
  잡고 눌러도 공격이 헛나간다.
- **"우리 모델이 잘못됐네: 세웠다가 버린 안."** Resolved Unit 조건을 유닛을 바꿔 끼운 누름에만 걸고 그냥 누를 때는 안 보자는 안이
  나왔다. 소유자가 접었다. *"그럴바에 조건 없는 같은 치유주문을 마지막에 넣는게 낫지"*. 액션 하나를 아끼는 대신 "이 조건은 그냥 누를
  때는 안 든다"를 배우게 하는 값이 더 크다는 판단이었다.

**이번 안이 그때와 다른 점.** 그때는 모든 액션의 규칙을 바꾸는 안이었고, 이번에는 사용자가 켜는 옵션이다. 켜지 않은 액션은 지금과
같고, `@.harm` 공격 사례도 그대로다. "그냥 누를 때는 조건이 없어진다"를 배우는 값은 옵션의 툴팁이 치른다. 그 값이 액션 하나를
아끼는 것보다 싼지는 그때와 같은 물음이고, 10절에 남겼다.

## 3. 정한 동작 (2026-10-11, 소유자)

### 3-1. 규칙

**옵션을 켜면, 그 액션이 유닛을 지정하지 않고 평소처럼 쓰는 바인딩에서 Resolved Unit 조건을 없앤다.** 그런 바인딩의 Resolved Unit
조건은 현재 대상을 본다(`ResolvedUnitOf`). 소유자의 말로는 *"조건이 안맞아서 넘어갔을때 마지막에 `@`가 현재의 대상(@target)으로
풀리는 순간에 resolved unit조건을 없애겠다는거"*.

그런 바인딩은 Target을 비워 둔 액션에서 셋이다.

- **그냥 누를 때의 바인딩.** Normal Cast가 켜져 있을 때만 있다.
- **Hover Cast를 Cast as usual로 둔 액션에서 마우스를 유닛에 올려 둔 채 누를 때의 바인딩.** Normal Cast가 켜져 있으면 그냥 누를
  때와 같은 바인딩이 받고, 꺼져 있으면 그 누름에만 서는 바인딩이 받는다. 소유자: *"hc usual target은 사실상 hc라기보다는
  유닛프레임위에서도 normalcast라는 의미"*.
- **Self Cast Key나 Focus Cast Key를 Cast as usual로 둔 액션에서 그 키를 누른 채 누를 때의 바인딩.** Cast as usual은 "이 액션에서는
  그 키를 누른 것을 신경 쓰지 말고 평소처럼 쓴다"를 고른 값이다. 그 키를 누를 때 차례를 넘기길 원했다면 Off를 골랐을 것이다.

각 바인딩에 딸린 전문화별 주문 항목과 부활 갈래(`GetBindingsForAction`의 `fillKnown`)도 같은 유닛으로 쓰므로 같이 적용된다.

**타입으로 가르는 예외는 없다** (2026-10-11, 소유자: *"예외를 만들 필요 없다"*). 주문이 아닌 타입도 위의 바인딩이면 똑같이 적용된다.
매크로, 탈것, Target에서 아무것도 안 고른 Target·Focus·ToggleMenu 타입, 그리고 꼬리(`GIVEBACK`, `COMMAND`. `FillBinding`이 BLOCK으로
바꾸고 유닛을 싣지 않는다)가 그렇다. 예를 들어 Resolved Unit 조건을 건 `GIVEBACK`에 옵션을 켜면, 그 꼬리까지 오는 그냥 누름마다
키를 게임에 돌려준다. 꼬리까지 오는 것은 그 위의 액션이 하나도 실행되지 않는 누름뿐이다(`handing-the-rest-of-a-key-to-the-game.md`
2-1).

### 3-2. 적용되지 않는 곳과 그 까닭

- **Target에서 무엇이든 고른 액션.** *"Target메뉴에서 어떤것이라도 지정되어 있으면 마찬가지로 이건 타겟이 핀 된거니까 `[]` 폴백이
  필요 없다"*. Normal Cast가 켜져 있든 꺼져 있든 같다. Target에서 `target`을 고른 액션도 여기에 든다. 그 액션의 Resolved Unit
  조건은 현재 대상을 보지만, 사용자가 대상을 골라 고정한 것이라 버튼에 `target`이 실려 나가고, 유닛 없이 쓰는 것이 아니다.
- **Self Cast Key나 Focus Cast Key를 누른 채 나나 주시 대상에게 쓸 때.** *"의도적으로 키를 하나 더 눌렀는데 그걸 폴백 시킬 필요는
  없을것 같고"*. 이 누름은 지금처럼 조건이 안 맞으면 그 키로 실행될 다음 액션으로 넘어간다. 스펙 S4의 "조합키를 누른 사람이 노린 곳이
  아닌 데로 나가지 않게"가 그대로 선다.
- **Hover Cast를 Cast on pointed unit으로 두고 마우스를 올린 유닛에게 쓸 때.** *"ON POINTED UNIT을 켰다면 ON USUAL TRG을 의도한게
  아니지 않나"*. 그 바인딩은 지금처럼 그 유닛의 조건을 본다. 안 맞으면 지금도 바로 다음 순서가 같은 액션의 그냥 누를 때 바인딩이고,
  Normal Cast가 켜져 있으면 그 바인딩에서 옵션이 적용된다. 디스코드 사례가 이렇게 된다. Normal Cast가 꺼져 있으면 넘어갈 바인딩이
  없으므로 옵션이 아무 일도 안 하고, 지금처럼 다음 액션으로 넘어간다. 수식키 없는 좌클릭·우클릭은 늘 이 경우다
  (`which-action-a-key-runs.md` §7).

**한 문장으로는 "이 액션을 유닛을 지정하지 않고 평소처럼 쓰는 경우에만 적용된다"이다.** 위의 예외는 모두 이 문장에서 나온다.

### 3-3. 액션 설정마다

| 액션 | 그냥 누를 때 | 마우스를 올리고 누를 때 | Self·Focus Cast Key를 누른 채 |
|---|---|---|---|
| Target 비움, Normal Cast 켬, Hover Cast는 Cast as usual | 조건 없이 평소처럼 | 조건 없이 평소처럼 | 그 줄이 Cast as usual이면 조건 없이 평소처럼. 아니면 지금 그대로 |
| Target 비움, Normal Cast 켬, Hover Cast는 Cast on pointed unit | 조건 없이 평소처럼 | 그 유닛이 맞으면 그 유닛에게, 아니면 평소처럼 | 같음 |
| Target 비움, Normal Cast 켬, Hover Cast는 Don't run while pointing | 조건 없이 평소처럼 | 지금처럼 실행 안 함 | 같음 |
| Target 비움, Normal Cast 끔, Hover Cast는 Cast as usual | 지금처럼 실행 안 함 | 조건 없이 평소처럼 | 같음 |
| Target 비움, Normal Cast 끔, Hover Cast는 Cast on pointed unit | 지금처럼 실행 안 함 | 지금 그대로 | 같음 |
| Target에서 무엇이든 고름 | 지금 그대로 | 지금 그대로 | 지금 그대로 |
| 수식키 없는 좌클릭·우클릭 | (없음) | 지금 그대로 | (없음) |

"조건 없이"는 Resolved Unit 조건만 없어진다는 뜻이다. 다른 유닛 조건과 그 밖의 조건은 그대로 본다.

**부활 액션도 다른 액션과 똑같이 처리한다** (2026-10-11, 소유자). 부활에 "죽은 아군" 같은 조건이 따로 필요 없는 것은 부활 갈래의
내부 조건이 그 일을 하기 때문이다. 사용자가 거는 바깥 조건에 무엇을 걸든 부활이라서 막을 까닭은 없다. 옵션이 빼는 것은 Resolved
Unit 조건뿐이다. 갈래들(`ActionBindings.lua`의 `ResurrectBranches`)과 각 갈래의 조건(전투 여부, 대상이 죽었는지, 파티·공격대원인지,
대상이 없는지)은 그대로 남아, 어느 갈래가 나갈지는 지금과 같은 규칙으로 정해진다. 예를 들어 Resolved Unit에 [내 파티]를 걸었다면,
옵션을 켠 뒤로는 그냥 누를 때 그 조건 없이 갈래들만으로 정해지므로 파티 밖의 죽은 아군이 대상이면 단일 부활 갈래가 나간다.

**마우스 버튼.** Target을 비우고 Normal Cast를 켠 마우스 버튼 액션의 개체창 위 클릭은 Hover Cast 값에 따라 다르다
(`which-action-a-key-runs.md` S4의 5).

- **Cast as usual.** 그냥 누를 때의 바인딩이 개체창 위 클릭도 받는다. 옵션을 켜면 그 바인딩이 조건을 안 보므로, 조건이 안 맞는 개체창
  위 클릭도 개체창 원래 동작으로 넘어가지 않고 평소처럼 쓴다. 사용자가 Normal Cast를 켜서 고른 평소처럼 쓰기라 규칙과 어긋나지 않는다.
- **Cast on pointed unit.** 개체창 위 클릭은 먼저 마우스를 올린 유닛에게 쓰는 바인딩이 받고, 그 유닛이 조건에 안 맞을 때만 그냥 누를
  때의 바인딩으로 넘어와 평소처럼 쓴다.
- **Don't run while pointing.** 개체창 위 클릭은 지금과 같다.

### 3-4. 실행 순서에서는 조건으로 센다

소유자: *"조건으로 세어야하지"*. Resolved Unit 조건만 걸린 액션도 옵션을 켜든 말든 조건 있는 액션으로 선다. 2026-09-15에 되돌린
구조(그냥 누를 때는 안 보고, 조합키를 누른 채 누를 때는 본다)가 옵션을 켠 이 액션과 같은 구조라, 안 세면 그날의 문제가 그대로
돌아온다.

**그 값.** 조건 있는 액션은 레이어보다 먼저 정렬된다(`Ordering.lua`의 `CompareActionOrder`). 그래서 계정 레이어에 Flash Heal
(Resolved Unit [우호], 옵션 켬)을, 캐릭터 레이어에 조건 없는 Smite를 같은 키에 두면, Flash Heal이 앞에 서고 그냥 누를 때는 늘
실행되므로 Smite는 그냥 눌러서는 절대 안 나간다. **그런데 화면에는 아무 표시도 없다.** 솔버는 `castModifier`를 축으로 두어
Self Cast Key·Focus Cast Key를 누른 채 쓰는 바인딩을 같은 키를 누른 바인딩끼리만 견준다(`Solver.lua`의 `castModifier` 컬럼).
Flash Heal의 그 바인딩들은 옵션이 적용되지 않아 여전히 나나 주시 대상이 [우호]인지 보므로, 조건 없는 Smite의 그 바인딩들을 덮지
못한다. 닿지 않음 표시(`BINDING_ERROR_UNREACHABLE`, "This action never runs. No matter what, another action on this key gets there
first.")는 그 액션의 바인딩이 모두 덮였을 때만 붙으므로(`IsUnreachableAction`), Smite는 표시 없이 그냥 누를 때를 잃는다. 실제로
Smite에 닿는 것은 Focus Cast Key를 누른 채 쓸 때 주시 대상이 없거나 [우호]가 아닌 경우뿐이다. Self Cast Key를 누른 채 쓸 때는 Flash Heal이
나에게 [우호]를 묻고, 나는 늘 우호라 Flash Heal이 받는다. 계정 설정에서 두 키를 다 끄거나 Smite가 두 줄을 Off로 두면 Smite의
바인딩이 그냥 누를 때의 것 하나라 표시가 붙는다. 이 "표시 없는 잃음"이 실행 순서에서 세기로
한 값이다.

### 3-5. Resolved Unit 조건이 그것만으로 아무것도 안 맞는 액션은 키에서 빼지 않고 오류를 표시한다

예를 들어 Resolved Unit에서 우호·적대·중립을 하나도 안 고른 경우다. 지금은 액션 검사가 이런 줄을 보면 액션의 바인딩을 통째로 뺀다
(`Issues.lua`의 `ACTION_CHECKS` 유닛 줄들, `Constants.lua`의 `BINDING_ISSUE_OUTCOMES`에서 OMIT).

옵션이 적용되는 바인딩이 있는 액션에서는 빼지 않는다. 그 바인딩은 조건을 안 보므로 실행될 수 있다. 나머지 바인딩(조합키를 누른 채
나나 주시 대상에게 쓰는 것, 마우스를 올린 유닛에게 쓰는 것)은 지금 있는 길로 걸러진다. `FillBinding`이 `dead`로 표시하고,
`UnrollIntoTiers`가 키의 바인딩 목록에 넣지 않는다. 액션 하나에 실행될 수 있는 바인딩이 하나라도 있으면 이슈가 아니라는
2026-09-17의 규칙이 이미 그 모양이다.

**오류는 표시한다.** 소유자: *"사용자가 애당초 이걸 의도했을거라고 생각하진 않거든"*. 역할을 하나도 안 골랐지만 파티·공격대 프레임
말고 다른 프레임 종류도 골라 둔 경우(`ROLES_NONE_ON_GROUP_FRAMES`, KEEP)와 같은 모양이다. 오류는 표시하되 살아남는 바인딩은
실행된다.

### 3-6. 메뉴

**옵션은 Resolved Unit 메뉴 안에 둔다.** 옵션이 아무 일도 안 하는 액션(3-2)에서도 잠그지 않고 그대로 보인다(소유자: *"그대로 노출"*).
잠그면 사용자가 정해진 순서를 따라야 한다. Target을 먼저 비운 다음에야 옵션을 켤 수 있다.

**툴팁은 언제 적용되는지를 늘 말한다.** 옵션이 아무 일도 안 하는 액션에서만 띄우는 것이 아니라, 항상 같은 내용을 보여 준다.
3-2의 한 문장이 그것이다. 셋째 예외를 "마우스를 올린 유닛에게 쓸 때는 적용되지 않는다"로만 적으면 디스코드 사례가 안 되는 것으로
읽히므로, 그쪽으로 읽히지 않게 쓴다.

### 3-7. 옵션을 켠 액션이 없는 키는 지금과 똑같이 동작한다

**한 키의 액션 가운데 옵션을 켠 것이 하나도 없으면, 그 키는 이 옵션이 생기기 전과 100% 같게 동작해야 한다** (2026-10-11, 소유자).
누름마다 어느 액션이 나가는지, 어느 유닛에 나가는지, 키를 잡는지 게임에 돌려주는지, 실행 순서, 이슈와 그 결과(OMIT, KEEP)가
모두 그대로다. 이 옵션이 바꾸는 것은 전부 옵션을 켠 액션 하나에서 시작한다. 그 액션과 같은 키에 있는 다른 액션이 영향을 받는
것(3-4의 Smite)은 그 키에 옵션을 켠 액션이 있기 때문이다.

바뀌어도 되는 것은 화면의 글과 메뉴뿐이다. Resolved Unit 메뉴에 칸이 하나 늘고, 7절의 문구가 모든 액션에서 바뀐다. 키가 하는
일은 바뀌지 않는다.

## 4. 저장

**`action.casting` 안에 둔다** (2026-10-11, 소유자). `Constants.lua`의 `CASTING_FIELDS`에 불리언 하나를 더한다. `SanitizeAction`과
내보내기·가져오기는 이 표를 읽으므로 따라온다(`Sanitize.lua`, `DebindStorage/Export.lua`는 내보낼 때 `SanitizeAction`을 거친다).
메뉴는 `"casting.<이름>"` 열쇠만 주면 Resolved Unit 메뉴 안에서도 읽고 쓴다(`Menus/ActionMenuModel.lua`의 `CastingHolder`).

**Resolved Unit 줄 안(`conditions.units["@"]`)에 두지 않은 까닭.**

- 유닛 줄의 필드 표 `UNIT_CONDITION_FIELDS`는 모든 유닛 줄이 같이 쓴다. `focus` 줄 같은 데 이 값이 있어도 `SanitizeUnitRow`가
  지우지 않아, 막으려면 Resolved Unit 줄만 보는 예외가 든다.
- `UnitConditionRemembersAxis`는 모드 두 개를 뺀 모든 필드를 조건 축으로 센다. 이 값은 축이 아니다.

**옛 버전.** 이 이름을 모르는 버전이 공유 문자열을 받으면 `SanitizeAction`이 지운다. 그 액션은 옵션이 꺼진 것처럼 돌아, 보낸 쪽보다
좁게 실행된다.

## 5. 짓는 법

**바인딩을 새로 만들지 않는다.** 3-1의 바인딩들은 이미 평소처럼 쓰고 있으므로, 그 바인딩이 Resolved Unit 조건을 안 보게만 하면 된다.

**바꾸는 자리마다 옵션을 켠 액션에서만 갈라진다.** 3-7을 지키는 것이 이것이다. 옵션이 꺼진 액션은 아래의 어느 자리에서도 지금과
같은 길을 지난다. 순서(`MakeOrderRecord`)와 보안 쪽에는 새 입력이 없다. 저장된 값이 없는 액션은 `SanitizeAction`과 내보내기에서도
지금과 같다.

- **표시는 바인딩에 따로 둔다.** `FillBinding`이 옵션을 읽어 3-1의 바인딩에만 세운다. Resolved Unit 조건을 `conditions.units`에서
  지우면 안 된다. `MakeOrderRecord`와 `IsConditionalBinding`이 그 표를 읽으므로, 지우면 3-4가 깨지고 2026-09-15의 버그가 돌아온다.
  Hover Cast의 "Don't run while pointing"이 `skipsPointedUnit`을 `conditions` 밖에 두는 것과 같은 모양이다.
- **가르는 기준은 "바인딩이 평소처럼 쓰는가"이고, 그것은 실제로 나가는 유닛이 비어 있는가다.** `CastUnitOf(binding)`이 nil이나
  `""`인 바인딩이다. 버튼 속성과 레코드에 실리는 유닛이 이 값이다(`Rebuild/KeyRecords.lua`). Target에서 유닛을 고른 액션은 그 유닛이,
  Self Cast Key·Focus Cast Key를 누른 채 나나 주시 대상에게 쓰는 바인딩은 `player`·`focus`가 실리므로 저절로 빠진다. 두 키를
  Cast as usual로 둔 것은 비어 있어 들어온다(`GetBindingsForAction`의 `selfAim`·`focusAim`).
  `ResolvedUnitOf`가 `target`을 돌려주는지로 가르면 안 된다. Target에서 `target`을 고른 액션이 딸려 들어온다.
  바인딩 표의 `unit` 필드로 갈라도 안 된다. Target에서 `none`을 고른 액션은 그 필드가 nil인데(`FillBinding`이 `castsAtNone`을
  세우고 `unit`을 비운다), 실제로는 `"none"`으로 나간다(`CastUnitOf`). 표시를 세우는 자리가 `FillBinding`이라 바로 옆의
  `binding.unit`을 보기 쉬운데, 그러면 `none`이 딸려 들어온다.
- **`BuildUnitStates`는 그 표시가 있는 바인딩에서 Resolved Unit 줄만 건너뛴다.** `addAimed` 전체를 건너뛰면 안 된다. 부활 갈래의
  조건(`branchUnit`)도 `addAimed`를 지나가므로, 통째로 건너뛰면 "죽은 아군" 조건까지 사라진다.
- **보안 쪽은 바뀌지 않는다.** 레코드는 `binding.unitConditions`를 그대로 싣고(`Rebuild/KeyRecords.lua`의 `BuildKeyRecord`),
  거기에 Resolved Unit 줄이 안 접힐 뿐이다. 스니펫은 그대로다.
- **이슈 검사.** 3-5대로 액션 검사가 Resolved Unit 줄이 비었을 때 옵션이 적용되는 바인딩이 있는지 알아야 한다. 결과(OMIT, KEEP)는
  `BINDING_ISSUE_OUTCOMES`에서 코드마다 하나로 정해지므로, KEEP으로 돌리려면 새 코드를 두거나 검사하는 자리에서 갈라야 한다.

## 6. 바뀌는 것

**솔버.** 옵션이 적용된 바인딩은 상자가 넓어진다. 매크로의 `[]`가 하는 일과 같다. 솔버에 새 축은 없다. 그 키에서 아래 액션의
같은 키 누름 바인딩이 덮이지만, 닿지 않음 표시(`BINDING_ERROR_UNREACHABLE`, 순서 목록에서는 `ORDER_FLAG_UNREACHABLE` "Never runs")는
아래 액션의 바인딩이 모두 덮여야 붙는다(`IsUnreachableAction`).
아래 액션에 Self Cast Key·Focus Cast Key 바인딩이 남아 있으면, 그냥 누를 때는 절대 안 나가는데도 표시가 없다(3-4의 Smite).
표시가 붙는 것은 남는 바인딩이 없는 아래 액션이다. 꼬리(`GIVEBACK`, `COMMAND`)는 Self·Focus Cast Key 바인딩이 없어
(`GetBindingsForAction`의 `isTail`) 대개 그렇지만, Hover Cast를 따르므로 마우스를 올린 유닛에게 쓰는 바인딩이 남을 수 있다. 계정
설정에서 두 키를 끈 경우나 그 액션이 두 줄을 Off로 둔 경우도 같은 물음이다.

**키를 게임에 돌려주는 판단.** 판단 쪽은 바인딩마다 만든 레코드를 그대로 읽는다(`UpdateBindings.lua`가 레코드마다 `JudgeLoop.lua`의
`JudgmentEntryFor`를 부른다). `handing-the-rest-of-a-key-to-the-game.md` 8-2의 B9~B13(키 X에 `a`(Resolved Unit [있음])를 두고 그
아래에 `GIVEBACK`을 둔 경우, `a`는 Target 비움, Normal Cast 켬, Focus Cast Key는 기본값)에서 `a`에 옵션을 켜면 이렇게 바뀐다.

- 그냥 X를 누를 때 `a`가 늘 실행되므로 X는 늘 Debind가 잡고, `GIVEBACK`까지 내려가지 않는다. 솔버가 `GIVEBACK`에 표시를 붙인다.
- B11: X를 게임에 돌려주던 것이 Debind가 잡는 것으로 바뀐다. ALT-X는 지금처럼 주시 대상에게 쓴다.
- B12: 게임의 X 키 동작이 나가던 것이 `a`를 평소처럼 쓰는 것으로 바뀐다.
- B10: 그대로다. Focus Cast Key를 누른 채 주시 대상에게 쓰는 바인딩은 옵션이 적용되지 않는다.
- B13: 지금은 X와 ALT-X를 둘 다 게임에 돌려주어 게임의 X 키 동작이 나간다. 옵션을 켜면 X를 Debind가 잡으므로, Focus Cast Key 쪽에서
  실행될 것이 없는 ALT-X는 X를 따라가고 아무 일도 안 한다(`which-action-a-key-runs.md` S4의 "맨 키를 따른다").

**유닛 없이 나가는 길.** 옵션이 적용된 바인딩은 지금도 유닛 없이 나가는 바인딩이라 새로 여는 길이 없다.

## 7. 문구와 도움말

- **옵션 이름은 정하지 않았다.** `CASTING_AS_USUAL`("Cast on the usual target")이 Hover Cast 줄에 이미 있고, 소유자는 "usual
  target"이 라벨로 잘 안 읽힌다고 했다. 출처는 `debind-b0`(세션 ID `3742c479-f9bb-441f-9b57-301f78be8746`)가 2026-10-11에 `debind-34`에
  넘긴 인계문이다.
- **옵션 툴팁**은 3-6대로 쓴다.
- **`RESOLVED_TARGET_DESC` 둘째 문단**은 "조건이 안 맞으면 이 액션이 누름을 건너뛰고 다음 액션이 받는다, 현재 대상이면 Auto Self
  Cast도 차례가 없다"다. 옵션을 켠 액션에서는 틀린 말이 되므로, 문단이 옵션을 말하게 고친다.
- **새 문구는 유닛 없이 나간 시전이 어디에 떨어지는지 말하지 않는다.** "Auto Self Cast가 나에게 쓴다"도, "현재 대상에게 간다"도 쓰지
  않는다. 쓸 수 있는 것은 우리 쪽 일이다. 그 조건을 보지 않는다는 것, 그리고 Target을 비워 둔 액션처럼 유닛 없이 나간다는 것이다.
  0절과 같은 규칙이다(`targeting.md`의 작성 주석: "What the game does with it is not ours to say"). 지금 `RESOLVED_TARGET_DESC`가 Auto
  Self Cast를 이름으로 부르므로 다음에 쓰는 사람이 그쪽으로 가기 쉽다. 그 문단의 "Auto Self Cast도 차례가 없다"는 다른 이야기라
  남는다. 우리가 그 누름을 건너뛴다는 말이기 때문이다.
- **`MARK_TOOLTIP_CONDITIONAL`**("Runs only while the conditions set on it hold.")은 옵션을 켜고 Resolved Unit 조건만 건 액션에서
  맞지 않는다. 그 액션은 3-4대로 조건 있는 액션으로 표시되지만, 평소처럼 쓰는 경우에는 조건과 상관없이 실행된다.
- **액션 툴팁**은 Resolved Unit을 "Resolved Unit - 요약" 한 줄로 그린다(`ActionTooltip.lua`). 옵션이 켜졌다는 것은 그 줄에 붙인다.
  `casting` 값이지만 Cast Options 줄들 아래에 그리지 않는다.
- **도움말.** `setting-keys-up.md`의 "One key for a friend and an enemy"(액션 둘 처방)와 `targeting.md`(Resolved Unit이 어느 유닛에
  묻는지)를 다시 읽는다. `help-pages` 스킬을 따른다.
- 문구는 `writing-user-facing-text.md`를 따른다.

## 8. 매크로 텍스트로 바꾸기

Target에서 `none`을 고른 액션에 옵션을 켜고 Resolved Unit 조건을 걸었다면, 바꾸고 나면 그냥 누를 때 그 조건을 안 본다. 바꾸면
Target이 비고 Resolved Unit 줄은 그대로 남아(`MacroText.lua`의 `AimedUnitKeyForMacroText`, `ConvertToMacroText`), 옵션이 적용되기
시작하기 때문이다. **이것은 따로 다루지 않는다** (2026-10-11, 소유자: *"매크로본문과 우리 액션이 100% 동일함을 보장하지 않고 그게
불가능한데"*). 바꾸기는 처음부터 같은 동작을 약속하지 않는다. Target을 비워 둔 액션을 바꾸면 조합키와 Hover Cast가 하던 일을 잃는 것도
같은 판단이다(`ConvertToMacroText` 주석, 2026-09-23, 소유자).

## 9. 테스트

- **헤드리스.** `which-action-a-key-runs.md`의 S5에 3-3 표의 줄마다 한 줄씩 더하고, 각 줄이 `tests/eval_spec.lua`의 `§S5 #n`
  하나다. 순서(3-4)는 `orderupgrade_spec`·`keymap_spec`, 오류 표시와 OMIT/KEEP(3-5)은 `tests/issue_spec.lua`, 6절의 B10~B13은
  `judgmentloop_spec`, 저장(4절)은 `sanitize_spec`·`export_spec`가 든다.
- **3-7은 지금 있는 테스트가 지킨다.** 지금 있는 헤드리스 스펙은 한 줄도 고치지 않고 통과해야 한다. 고쳐야 통과하는 스펙이 나오면
  3-7이 깨진 것이고, 코드부터 의심한다. Target을 비워 둔 액션의 Resolved Unit 조건은 `eval_spec`, `issue_spec`, `judgmentloop_spec`의
  B9~B13이 이미 든다.
- **출력 골든도 움직이지 않아야 한다**(`tests/emit-golden.txt`, `tests/emit-shipped-golden.txt`). 다만 지금 픽스처의 Resolved Unit 행은
  둘 다 Target에서 `target`을 고른 액션이라(`tests/emit_fixture.lua`의 CTRL-F8, CTRL-F9) 이 옵션이 갈라지는 길에 닿지 않는다. 구현에
  앞서 Target을 비운 액션에 Resolved Unit 조건을 건 줄을 픽스처에 더하고, 골든을 그 커밋에서 따로 갱신한다. 옵션을 넣는 커밋은
  골든을 바꾸지 않는다.
- **`/debtest`가 닿는 것.** 누름마다 어느 바인딩이 이기고 어느 유닛에 나가는지.
- **원리상 못 닿는 것.** 유닛 없이 나간 시전이 어디에 떨어지는지. 게임이 정한다. `which-action-a-key-runs.md` §10과
  `matching-the-clients-cast-targeting.md` §4가 같은 말을 한다.

## 10. 정할 것

**만들지 말지.** 2절의 저울이다. 액션 하나를 아끼는 값과, "유닛을 지정하지 않고 평소처럼 쓰는 경우에는 Resolved Unit 조건이 없어진다"를
배우는 값을 단다.

## 11. 버린 안

- **Resolved Unit 조건을 보는 모든 바인딩 뒤에 대체 바인딩을 세우는 안** (이 문서의 첫 초안). 그 정의로는 Focus Cast Key를 누른 채
  주시 대상이 안 맞을 때 유닛 없이 쓰게 된다. 소유자: *"왜 기존 FCK, SCK의 동작을 바꾸는것이 이 선택에 포함되는거야?"*.
  처음 한 말("`[]`로 나간다")은 어느 키를 누를 때인지 말하지 않았고, 조합키까지 묶은 것은 초안의 해석이었다. 3-1이 대신한다.
- **Target에서 유닛을 고른 액션을 `[@focus,help][]` 꼴로 만드는 안.** 대상을 고른 사용자는 평소처럼 쓰기를 고르지 않았다(3-2).
  그 모양을 원하면 지금처럼 액션을 둘로 나눈다. 위 액션은 Target에서 Focus를 고르고 조건을 걸고, 아래 액션은 Target을 비운다.
  이 안을 버리면서, 초안의 구현이 그 액션을 만들 수 없었다는 것도 묻혔다. 그 액션은 그냥 누를 때의 바인딩 바로 뒤에 대체가 서야
  했는데, 그냥 누를 때의 바인딩은 목록의 `[1]`에 고정이고 키에 늘어놓을 때 목록을 뒤에서부터 읽어 늘 맨 마지막이 된다
  (`GetBindingsForAction`, `Debind.lua`의 `UnrollIntoTiers`). 다시 꺼낼 때는 목록 모양부터 바꿔야 한다.
- **Normal Cast를 끄고 Cast on pointed unit인 액션에 "마우스를 올렸다"만 남긴 대체 바인딩을 세우는 안.** 사용자는 마우스를 올린
  유닛에게 쓰기를 골랐다(3-2). 이 안대로라면 수식키 없는 좌클릭으로 적 개체창을 클릭해도 그 적이 대상으로 잡히지 않고 힐이 유닛
  없이 나갔다.
- **Self Cast Key·Focus Cast Key의 Cast as usual에서도 적용하지 않는 안.** 한때 "일부러 키를 하나 더 눌렀다"를 근거로 정했다가 되돌렸다.
  Cast as usual은 그 키를 신경 쓰지 말라는 값이고, Hover Cast의 Cast as usual을 Normal Cast로 본 것과 같은 눈으로 보면 같은 답이다.
  되돌리면서 툴팁이 한 문장이 됐다.
- **옵션이 아무 일도 안 하는 액션에서 메뉴를 잠그는 안.** 잠그면 Target을 먼저 비워야 옵션을 켤 수 있어, 사용자가 순서를 따라야 한다.
- **부활에서 옵션을 잠그는 안.** 3-3의 부활 문단.
- **Resolved Unit 줄 안에 저장하는 안.** 4절.
