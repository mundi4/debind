# action / binding / placement 모양

> **표준 문서다.** 규칙이라서 자리를 안 옮긴다. 이 모양이 왜 이 모양인지, 그리고 무엇을 대신
> 기각했는지는 `legacy/straightening-out-action-and-binding.md`에 있다.
>
> **여기 적힌 것이 계약이다.** 코드 주석은 이 문서를 되풀이하지 않고, 자기 자리에서만 뜻이
> 있는 것을 적는다.

리포에 도는 액션 모양은 셋이고, 넷째가 있다.

| | 사는 곳 | 무엇 |
|---|---|---|
| **action** | SavedVariables (`Profile.lua`의 `KEYS_TO_SAVE`) | 저장. 사용자가 편집하는 것 |
| **binding** | `Misc.lua`의 `GetBindingInfoForAction` | 액션 하나의 **순수 파생**. 솔버와 방출부가 읽는다 |
| **placement** | `Misc.lua`의 `MakeOrderRecord` | 프로필 **안에서의 자리**. 비교자가 읽는 유일한 것 |
| **payload `t`** | `UpdateBindings.lua`가 굽는 스니펫 소스 | 제한 환경 안에서 사는 셋째 모양. 아래 §5 |

---

## 1. action

**흐름은 한 방향이다.** 바인딩은 액션에서 다시 만들어지고 액션으로 되쓰이지 않는다. 그래서
바인딩을 정규화해도 사용자가 적은 것이 안 바뀐다.

```
action
    type value          필수. `Constants.SPELL` 계열. value는 타입에 따라 주문/아이템 id,
                        매크로 본문, 펫 명령 ...
                        **`USESLOT`의 value는 `INVSLOT_*` 칸 번호다.** `ITEM`에 칸 번호를
                        넣지 않고 타입을 나눈 것은 13이 멀쩡한 아이템 id이기도 해서다. 저장된
                        값만 봐서는 둘이 구별이 안 되고, 구별할 수 없는 값은 나중에
                        마이그레이션도 못 한다. 게임에 나갈 때는 둘 다 `*type-="item"`이다
                        **`SPEC_RESOLVED_TYPES` 셋은 value가 없다.** 어느 주문인지는 클래스와
                        전문화가 정한다 (`SpecSpells.lua`)
    key                 걸린 키. **문자열이다.** 없으면 이 액션은 아무 데도 안 걸린다.
                        도착한 액션도 도착한 키를 여기 든다
    name icon           표시 전용. 솔버도 런타임도 안 읽는다
    unit                겨누는 대상. `UNIT_INFO`의 키. **조건이 아니다** (§2)
    seq                 자기 키 그룹 안에서의 자리, 1..n. 그룹이 바뀔 때마다 다시 매겨진다.
                        키가 없으면 이것도 없다
                        (`Profile.lua`의 `RenumberKeyGroup`, `PlaceInKeyGroup`)
    priority            숫자. 없으면 `Constants.DEFAULT_IMPORTANCE`
    arrivalID           **숫자.** 어느 도착이 이 액션을 넣었는가, 도착 하나에 하나씩
                        (`NextArrivalID`). **이게 있는 동안 이 액션은 격리된다.** 프로필에
                        있고, 그려지고, 아무 키에도 안 걸린다 (`BuildKeyMap`). 지우는 것이
                        읽는 이의 승낙이다. 같은 키에 두 세트가 앉을 수 있어서, 키 그룹을
                        가르는 나머지 절반이 이것이다.
                        옛 `imported`가 `key`와 이 둘로 풀렸다 (`dbver <= 5`)
    keepInBindingContext
                        게임이 가져간 키에도 그래도 걸 것이냐. 조건이 아니라 예외다
    casting             **어느 누름에서 이 액션이 서는가.** 표 하나에 값 넷이고, 모양과 뜻은
                        `which-action-a-key-runs.md` §8이 든다. 조건이 아니다 (§2)
    conditions          **언제 발동하느냐. 전부 이 안에 있다** (§3)
```

