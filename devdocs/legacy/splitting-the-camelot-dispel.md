# 카멜롯의 해제를 두 타입으로 나누기 (2026-09-27 시작)

> 상태: **구현했다 (2026-09-29).** 모양은 1절(2026-09-27), 리테일 취급과 3절의 표시 규칙과 항목 목록은
> 2026-09-29에 소유자와 정했다.
>
> 쓴 세션: `debind-79`, 세션 ID `5a7f79cc-6b09-49ea-a2d4-a64a184c451a`.

2026-09-25에 카멜롯 주문표를 채우면서 해제 주문이 둘 이상인 직업은 해제를 비워 두었다. 액션은 주문
하나를 시전하는데 저주와 독 중 무엇을 뜻했는지 모른다는 이유였다. 그런데 카멜롯에서는 마법사를 뺀
전부가 둘이라, 해제 액션은 사실상 마법사만의 것이 되어 있었다.

## 1. 모양 (2026-09-27, 소유자)

**카멜롯에서 해제는 두 타입이다.**

| 타입 | 푸는 것 |
|---|---|
| `dispel` | 질병, 저주 |
| `dispel2` | 마법, 독 |

**묶음이 이렇게 된 이유는 한 묶음 안에 종류 둘을 가진 직업이 없어서다.** 드루이드(저주, 독), 사제(질병,
마법), 주술사(질병, 독)는 두 종류가 한 묶음씩 갈리고, 마법사는 저주 하나다. 성기사는 Cleanse가 셋을
다 풀어 두 타입이 같은 주문이 되는데, 어느 쪽에서도 틀린 주문이 아니다.

**사용자에게는 이쪽이 오히려 낫다** (소유자). 힐러를 여럿 키우는 사람은 "저주·질병 키"와 "독·마법 키"로
생각하고, 어느 캐릭터에서든 같은 약화 효과에 같은 키를 누른다. 계정 층에 한 번 거는 이 애드온의 쓰임
그대로다.

**`dispel`이 질병·저주인 이유는 마법사다.** 지금 카멜롯에서 해제 액션이 도는 직업은 마법사뿐이고
그 주문(Remove Lesser Curse)이 이 묶음이다. 이미 걸린 액션이 뜻을 안 바꾸므로 옮길 것이 없다.

**리테일에서는 두 타입이 완전히 같다** (2026-09-29, 소유자). 전문화마다 해제가 하나이고 그 하나가 여러
종류를 푼다. 리테일 주문표는 두 타입에 같은 목록을 적는다(`SpecSpells_Mainline.lua`의 `SetDispel`). 없는
칸을 다른 칸으로 대신 읽는 분기는 두지 않았다. 선택 창에는 둘 다 서고, 리테일에서는 이름도 설명도 같다. 두
타입의 이름은 클라이언트마다 다르다(카멜롯은 약화 효과 종류로 부른다, 4절 로케일). 2절 표의 카멜롯 성기사도
두 타입이 같은 주문이다.

### 접은 안

다툰 자리는 `0-DIARY.md`의 "camelot의 해제 둘" 절에 있다. 여기는 다시 올라오지 않게 이유만 둔다.

- **직업 층에서 주문으로 덮는다.** 해제 액션은 계정 층에 걸려고 있는 것이다. 마법사 말고는 전부 덮어야
  하면 그 직업들에게 이 액션은 없는 것과 같다.
- **액션 하나에 종류(저주, 독, 질병, 마법)를 고르는 설정을 붙인다.** 계정 층 액션의 설정은 모든 캐릭터에
  가고, 어느 종류를 골라도 몇 직업에선 키가 죽는다.
- **액션 안에 직업마다 주문을 고르는 값을 둔다.** 마법사 말고는 전부 골라야 하고, 고르고 나도 나머지
  해제는 따로 걸어야 해서 각 직업의 절반만 덮는다.
