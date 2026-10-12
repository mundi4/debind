# Resolved Unit 조건이 안 맞을 때 나에게 쓰는 옵션 (2026-10-12 계획)

> 상태: **동작은 소유자와 2026-10-12에 다시 정했다(3절). 코드와 문구는 3절과 5절대로 구현했다(저장 이름 `casting.fallbackToSelf`).**
> 2026-10-11의 옛 설계(`faaf87e`, "유닛 없이 나가는 바인딩에서 조건을 안 묻는다")는 2절의 까닭으로 버렸고 그 코드는 지웠다.
> 툴팁에서 소유자가 정하지 않은 두 문장(안 켰을 때의 동작, 게임의 Auto Self Cast와의 관계)은 비어 있다(7절). 도움말에 넣을지는 소유자가 정하지 않았고, 넣는다면 무엇을 쓸지를
> `setting-keys-up.md`와 `targeting.md` 머리 주석에 적어 두었다.
>
> 다시 쓴 세션: `debind-85` (세션 ID `9cd7550f-cb70-483d-af31-d3c6140fbb66`). 옛 설계는 `debind-34`가 처음 쓰고 `debind-be`가
> 소유자와 정한 내용으로 다시 쓰고 `debind-79`가 구현했다(`ed2ba22`, `81bbe11`, `faaf87e`). 그 검토 기록은 debind-notes의
> `reviewing-the-resolved-unit-fallback-2026-10-11.md`에 있다. 오늘의 논의와 그 문구 초안은 `falling-back-to-yourself.md`에 있다.

## 0. 이 문서에서 쓰는 말

**평소 대상.** 유닛을 지정하지 않고 쓰는 것. 매크로의 `[]`이고, Target을 비워 둔 액션을 그냥 누를 때와 같다. 어디에 떨어지는지는
게임이 정하고 우리는 말하지 않는다(`targeting.md`의 작성 주석 "What the game does with it is not ours to say").

**말한 유닛.** 사용자가 그 시전이 갈 유닛을 직접 고른 것. Target에서 고른 유닛, 그리고 Self·Focus Cast Key 줄을 "나에게 / 주시
대상에게"로 두고 그 키를 쥔 누름의 나·주시 대상. 가리킨 유닛과 평소 대상은 말한 유닛이 아니다. 정의와 까닭은
`deciding-what-a-press-runs.md` §1이다.

**폴백.** 이 문서가 만들자는 체크박스. Resolved Unit 메뉴 안에 둔다. 켜면 말하지 않은 유닛이 Resolved Unit 조건에 안 맞을 때 그
누름이 **나에게** 간다.

## 1. 왜

디스코드의 한 사용자가 `/cast [@mouseover,help,nodead][] Lesser Heal`을 Debind 액션으로 옮기는 법을 물었다. 지금은 액션 둘로
옮긴다(도움말 "One key for a friend and an enemy", `setting-keys-up.md`). 액션 하나로 하려고 Hover Cast를 가리킨 유닛에게로 두고
Resolved Unit에 [우호][생존]을 걸면, 그 조건이 그냥 누를 때는 현재 대상을 봐서 적을 잡고 있으면 누름이 건너뛰어지고, 매크로의
`[]`에 해당하는 것이 안 나간다.

**이 옵션의 목적은 우호 주문이 그 자리에서 나에게 떨어질 수 있게 하는 것이다** (2026-10-11, 2026-10-12, 소유자). 매크로 사용자가
`[]` 대신 `[@player]`를 붙이는 그 자리다.

## 2. 접은 안 둘

### 2-1. 2026-09-15: 그냥 누를 때 `"@"`를 안 보는 규칙

`0-DIARY.md` 2026-09-15의 두 절. 한때 Target을 비워 둔 액션은 그냥 누를 때 Resolved Unit 조건을 안 봤고, 소유자가 되돌렸다. 조건이
사라지면 순서와 표시가 틀리고, `@.harm` 공격 뒤에 `@.help` 치유를 둔 키에서 우호 대상을 잡고 눌러도 공격이 헛나간다. 모든 액션의
규칙을 바꾸는 안이었다. 이번 것은 사용자가 액션마다 켜는 옵션이라, 켜지 않은 액션은 지금과 같다.