**`KEYS_TO_SAVE`가 유일한 명단이다.** 거기 없는 필드는 누가 써넣든 `CleanUpDB`가 걷어내므로
저장되지 않는다.

---

## 2. 조건이 아닌 것 셋

이름이나 자리 때문에 조건으로 읽히기 쉬운데 아닌 것들이다. 셋 다 **겨누는 것**이나
**예외**를 말한다.

**`unit`은 액션이 겨누는 대상이다.** 매크로의 `[@unit]`이라 동작 자체가 바뀐다. 쓰는 곳은
둘이다. `Target` 메뉴의 라디오, 그리고 선택 창의 기타 탭이 유닛마다 한 줄씩 내는 대상 지정과
주시 대상 지정과 메뉴 열기 행(`ActionCatalog.lua`의 `AddOwnCommands`). 대상 메뉴가 이슈 갈래로 `"unit"`을 넘기므로
`GetBindingIssue(action, "unit")`은 **겨눌 대상의 문제**를 묻는 것이지 유닛 조건을 묻는 것이
아니다.

**`conditions.units`는 정반대다.** 언제 발동하느냐이고 동작은 안 바뀐다. `Units`
메뉴가 쓰고, `Target` 메뉴의 아래쪽 절반도 `"@"`로 여기에 쓴다.

**`casting`도 조건이 아니다.** 누름의 종류마다 이 액션이 바인딩을 갖느냐, 그리고 그 바인딩이
어디로 나가느냐를 정한다. 언제 발동하느냐를 말하는 것이 아니라 **어느 누름의 줄에 서느냐**를
말한다 (`which-action-a-key-runs.md` §3, §6).

---

## 3. conditions

조건은 셋으로 갈린다. **유닛 밖의 축**은 값 하나씩 평평하게 눕고, **`units`**는 유닛마다 표를
하나씩 들고, **스위치**는 자기 이름으로 앉는다.

**어느 이름이 조건인지는 `Constants.IsConditionField` 하나가 답한다.** 코드에서 물을 때 보는
것은 그 함수지 아래 표가 아니다. 그 함수는 `CONDITION_FIELDS`에 없어도 **`$`로 시작하면
조건**이라고 답하는데, 스위치가 그 이름으로 저장되기 때문이다
(`legacy/redesigning-custom-states.md`).

### 3-1. 유닛 밖의 축

메뉴 칸은 그 묶음의 locale 키다(`DropDownMenus.lua`). 재는 식은 `Constants.STATE_EVAL_EXPRESSIONS`의
값 그대로다.

| 필드 | 저장값 | 어느 메뉴가 쓰나 | 런타임이 재는 것 |
|---|---|---|---|
| `groups` | `GROUP_NONE/PARTY/RAID` 마스크 | `CONDITION_GROUP` | `UnitPlayerOrPetInRaid("player")`이면 공대, 아니면 `UnitPlayerOrPetInParty("player")`이면 파티, 아니면 없음 |
| `specs` | 1..5 마스크. 5는 이름 없는 초기 전문화 | `CONDITION_SPEC` | **안 잰다.** 비보안 쪽 `BuildKeyMap`이 걸러서 솔버에도 스니펫에도 안 간다 |
| `forms` | `2^0`..`2^10` | `CONDITION_SHAPESHIFT` | `GetShapeshiftForm()` |
| `bonusbars` | `2^0`..`2^5` | `CONDITION_ACTIONBARS` | `GetBonusBarOffset()` |
| `specialbar` | true \| false \| nil | `CONDITION_ACTIONBARS` | `HasVehicleActionBar() or HasOverrideActionBar() or HasTempShapeshiftActionBar()`에 `petbattle`을 얹은 값 |
| `extrabar` | 같음 | `CONDITION_ACTIONBARS` | `HasExtraActionBar()` |
| `combat` | 같음 | `CONDITION_COMBAT` | `PlayerInCombat()` |
| `stealth` | 같음 | `CONDITION_STEALTH` | `IsStealthed()` |
| `petbattle` | 같음 | `CONDITION_MISC` | `SecureCmdOptionParse("[petbattle]")` |
| `mounted` | 같음 | `CONDITION_MISC` | `IsMounted()` |
| `indoors` | 같음 | `CONDITION_MISC` | `IsIndoors()` |
| `flyable` | 같음 | `CONDITION_MISC` | `IsFlyableArea()` |
| `advflyable` | 같음 | `CONDITION_MISC` | `IsAdvancedFlyableArea()` |
| `flying` | 같음 | `CONDITION_MISC` | `IsFlying()` |
| `skyriding` | 같음 | `CONDITION_MISC` | `GetBonusBarOffset() == BONUSBAR_SKYRIDING` |
| `known` | true \| nil | `CONDITION_KNOWN` | 이름이 곧 조건문인 `"[known:<주문 id>]"`를 `SecureCmdOptionParse`가 판다 |
| `frameTypes` | `FRAMETYPE_*` 마스크 | `CONDITION_HOVER` | 유닛이 아니라 **프레임**. 스니펫이 프레임 레코드에 대고 직접 본다 |
| `$이름` | true \| false \| nil | `CONDITION_CUSTOM_STATES` | `States[이름]` |