- **첫째 해제, 둘째 해제.** 직업마다 무엇이 첫째인지를 우리가 정하는 것이라 뜻이 없다. 지금 모양은
  묶음이 약화 효과의 종류라서 사용자가 읽을 수 있는 뜻이 있다.
- **누를 때 대상의 약화 효과 종류를 재서 고른다.** 제한 환경은 전투 중에 그 값을 못 읽고, 요즘 오라
  값은 secret으로 와서 비보안 쪽에서도 못 읽는 것이 기본이다(소유자). Smart Cast의 해제 갈래가 전투 밖
  전용이었다가 빠진 것(`adding-spec-resolved-actions.md` §10)이 같은 벽이다.
- **매크로처럼 첫째가 거절되면 둘째로 넘긴다.** 거절이 클라이언트에서 나는지 서버에서 나는지 모르는
  동작 위에 선 안이었고 소유자가 접었다.
- **리테일에서 `dispel2`는 나갈 주문이 없는 타입.** 카멜롯에서 가져온 `dispel2` 액션이 리테일에서 키를
  쥐고 아무것도 안 시전한다. 전문화의 해제가 나가는 것이 그 사용자가 바랐을 일이다(소유자).
- **리테일 선택 창에서 `dispel2`를 숨긴다.** 가져오면 리테일에도 `dispel2` 행이 생기므로, 숨기면 얻을 수는
  있고 고를 수는 없는 타입이 된다. 둘 다 보이고 툴팁이 같다고 알린다(소유자).

## 2. 주문표

wowhead forever의 직업 주문 목록(`/forever/spells/abilities/<직업>`)에서 읽었다. 괄호는 배우는 레벨이다.
비용은 기본 마나 대비다.

| 직업 | `dispel` (질병, 저주) | `dispel2` (마법, 독) |
|---|---|---|
| 마법사 | Remove Lesser Curse 475 (18) | 없음 |
| 드루이드 | Remove Curse 2782 (24) | Cure Poison 8946 (14), Abolish Poison 2893 (26) |
| 사제 | Cure Disease 528 (14), Abolish Disease 552 (32) | Dispel Magic 527 (18) |
| 주술사 | Cure Disease 2870 (22) | Cure Poison 526 (16) |
| 성기사 | Purify 1152 (8), Cleanse 4987 (42) | Purify 1152 (8), Cleanse 4987 (42) |

전사, 사냥꾼, 도적, 흑마법사는 아군 해제가 없다. 흑마법사 지옥사냥개의 Devour Magic은 아군을 푸는
주문이 아니다(소유자).

**드루이드의 Cure Poison은 퀘스트로 배운다**(Power over Poison, 6125). 기존 표가 기댄
`DebindCamelotProbe`의 트레이너 기록에는 안 나온다. 사제의 Abolish Disease는 트레이너 기록에 있었는데
기존 파일 주석에서 빠져 있었다.

**판단은 각 주문 페이지의 툴팁 설명까지 읽고 했다.** 효과 목록(`Dispel (Poison)` 같은 줄)만으로는 하위와
상위의 관계가 안 보인다. 설명 그대로:

| id | 설명 |
|---|---|
| 475 | Removes 1 Curse or Bane from a friendly target. |
| 2782 | Dispels 1 Curse or Bane from a friendly target. |
| 8946 | Cures 1 poison effect on the target. |
| 2893 | Attempts to cure 1 poison effect on the target, and 1 more poison effect every 2 seconds for 8 sec. |
| 528 | Removes 1 disease from the friendly target. |
| 552 | Attempts to cure 1 disease effect on the target, and 1 more disease effect every 5 seconds for 20 sec. |
| 527 | Dispels magic on the target, removing 1 harmful spell from a friend or 1 beneficial spell from an enemy. |
| 526 | Cures 1 poison effect on the target. |
| 2870 | Cures 1 disease on the target. |
| 1152 | Purifies the friendly target, removing 1 disease effect and 1 poison effect. |
| 4987 | Cleanses a friendly target, removing 1 poison effect, 1 disease effect, and 1 magic effect. |

