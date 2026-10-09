# 고칠 것

> 상태: 미착수. 항목 3, 8, 9, 10, 11, 12. 3은 고칠 것이 아니라 소유자가 정할 기본값 하나로 줄었다(2026-10-09). 1(유닛 조건 fold가 갈림)과 2(키트가 방출의 레코드 배치를 따로 베껴 세다 갈림)는
> 2026-10-08에 고쳐서 여기서 뺐다. 둘 다 같은 규칙을 두 곳 이상에 따로 적어 둔 것이 원인이었다. 4(키트의 Tail 시험
> 넷이 beat와 리빌드를 못 가름)도 같은 날 넷 다 `WaitOnBeat`로 바꿔서 뺐다. 6(`macrotext_spec`이 `EmitMacroTextArg`를
> 베껴 잼)도 같은 날 `BuildMacroTextEntries`가 내는 글을 직접 재게 바꾸고 `bakeFixed`를 지워서 뺐다. 이것도 같은 규칙을
> 두 곳에 적어 둔 것이었다. 5(조건끼리 모든 상태를 덮는 키도 beat에 오름)도 같은 날 고쳐서 뺐다. 그대로 두는 길은
> 소유자가 받지 않았다. `IsAlwaysOurs`가 앞선 "우리 것" 항목들을 합쳐서, 판정 아이템 자신의 열로 묻는다. 7(수동
> 스위치의 `[$x]`·`[no$x]` 키도 beat에 오름)도 같은 날 고쳐서 뺐다. 정의된 스위치는 수동이든 계산식이든 읽는 곳에서
> 늘 켜짐 아니면 꺼짐이라, 그 열은 이제 두 칸이다. "설정 안 됨" 칸은 정의 없는 이름에만 남는다.
>
> 쓴 세션: `debind-45` (세션 ID `69a358ab-115a-49d9-9681-65106e3c7003`). 8과 9는 `debind-3e`
> (세션 ID `9c6ce919-05ff-4e0d-aa1f-839f97dff70f`). 10~12는 `debind-32`
> (세션 ID `01cfef58-000e-45b7-b719-95b834c3e734`).

다른 일을 하다 찾은 결함이다. 그 일의 범위가 아니라 여기 따로 둔다.

## 3. 설정 "Action Button keys"의 기본값

찾은 곳: 344519d 뒤의 빈 에이전트 검토(2026-10-08). 원래는 조건 "Replaced Action Bar"가 애완동물 대전까지 덮던 결함과
함께 적었다. 그 결함은 2125916이 `specialbar`와 `petbattle`을 마스크 `bartakeover` 하나로 합쳐 고쳤다
(`turning-replaced-action-bar-into-bar-takeover.md`). 그 계획 밖이던 이것만 남았다.

지금 기본값은 "Pet Battles"만 켬이다(`giveBackOnReplacedBar` 끔). 끈 근거는 `ActionBindings.lua`의
`GiveBackOnReplacedBar` 주석이다. 바뀐 단축바는 대개 전투 중이라, 그때 키가 다른 일을 하는 것이 곧 손해다. 켤 근거는
"Filled buttons only"를 없앤 근거와 같다(`giving-keys-back-when-no-action-runs.md` 1절). 끄면 차량 기술을 그 키로 못
누른다. 소유자가 생각해 보기로 했다(2026-10-08).

## 8. 마스크 조건의 범위 밖 비트를 누름과 loop가 다르게 읽는다

찾은 곳: 2125916의 `/code-review high`(2026-10-08). 지적은 `bartakeover`였는데, 같은 모양이 다른 마스크에도 있다.

### 무엇이 다르나

마스크 조건에 그 축이 쓰는 비트 밖의 비트만 있으면(예: `groups = 8`, `bonusbars = 64`, `bartakeover = 8`), 누름과
판정 loop가 서로 다른 답을 낸다.

| 필드 | 누름 (`ConditionText.lua`의 `StateAlternatives`) | loop (`Judgment.lua`의 `constrain`) |
|---|---|---|
| `groups` | 세 비트가 다 없으면 맨 끝 갈래로 가서 `[group:raid]` | `band(8, 7) = 0`, 절대 안 맞음 |
| `bonusbars` | 대안이 빈 `{}`라 제한 없음 | 절대 안 맞음 |
| `bartakeover` | 대안이 빈 `{}`라 제한 없음 | 절대 안 맞음 |
| `forms` | 누름도 `GetShapeshiftForm()`의 비트를 대조하니 절대 안 맞음 | 절대 안 맞음. 갈리지 않는다 |

