> 상태: §8의 세 단계를 구현했다. **§6-2(스위치 게이트)는 아직 제안이고**, §8이 순서를 안 매겨
> 둔 것도 그것 하나다. 어느 층이 무엇을 덮고 무엇을 원리상 못 보는지는 §7이 든다.

# `known` 조건을 리빌드 때 굽기

`known` 조건이 걸린 레코드는 지금 두 군데에서 매번 다시 잰다. 5Hz 상태 루프가
`SecureCmdOptionParse("[known:<id>]")`를 상태마다 한 번씩 돌리고(`UpdateBindings.lua`의
`[known:` 갈래), 클릭 경로가 레코드마다 같은 파싱을 한 번 더 한다
(`SecureBindings.lua:1522`).

그럴 필요가 없는 주문이 있다. 어떤 주문의 `known` 답은 다음 리빌드 전에는 절대 안 움직이고, 그런
주문은 리빌드 때 한 번 재서 결과를 굽고 축에서 빼면 된다.

## 1. 이 최적화가 필요한 이유

레이어는 전문화까지만 따라간다. "이 특성을 찍었나"를 묻는 수단은 `known`뿐이므로, 특성을 자주
갈아치우는 사람일수록 여러 주문에 `known`을 바른다. 전장을 뛰는 쪽이 특히 그렇다. 즉 이 축은
드물게 쓰이는 축이 아니라, 특성을 많이 만지는 프로필에서 가장 두꺼워지는 축이다.

그리고 그렇게 발린 것들이 정확히 이 최적화가 걷어내는 쪽이다. 특성으로 오는 주문이라 표에 잡히고,
특성 변경은 전투 밖에서 리빌드를 낸다.

**한 번 재는 값도 다른 축보다 비싸다.** 나머지 축은 화이트리스트에 오른 함수를 그냥 부른다
(`Constants.STATE_EVAL_EXPRESSIONS`의 `PlayerInCombat()`, `IsStealthed()`, `GetShapeshiftForm()`
같은 것들). `known`은 그런 함수가 없어서 매크로 조건식을 문자열로 넘기고 `SecureCmdOptionParse`가
파싱하게 하는 수밖에 없다. 파싱을 거치는 축은 `petbattle`과 `known` 둘뿐인데, 앞엣것은 프로필이
아무리 커도 한 번이고 `known`은 **서로 다른 주문 수만큼**이다. 단가가 높은 쪽이면서 개수가
프로필을 따라 자라는 유일한 축이다.

## 2. 두 물음을 가른다

이 설계의 척추다. 섞으면 틀린다.

**지금 답이 무엇인가.** 리빌드 때 비보안 쪽에서 `SecureCmdOptionParse("[known:<id>]")`를 그대로
부른다. 스니펫이 쓰는 것과 **같은 함수에 같은 문자열**이므로 정의상 답이 갈릴 수 없다.
`IsPlayerSpell`을 다시 구현하지 않는다. 그러면 "`[known:]`이 정말 `IsPlayerSpell`인가"라는 물음
자체가 안 생긴다.

**다음 리빌드 전에 바뀔 수 있는가.** 이건 분류표가 답한다. 표는 답을 계산하지 않는다. 답이
고정인지만 말한다.

**틀리는 방향이 대칭이 아니다.** 표에 빠지면 지금처럼 매 틱 재게 되므로 정답이고 최적화만 못
한다. 표에 잘못 들어가면 전투 중에 답이 뒤집혀도 안 고쳐지고, 키 하나가 아무 소리 없이 죽는다.
그러므로 **확실할 때만 넣는다**가 표를 만드는 유일한 규칙이다.

## 3. 분류표

새 파일 `Debind/KnownSpells.lua`. `Debind.xml`에서 `UpdateBindings.lua`보다 앞에 둔다.

`spellID -> 레벨` 하나짜리 표다. 뜻은 "이 주문의 `known` 답은 캐릭터가 그 레벨에 이른 뒤로는 다음
리빌드 전에 안 바뀐다"이고, 세 갈래를 한 표에 합친다. 특성과 PvP로 들어오는 주문은 레벨을 안
타므로 `0`이 들어가고, 레벨로 배우는 기본 주문은 배우는 레벨이 들어간다.