**저주 해제 둘은 "Curse or Bane"을 푼다.** Bane은 다른 주문이 설명에 안 적는 종류이고, 저주 해제 쪽에만
붙어 있으니 묶음은 그대로다.

Dispel Magic 988(36)은 527의 2랭크다. 랭크는 이름으로 시전되므로(`Spells.lua`) 표에 안 넣는다.

## 3. 한 칸에 주문 둘: 하위와 상위

한 칸에 둘이 적힌 곳은 같은 종류의 **하위 주문과 상위 주문**이다.

| 하위 | 상위 | 비용 | 상위가 더 하는 것 (2절 설명) |
|---|---|---|---|
| Cure Poison 8946 | Abolish Poison 2893 | 둘 다 16% | 8초 동안 2초마다 하나씩 더 푼다 |
| Cure Disease 528 | Abolish Disease 552 | 둘 다 15% | 20초 동안 5초마다 하나씩 더 푼다 |
| Purify 1152 | Cleanse 4987 | 둘 다 8% | 마법 하나를 더 푼다 |

Abolish 둘의 설명은 "Cures"가 아니라 "Attempts to cure"인데, 첫 해제가 하위 주문보다 약하다는 뜻이 아니다.
소유자가 가져온 사용자 글(드루이드의 Cure Poison과 Abolish Poison): Cure Poison은 지금 걸린 독만 풀고
걸린 것이 없으면 "해제할 것이 없다"로 실패한다. Abolish Poison은 지금 걸린 독을 풀고 이어서 8초 동안
2초마다 새로 걸리는 독을 푼다. 그래서 싸움 직전에 미리 걸어 둘 수 있다.

**비용이 같고 상위가 하위를 다 포함하므로, 배웠으면 늘 상위다.** 설정을 두지 않는다. 클래식은 마나에
예민해서 비용이 달랐으면 이 결론이 안 섰다. 그러니 이 절은 비용이 같다는 사실에 기대고 있다.

**해제·공격대 버프는 모두 항목의 목록 하나로 푼다** (2026-09-29, 소유자). 전에는 주문 하나(`dispel`,
`raidbuff`)에 흑마법사만 `dispelGate`(`{ cast, known = { id, ... } }`)를 덧댄 모양이었다. 카멜롯을 그 위에
또 덧대면 누더기가 되므로, 세 타입이 같은 모양이 됐다. 항목은 `cast`(시전하는 주문)와, 묻는 것이 `cast`
자신이 아닐 때만 `known`(묻는 id)을 든다.

| 경우 | 목록 |
|---|---|
| 주문 하나 (리테일 해제, 공격대 버프, 카멜롯 마법사) | `{ {cast=X} }` |
| 흑마법사 해제 | `{ {cast=119898, known=119905}, {cast=119898, known=132411} }` |
| 카멜롯 두 주문 칸 | `{ {cast=상위}, {cast=하위} }` |

없어진 것: `dispelGate` 필드, `SpellForType`의 "흑마법사만의 둘째 값", `FillBinding`의 `gate.cast`
분기, `GetBindingsForAction`의 `ASK_OWN_SPELL`.

**`known`이 없는 항목은 이름으로 묻는다.** 바인딩의 `known`이 `true`가 되고, `KnownSpellAsked`가 그것을
바인딩이 **시전하는** 주문(`spellToCast`)의 이름으로 바꾼다. 주문 하나짜리 타입이 전부터 나가던 모양(이름)
그대로라 리테일이 게임에 보내는 것은 바뀌지 않았다(발신 골든이 그대로다). `spell`이 아니라 `spellToCast`를
이름으로 삼는 것은, 카멜롯에서 행은 하위를 보이는데 원본 바인딩은 상위를 시전할 수 있어서다. `spell`로
물으면 상위 주문을 하위의 `known` 아래서 시전한다. 흑마법사는 이름으로 물으면 늘 참이라
(`adding-spec-resolved-actions.md` §3-1) id를 `known`으로 든다.