**불리언 축은 셋 다 다른 답이다.** 메뉴가 [사용 안 함] [예] [아니오] 세 라디오를 내고, 저장은
각각 nil, true, false다.

**전부 켠 마스크는 조건이 아니다.** `GetBindingInfoForAction`의 정규화가 `groups` `specs`
`forms` `bonusbars`를 `_ALL`로 접고, 방출부는 `_ALL`인 값을 안 싣는다(`CONDITION_AXES`의
`allValue`). 거꾸로 **0은 저장한다.** 아무것도 안 고른 것은 정규화할 사실이 아니라 이슈이고,
그 넷은 §7의 검사가 잡는다.

**`known`은 다른 것들과 달리 세 번째 값이 없다.** 자기 주문에 대해 묻는 것이라 `false`는
"안 배웠을 때만 시전"이 되고 그런 상태는 없다. 정규화가 `false`를 지우고, 주문도 전문화 파생
타입도 아닌 액션에 붙은 값도 지운다. 나가는 것은 조건값이 아니라 대괄호까지 포함한 문자열
하나이고, 그 문자열이 `States`의 키이자 클릭 경로가 그대로 넘기는 값이다.

**`skyriding`은 혼자 남의 값을 읽는다.** `bonusbars`와 같은 `GetBonusBarOffset()`을 보고 그
값이 `BONUSBAR_SKYRIDING`이냐를 묻는다. 축을 따로 둔 것은 모델이 아니라 메뉴 때문이다. "날 때"를
찾는 사람이 행동 단축바 설정 아래를 뒤지지는 않는다. 값이 겹치는 만큼 **둘을 같이 걸면 성립
안 하는 쌍이 나오고**, 그건 §7의 검사가 잡는다. 솔버는 이 겹침을 문제로 안 본다
(`Solver.lua` 머리 주석의 "Across columns").

**`indoors`는 `IsIndoors()` 하나만 읽는다. 거짓이 "실외"는 아니다.** `IsOutdoors()`도 있지만
둘은 여집합이 아니라서(던전 로딩 화면에서 둘 다 거짓이다) 한 함수를 불리언으로 읽는 쪽만
컬럼 분할이 성립한다.

**재는 것은 그 축을 실제로 건 키가 있을 때뿐이다.** 리빌드가 레코드에서 축을 읽어
`_measuredStates`를 채우고, 그 값이 상태 루프의 줄과 걸 이벤트를 정한다
(`CollectRecordAxes`, `CollectDriverEvents`). 등록은 **정밀도만** 바꾼다. 아무도 안 물은 축은
`States`에 자리가 없고, 자리가 없는 축은 비교에 안 온다.

### 3-2. `units`

유닛 하나에 표 하나다. 앞의 셋이 모드고, 뒤의 넷이 축이다.