**표는 레벨을 안 탄다.** 아직 못 배운 주문도 주문책에 배우는 레벨을 달고 그대로 있으므로, 어느
레벨에서 만들어도 같은 표가 나온다. 레벨업이 표를 낡게 만들 수가 없다.

**두 갈래가 같은 주문을 넣으면 높은 레벨이 남는다.** 아직 못 이른 레벨이 전투 중에 답을 뒤집을
수 있는 유일한 것이라, 낮은 쪽을 남기면 리빌드 없이 참이 될 답을 거짓으로 접게 된다.

### 3-1. 레벨로 배운 기본 주문

레벨은 안 내려가므로, 이미 배운 기본 주문은 잊는 경로가 없다. 이건 우리 이벤트 목록에 기대는
논증이 아니라 세상에 대한 사실이라, 우리가 모르는 계기가 전투 중에 터져도 바꿀 것이 없다.

주문책을 도는 코드는 이미 있다. `ActionCatalog.lua:591-618`이 `GetNumSpellBookSkillLines`와
`GetSpellBookSkillLineInfo(i)`로 스킬라인을 나눠 돌고, `itemIndexOffset`과 `numSpellBookItems`로
슬롯 범위를 잡는다. 같은 모양을 쓴다.

- `Enum.SpellBookSpellBank.Player`만 돈다. **펫 뱅크는 안 돈다.** 소환으로 전투 중에 주문책이
  바뀐다.
- 항목마다 `C_SpellBook.GetSpellBookItemInfo`.
- `C_SpellBook.GetSpellBookItemLevelLearned(slot, bank)`이 값을 주면 그 값을 넣는다. 카탈로그가
  이미 이 API로 "레벨 40에 배웁니다" 부제를 그리고 있다(`ActionCatalog.lua:484`). 아직 안 배운
  주문(`Enum.SpellBookItemType.FutureSpell`)도 같이 넣는다. 걸러내는 것은 표가 아니라 굽는
  자리이고, 거기서 `UnitLevel("player")`과 대보면 된다.
- 넣는 키는 셋이다. `info.spellID`, `info.actionID`, 그리고
  `C_SpellBook.FindBaseSpellByID(info.spellID)`. 사용자가 어느 ID로 저장했는지가 갈리기
  때문이다. 카탈로그는 base로 되돌려 저장하고(`ActionCatalog.lua:469`), `binding.spell`은 다른
  길로 올 수 있다.

### 3-2. 특성으로 오는 주문

특성 변경은 전투 중에 불가능하고 `TRAIT_CONFIG_UPDATED`가 리빌드를 낸다(`Events.lua:169`).
전문화 변경도 마찬가지다(`Events.lua:250`).

- `C_ClassTalents.GetActiveConfigID()`로 설정을 잡고, `C_Traits.GetConfigInfo(configID).treeIDs`로
  트리를 잡는다.
- 트리마다 `C_Traits.GetTreeNodes(treeID)`가 노드 ID를 전부 준다. 문서가 "Contains nodes for all
  class specializations"라고 적어둔 그 목록이다(`SharedTraitsDocumentation.lua:523`).
- 노드마다 `C_Traits.GetNodeInfo(configID, nodeID)`.
- **`entryIDs`를 돈다.** `entryIDsWithCommittedRanks`도 `activeEntry`도 아니다. 여기가 이번에
  제일 놓치기 쉬운 자리다. 하나의 특성이 두 주문 중 하나를 고르게 하는 노드는
  `Enum.TraitNodeType.Selection`이고(`TraitConstantsDocumentation.lua:259`), **안 고른 쪽 주문도
  표에 들어가야 맞다.** 그 주문의 `known`이 특성으로 움직이기 때문이다. 블리자드 자신의 주문
  검색도 `entryIDs`를 돈다(`Blizzard_SpellSearchNameFilter.lua:60`,
  `Blizzard_SpellSearchTextFilter.lua:53`, `:134`). 찍은 것만 보는
  `entryIDsWithCommittedRanks`는 액션바 표시에만 쓴다(`Blizzard_SpellSearchUtil.lua:109`).
- 엔트리마다 `C_Traits.GetEntryInfo(configID, entryID)`. `definitionID`가 nil이면 서브트리 선택
  노드의 엔트리다(`SharedTraitsDocumentation.lua:980`). 주문이 아니라 건너뛴다.
