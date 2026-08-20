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
    key                 걸린 키. 없으면 이 액션은 아무 데도 안 걸린다.
                        **숫자는 아직 키를 안 정한 키 그룹이다** (`NextSyntheticKey`)
    name icon           표시 전용. 솔버도 런타임도 안 읽는다
    unit                겨누는 대상. `UNIT_INFO`의 키. **조건이 아니다** (§2)
    seq                 자기 키 그룹 안에서의 자리, 1..n. 그룹이 바뀔 때마다 다시 매겨진다
                        (`Profile.lua`의 `RenumberKeyGroup`)
    priority            숫자. 없으면 `Constants.DEFAULT_PRIORITY`
    imported            도착한 키. **이게 있는 동안 이 액션은 격리된다.** 프로필에 있고,
                        그려지고, 아무 키에도 안 걸린다 (`BuildKeyMap`)
    keepInBindingContext
                        게임이 가져간 키에도 그래도 걸 것이냐. 조건이 아니라 예외다
    ignoreHoverUnit     겨누는 것을 바꾼다 (§2)
    conditions          **언제 발동하느냐. 전부 이 안에 있다** (§3)
```

**`KEYS_TO_SAVE`가 유일한 명단이다.** 거기 없는 필드는 누가 써넣든 `CleanUpDB`가 걷어내므로
저장되지 않는다.

---

## 2. 조건이 아닌 것 셋

이름이나 자리 때문에 조건으로 읽히기 쉬운데 아닌 것들이다. 셋 다 **겨누는 것**이나
**예외**를 말한다.

**`unit`은 액션이 겨누는 대상이다.** 매크로의 `[@unit]`이라 동작 자체가 바뀐다. 쓰는 것은
`Target` 메뉴의 라디오뿐이다. 그 메뉴가 이슈 갈래로 `"unit"`을 넘기므로
`GetBindingIssue(action, "unit")`은 **겨눌 대상의 문제**를 묻는 것이지 유닛 조건을 묻는 것이
아니다.

**`conditions.units`는 정반대다.** 언제 발동하느냐이고 동작은 안 바뀐다. `Units`
메뉴가 쓰고, `Target` 메뉴의 아래쪽 절반도 `"@"`로 여기에 쓴다.

**`ignoreHoverUnit`은 조건이 아니다.** `binding.unit`을 빈 문자열로 두느냐 `"hover"`로
채우느냐를 가른다. 겨누는 것을 바꾸지 언제 나가는지를 바꾸지 않는다.

---

## 3. conditions

```
action.conditions
    units               { [유닛 이름 또는 "@"] = 조건 }. `"@"`는 `unit`이 가리키는 유닛을
                        가리키는 포인터라, `unit`이 없어지면 같이 죽는다
    frameTypes          `FRAMETYPE_*` 마스크. **유닛이 아니라 프레임**을 말한다.
                        호버 조건이 없으면 뜻이 없다
    groups              `GROUP_*`      forms      `FORM_*`      bonusbars  `BONUSBAR_*`
    combat stealth pet petbattle specialbar extrabar
                        true | false | nil
    known               true | nil, 그리고 주문일 때만. **다른 것들과 달리 세 번째 값이 없다.**
                        자기 주문에 대해 묻는 것이라 `false`는 "안 배웠을 때만 시전"이 되고
                        그런 상태는 없다
    $state1..$state5    true | false | nil. 커스텀 상태 조건
```

**어느 이름이 조건인지는 `Constants.IsConditionField` 하나가 답한다.** 목록을 다시 적지 말 것.
그 함수는 `CONDITION_FIELDS`에 없어도 **`$`로 시작하면 조건**이라고 답하는데, 커스텀 상태가 그
이름으로 저장되고 재설계가 슬롯 다섯을 임의 이름으로 풀기 때문이다
(`redesigning-custom-states.md`).

**빈 표는 안 남긴다.** 저장 쪽은 `CleanUpDB`가, 편집 쪽은 `DropDownMenus.lua`의
`PruneConditions`가 지운다. 표가 있느냐를 게이트로 쓰는 자리가 있어서, 빈 표는 조건이 하나도
없는 액션을 조건부로 만든다. 그러면 발동 순서가 바뀐다.

**`hover`와 `reactions`는 더 이상 저장되지 않는다.** `dbver <= 4`가 둘을
`units["hover"]`로 접었다(그때 이름은 `checkedUnits`였고, `dbver <= 5`가 옮기면서 바꿨다).
마이그레이션이 안 닿은 프로필과 그 전에 공유된 문자열에는
아직 있고, `HoverConditionFromLegacy`가 **사본 위로** 들어올린다.

---

## 4. binding

액션 하나의 순수 파생이다. `GetBindingInfoForAction`이 리빌드마다 **제자리에서** 다시 채운다.

```
binding
    type value key unit ignoreHoverUnit     액션에서 그대로. `unit`만 다르다(아래)
    conditions                              정규화된 조건. 액션 쪽과 같은 이름, 다른 값
    hover                                   true | false | nil
    unitStates unitStatesOpaque             솔버가 유닛에 대해 읽는 전부
```

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

유닛만 예외로 `t.units[유닛]`으로 한 겹 들어간다. 축이 셋이라(`exists`/`reaction`/`dead`)
평평하게 펴면 유닛마다 이름이 셋씩 늘어난다.

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

셋은 그 이름의 액션 필드가 아예 없다. `hover`와 `reactions`는 저장에서 접혔고, `macro`는
"매크로 이름이 가리키는 것이 없다"를 뜻한다. 거꾸로 조건인데 갈래가 없는 것도 있다. `combat`이나
`known`에는 모순을 잡는 검사가 아직 없다.

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
- **전송 포맷도 같이 본다.** `Export.lua`의 `ACTION_FIELDS`와 `CONDITION_TYPES`가 저장 명단과
  맞는지는 `check:export-fields`가 지킨다. 한쪽에만 넣으면 아무 데서도 안 터지고, 받는 쪽은
  조건 하나가 빠진 액션을 얻는다. **더 자주 발동하는 쪽**이다.