```
conditions.units[유닛]
    { exists = true }      있을 때
    { exists = false }     없을 때
    { disabled = true }    이 유닛에 조건 없음
    reaction               `REACTION_HELP/HARM/OTHER` 마스크
    dead                   true(죽었을 때) | false(살았을 때) | nil
    group                  `UNITGROUP_NONE/PARTY/RAID` 마스크
    role                   `ROLE_TANK/HEALER/DAMAGER/NONE` 마스크. **hover에만**
```

**모드 셋이 저마다 자기 값을 든다.** 한때는 빈 표가 [있을 때]였다. 리포의 나머지는 빈 표를
아무것도 아닌 것으로 접으므로 그 하나만 반대 규약이었고, `ActionSignature`가 그렇게 접는 바람에
유닛 조건 하나만 걸린 액션이 조건 없는 액션과 **같은 서명**을 냈다. 중복 제거가 그 둘을 한
쌍으로 봤다. `dbver <= 6` 단계가 옛 값을 올린다.

**표시가 하나도 없는 표는 옛 값이고, [있을 때]로 읽는다.** 사다리를 아직 안 탄 값이 그 모양으로
오는데(페이로드가 대표적이다), 그것을 [조건 없음]으로 읽으면 걸어둔 조건이 조용히 사라져
바인딩이 제 것 아닌 키까지 가져간다. `UnitConditionForBinding`이 옛 이름 `off`도 같은 이유로
받는다.

**모드를 옮겨도 축은 안 지운다.** [사용 안 함]이나 [없을 때]로 옮겼다고 골라둔 값을 지우면
되돌렸을 때 처음부터 다시 골라야 한다. 옵션을 끄는 것이지 지우는 것이 아니고, 그래서 저장
모양과 바인딩 모양이 다르다. 이음매는 `UnitConditionForBinding` 하나이고, 바인딩 쪽은 기억을
안 들고 간다.

**옛 스칼라도 그 함수가 받는다.** `true`/`false`/`"help"`/`"harm"`이 손으로 고친 프로필과 아직
안 옮겨진 문자열로 들어온다. **모르는 스칼라는 없음 점으로 읽되 바인딩에 표시를 남긴다**
(`unitConditionUnreadable`이 `unitStatesOpaque`가 된다). 없음 점은 "있을 때"의 부분집합이
아니라서, 그대로 축에 올리면 진짜 [없을 때] 바인딩을 덮고 솔버가 그것을 지운다.

축이 재지는 방식:

- **`reaction`**: `PlayerCanAssist`가 참이면 help, 아니면 `PlayerCanAttack`이 참이면 harm,
  아니면 other. 셋 중 정확히 하나로 떨어진다. 전부 켠 값은 안 쓰고 0은 쓴다.
- **`dead`**: `UnitIsDead(u) or UnitIsGhost(u)`. **유령도 죽음이다.** 매크로 `[dead]`가 그렇게
  세고, 제한 환경에는 `UnitIsDeadOrGhost`가 없어서 둘 다 물어야 한다. 살아 있다고 읽으면
  시체에 치유가 나간다.
- **`group`**: `UnitPlayerOrPetInRaid`와 `UnitPlayerOrPetInParty`를 **둘 다** 묻는다. 체인이
  아니다. 저장은 겹치는 세 상자이고, 솔버와 스니펫으로 갈 때 `UnitGroupToCells`가 네
  칸(`neither`/`party`/`raid`/`both`)으로 편다. 상자끼리 `band`를 걸면 [파티]와 [공대]의
  교집합이 0으로 나와 발동할 수 있는 바인딩이 통째로 빠진다.
- **`role`**: 유닛 행이 아니라 **hover 슬롯**에서 읽는다(`unitframe.role`). 맵의 키가 그룹 유닛
  토큰이라 개체창이 쥐어준 유닛만 답할 수 있다. 슬롯이 nil이면 답할 수 없다는 뜻이라 이 축은
  아예 안 선다.

**생사와 반응은 한 축의 곱이고 소속과 역할은 따로 선다.** 앞의 둘은 `binding.unitStates`의 유닛
마스크로 접히고(`UNITSTATE_*`), 소속은 `binding.unitGroups[유닛]`, 역할은 `binding.unitRole`로
따로 간다. 왜 곱이고 왜 따로인지는 `Constants.lua`의 `UNITSTATE_NONE` 위 문단이 든다.