- `C_Traits.GetDefinitionInfo(definitionID)`에서 **`spellID`와 `overriddenSpellID`를 둘 다**
  넣는다. 뒤엣것은 이 특성이 덮어쓰는 기본 주문이고, 특성을 찍고 빼는 것이 그 기본 주문의
  `known`을 움직일 수 있는 자리다. 3-1에서 이미 들어갔더라도 겹치는 것은 무해하다.
- **영웅 특성은 따로 안 돈다.** 별도 트리가 아니라 같은 설정 안의 서브트리이고, 서브트리 노드에
  `subTreeID`가 붙어 있을 뿐 `GetTreeNodes`가 전부 준다(`SharedTraitsDocumentation.lua:1039`).
  `subTreeActive`는 안 본다. 안 고른 서브트리의 주문도 표에 들어가야 맞다.

### 3-3. PvP 특성

- 슬롯 번호 1부터 `C_SpecializationInfo.GetPvpTalentSlotInfo(i)`가 nil을 줄 때까지 돈다. 개수를
  적어두지 않는 이유는 그 숫자가 판마다 갈리기 때문이고, nil로 끊는 것은 블리자드 UI가 하는 것과
  같은 모양이다.
- 슬롯의 `availableTalentIDs`를 쓴다(`SpecializationInfoDocumentation.lua:498`). 찍은 것
  (`selectedTalentID`)이 아니라 **그 전문화에서 고를 수 있는 전부**다.
- 특성 ID마다 `C_SpecializationInfo.GetPvpTalentInfo(id).spellID`
  (`SpecializationInfoDocumentation.lua:482`).

## 4. 언제 만드나

로그인에 한 번, 그리고 전문화가 바뀌어 처음 만나는 전문화마다 한 번. 전문화 번호로 캐시한다.

특성을 찍고 뺄 때마다 다시 만들 필요가 없다. 물어보는 것이 "지금 이 특성이 찍혀 있나"가 아니라
"이 주문이 특성으로 오는 주문인가"라서, 답이 선택의 성질이 아니라 트리의 성질이다. 트리는 패치
전까지 안 바뀐다.

`C_ClassTalents.GetActiveConfigID()`는 지금 전문화의 설정을 준다. 다른 전문화를 보려면 그
전문화로 바꿔야 하고, 바꾸면 새로 만나는 전문화라 그때 만든다. 그래서 늘 활성 설정만 읽으면 된다.

레벨업으로는 다시 안 만든다. 표가 담는 것이 "배웠나"가 아니라 "몇 레벨에 배우나"라서 레벨을 안
타기 때문이다.

## 5. 굽는 자리

`UpdateBindings.lua:1913-1922`. 지금은 파생 축이 무조건 `[known:<spell>]`을 굽는다.

주문 ID를 구한 다음 표에 묻는다. 표에 값이 있고 그 값이 `UnitLevel("player")` 이하이면 이 주문의
답은 고정이다. 셋으로 갈린다.

- **고정이고, 지금 참이다.** `known` 필드를 아예 안 굽는다. 조건이 이미 만족이다.
- **고정이고, 지금 거짓이다.** 이 리빌드 동안 이 레코드는 절대 안 맞으므로 **키 목록에서 뺀다.**
  런타임이 지금 하는 일(`SecureBindings.lua:1522`가 레코드를 건너뛰고 다음 레코드로 넘어간다)과
  결과가 같다.
- **고정이 아니다.** 지금 그대로 `[known:<spell>]`을 굽는다. 표에 없는 주문과, 표에 있지만 아직
  그 레벨에 못 이른 주문이 여기다. 뒤엣것은 전투 중에 레벨이 올라 답이 참으로 뒤집힐 수 있어서
  거짓으로 접으면 안 되는 자리다.

이러면 그 문자열이 `_measuredStates`에 안 들어가고, 따라서 5Hz 루프의 파싱이 빠지고,
`UpdateBindings.lua:622-628`의 `SPELLS_CHANGED` 등록도 같이 빠지고, 클릭 경로의 검사도 빠진다.

## 6. 딸려 오는 두 곳

### 6-1. 목록에 적히는 말

정적으로 거짓이라 빠진 바인딩은 화면에 이유가 있어야 한다. 이미 있는 것을 쓴다.
`row.noSpell`(`Profile.lua:2739`)이 그 자리이고, 문구는 `ORDER_FLAG_NO_SPELL`
(`DebindUI.lua:4477`, `Locales/enUS.lua:832`의 "No spell")이다.