거르는 곳도 없다. 이슈 검사는 `== 0`만 보고(`Issues.lua`), `FillBinding`은 전체 비트가 다 켜졌을 때만 전체값으로 접는다.
메뉴로는 이런 값이 안 생긴다. 손으로 고친 SavedVariables나 붙여넣은 문자열에서만 온다. 붙여넣기는
`CONDITION_TYPES`가 타입(`"number"`)만 본다.

### 고치는 길

애드온이 안 쓰는 값이니 `INVALID_ACTION`이 맞아 보인다(손으로 만든 데이터는 고쳐 주지 않는다는 결정, 2026-10-08). 걸리는
것이 하나 있다. `normalize_spec`의 "범위를 넘는 마스크는 정규 전체값으로 잘린다"가 `ALL * 2 + 1`을 전체값으로 접는 것을
고정한다. 그 테스트는 위 결정보다 먼저 생겼다. 접기를 남길지, 범위 밖 비트가 하나라도 있으면 `INVALID_ACTION`으로 볼지를
정해야 한다.

## 9. 사다리 단계가 지금 판의 표를 읽는다

찾은 곳: 같은 리뷰. `dbver <= 5` 단계가 무엇이 조건인지를 지금의 `Constants.IsConditionField`에 물었다. 그래서 그 표에서
빠진 `pet`, `frameTypes`, `specialbar`, `petbattle`이 5판 이하 프로필에서 옮겨지지 않고 `CleanUpDB`에 지워졌다. 그 단계는
5판의 이름을 직접 들게 고쳤다. 같은 모양이 다른 단계에 남아 있다.

- `dbver <= 1`: `Constants.BASIC_UNITS`, `Constants.SPECIAL_UNITS` (`Migration.lua`의 `checkUnitExists`·`checkedUnit` 옮기기)
- `Constants.SPEC_RESOLVED_TYPES`를 읽는 단계
- `MigrateSwitches`의 `Constants.IsSwitchName`

이 표들이 바뀌면 옛 프로필의 값이 조용히 다르게 옮겨진다. 각 단계가 자기 판의 값을 직접 들게 할지, 그 표가 그 판 이후로
안 바뀌었다는 것만 확인하고 둘지를 단계마다 정해야 한다.

## 10. 메뉴의 "끄기" 칸이 체크를 풀면 `disabled = false`를 쓴다

찾은 곳: `checking-pasted-strings-and-keeping-actions-canonical.md` 3절 3번의 `/code-review high`(2026-10-09).

"끄기"는 `USE_CHECKED_VALUE`(`MenuKit.TOGGLE`)로 쓰고, 토글은 꺼짐을 nil이 아니라 `false`로 쓴다(`MenuKit.lua`의
`setValue`). 키 결과는 nil과 같지만, 같은 액션인지 묻는 비교(`IDENTITY_FIELDS`)에는 다른 값이라 한 번 켰다 끈 액션과 손대지
않은 액션이 다르게 읽히고, 내보내기에도 `disabled = false`가 실린다. `FoldIntoStoredShape`도 확인 장치(`tests/canonical.lua`)도
이 값을 보지 않는다. 쓰는 쪽에서 nil을 쓸지, 접기에 넣을지 정해야 한다.

## 11. 빈 `conditions.units = {}`를 접지 않는다

찾은 곳: 같은 리뷰.

메뉴는 유닛 조건을 다 지우면 `units`를 nil로 둔다(`ActionMenuModel.lua`의 `WriteUnitConditionMode`, `ActionMenuNodes.lua`의
`WritePlayerLife`). 붙여넣은 문자열의 `units = {}`는 타입 검사(`"table"`)를 지나 그대로 들어와 `conditions`를 비지 않은 표로
남긴다. 바인딩은 `units`를 늘 떼고 다시 세우니(`FillBinding`) 키 결과는 같지만, 같은 액션인지 묻는 비교(`IDENTITY_FIELDS`)에는
메뉴가 만든 같은 액션과 다르게 읽히고 내보내기에도 실린다. 접을지 정해야 한다.

## 12. 확인 장치가 불러온 레이어만 본다

찾은 곳: 같은 리뷰.

`tests/canonical.lua`의 `Sweep`은 `GetProfileLayer(1..)`만 훑는다. 도착한 액션을 다른 직업의 칸처럼 불러오지 않은 곳에 놓으면
(`PlaceArrivedActions`의 `StoredActionsAt`) 그 액션은 장치가 보지 못한다. `DebindVars.layers`의 모든 칸을 훑도록 넓혀야 한다.