### 3-3. 유닛마다 어느 메뉴가 쓰나

| 유닛 | 쓰는 메뉴 | 걸 수 있는 축 |
|---|---|---|
| `unitframe` | `CONDITION_UNITS` (`CreateUnitConditionMenu`) | 넷 전부. 역할과 `frameTypes`도 이 줄에서만 건다 |
| `"@"` | `TARGET_UNIT` 아래 `ONLY_IF` (`CreateTargetUnitMenuItem`) | 반응·생사·소속. [없을 때]는 잠겨 있다 |
| `player` | `CONDITION_LIFE` (`CreateSelfLifeConditionMenu`) | **`dead` 하나** |
| `target` `focus` `mouseover` `tank` `healer` `maintank` `mainassist` `custom1` `custom2` | `CONDITION_UNITS` (`CreateUnitConditionMenu`) | 반응·생사·소속 |
| `pet` | `CONDITION_UNITS` (`CreateUnitConditionMenu`) | **존재와 생사 둘** |
| `none` | 없음 | 없음 |

`pet`에 반응과 소속이 없는 것은 `UNIT_INFO.pet.conditionAxes`가 그 둘을 닫아서다. 자기 소환수는
언제나 도울 수 있고 소속도 답이 하나라, 고를 것이 있는 축은 존재와 생사뿐이다. **소환수가
있느냐를 묻는 자리는 여기 하나다.** 같은 것을 묻던 `pet` 조건 축은 없어졌고, 스위치 정의식의
`[pet]`도 이 행에 걸린다(`UpdateBindings.lua`의 `SWITCH_GATE_UNITS`).

`none`은 유닛이 아니라 **대상 입력을 받게 하는 것**이라 조건이 붙을 자리가 아예 없다.

**`"@"`는 `unit`을 가리키는 포인터다.** 가리킬 것이 없으면 정규화가 지우고, 대상이 `none`이거나
`player`일 때도 지운다. 앞의 둘은 겨눌 유닛이 없고, `player`는 자기 자신이라 존재를 물을 것이
없다.

### 3-4. `player`가 다른 유닛과 다른 자리

**존재/부재 라디오가 없다.** 자기 자신은 늘 있으니 걸 것이 없고, 그래서 축을 세워줄 라디오도
없다. 다른 유닛의 축 setter는 그 라디오가 표를 만들어둔 뒤에만 불리는데 여기는 첫 클릭이 표를
만든다. 지울 때도 같다. 축 하나짜리 자리라 그 값을 비우면 남는 것이 없고, 빈 표를 남기면
아무것도 안 고른 유닛이 프로필에 쌓인다. 켠 적 있는 `disabled` 표시도 같이 지운다.

**최상위 `conditions.dead`를 새로 두지 않았다.** 저장은 `units.player.dead`이고 새 조건이 아니다.
그 축은 이미 끝까지 서 있다. 솔버 컬럼도, 방출도, 상태 루프도, 클릭 경로도 `player`를 다른
유닛과 똑같이 잰다(`UnitExists("player")`가 늘 참이라 존재 축은 언제나 참이다). 같은 물음이 두
형태로 저장되면 솔버가 다른 상자로 보고, 컬럼과 방출과 두 경로를 한 벌씩 더 쓰게 된다.

**`Units` 묶음에 `player`를 넣지 않는다.** 넣으면 한 값을 두 메뉴가 편집한다. 그리는 줄과 세는
유닛이 같은 목록이어야 하고 그 목록이 `isListedUnit`인데, `player`가 거기서 빠져 있는 동안
[전부 사용 안 함]이 **안 보여주는 조건을** 꺼버렸고 그 메뉴에는 되살릴 줄이 없었다.