### 2-2. 2026-10-11: 유닛 없이 나가는 바인딩에서 `"@"`를 안 묻는 옵션 (`faaf87e`)

옵션을 켜면 유닛을 싣지 않고 나가는 바인딩(그냥 누름, Hover Cast 평소 대상의 가리킨 누름, Self·Focus Cast Key 평소 대상의 누름)에서
Resolved Unit 조건을 묻지 않는다. 그 누름은 `[]`로 나간다. 저장은 `casting.usualIgnoresResolvedUnit`, 바인딩 표시는
`ignoresResolvedUnit`.

**버린 까닭 (2026-10-12, 소유자, Penance).** 수양 사제의 Penance는 아군이면 치유, 적이면 피해다. 사용자가 "이 키는 치유만"으로
[우호]를 걸었는데 그냥 누를 때 `"@"`를 빼면, 적을 잡고 누른 누름이 `[]`로 나가서 그 적을 때린다. 적도 그 주문의 유효한 대상이라
Auto Self Cast가 받지 않는다. 매크로의 `[]`도 같은 구멍이고, 그래서 Penance 쓰는 사람은 `[]` 대신 `[@player]`를 쓴다. *"틀리지 않게
하려면 [@player] 바인딩 쌍둥이를 추가하는 방식이 되어야할 것 같아."*

같은 날 그 전에 드러난 것: 이 설계는 이름을 지을 수 없었다. 목적은 "나에게 떨어지게"인데 우리는 주문이 우호인지 적대인지도,
나에게 쓸 수 있는지도 모르고, Cast Options의 Auto Self Cast 줄은 CVar를 누르는 동안 켜고 끄는 것뿐이라 self cast를 보장하지
못한다. 그래서 이름이 메커니즘("current target에서는 안 묻는다")이 됐고, 조건 범위를 조정하는 범용 기능처럼 읽혔다. 에이전트 여섯의
이름이 전부 걸린 기록은 `falling-back-to-yourself.md` 1절이다.

## 3. 정한 동작 (2026-10-12, 소유자)

### 3-1. 규칙

**옵션을 켜면, 말하지 않은 유닛이 Resolved Unit 조건에 안 맞을 때 그 누름은 나에게 간다.** `player`를 실은 바인딩이 그 자리에
선다. 다른 조건은 그대로 본다. **Resolved Unit 조건은 나에게 다시 묻지 않는다.**

- **왜 `[]`가 아니라 나에게인가.** 유닛이 `player`로 고정되니 적에게 갈 수 없고, 주문이 우호인지 적대인지 우리가 몰라도 된다. 그
  유닛에 그 주문을 쓸 수 있는지는 여전히 모르지만, 그것은 Self Cast Key 줄의 "Cast on yourself"와 같은 약속이고 같은 한계다.
- **왜 조건을 나에게 다시 묻지 않는가.** 사용자가 건 조건은 겨누던 유닛을 설명한 것이지 자기를 설명한 것이 아니다. [우호][탱커]를
  건 치유의 폴백은 내가 탱커가 아니어도 나에게 간다. 피해 주문에 [적대]를 걸고 켜면 나에게 나가서 게임이 거부하고 그 누름은
  삼켜진다. 그 조합을 고른 것은 사용자다.
- **왜 말한 유닛에서는 안 서는가.** 말한 유닛은 머문다(`deciding-what-a-press-runs.md` §2 규칙 2). Target에서 고른 유닛은 액션
  전체에 대해 말한 것이고, 쥔 Self·Focus Cast Key가 보내는 나·주시 대상은 그 누름에 대해 말한 것이다. 그 유닛이 안 맞으면 그
  누름은 이 액션에서 끝나고 다음 액션의 차례다. 클라이언트는 Focus Cast Key를 쥔 시전이 주시 대상에 안 맞으면 Auto Self Cast로
  나에게 보내지만(2026-10-12 측정) 우리는 따르지 않는다. *"fck는 hc와 달라. 사용자가 alt키를 눌러서 의도를 분명히 했다는것이
  다르지."* 가리킨 것은 마우스가 거기 있었을 뿐이다.

### 3-2. 폴백이 서는 자리

