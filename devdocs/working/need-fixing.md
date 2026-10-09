# 고칠 것

> 상태: 미착수. 항목 3, 9, 10, 12, 13, 14. 3은 고칠 것이 아니라 소유자가 정할 기본값 하나로 줄었다(2026-10-09). 1(유닛 조건 fold가 갈림)과 2(키트가 방출의 레코드 배치를 따로 베껴 세다 갈림)는
> 2026-10-08에 고쳐서 여기서 뺐다. 둘 다 같은 규칙을 두 곳 이상에 따로 적어 둔 것이 원인이었다. 4(키트의 Tail 시험
> 넷이 beat와 리빌드를 못 가름)도 같은 날 넷 다 `WaitOnBeat`로 바꿔서 뺐다. 6(`macrotext_spec`이 `EmitMacroTextArg`를
> 베껴 잼)도 같은 날 `BuildMacroTextEntries`가 내는 글을 직접 재게 바꾸고 `bakeFixed`를 지워서 뺐다. 이것도 같은 규칙을
> 두 곳에 적어 둔 것이었다. 5(조건끼리 모든 상태를 덮는 키도 beat에 오름)도 같은 날 고쳐서 뺐다. 그대로 두는 길은
> 소유자가 받지 않았다. `IsAlwaysOurs`가 앞선 "우리 것" 항목들을 합쳐서, 판정 아이템 자신의 열로 묻는다. 7(수동
> 스위치의 `[$x]`·`[no$x]` 키도 beat에 오름)도 같은 날 고쳐서 뺐다. 정의된 스위치는 수동이든 계산식이든 읽는 곳에서
> 늘 켜짐 아니면 꺼짐이라, 그 열은 이제 두 칸이다. "설정 안 됨" 칸은 정의 없는 이름에만 남는다.
> 8(마스크 조건의 범위 밖 비트를 누름과 loop가 다르게 읽음)과 11(빈 `conditions.units`를 접지 않음)은 2026-10-09에 뺐다.
> `SanitizeAction`(`sanitizing-actions-with-one-function.md`)이 불러올 때와 가져올 때 범위 밖 비트를 잘라 내고 빈 `units`를
> 접는다. 메뉴는 둘 다 만들지 않는다.
>
> 쓴 세션: `debind-45` (세션 ID `69a358ab-115a-49d9-9681-65106e3c7003`). 9는 `debind-3e`
> (세션 ID `9c6ce919-05ff-4e0d-aa1f-839f97dff70f`). 10~12는 `debind-32`
> (세션 ID `01cfef58-000e-45b7-b719-95b834c3e734`). 13·14는 `debind-4b`가 `debind-6c`의 보고에서 옮겼다
> (세션 ID `606704f4-0b90-4e5a-93e4-cdefc063f074`).

다른 일을 하다 찾은 결함이다. 그 일의 범위가 아니라 여기 따로 둔다.

## 3. 설정 "Action Button keys"의 기본값

찾은 곳: 344519d 뒤의 빈 에이전트 검토(2026-10-08). 원래는 조건 "Replaced Action Bar"가 애완동물 대전까지 덮던 결함과
함께 적었다. 그 결함은 2125916이 `specialbar`와 `petbattle`을 마스크 `bartakeover` 하나로 합쳐 고쳤다
(`turning-replaced-action-bar-into-bar-takeover.md`). 그 계획 밖이던 이것만 남았다.

지금 기본값은 "Pet Battles"만 켬이다(`giveBackOnReplacedBar` 끔). 끈 근거는 `ActionBindings.lua`의
`GiveBackOnReplacedBar` 주석이다. 바뀐 단축바는 대개 전투 중이라, 그때 키가 다른 일을 하는 것이 곧 손해다. 켤 근거는
"Filled buttons only"를 없앤 근거와 같다(`giving-keys-back-when-no-action-runs.md` 1절). 끄면 차량 기술을 그 키로 못
누른다. 소유자가 생각해 보기로 했다(2026-10-08).

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

## 12. 확인 장치가 불러온 레이어만 본다

찾은 곳: 같은 리뷰.

`tests/canonical.lua`의 `Sweep`은 `GetProfileLayer(1..)`만 훑는다. 도착한 액션을 다른 직업의 칸처럼 불러오지 않은 곳에 놓으면
(`PlaceArrivedActions`의 `StoredActionsAt`) 그 액션은 장치가 보지 못한다. `DebindVars.layers`의 모든 칸을 훑도록 넓혀야 한다.

## 13. 처음 옛 설정을 가져오는 접속에서 합쳐 둔 대기 액션이 사라진다

찾은 곳: `sanitizing-actions-with-one-function.md` 7절 3번(2026-10-09, `debind-6c`가 코드로 확인했다).

`InitDB`의 `MergePendingActions`가 이 캐릭터의 대기 액션을 불러온 레이어로 옮기고 공유 칸에서는 지운다. 그 뒤
`PLAYER_LOGIN`의 `RunLegacyMigration`이 `MergeLayers`로 `into[class][spec]`을 통째로 갈아 끼우고, `LoadProfile`이 갈아 낀
칸을 불러온다. 합쳐 둔 대기 액션은 갈려 나간 옛 칸에만 남아 있다가 사라진다. sanitize 작업 전부터 그랬다. 대기 칸이 있는
캐릭터가 바로 그 접속에서 처음 옛 설정(`Debounce`)을 가져와야 생긴다.

## 14. 계정을 걷는 함수가 다른 캐릭터 칸의 표 아닌 목록과 원소를 그대로 넘긴다

찾은 곳: 같은 일.

`ForEachStoredList`, `ForEachStoredAction`, `ForEachPendingAction`은 다른 캐릭터의 칸을 저장된 그대로 넘긴다. 목록이 표가
아니면 `#`에서, 원소가 표가 아니면 그 원소를 읽는 자리에서 터진다. 읽는 쪽은 스위치 이름 바꾸기
(`RenameSwitchEverywhere`), 스위치 창의 사용처 세기(`CollectSwitchUsage`, `CountSwitchReferences`), 계정 전체 백업
(`BuildAccountPayload`)이다. 다른 캐릭터의 칸은 그 캐릭터로 접속할 때만 sanitize를 지나니
(`sanitizing-actions-with-one-function.md` 2-2), 그 전까지는 손으로 고친 값이 그대로 있다. 그 문서의 7절 3번은 계정 전체
백업의 원소만 막았다. 걷는 함수에서 거를지, 읽는 쪽마다 막을지 정해야 한다.