**읽는 이의 소속은 `units.player.group`이 아니라 `conditions.groups`다.** 메뉴로는 전자를 못
만든다. 손으로 고친 프로필이나 옛 문자열로 들어오면 그것도 그대로 돈다. `BuildUnitStates`도
방출도 유닛 이름을 안 가려서 네 칸으로 나가고, 런타임이 `player`에 두 술어를 잰다. 축이 둘이라
컬럼도 둘이고, 솔버는 둘을 다 좁히는 쪽으로 읽는다.

### 3-5. 표에 대한 두 규칙

**빈 표는 안 남긴다.** 저장 쪽은 `CleanUpDB`가, 편집 쪽은 `DropDownMenus.lua`의
`PruneConditions`가 지운다. 표가 있느냐를 게이트로 쓰는 자리가 있어서, 빈 표는 조건이 하나도
없는 액션을 조건부로 만든다. 그러면 발동 순서가 바뀐다.

**`hover`와 `reactions`는 더 이상 저장되지 않는다.** `dbver <= 4`가 둘을 `units["hover"]`로
접었다(그때 이름은 `checkedUnits`였고, `dbver <= 5`가 옮기면서 바꿨다). 마이그레이션이 안 닿은
프로필과 그 전에 공유된 문자열에는 아직 있고, `HoverConditionFromLegacy`가 **사본 위로**
들어올린다.

---

## 4. binding

액션 하나의 순수 파생이다. **하나가 아니라 목록이다.** `GetBindingsForAction`이 액션당 배열 하나를
내고, `[1]`이 **원본**, 그 뒤가 **파생**이다. 원본은 `GetBindingInfoForAction`이 내는 표 그대로이고
둘 다 리빌드마다 **제자리에서** 다시 채운다.

```
binding
    type value key unit                     액션에서 그대로. `unit`만 다르다(아래)
    conditions                              정규화된 조건. 액션 쪽과 같은 이름, 다른 값
    castModifier hoverTwin                  이 바인딩이 받는 누름의 종류. 원본은 `CASTMOD_NONE`에
                                            `hoverTwin`이 없고, 층은 이 둘로만 정해진다
                                            (`which-action-a-key-runs.md` §3)
    normalCast                              `false`면 원본이 마지막 층에서 빠진다. 원본만 든다
    spell                                   `SPEC_RESOLVED_TYPES`가 오늘 내는 주문. 그 밖에는 nil
    spellbook                               probe 파생만 든다. 누를 때 주문서에 있는지 묻는 id
    unitStates unitGroups unitRole unitStatesOpaque
                                            솔버가 유닛에 대해 읽는 전부 (§3-2). 못 읽는 값을
                                            만나면 `unitConditionUnreadable`이 마지막 것이 된다
```

**리빌드가 넷을 더 얹는다.** `clickframe` `clickframeName` `clickbutton` `pressAndHold`는
`UpdateBindings.lua`가 이 표에 직접 써넣는 값이고, 액션의 순수 파생이 아니라
이번 빌드의 배선이다.

**액션의 답은 원본의 답이다.** 이슈 검사, 순서 레코드, 매크로 변환, 툴팁이 전부 원본에 묻는다.
목록을 받는 것은 `BuildKeyMap` 하나이고, `IsUnreachableAction`만 목록 전부를 본다(전부 죽어야
액션이 죽은 것이다).

**파생은 원본을 복사하지 않고 액션에서 다시 채운다.** 아래 `"@"` 정리가 `unit`을 보고 지우므로,
원본을 채운 뒤에 `unit`만 바꾸면 이미 지워진 `"@"`를 되살릴 길이 없다. 그래서 채우기 함수 하나가
나갈 `unit`, 조합키 칸, 가리킨 유닛 칸에 얹을 조건을 인자로 받고, 원본과 파생이 다른 인자로 부른다.

**파생은 쌍둥이 셋과 probe다.** 어느 액션이 어느 쌍둥이를 갖고 쌍둥이가 무엇으로 나가는지는
`implementing-focus-and-self-cast.md` §3-4가 든다.