항목마다 바인딩 하나가 제 `known`을 묻고 제 `cast`를 시전한다. 이 `known`은 어느 항목을 쓸지 고르는
검사라서 사용자 설정과 상관없이 늘 붙는다. 사용자 설정은 "Spell to Cast"(`skipWhenUnusable`) 하나이고,
아는 항목이 하나도 없을 때만 갈린다. 켜졌으면 원본이 첫 항목이고 나머지가 파생되며, 아무것도 모르면 키가
다음 액션으로 넘어간다. 꺼졌으면 원본이 키만 쥐고(`holdsOnly`) 모든 항목이 파생된다. 이 규칙과 그 이유는
`adding-spec-resolved-actions.md` §4에 있고, 지금 흑마법사 길이 그대로 따른다.
항목은 상위부터 적어 상위가 앞에 선다. 상위를 배웠으면 리빌드가 그 `known`을 참으로
굳혀(`Spells.SettleKnown`) 하위 바인딩은 덮이고 솔버가 뺀다(`adding-spec-resolved-actions.md` §4 끝).
`known`은 누를 때 재므로 전투 중 레벨업에도 따로 할 일이 없다.

굳히는 것은 주문책이 그 주문의 배우는 레벨을 답할 때뿐이다(`Spells.lua`의 `IsFixed`,
`GetSpellBookItemLevelLearned`). 카멜롯 주문책은 배운 주문에 레벨을 답한다. 2026-09-25 프로브 기록에서
Frostbolt 4, Fireball 2랭크 6, Drain Soul 10으로 wowhead의 "Requires level"과 같았다. 해제 주문은 잰
캐릭터들이 아직 배우지 않아 기록에 없고, wowhead에는 2893이 26, 퀘스트로 배우는 8946도 14로 레벨이 있다.
퀘스트로 배운 주문을 잰 표본은 없다. 답이 없는 주문이 있더라도 하위 바인딩이 솔버에 남을 뿐, 누를 때
상위부터 재므로 나가는 주문은 같다.

**부활은 이 목록에 들지 않는다** (소유자). 부활은 어느 주문을 배웠느냐만으로 정해지지 않고, 전투 중인지와
대상(죽었는지, 파티·공격대인지, 대상이 있는지)이 갈래를 고른다. 그래서 `ResurrectSpells`와
갈래(`ResurrectBranches`)로 따로 남는다.

**목록 행과 툴팁이 보이는 주문** (2026-09-29, 소유자). `SpellForType`의 첫 값이 이름과 아이콘을 정한다
(`adding-spec-resolved-actions.md` §8). 지금 아는 것 중 가장 위, 하나도 모르면 가장 아래다. 가장
위는 상위 주문이고(Cure Poison → Abolish Poison), 가장 아래는 그 캐릭터가 먼저 배울 주문이다. 상위는
클라이언트의 override가 아니라 따로 배우는 새 주문이다. 하위를 대신하는 것은 우리가 고르는 일이고,
그 근거는 위의 "배웠으면 늘 상위다"다.

"아는가"는 그 항목의 바인딩이 묻는 것과 같은 물음으로 잰다(`SpecSpells.lua`의 `ShownSpell`,
`Known.lua`의 `KnownSpellOfEntry`). id로 재면 주문책도 답하는데, 주문책에는 아직 못 배운 주문도 배우는 레벨을
달고 있어서(`baking-the-known-condition.md`) 누름이 시전하지 않는 주문을 행이 보일 수 있다.

**행의 "주문이 없다" 표시도 항목 전부를 본다** (`Profile.lua`의 `noSpell`). 체크된 원본은 첫 항목(상위)을
묻지만, 상위를 안 배운 드루이드도 같은 키로 하위를 시전한다. 모든 항목이 없을 때만 표시한다.

## 4. 이름과 설명