| 누름 | 서는 자리 |
|---|---|
| 그냥 누름 (Normal Cast 켬) | 평소 대상이 안 맞은 뒤 |
| 가리킨 누름, Hover Cast 가리킨 유닛에게 | 가리킨 유닛이 안 맞고 평소 대상도 안 맞은 뒤. Normal Cast가 꺼져 있으면 가리킨 유닛이 안 맞은 뒤 |
| 가리킨 누름, Hover Cast 평소 대상 | 평소 대상이 안 맞은 뒤. Normal Cast가 꺼져 있어도 같다 |
| 가리킨 누름, Hover Cast 건너뜀 | 서지 않는다. 그 누름에 이 액션이 없다 |
| Self·Focus Cast Key를 쥔 누름, 그 줄이 평소 대상 | 평소 대상이 안 맞은 뒤 |
| Self·Focus Cast Key를 쥔 누름, 그 줄이 나에게·주시 대상에게 | **서지 않는다.** 말한 유닛 |
| Target을 고른 액션 (`Always Ask` 포함) | **서지 않는다.** 말한 유닛 |
| 개체창 클릭 | 가리킨 누름과 같다. 수식키 없는 왼클릭·오른클릭도 같다 |

**가리킨 유닛이 안 맞으면 평소 대상을 먼저 시도한다.** `[@mouseover,help,nodead][]`에서 가리킨 유닛이 안 맞으면 `[]`가 현재 대상을
본다. 폴백이 hover 쌍둥이 바로 뒤에 서면 그 차례가 없어진다. 그래서 폴백은 그 층에서 이 액션의 말하지 않은 바인딩 **맨 뒤**에 선다.

**타입으로 가르는 예외는 없다** (2026-10-11, 소유자). 주문이 아닌 타입도 같다. 유닛을 못 싣는 타입(매크로, 탈것)은 `player`를 실어
주고 쓰는지는 그 액션의 몫이다. 꼬리(`GIVEBACK`, `COMMAND`)는 유닛을 싣지 않으므로 꼬리의 폴백은 꼬리 자신이다(`"@"`가 안 맞아도
꼬리가 이긴다). **부활은 폴백이 없다.** 아무도 자기를 부활시키지 않아서 부활에 self 단이 없는 것(`GetBindingsForAction`)과 같은
까닭이다.

### 3-3. 액션 설정마다 (스펙 #73~94의 요약)

| 액션 | 그냥 누를 때 | 가리키고 누를 때 | Self·Focus Cast Key를 쥔 채 |
|---|---|---|---|
| Target 비움, Normal Cast 켬, Hover Cast 평소 대상 | 안 맞으면 나에게 | 안 맞으면 나에게 | 그 줄이 평소 대상이면 안 맞을 때 나에게. 나에게·주시 대상에게면 지금 그대로(건너뜀) |
| Target 비움, Normal Cast 켬, Hover Cast 가리킨 유닛에게 | 안 맞으면 나에게 | 그 유닛이 맞으면 그 유닛에게, 아니면 평소 대상, 아니면 나에게 | 같음 |
| Target 비움, Normal Cast 켬, Hover Cast 건너뜀 | 안 맞으면 나에게 | 지금처럼 건너뜀 | 같음 |
| Target 비움, Normal Cast 끔, Hover Cast 평소 대상 | 지금처럼 건너뜀 | 안 맞으면 나에게 | 같음 |
| Target 비움, Normal Cast 끔, Hover Cast 가리킨 유닛에게 | 지금처럼 건너뜀 | 그 유닛이 맞으면 그 유닛에게, 아니면 나에게 | 같음 |
| Target에서 무엇이든 고름 | 지금 그대로 | 지금 그대로 | 지금 그대로 |
| 수식키 없는 좌클릭·우클릭 | (없음) | 그 유닛이 맞으면 그 유닛에게, 아니면 나에게 | (없음) |

"안 맞으면"은 Resolved Unit 조건만이다. 다른 유닛 조건과 그 밖의 조건이 안 맞으면 지금처럼 건너뛴다.

### 3-4. 실행 순서에서는 조건으로 센다

소유자: *"조건으로 세어야하지"* (2026-10-11). 옵션을 켜든 말든 Resolved Unit 조건이 걸린 액션은 조건 있는 액션으로 선다.