지금 `noSpell`은 "물어볼 주문이 없다"(전문화가 해당 주문을 안 가진다)만 담는데, 여기에 "주문은
있는데 안 배웠다"가 더 붙는다. 사용자가 읽는 말로는 둘 다 "그 주문이 없다"이므로 문구는 그대로
간다.

`IsRowOffSpec`(`Ordering.lua:168`)이 이미 `noSpell`을 전문화 행들과 같이 묶어두고 있다. 이
경우를 되돌리는 것이 특성 변경이므로 그 분류가 그대로 맞다.

`KnownConditionCanHold`(`Misc.lua:1316`)는 안 건드린다. 다른 물음이다.

### 6-2. 스위치 게이트

**여기가 가장 크게 버는 자리다.** 계산식 스위치는 게이트가 있으면 그 더티 플래그가 섰을 때만
파싱한다(`UpdateBindings.lua:2838-2851`). 게이트를 만드는 것은
`CollectSwitchGate`/`SwitchGateFlag`이고, 못 알아본 토큰이 하나라도 있으면 **식 전체가**
게이트를 못 갖는다.

`known`은 `SWITCH_GATE_STATES`에 없다. 그래서 스위치 식에 `[known:...]`이 하나만 들어가도 그
스위치는 게이트를 영영 못 갖고, 식 전체를 0.2초마다 `SecureCmdOptionParse`에 통째로 넘긴다.
토큰 하나가 아니라 식 하나가 통째로다.

§5가 고정이라고 판정하는 주문이면 그 토큰은 이 리빌드 동안 상수다. 상수는 답을 못 움직이므로
**플래그를 안 내는 토큰**으로 처리하면 된다. 지금처럼 "못 알아봤다"로 처리하지 않는다. 그러면
나머지 토큰이 전부 알아볼 수 있는 것일 때 스위치가 게이트를 되찾는다.

- **숫자 인자만 받는다.** `(no)known:<number>`다. 이름 인자
  (`[known:주문이름]`)는 이름에서 ID로 내려가는 단계가 하나 더 붙고 그 단계가 확실하지 않으므로
  지금처럼 게이트를 포기한다. `SwitchGateFlag`는 앞의 `no`를 이미 떼고 나서 단어를 보므로
  (`UpdateBindings.lua`) `noknown:123`도 같은 갈래로 들어온다.
- **"플래그가 없다"와 "못 알아봤다"를 갈라야 한다.** `CollectSwitchGate`는 지금 아무것도 안
  담기면 `nil`을 돌려주고, 호출부는 그 `nil`을 "게이트 없음"으로 읽는다
  (`UpdateBindings.lua:310`). 토큰이 전부 정적 `known`인 식이 정확히 그 모양이 되므로, 빈
  게이트는 `nil`이 아니라 **빈 표**로 돌려줘야 한다. 그러면 나가는 줄이
  `if (DirtyFlags.forceAll) then`이 되고, 이건 리빌드가 여는 첫 패스에서 한 번 재고 그 뒤로는
  안 재는 것이라 뜻이 맞다.
- 고정이 아닌 `known`은 지금 그대로 게이트를 포기한다.

**식이 통째로 정적이면 게이트가 아니라 아예 뺀다.** `[known:xxx]` 하나짜리 식은 리빌드 때 값이
참이나 거짓으로 완전히 정해진다. 그러면 상태 루프에 줄을 낼 이유가 없다. `BuildSwitchesSnippet`이
이미 리빌드마다 `SetSwitch(이름, 값, true)`를 내고 있으므로(`UpdateBindings.lua:536-538`) 거기에
계산된 값을 리터럴로 실어 보내고, "Update Switches" 쪽에는 아무것도 안 낸다.
`SwitchExpressions[이름]`도 안 쓴다. 파싱이 리빌드당 1회가 아니라 0회가 된다.

이게 바로 아래 문단의 `$traitx_on` 모양이 도달하는 자리다.

**식은 안 고친다.** 정적 토큰을 지워봐야 그룹에 다른 토큰이 남으면 파싱할 토큰 하나가 줄
뿐이고(`[noknown:x, combat]`과 `[combat]`은 사실상 같다), 거짓으로 접히는 토큰은 지우려면
뒤따르는 값까지 손대야 해서 식을 구조로 뜯게 된다. `known:0` 같은 고정 거짓으로 갈아치우는
길도 있지만 그것도 조건문 파싱 한 번이라 셈이 그대로다. 문자열을 건드려서 버는 것이 없으므로
건드리지 않는다. 게이트만 고친다.

