# 카멜롯의 해제를 두 타입으로 나누기 (2026-09-27 시작)

> 상태: **모양은 소유자와 정했다(1절). 구현 전.** 3절의 표시 규칙 하나는 아직 소유자에게 안 물었다.
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

**리테일은 그대로다.** 전문화마다 해제가 하나이고 그 하나가 여러 종류를 푼다. `dispel2`는 리테일 주문표에
없어서 리테일에서는 나갈 주문이 없는 타입이 된다(3절).

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

Abolish 둘의 설명은 "Cures"가 아니라 "Attempts to cure"다. 첫 해제가 하위 주문보다 약하다는 뜻인지는
설명만으로는 모른다.

**비용이 같고 상위가 하위를 다 포함하므로, 배웠으면 늘 상위다.** 설정을 두지 않는다. 클래식은 마나에
예민해서 비용이 달랐으면 이 결론이 안 섰다. 그러니 이 절은 비용이 같다는 사실에 기대고 있다.

**모양은 부활의 갈래와 같다.** 주문마다 바인딩 하나가 제 주문을 `known`으로 묻고 제 주문을 시전한다.
상위가 앞에 선다. 상위를 배웠으면 리빌드가 그 `known`을 참으로 굳혀(`Spells.SettleKnown`) 하위
바인딩은 덮이고 솔버가 뺀다(`adding-spec-resolved-actions.md` §4 끝). `known`은 누를 때 재므로 전투 중
레벨업에도 따로 할 일이 없다.

흑마법사의 `dispelGate`는 쓸 수 없다. 그쪽은 시전하는 주문이 하나이고 묻는 id만 여럿이다. 여기서는 시전하는
주문 자체가 둘이다.

**남은 물음: 목록 행과 툴팁이 어느 주문을 보이나.** `SpellForType`의 첫 값이 이름과 아이콘을 정한다
(`adding-spec-resolved-actions.md` §8). 권하는 답은 "리빌드 때 아는 것 중 가장 위, 하나도 모르면 가장
아래"다. 가장 아래는 그 캐릭터가 먼저 배울 주문이다. 소유자에게 아직 안 물었다.

## 4. 고칠 자리

**`Constants.DISPEL`로 grep하면 빠지는 자리가 있다.** `SPEC_RESOLVED_TYPES`, `SpecSpells.KIND_BY_TYPE`,
`TYPES_WITH_UNIT`처럼 타입을 표로 받는 자리를 따라가야 한다.

- **`Constants.lua`**: `DISPEL2`를 두고 `TYPES_WITH_UNIT`, `SPEC_RESOLVED_TYPES`에 넣는다.
- **`SpecSpells_Camelot.lua`**: 2절 표. 머리 주석의 "No dispel for a class with two or more"와 직업마다의
  "No dispel:" 줄은 이 결정으로 거짓이 되므로 새 모양의 이유로 다시 쓴다. 칸 하나가 주문 여럿(상위부터)을
  들 수 있어야 한다.
- **`SpecSpells.lua`**: `Resolve`, `KIND_BY_TYPE`, `SpellForType`이 `dispel2`와 여러 주문짜리 칸을 답한다.
  3절의 표시 규칙이 여기서 첫 값을 고른다.
- **`ActionBindings.lua`의 `GetBindingsForAction`**: 여러 주문짜리 칸이면 부활처럼 갈래를 세운다
  (`ResurrectBranches` 옆). 갈래는 조건을 더하지 않고 `known`과 시전 주문만 든다. `FillBinding`의
  `branch` 길이 `ApplyResurrectBranch`를 부르므로 그 자리가 갈라져야 한다.
- **`ActionCatalog.lua`**: 주문 탭에 세우는 타입 목록에 `dispel2`를 더하되, **주문표가 그 타입을 가질 때만**
  세운다. 클라이언트 이름으로 가르지 않는다(`Client/Classes.lua` 머리 주석의 방침).
- **`ActionDisplay.lua`**, **`ActionTooltip.lua`**: 타입 이름 표와 툴팁의 주문 줄.
- **`DebindStorage/Import.lua`의 `VALUE_SHAPES`**: `DISPEL2 = false`. 없으면 카멜롯에서 내보낸 문자열이
  리테일에서 통째로 거절된다.
- **로케일**: 리테일에서도 가져온 `dispel2`의 행이 그려지므로 기본 `enUS.lua`에 `TYPE_DISPEL2`와
  `TYPE_DISPEL2_DESC`를 둔다. 카멜롯 이름과 설명은 `Locales/Camelot/enUS.lua`가 `TYPE_DISPEL`,
  `TYPE_DISPEL_DESC`, `TYPE_DISPEL2`, `TYPE_DISPEL2_DESC`를 덮는다. 문구는 `writing-user-facing-text.md`를
  먼저 읽는다. 클라이언트에 `ENCOUNTER_JOURNAL_SECTION_FLAG7`부터 `10`까지("Magic Effect", "Curse Effect",
  "Poison Effect", "Disease Effect")가 있다.
- **`Issues.lua`**, **`Menus/ActionMenuItems.lua`**, **`Profile.lua`**: `Constants.RESURRECT`나 `DISPEL`을
  이름으로 비교하는 자리가 있다. 새 타입이 같은 대접을 받아야 하는지 하나씩 본다.
- **문서**: 구현이 끝나면 `shipping-on-the-camelot-client.md` 6절 끝 문장("해제 주문이 둘 이상인 직업은
  해제를 두지 않는다")과 `adding-spec-resolved-actions.md` §3-1의 "전문화마다 정확히 하나다"가 카멜롯에서
  거짓이 된다. 둘 다 이 문서를 가리키게 고친다.

## 5. 테스트

- **헤드리스** (`tests/specspells_spec.lua`): 카멜롯 표로 직업마다 두 타입의 풀이. 여러 주문짜리 칸이 상위부터
  갈래를 세우고 각자 제 id를 `known`으로 묻는지. 상위를 아는 상태에서 하위 바인딩이 솔버에 덮이는지.
  `dispel2`가 없는 표(리테일)에서 `dispel2` 액션이 키를 쥐고 아무것도 안 시전하는지(§4).
- **가져오기** (`tests/import_spec.lua`): `dispel2`가 값 없는 모양으로 받아지는지. 지금 세 타입을 도는
  루프가 있다.
- **`/debtest`**: 레벨이 다른 카멜롯 캐릭터가 있어야 재는 하위에서 상위로 넘어가는 것은 킷이 세울 수 없다.
  헤드리스가 `known` 갈래 모양까지 덮고, 누를 때의 `known` 판정은 기존 해제·부활과 같은 길이다.