**키에는 네 층으로 선다.** `BuildKeyMap`은 원본을 정렬한 뒤 키 전체를 self 쌍둥이, focus 쌍둥이,
hover 쌍둥이, 원본의 네 층으로 펼친다. 자기 placement를 받는 파생은 hover 쌍둥이뿐이고, 그 순서
기록은 쌍둥이의 조건을 단 액션으로 본 것이다.

**probe**는 흑마법사의 해제에만 붙는다. `SpellForType`의 둘째 값(펫이 쓰는 주문)을 `spell`과
`spellbook`에 넣은 사본이고, 누를 때 `FindSpellBookSlotBySpellID`가 주문서를 보고 갈린다
(`SpecSpells.lua`). 바인딩마다 하나씩 서고, 자기 바인딩 바로 앞에 붙은 채 층을 옮긴다.

목록은 원본, probe, hover 쌍둥이와 그 probe, focus 쌍둥이와 그 probe, self 쌍둥이와 그 probe 순으로
채우고, `BuildKeyMap`이 뒤에서 앞으로 걸으며 층마다 골라 담는다.

**`binding.unit`은 `action.unit`이 아니다.** 매크로가 실제로 겨눌 유닛이다. 대상을 못 갖는
타입이면 지워지고, 호버 액션이 자기 대상이 없으면 **호버한 유닛으로 채워진다.** "사용자가
무언가를 골랐는가"에 답하는 것은 `action.unit`뿐이고, `"@"` 정리가 그 채워넣기보다 앞서야
하는 이유가 그것이다.

**`binding.hover`는 `units["hover"]`에서 파생된다** (`DeriveHoverFields`). `false`와
`nil`은 다른 답이다. `false`는 "안 올렸을 때만"이고 `nil`은 "상관 안 함"이라, 둘을 갈라서 읽는
자리가 여럿이다(발동 순서, 클릭 경로, 솔버의 프레임 종류 컬럼, 키 유효성).

**`binding.conditions`는 비어 있을 수 있다.** 표를 재사용하느라 늘 존재한다. 저장 쪽은
반대로 빈 표를 안 남긴다. `next`는 둘 다 맞게 답한다.

**정규화가 하는 일**: 못 갖는 조건을 지우고, 마스크가 전체 비트면 `_ALL`로 접고, 호버를
채워 넣는다. 전부 액션 하나로 닫히는 계산이다.

---

## 5. 셋째 모양: 스니펫이 보는 `t`

`UpdateBindings.lua`의 방출 블록이 **스니펫 소스 문자열**을 굽고, 제한 환경이 그것을 실행해
`t`를 만든다. `SecureBindings.lua`가 `t.groups`, `t.combat`처럼 읽는다.

**이 표는 평평하다. 중첩하지 않는다.** 액션이나 바인딩과 같은 모양일 이유가 없고, 여기는
제한 환경 안이라 값이 비싸다. 방출부는 `binding.conditions.X`를 읽어서 `t.X`로 굽고, 읽는 자리와 쓰는 자리의 모양이 다른
것이 정상이다.

유닛만 예외로 `t.units[유닛]`으로 한 겹 들어간다. 축이 여럿이라 평평하게 펴면 유닛마다 이름이
그만큼 늘어난다.

```
t.units[유닛]
    exists              true | false. false면 나머지는 안 나간다
    dead                true | false
    reaction group role 상자가 아니라 **집합**이다. `u.reaction.help = true` 꼴로 굽는다
```

**마스크가 아니라 집합인 것이 요지다.** 제한 환경이 마스크에 강요하는 `%` 관용구는 조회 둘에
산술까지 드는데, 소속은 조회 한 번이면 끝난다. `group`은 저장의 겹치는 세 상자가 아니라 네
칸이고(§3-2), `role`은 hover 항목에만 나간다. 다른 유닛에 실으면 재는 쪽이 그 행을 안 채워
`cond.role[nil]`이 되고 그 키가 조용히 죽는다.

---

## 6. placement

**액션 하나로 답이 안 나오는 유일한 것.** 프로필 안에서의 자리이기 때문이다.

```
placement (`MakeOrderRecord`)
    priority hover isConditional            액션/바인딩에서 파생된다
    layerRank specRank seq                  프로필에서의 자리
```

