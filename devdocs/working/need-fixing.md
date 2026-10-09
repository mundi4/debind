# 고칠 것

> 상태: 미착수. 항목 3, 9. 3은 고칠 것이 아니라 소유자가 정할 기본값 하나로 줄었다(2026-10-09). 1(유닛 조건 fold가 갈림)과 2(키트가 방출의 레코드 배치를 따로 베껴 세다 갈림)는
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
> 10(메뉴의 "끄기" 칸이 `disabled = false`를 씀)도 2026-10-09에 고쳐서 뺐다. 메뉴의 `ActionValues.Set`이 `disabled`의
> `false`를 nil로 접고, 확인 장치(`tests/canonical.lua`)도 이제 그 값을 잡는다(`sanitizing-actions-with-one-function.md`
> 7절 4번, `debind-6c`).
> 13·14·15는 2026-10-09에 다루지 않기로 하고 `0-IDEAS.md`로 옮겼다(소유자). 왜 지금 안 하는지와 무엇이 바뀌면 다시
> 보는지는 거기 있다.
> 12(확인 장치가 불러온 레이어만 봄)도 같은 날 고쳐서 뺐다(`debind-6c`). `tests/canonical.lua`가 불러온 레이어에 더해
> `DebindVars.layers`의 모든 칸, 아직 안 붙은 이 캐릭터의 칸, 모든 캐릭터의 `pendingActions`를 훑고, 찾은 것마다 자리를
> 같이 적는다. 표가 있어야 할 자리의 다른 값, 이름 밑이나 구멍 너머의 원소도 알린다. 장치가 그 자리들에 닿는지는
> `canonical_spec`이 묻는다.
>
> 쓴 세션: `debind-45` (세션 ID `69a358ab-115a-49d9-9681-65106e3c7003`). 9는 `debind-3e`
> (세션 ID `9c6ce919-05ff-4e0d-aa1f-839f97dff70f`). 10~12는 `debind-32`
> (세션 ID `01cfef58-000e-45b7-b719-95b834c3e734`). 13~15는 `debind-4b`가 `debind-6c`의 보고에서 옮겼다
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