리테일의 `TYPE_DISPEL2`와 `TYPE_DISPEL2_DESC`는 `TYPE_DISPEL`과 `TYPE_DISPEL_DESC`의 값을 그대로 받는다
(2026-09-29, 소유자). 둘이 같은 주문이라 같은 이름과 같은 설명으로 선다. 키는 따로 둔다. 키가 없으면 이름
표가 대신 읽을 키를 고르는 분기가 생긴다.

**한 키에 둘을 걸면 뒤의 것에 "Never runs"가 붙는다.** 앞의 것에 완전히 가려져 솔버가 빼기 때문이고,
누르면 앞의 것이 같은 주문을 시전하므로 동작은 같다. 사실대로의 표시라 따로 막지 않았다.

카멜롯은 `Locales/Camelot/enUS.lua`가 네 키를 덮는다. 이름은 "Dispel: Curse, Disease"와
"Dispel: Magic, Poison"이다. "Dispel Magic ..."으로 쓰지 않은 것은 그것이 사제 주문 이름이라서다. 약화 효과
종류의 클라이언트 단어는 카멜롯에 있다고 확인된 것이 없어 영어로 적었다(리테일에는
`ENCOUNTER_JOURNAL_SECTION_FLAG7`부터 `10`까지 "Magic Effect" 등이 있다).

**타입을 이름으로 비교하는 자리.** `Constants.DISPEL`을 이름으로 적은 곳은 `ActionDisplay.lua`의 이름 표,
`ActionCatalog.lua`의 선택 창 목록, `DebindStorage/Import.lua`의 `VALUE_SHAPES`, `tests/import_spec.lua`의
루프가 전부고, 넷 다 `DISPEL2`를 더했다. `Issues.lua`, `Menus/ActionMenuItems.lua`, `Profile.lua`,
`ActionTooltip.lua`가 이름으로 비교하는 것은 `RESURRECT`뿐이라 `dispel2`는 `dispel`과 같은 쪽으로 간다.

## 5. 커버리지

- **카멜롯** (`tests/camelotdispel_spec.lua`, 카멜롯 세상에서 돈다. 캐릭터가 드루이드라 `dispel2`가
  Abolish Poison, Cure Poison 두 항목이다):
  - 안 켰을 때 상위, 하위, 키를 쥐는 바인딩 순으로 서고 각자 제 주문 이름을 묻는 것. 아무것도 모르면 키를
    쥐고, 하위만 알면 하위를, 둘 다 알면 상위를 시전하는 것.
  - 켰을 때 행은 하위를 보이는데 원본은 상위를 묻고 시전하는 것. 모르면 뒤 액션이 받는 것.
  - 행이 보이는 주문이 아는 것 중 첫째, 없으면 마지막인 것(아이콘까지).
  - 하위를 알면 행에 "주문이 없다"가 안 붙고, 둘 다 모르면 붙는 것.
- **리테일** (`tests/specspells_spec.lua`): `dispel2`가 `dispel`과 같은 주문으로 풀리고 누르면 그것이 나가는
  것. 흑마법사의 두 id는 새 항목 모양으로 기존 스펙이 그대로 잰다.
- **두 클라이언트의 풀이** (`tests/client_spec.lua`): 드루이드의 두 해제가 클라이언트마다 무엇으로 풀리는지.
- **가져오기** (`tests/import_spec.lua`): 네 타입이 값 없이 받아지는 것. `PayloadIsImpossible`에 묻는다.
  전에는 `PlanArrival`만 불러서 `VALUE_SHAPES`에서 타입이 빠져도 통과했다.
- **`/debtest`** ("Spec spells: every camelot dispel and buff id is a spell"): 카멜롯 표의 해제·버프 id가
  전부 그 클라이언트의 주문인 것. 헤드리스는 표를 주어진 대로 받으므로 잘못 적은 id를 못 본다.
- **원리상 못 닿는 것.** 카멜롯 주문 이름에 대한 `[known:]`의 답과, 상위를 배운 뒤 주문책이 레벨을 답해
  리빌드가 굳히는지는 게임에서만 난다. 헤드리스는 그 답을 세상에 세워 두고 잰다.