**이 축을 제일 잘 쓰는 모양이 지금은 제일 비싼 모양이다.** 특성을 자주 갈아치우는 사람이 같은
검사를 여러 키에서 재사용하려면 `[known:<id>]` 하나짜리 스위치를 만들어 이름으로 참조하는 것이
자연스러운 길이다. 그런데 그 스위치가 게이트를 못 가지므로 식이 0.2초마다 파싱된다. 참조하는
쪽은 공짜다. 스위치 이름은 `SetSwitch`가 `DirtyFlags[name]`을 세우고 클릭 경로는 `States`에서
바로 읽는다. 즉 비용이 전부 그 한 스위치에 몰려 있고, 위 변경이 그것을 리빌드당 한 번으로
바꾼다.

### 6-3. 솔버

`Solver.lua:300-302`가 `known`을 주문마다 컬럼으로 세운다. 정적으로 참이면 그 축이 사라져 컬럼이
하나 줄고, 정적으로 거짓이면 바인딩 자체가 없다. 둘 다 지금 런타임과 결과가 같아야 한다. 참이면
항상 통과하고 거짓이면 항상 건너뛰기 때문이다. 다만 이건 말로 한 논증이므로 §7이 스펙으로 잡는다.

## 7. 어느 층이 무엇을 보나

**헤드리스 스펙이 보는 것.** 분류기를 순수 함수로 짜고 WoW API를 주입받게 하면 전부 헤드리스로
간다. `Ordering.lua`가 이미 그 모양이다.

- 선택 노드에서 **안 고른 쪽 주문이 표에 들어오는지.** 이번에 제일 놓치기 쉬운 것이므로
  `entryIDsWithCommittedRanks`로 짠 구현에 대고 먼저 빨간 것을 본다.
- `overriddenSpellID`가 표에 들어오는지.
- 서브트리 노드의 주문이, 그 서브트리를 안 골랐어도 표에 들어오는지.
- `definitionID`가 nil인 엔트리에서 안 죽는지.
- 아직 안 배운 주문이 배우는 레벨을 달고 표에 들어오는지, 펫 뱅크가 빠지는지. 같은 주문책에
  대고 레벨만 달리 물었을 때 표가 같은지.
- PvP 슬롯을 nil에서 끊는지, `availableTalentIDs` 전부를 넣는지.
- 굽기 세 갈래. 고정이고 참이면 필드 없음, 고정이고 거짓이면 바인딩 없음, 고정이 아니면
  `[known:<id>]` 그대로. 아직 그 레벨에 못 이른 주문이 셋째 갈래로 가는지도 같이 본다.
  `_measuredStates` 내용과 `SPELLS_CHANGED` 등록까지 같이 본다.
- 정적으로 참인 `known`이 발동 순서를 안 바꾸는지. 제한 환경에 그 주문을 **안 알려준 채로**
  물어야 뜻이 산다. 축이 남아 있으면 거기서 지므로, 이기는 것이 곧 축이 없다는 말이다.
- 정적으로 거짓이라 빠진 레코드가 이겼는지 졌는지가 아니라 **개수로** 확인되는지. 하나 빠지면
  뒤 레코드의 번호가 당겨져서 이긴 번호만 보면 둘이 안 갈린다.
- 정적으로 거짓인 행에 `noSpell`이 서고 참인 행에는 안 서는지.

**원리상 못 보는 것.** 표가 실제 클라이언트에서 진짜로 그 주문들을 담는지는 헤드리스가 못 본다.
주입한 가짜 API가 답하는 것이라, 검증되는 것은 우리 순회 논리뿐이고 블리자드가 그 필드에 무엇을
넣는지가 아니다. 세 갈래(레벨, 클래스와 전문화 트리, PvP), 선택 노드 양쪽, 영웅 특성 서브트리가
여기 해당한다. 이건 게임 안에서만 답이 난다.

## 8. 순서

1. `KnownSpells.lua`와 그 스펙. 여기까지는 굽는 쪽을 안 건드린다.
2. `UpdateBindings.lua`의 굽는 자리와 그 스펙.
3. `noSpell` 확장과 솔버 확인 스펙.
