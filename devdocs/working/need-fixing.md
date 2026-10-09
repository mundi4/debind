# 고칠 것

> 상태: 미착수. 항목 18. 17(바인딩 쪽이 옛 저장 모양을 읽음)은 2026-10-10에
> `cleaning-up-old-shapes-in-the-unreleased-step.md`로 옮겼다(`debind-af`). 1(유닛 조건 fold가 갈림)과 2(키트가 방출의 레코드 배치를 따로 베껴 세다 갈림)는
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
> 바인딩을 짓는 쪽에 지금 판이 따로 남는다. 그것은 `cleaning-up-old-shapes-in-the-unreleased-step.md`가 다룬다.
>
> 쓴 세션: `debind-45` (세션 ID `69a358ab-115a-49d9-9681-65106e3c7003`). 9는 `debind-3e`
> (세션 ID `9c6ce919-05ff-4e0d-aa1f-839f97dff70f`). 10~12는 `debind-32`
> (세션 ID `01cfef58-000e-45b7-b719-95b834c3e734`). 13~15는 `debind-4b`가 `debind-6c`의 보고에서 옮겼다
> (세션 ID `606704f4-0b90-4e5a-93e4-cdefc063f074`). 16·17은 `debind-6c`(세션 ID `21c5d56d-a7ef-49e7-b1df-24fc109c27b2`). 17은 `debind-af`
> (세션 ID `d9fbd825-1a2a-44c4-98fa-a5173c039ed5`)가 고쳐 썼고, 18도 썼다.

다른 일을 하다 찾은 결함이다. 그 일의 범위가 아니라 여기 따로 둔다.

## 18. 받은 문자열의 깨진 값에서 6 -> 7 단계가 터진다

찾은 곳: 7 -> 8 단계의 리뷰(2026-10-10, `debind-af`). 그 일의 diff 밖이라 여기 둔다.

**규칙:** 사다리는 받은 값이 무엇이든 터지면 안 된다(`Migration.lua` 머리주석, `sanitizing-actions-with-one-function.md`
7절 3번). 깨진 값을 어떻게 할지는 sanitize가 정한다. 사다리가 할 일은 터지지 않는 것뿐이다.

**지금:** 5판·6판 문자열이 6 -> 7 단계를 탄다. 페이로드의 판은 5 아래로 내려가지 않는다(`OLDEST_PAYLOAD_DBVER`). 그
단계에는 타입을 묻지 않고 값을 쓰는 자리가 다섯 있다. 손으로 고친 문자열이 그 자리에 깨진 값을 들고 오면 터진다.
애드온이 멈추지는 않는다. `DecodeExportString`의 `pcall`이 받아서 문자열 전체를 `BAD_PAYLOAD`로 거절하고 에러를
알린다. 그 액션은 sanitize까지 가지 못한다. 서랍 항목도 같은 단계를 탄다(`Vars`가 항목마다 `pcall`).

- 번호 다시 매기기의 옛 비교자(`OlderOrder`)가 `priority`와 `seq`를 `<`로 비교한다. 숫자가 아니면 터지고, NaN이면
  `sort`가 터질 수 있다.
- 같은 자리의 묶음 이름이 `action.key .. "\0"`이다. `key`가 불리언이나 표면 터진다.
- `conditions`와 `conditions.units`를 표인지 묻지 않고 인덱싱하거나 `pairs`에 넘긴다. `exists` 채우기, `pet` 옮기기,
  프레임 마스크 옮기기, `HasAnyCondition`, Cast Options 변환 앞의 `UnitConditionAt7` 호출이 그 자리다.
- `known` 변환이 `C_Spell.GetSpellName`에 `action.value`를 타입 검사 없이 넘긴다. `conditions`가 표가 아니면
  `conditions.known`에서 먼저 터진다.
- Cast Options 변환과 번호 다시 매기기가 `casting`을 표인지 묻지 않고 읽고 쓴다.

**고칠 때:** 각 자리에서 터지지만 않게 막는다. 깨진 값에 뜻을 주는 갈래는 더하지 않는다. 4판 이하의 단계는
페이로드가 닿지 않으므로 대상이 아니다.
