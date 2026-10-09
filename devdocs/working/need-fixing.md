# 고칠 것

> 상태: 미착수. 항목 3, 16. 3은 고칠 것이 아니라 소유자가 정할 기본값 하나로 줄었다(2026-10-09). 1(유닛 조건 fold가 갈림)과 2(키트가 방출의 레코드 배치를 따로 베껴 세다 갈림)는
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
> 9(사다리 단계가 지금 판의 표를 읽음)도 같은 날 고쳐서 뺐다(`debind-6c`). 사다리의 단계마다 자기 판의 표, 타입 이름,
> 비트를 직접 든다(`_AT_N`). 비교하는 값도 쓰는 값도 그렇다. 페이로드의 같은 단계(`RenameManifestSwitchFields`)와 옛 설정
> 가져오기의 `/click` 고치기(`RepairLegacyClickTargets`)도 같다. 규칙은 `MigrateLayer` 머리주석에 있다. 이미 어긋나 있던 것이
> 둘이었다. 1 -> 2 단계는 지금 표가 `unitframe`이라 부르는 개체창 유닛을 1판 이름 `hover`로 묻지 못해 옮기지 않았다.
> 6 -> 7 단계가 읽던 표에는 그 뒤에 더해진 `dispel2`가 들어 있었다. 6판 데이터에는 없는 타입이라 결과는 같았다. 단계가
> 부르는 지금 코드의 함수는 크기가 다른 일이라 16번으로 따로 뒀다.
>
> 쓴 세션: `debind-45` (세션 ID `69a358ab-115a-49d9-9681-65106e3c7003`). 9는 `debind-3e`
> (세션 ID `9c6ce919-05ff-4e0d-aa1f-839f97dff70f`). 10~12는 `debind-32`
> (세션 ID `01cfef58-000e-45b7-b719-95b834c3e734`). 13~15는 `debind-4b`가 `debind-6c`의 보고에서 옮겼다
> (세션 ID `606704f4-0b90-4e5a-93e4-cdefc063f074`). 16은 `debind-6c`(세션 ID `21c5d56d-a7ef-49e7-b1df-24fc109c27b2`).

다른 일을 하다 찾은 결함이다. 그 일의 범위가 아니라 여기 따로 둔다.

## 3. 설정 "Action Button keys"의 기본값

찾은 곳: 344519d 뒤의 빈 에이전트 검토(2026-10-08). 원래는 조건 "Replaced Action Bar"가 애완동물 대전까지 덮던 결함과
함께 적었다. 그 결함은 2125916이 `specialbar`와 `petbattle`을 마스크 `bartakeover` 하나로 합쳐 고쳤다
(`turning-replaced-action-bar-into-bar-takeover.md`). 그 계획 밖이던 이것만 남았다.

지금 기본값은 "Pet Battles"만 켬이다(`giveBackOnReplacedBar` 끔). 끈 근거는 `ActionBindings.lua`의
`GiveBackOnReplacedBar` 주석이다. 바뀐 단축바는 대개 전투 중이라, 그때 키가 다른 일을 하는 것이 곧 손해다. 켤 근거는
"Filled buttons only"를 없앤 근거와 같다(`giving-keys-back-when-no-action-runs.md` 1절). 끄면 차량 기술을 그 키로 못
누른다. 소유자가 생각해 보기로 했다(2026-10-08).

## 16. 사다리 단계가 지금 코드의 함수를 부른다

찾은 곳: 9번을 고치면서(2026-10-09, `debind-6c`). 9번은 단계가 읽는 표와 값을 그 판의 것으로 바꿨다. 단계가 부르는
함수는 남았다. 함수의 답은 지금 코드의 규칙을 따르니, 그 규칙이 바뀌면 옛 프로필이 조용히 다르게 옮겨진다.

- `dbver <= 4`(개체창 조건 접기): `UnitFrameConditionFromLegacy`, `UnitConditionForBinding`
- `dbver <= 6`(번호 다시 매기기의 조건 판정, 개체창 조건을 `casting`으로 옮기기): `UnitConditionForBinding` 세 번
- `dbver <= 6`(유닛 이름 바꾸기, 액션과 스위치 식): `RenameUnitInMacroText`

`UnitConditionForBinding`은 이미 그것을 부르는 단계보다 새 모양을 읽는다. 그 함수의 주석이 "옛 이름 `off`는 여기서
읽지 않는다"고 한다. `off`를 `disabled`로 바꾸는 것은 `dbver <= 6` 단계이고, `dbver <= 4` 단계가 그 함수를 부른다.

클라이언트에 묻는 둘은 이 항목이 아니다. `dbver <= 6` 단계의 `C_Spell.GetSpellName`과 `MigrateDB`의 `CanonicalSpellID`다.
코드의 규칙이 아니라 게임의 자료를 읽는 것이고, `CanonicalSpellID` 쪽은 그렇게 읽는 것이 소유자의 결정이다(그 자리의 주석).

고치려면 함수의 그 판 모양을 단계 안에 옮겨 적어야 한다. 표 하나를 옮기는 것보다 큰 일이다. `RenameUnitInMacroText`는
매크로 본문 파서다. `dbver <= 4` 단계의 주석은 반대 까닭도 적는다. 바인딩을 짓는 쪽도 사다리가 아직 안 닿은 프로필을 같은
규칙으로 올려야 하는데, 두 벌로 적으면 그 규칙이 갈린다는 것이다.