**그 값.** 조건 있는 액션은 레이어보다 먼저 정렬된다(`Ordering.lua`). 계정 레이어에 Flash Heal(Resolved Unit [우호], 폴백 켬)을,
캐릭터 레이어에 조건 없는 Smite를 같은 키에 두면, Flash Heal이 앞에 서고 그냥 누를 때는 늘 실행되므로(안 맞으면 나에게) Smite는
그냥 눌러서는 절대 안 나간다. **그런데 화면에는 아무 표시도 없다.** 닿지 않음 표시(`IsUnreachableAction`)는 그 액션의 바인딩이
모두 덮였을 때만 붙는데, Smite의 Focus Cast Key 바인딩은 Flash Heal의 focus 쌍둥이(주시 대상에 [우호]를 묻고 폴백 없음)가 덮지
못한다. 이 "표시 없는 잃음"이 순서에서 세기로 한 값이다.

### 3-5. Resolved Unit에 반응을 하나도 안 고른 액션

지금은 액션 검사가 이런 줄을 보면 바인딩을 통째로 뺀다(`Issues.lua`, OMIT). 폴백을 켠 액션에서는 빼지 않는다. 폴백이 나갈 수
있어서다. 나머지 바인딩은 지금 있는 길로 걸러진다. **오류는 표시한다**(소유자: *"사용자가 애당초 이걸 의도했을거라고 생각하진
않거든"*). 2026-10-11에 정한 그대로다.

### 3-6. 메뉴

**옵션은 Resolved Unit 메뉴 안, 조건 줄 아래에 둔다** (2026-10-12, 소유자: *"애당초 내가 조건을 걸었고(exists,help,nodead) 그
조건이(그 조건들만) 특정 상황에서 무시된다면 그 조건이 보이는곳에 이 옵션이 보이는게 맞지 않냐"*). 날리는 것이 `"@"` 조건뿐이라
"여기 조건을"이라는 지시가 그 자리에서만 선다. 아무 일도 안 하는 액션(Target을 고른 액션)에서도 잠그지 않고 그대로 보인다
(2026-10-11, 소유자: *"그대로 노출"*). 잠그면 사용자가 정해진 순서를 따라야 한다.

### 3-7. 옵션을 켠 액션이 없는 키는 지금과 똑같이 동작한다

**한 키의 액션 가운데 옵션을 켠 것이 하나도 없으면, 그 키는 이 옵션이 생기기 전과 100% 같게 동작해야 한다** (2026-10-11, 소유자).
누름마다 어느 액션이 어느 유닛에 나가는지, 키를 잡는지 돌려주는지, 실행 순서, 이슈와 그 결과가 모두 그대로다. 바뀌어도 되는 것은
화면의 글과 메뉴뿐이다.

## 4. 저장

**`action.casting` 안의 불리언 하나** (2026-10-11, 소유자). 이름은 가칭 `fallbackToSelf`. `Constants.lua`의 `CASTING_FIELDS`에
더하면 `SanitizeAction`과 내보내기·가져오기가 따라온다. 메뉴는 `"casting.<이름>"` 열쇠로 Resolved Unit 메뉴 안에서도 읽고 쓴다
(`Menus/ActionMenuModel.lua`의 `CastingHolder`).

**`usualIgnoresResolvedUnit`은 없앤다.** 태그에 안 들어갔으니 마이그레이션 없이 `CASTING_FIELDS`에서 빼고, `SanitizeAction`이 모르는
이름을 버리는 길로 지워진다. 같은 이름을 그대로 쓰면 옛 뜻으로 저장된 값이 새 뜻으로 읽히므로 이름을 바꾼다.

Resolved Unit 줄 안(`conditions.units["@"]`)에 두지 않는 까닭은 2026-10-11 그대로다. `UNIT_CONDITION_FIELDS`는 모든 유닛 줄이 같이
쓰고, `UnitConditionRemembersAxis`는 모드 둘을 뺀 모든 필드를 조건 축으로 센다.

## 5. 짓는 법

**바인딩 하나를 더 만든다.** 옛 설계와 다른 점이 이것이다. 옛 설계는 있는 바인딩의 조건을 뺐고, 이 설계는 `player`를 실은
바인딩을 말하지 않은 바인딩 뒤에 세운다.

- **폴백 바인딩.** `FillBinding`이 만든다. 유닛은 `player`, `castModifier`는 그 층의 것, `unitConditions`에서 Resolved Unit 줄을
  뺀 것(`BuildUnitStates`에서 `"@"`만 건너뛴다. `addAimed` 전체를 건너뛰면 부활 갈래의 조건까지 사라지는데, 부활에는 폴백이 없으니
  여기서는 닿지 않는다). 값이 얹은 [`H` 있음](Normal Cast 끔)과 [`H` 없음](`"skip"`)은 그대로 받는다. `conditions.units`에서
  `"@"`를 지우면 안 된다. `MakeOrderRecord`와 `IsConditionalBinding`이 그 표를 읽으므로 3-4가 깨진다.
- **층마다 하나.** 3층은 원본 뒤(원본이 없으면 hover 쌍둥이 뒤). 1·2층은 그 줄이 평소 대상인 쌍둥이 뒤. 나에게·주시 대상에게로
  나가는 쌍둥이 뒤에는 없다. Target을 고른 액션에는 없다.
- **전문화별 주문 항목도 같이 딸린다.** 스펙 주문 액션은 바인딩마다 `known`을 묻는 파생 바인딩이 딸리고(`fillKnown`), 폴백에도
  같은 항목이 같은 방식으로 딸린다. 폴백의 유닛과 조건으로 `fillKnown`을 한 번 더 부르는 것이다. 부활 갈래는 닿지 않는다(3-2,
  부활에는 폴백이 없다).
- **꼬리의 폴백은 `"@"` 줄만 뺀 꼬리 바인딩 하나다.** `FillBinding`이 꼬리를 BLOCK으로 바꾸고 유닛을 비우므로 `player`를 실을 데가
  없고, 서는 자리와 조건만 폴백의 것이다. 그래서 `"@"`가 안 맞아도 꼬리가 이긴다(스펙 #88).
- **가르는 기준은 "그 바인딩이 말하지 않은 유닛으로 나가는가"다.** `CastUnitOf(binding)`이 nil이나 `""`인 바인딩(평소 대상), 그리고
  `pointedUnit`을 실은 hover 쌍둥이. Target을 고른 액션은 `ActionHasPickedUnit`으로 빠진다. `none`은 고른 대상이다(`castsAtNone`).
- **목록 모양.** `GetBindingsForAction`은 `list[1]`에 원본을 두고 뒤에서부터 채우며, `UnrollIntoTiers`가 목록을 끝에서부터 걸어
  나중 항목이 같은 층 앞에 선다. 원본은 늘 그 액션의 맨 뒤다. **폴백은 원본보다 뒤에 서야 하므로 이 걷기로는 자리가 없다**
  (2026-10-11 11절이 적어 둔 걸림). `list[1]`을 원본으로 읽는 곳은 `Debind.lua`의 `BuildKeyMap` 하나다(`Solver.lua`와 `Issues.lua`는
  목록 전체를 건다. 2026-10-12, 구현 세션 `debind-7f`가 확인). 그래서 `list[1]`은 그대로 두고, 폴백 바인딩에 표시(`fallback = true`)를 두어 `UnrollIntoTiers`가 **층마다 보통
  항목을 끝에서부터 건 다음 폴백 항목을 건다.** 솔버와 판단은 `UnrollIntoTiers`가 편 순서를 읽으므로 그대로 따라온다.
- **보안 쪽은 바뀌지 않는다.** 폴백은 `player`를 실은 보통 바인딩이라 레코드와 스니펫에 새 입력이 없다.
- **이슈 검사.** 3-5대로 Resolved Unit 줄이 비었을 때 폴백이 서는지 알아야 한다. 지금 `Issues.lua`가 `ignoresResolvedUnit`을 보는
  자리(`list[i].ignoresResolvedUnit and BindingStands(list[i])`)를 폴백 바인딩을 보는 것으로 바꾼다.
- **지우는 것.** `FillBinding`의 `ignoresResolvedUnit`, `UsualIgnoresResolvedUnit`, `Conditions/Units.lua`의 그 분기, `Constants.lua`의
  필드와 주석, `Sanitize.lua`의 줄, 메뉴 셋(`ActionMenuItems`, `ActionMenuModel`, `ActionMenuNodes`)의 그 열쇠, `DebindUI.lua`,
  `enUS.lua`의 문구 여섯 자리. 헤드리스 열 개와 `DebindDev/Tests/Menus.lua`가 그 이름을 쓴다(9절).

## 6. 바뀌는 것

**솔버.** 폴백 바인딩은 `"@"` 줄이 없는 상자라 그 층에서 아래 액션의 같은 누름 바인딩을 덮는다. 새 축은 없다. 닿지 않음 표시는
아래 액션의 바인딩이 모두 덮여야 붙는다(3-4).

**키를 게임에 돌려주는 판단.** `handing-the-rest-of-a-key-to-the-game.md` 8-2의 B9~B13(키 X에 `a`(Resolved Unit [있음])를 두고 그
아래에 `GIVEBACK`, `a`는 Target 비움, Normal Cast 켬)에서 `a`에 폴백을 켜면: 그냥 X는 `a`가 늘 실행되므로(안 맞으면 나에게) X는 늘
Debind가 잡고 `GIVEBACK`까지 안 내려간다. B11·B12가 그렇게 바뀌고, B10(Focus Cast Key를 쥔 채 주시 대상에게)은 그대로, B13은 X를
Debind가 잡으므로 ALT-X는 X를 따라가 아무 일도 안 한다.

**나가는 길.** 폴백은 `player`를 실은 시전이라 self 쌍둥이가 이미 쓰는 길이고 새로 여는 길이 없다.

## 7. 문구와 도움말

- **자리는 Resolved Unit 메뉴 안.** 느낌은 "위 조건이 맞지 않을 때 나에게 시전"(소유자). 창에 이미 있는 말 "Cast on yourself"로
  된다. 읽는 사람 시험(페르소나 둘 × 라벨만/툴팁, 시나리오 열 개)은 `falling-back-to-yourself.md` 4절이고, 그 문서는 `.zzz`에
  있어 클라우드 세션은 못 읽는다. 시험한 초안은 이것이고, **이것을 그대로 쓴다**(아래의 "고칠 것"을 반영해서). 소유자가 정하지
  않은 두 문장은 비워 둔다.
  - 라벨(`RESOLVED_TARGET_USUAL`을 대신하는 키): `Otherwise, cast on yourself`
  - 툴팁: `When the unit a press would use this action on does not meet these conditions, the press casts on you instead, with
    these conditions left unasked. A press with the Self Cast Key or Focus Cast Key held stays on you or your focus, and an action
    with a unit picked under Target stays on that unit: there, a unit that does not fit still sits the press out.`
  - **둘째 문장은 시험한 그대로 쓰면 틀린다** (2026-10-12, `debind-7f`가 짚음). 시전 키 줄을 `Cast on the usual target`으로 두면
    쥔 누름도 폴백이 서는데(스펙 #76), 문장은 쥔 누름이 다 머문다고 읽힌다. 창의 동사("sends this action to you")로 좁힌다:
    `A press the Self Cast Key or the Focus Cast Key sends to you or your focus stays there, and an action with a unit picked under
    Target stays on that unit: there, a unit that does not fit still sits the press out, and the next action on the key takes it.`
  - 시험 결과: 툴팁까지 받은 둘은 열 시나리오 중 힐러 10, 캐주얼 7(틀림 0)이었고, 라벨만 받은 둘은 쥔 키와 Target을 고른 액션에서
    나에게 간다고 봤다. 넷 다 켜는 의도("버려질 누름이 셀프 치유가 되게")를 같게 적었다.
- **툴팁은 두 문장이다.** 안 맞으면 나에게 간다는 것, 그리고 유닛을 고른 자리(Target, 쥔 Self·Focus Cast Key)는 거기 머문다는 것.
  둘째는 예외가 아니라 창의 다른 줄이 이미 하는 약속을 한 번 더 가리키는 것이다. 시험에서 라벨만 받은 둘은 쥔 키에서도 나에게
  간다고 봤고 툴팁의 둘째 문장이 둘 다 고쳤다.
- **고칠 것**(시험에서 걸린 것): "안 맞거나 없으면"; "left unasked"는 "without checking them on you"로; "sits the press out"
  뒤에 `CASTING_SKIP_DESC`의 "the next action on the key takes it". 안 켰을 때의 동작 한 문장과 게임의 Auto Self Cast와의 관계
  한 문장은 소유자가 정한다. 후자는 "게임의 Auto Self Cast는 그대로"까지만 말할 수 있다.
- **`RESOLVED_TARGET_DESC` 둘째 문단**("조건이 안 맞으면 건너뛰고 다음 액션이 받는다, 현재 대상이면 Auto Self Cast도 차례가 없다")은
  옵션을 켠 액션에서 틀리므로 옵션을 말하게 고친다. "Auto Self Cast도 차례가 없다"는 우리가 그 누름을 건너뛴다는 말이라 남는다.
- **새 문구는 시전이 어디에 떨어지는지 말하지 않는다.** `player`를 실어 보낸다는 것까지가 우리 일이다. 나에게 쓸 수 있는 주문인지는
  말하지 않는다. `SELF_CAST_KEY_DESC`의 주석이 같은 한계를 적고 있다.
- **`MARK_TOOLTIP_CONDITIONAL`**("Runs only while the conditions set on it hold.")은 폴백을 켜고 Resolved Unit 조건만 건 액션에서
  맞지 않는다. 그 액션은 조건 있는 액션으로 표시되지만 말하지 않은 유닛에서는 조건과 상관없이 나간다.
- **액션 툴팁**은 Resolved Unit 줄에 폴백이 켜졌다는 것을 붙인다. `casting` 값이지만 Cast Options 줄 아래에 그리지 않는다.
- **도움말은 이 작업에 든다.** `setting-keys-up.md`의 "One key for a friend and an enemy"(액션 둘 처방)에 폴백 하나로 되는 길과
  매크로 타입으로 붙이는 길을 더한다. `targeting.md`는 Resolved Unit이 어느 유닛에 묻는지와 폴백. `help-pages` 스킬을 따르고, 그
  스킬이 말하는 대로 어느 페이지를 어떻게 고칠지 먼저 소유자에게 묻는다.
- 문구는 `writing-user-facing-text.md`를 따른다. 이름 다섯 개가 전부 걸린 옛 초안은 돌아갈 일이 없어 옮기지 않았다.

## 8. 매크로 텍스트로 바꾸기

Target에서 `none`을 고른 액션에 폴백을 켜고 Resolved Unit 조건을 걸었다면, 바꾸고 나면 Target이 비어 폴백이 서기 시작한다.
**따로 다루지 않는다** (2026-10-11, 소유자: *"매크로본문과 우리 액션이 100% 동일함을 보장하지 않고 그게 불가능한데"*). 바꾸기는
처음부터 같은 동작을 약속하지 않는다.

## 9. 테스트

- **헤드리스.** `deciding-what-a-press-runs.md` §6 #73~94가 한 줄에 `tests/eval_spec.lua`의 테스트 하나다. #73~89는 정답이 바뀌는
  줄이라 기존 테스트를 고치고, #90~94는 새 줄이다. 순서(3-4)는 `keymap_spec`, 오류 표시와 OMIT/KEEP(3-5)은 `issue_spec`, 6절의
  B10~B13은 `judgmentloop_spec`, 저장(4절)은 `sanitize_spec`·`export_spec`·`import_spec`, 메뉴는 `actionmenutree_spec`, 툴팁은
  `display_spec`, 부활에 폴백이 없는 것은 `resurrect_spec`. 지금 그 열 개가 `usualIgnoresResolvedUnit`을 쓴다.
  **새 줄은 고치기 전 코드에서 빨간 것을 보고 넘긴다.**
- **3-7은 지금 있는 테스트가 지킨다.** 옵션과 무관한 헤드리스 스펙은 한 줄도 고치지 않고 통과해야 한다. 고쳐야 통과하는 스펙이
  나오면 3-7이 깨진 것이고 코드부터 의심한다.
- **출력 골든도 움직이지 않아야 한다**(`tests/emit-golden.txt`, `tests/emit-shipped-golden.txt`). 픽스처의 CTRL-SHIFT-F8부터
  CTRL-SHIFT-F10까지가 폴백이 설 수 있는 자리에 닿는 줄이고 옵션은 켜지 않았다.
- **`/debtest`.** `DebindDev/Tests/Menus.lua`의 그 케이스가 새 이름으로 바뀐다. 누름마다 어느 바인딩이 이기고 어느 유닛에 나가는지는
  키트가 든다.
- **원리상 못 닿는 것.** 나에게 보낸 시전을 게임이 받는지(나에게 쓸 수 없는 주문). 그리고 Penance 같은 주문의 실제 동작. 둘 다
  게임이 정한다.

## 10. 만들기로 한 것

**만든다** (2026-10-11, 소유자). 2-2의 설계를 버리고 3절로 다시 만드는 것은 2026-10-12에 정했다.

## 11. 버린 안

- **유닛 없이 나가는 바인딩에서 `"@"`를 안 묻는 안** (2-2, `faaf87e`). Penance.
- **Resolved Unit 조건을 보는 모든 바인딩 뒤에 대체 바인딩을 세우는 안** (첫 초안). Focus Cast Key를 누른 채 주시 대상이 안 맞을 때
  유닛 없이 쓰게 된다. 소유자: *"왜 기존 FCK, SCK의 동작을 바꾸는것이 이 선택에 포함되는거야?"*. 지금 설계는 말한 유닛 뒤에는 안
  세우므로 그 물음이 다시 서지 않는다.
- **Target에서 유닛을 고른 액션을 `[@focus,help][]` 꼴로 만드는 안.** 대상을 고른 사용자는 폴백을 고르지 않았다(말한 유닛). 그
  모양을 원하면 액션을 둘로 나눈다.
- **Hover Cast 줄의 값으로 좁히는 안** (2026-10-12). "가리킨 유닛이 안 맞으면 평소 대상"을 Hover Cast 값 하나로. 소유자: *"예를
  hovercast 로 뒀을뿐 mouseover대신 focus를 넣어도 같아"*. 한 유닛에 묶은 것이라 버렸다.
- **Cast Options의 Auto Self Cast 줄 아래로 옮기고 "Auto Self Cast에게 차례를 준다"로 이름 짓는 안** (2026-10-12). 그 줄은 CVar를
  켜고 끄는 것뿐이라 self cast를 보장하지 못하고, 날리는 조건이 `"@"`뿐이라 "여기 조건을"이 서는 자리는 조건 메뉴다.
- **폴백이 조건을 나에게 다시 묻는 안** (2026-10-12). [우호][탱커]를 건 치유에서 내가 탱커가 아니면 막힌다. 조건은 겨누던 유닛을
  설명한 것이다.
- **쥔 Focus Cast Key 누름에서도 폴백을 세우는 안** (2026-10-12). 클라이언트가 그렇게 하지만(Auto Self Cast), 쥔 키는 의도를 분명히
  한 것이고 FCK를 쓰는 사람이 드물어 게임이 길러 놓은 예상도 약하다. 어느 쪽이 맞고 틀리다가 아니라 사용자가 예상하는 결과로 갈리는
  것이고, 예상은 라벨이 만든다.
- **옵션이 아무 일도 안 하는 액션에서 메뉴를 잠그는 안.** 3-6.
- **부활에서 옵션을 잠그는 안** (2026-10-11). 옛 설계에서는 부활도 다른 액션과 같았다. 새 설계에서는 부활에 폴백이 없고(3-2), 그래서
  잠글 것도 없다. 켜도 아무 일도 안 하는 것은 Target을 고른 액션과 같은 모양이다.
- **Resolved Unit 줄 안에 저장하는 안.** 4절.
- **액션 둘, 매크로 타입, 사본 추가 버튼, 줄마다 조건** (2026-10-12, 대안 넓히기). 액션 둘은 지금 도움말이고 줄이 두 배다. 매크로
  타입은 `[@mouseover,help,nodead][@player]`를 그대로 붙이는 길이고 새 기능 없이 되지만 Debind의 유닛과 순서를 잃는다. 도움말이
  말해 줄 길이고 옵션을 대신하지는 않는다. 사본 추가 버튼은 액션 둘과 같다. 줄마다 조건은 이 한 사례에 비해 UI가 너무 크다.