`CompareActionOrder`가 받는 것은 이것 하나다. 만드는 곳은 셋이고
(`BuildKeyMap` / `MakeRow` / `RenumberKeyGroup`) 셋 다 `MakeOrderRecord`를 거친다.

**바인딩 안에 넣지 않는다.** 예전에는 `BuildKeyMap`이 `layerRank`/`seq`/`isConditional`을
바인딩에 직접 써넣었고 아무도 안 지웠다. 그래서 "바인딩은 액션의 순수 함수"가 규약이지
사실이 아니었다. 지금은 바인딩 **옆**의 약한 키 표에 산다(`Debind.lua`의 `Placements`).

---

## 7. 이슈 갈래

**어느 컨트롤을 빨갛게 칠할지의 이름이지 필드 이름이 아니다.** 목록은
`Constants.BINDING_ISSUE_CATEGORIES`다.

넷은 그 이름의 액션 필드가 아예 없다. `hover`와 `reactions`는 저장에서 접혔고, `macro`는
"매크로 이름이 가리키는 것이 없다", `states`는 "액션이 정의 없는 스위치를 가리킨다"를 뜻한다.
거꾸로 조건인데 갈래가 없는 것이 더 많다. 아무것도 안 고른 0을 잡는 것은 `groups` `specs`
`forms` `bonusbars` 넷과 유닛 쪽 마스크(반응·프레임 종류·유닛 상태·역할)뿐이고, `combat`
`stealth` `known` `mounted` `indoors` `flyable` `advflyable` `flying` `extrabar`에는
모순을 잡는 검사가 아직 없다.

**갈래 하나가 두 필드를 대조하는 경우가 넷 있다.** `specialbar`와 `petbattle`, `skyriding`과
`bonusbars`, 그리고 읽는 이의 소속(`groups`)이 [혼자]뿐일 때 걸리는 둘이다. 뒤의 둘은 혼자
있으면 역할 별칭 유닛들이 비고(`UNITS_ABSENT_WHEN_SOLO`) 역할 맵도 비기 때문에, 그 유닛이
있어야 한다는 조건이나 진짜 역할을 고른 조건과 만나면 눌러도 아무 일이 안 난다. 넷 다 **양쪽
갈래로 똑같이 보고된다.** 두 절반이 서로 다른 메뉴에 살기 때문에, 어느 쪽을 열었든 그 사람에게
무언가가 보여야 한다. 어느 한쪽만 칠하면 나머지 메뉴는 멀쩡해 보이고 그쪽으로 푸는 길이
화면에서 사라진다.

**없는 이름으로 물으면 모든 갈래가 비켜가 nil이 나오고, 그건 "문제 없음"과 생김새가 같다.**
그래서 `GetBindingIssue`가 DEBUG에서 그 물음을 세운다. 목록 행이 그렇게 죽은 갈래 넷을 묻고
있었고, 남은 것들이 같은 판단을 이미 내려서 증상이 없었다.

---

## 8. 저장 형식을 바꿀 때

- **`dbver`는 나가기 전까지 하나만 올린다.** 나간 적 없는 번호를 둘로 쪼개면 세상에 없는 중간
  상태를 위한 단계가 생기고, 그 단계는 아무 데이터도 안 만나면서 영원히 남는다.
- **단계는 오름차순이다.** `MigrateLayer`의 각 단계는 자기 앞 단계가 낸 모양 위에서 돈다.
  순서를 뒤집으면 앞 단계가 찾던 모양이 이미 사라져 있고, `dbver`는 올라가 있어서 다시 돌
  기회가 없다.
- **전송 포맷도 같이 본다.** `DebindStorage/Export.lua`의 `ACTION_FIELDS`와 `CONDITION_TYPES`가 저장 명단과
  맞는지는 `check:export-fields`가 지킨다. 한쪽에만 넣으면 아무 데서도 안 터지고, 받는 쪽은
  조건 하나가 빠진 액션을 얻는다. **더 자주 발동하는 쪽**이다.
