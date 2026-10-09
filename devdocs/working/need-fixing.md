# 고칠 것

> 상태: 남은 항목이 없다. 1(유닛 조건 fold가 갈림)과 2(키트가 방출의 레코드 배치를 따로 베껴 세다 갈림)는
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
> 16(사다리 단계가 지금 코드의 함수를 부름)도 같은 날 고쳐서 뺐다(`debind-6c`). 원칙은 소유자가 냈다. 옛 판에서 유효했던
> 값은 사다리를 타는 동안 그대로 가고, 그 값을 못 쓰게 된 판으로 넘어가는 단계에서만 지워지거나 바뀐다. 단계가 부르던
> 함수는 그 판의 것을 `Migration.lua`에 든다(`UnitConditionAt5`·`At7`, `UnitFrameConditionAt5`, `RenameUnitInMacroTextAt7`).
> 매크로 본문의 유닛 이름 바꾸기는 사다리만 쓰던 것이라 `MacroText.lua`에서 옮겨 왔고, 그쪽에는 남지 않았다. 앞의 둘은
> 바인딩을 짓는 쪽에 지금 판이 따로 남는다. 그쪽은 사다리가 안 닿은 프로필을 읽는 자리인데, `hover`와 `reactions`는
> 저장하지 않는 이름이라 `SanitizeAction`이 모든 문에서 떼므로 지금은 닿는 데이터가 없다.
>
> 쓴 세션: `debind-45` (세션 ID `69a358ab-115a-49d9-9681-65106e3c7003`). 9는 `debind-3e`
> (세션 ID `9c6ce919-05ff-4e0d-aa1f-839f97dff70f`). 10~12는 `debind-32`
> (세션 ID `01cfef58-000e-45b7-b719-95b834c3e734`). 13~15는 `debind-4b`가 `debind-6c`의 보고에서 옮겼다
> (세션 ID `606704f4-0b90-4e5a-93e4-cdefc063f074`). 16은 `debind-6c`(세션 ID `21c5d56d-a7ef-49e7-b1df-24fc109c27b2`).

다른 일을 하다 찾은 결함이다. 그 일의 범위가 아니라 여기 따로 둔다.
