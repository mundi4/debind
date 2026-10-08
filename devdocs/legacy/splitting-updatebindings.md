# `UpdateBindings.lua`를 가른다 (2026-10-08)

> 상태: **다 들어갔다** (2026-10-08). 계획은 소유자가 다 받았다. 계획과 달라진 자리는 7절에 있다.
>
> 쓴 세션: `debind-f9` (세션 ID `ff9c24d6-42e2-4547-916f-3d084dffcbcf`). 조사도 이 세션이 했다.

## 1. 왜

이 파일은 Lua가 한 함수에 허락하는 local 200개 한도에 닿았다. 파일의 최상위가 한 함수라서 최상위 local이 다 거기에 든다.
`luac5.1 -l -l`로 센 최상위 local이 204개이고, 한 시점에 살아 있는 것의 최대치가 198이다(2026-10-08). `do ... end`로
자리를 만드는 것은 증상만 덮는다. 한도에 닿은 것은 5,017줄 한 파일이 성격이 다른 일을 여럿 하기 때문이다(소유자).
이 항목은 `0-IDEAS.md`에 있다가 여기로 왔다.

## 2. 지킬 것

- **동작이 안 바뀐다.** 단계마다 `npm test`의 두 패스가 초록이고, emit 골든 두 벌(`tests/emit-golden.txt`,
  `tests/emit-shipped-golden.txt`)이 바이트 그대로다. 버튼 이름이 `NextButtonName`의 순번이라, 걷는 순서가 하나라도
  바뀌면 골든이 움직인다. 골든이 움직이면 이동이 아니라 동작이 바뀐 것이다.
- **스니펫 골든도 안 움직인다.** `UpdateBindings.lua`의 리터럴 스니펫 일곱이 전부 리빌드 진행 쪽에 있고, 진행은
  `UpdateBindings.lua`에 남는다. 골든 키는 `Debind/` 아래 상대 경로다.
- **새 파일 이름은 `Debind/` 안에서 겹치지 않는다.** 이 저장소는 파일을 이름으로 인용한다.
- 파일은 Edit와 Write로만 고친다.

## 3. 무엇이 어디로 가는가

새 파일은 `Debind/Rebuild/`에 둔다. 코드가 이 일을 이미 "rebuild"라고 부른다. 폴더 기준은 9절이다.

| 파일 | 든 것 |
|---|---|
| `Rebuild/Rebuild.lua` | 모듈 표 `DebindPrivate.Rebuild`. 출력 버퍼(`_strArr`, `appendLine`, `appendKeyValue`, `AssertSnippetCompiles`), `sortedKeys`, 리빌드마다 비우는 등록부(`_switches`, `_macrotexts`, `_macrotextBindings`, `_unitsSeen`, `readsRole`)와 그것을 쓰는 함수들(`addSwitch`, `addMacrotext`, `addMacrotextBinding`, `SwitchArgIsLive`, `ComposedReads`, `ResetContext`), 매크로 본문 항목(`EmitMacroTextArg`, `EmitMacroTextEntries`, `BuildMacroTextEntries`) |
| `Rebuild/ButtonAttributes.lua` | `Automatics*`, 버튼 캐시와 표(`BindingAttrsCache`, `WrappedAttrsCache`, `_wrappedButtons`, `_wrappedRelease`, `_actionSlots`, `_barClickButtons`), `NextButtonName`, `CollectBindingFacts`, `DescribeBinding`, `StampBinding`, `SetBindingAttributes`, 그리고 `UpdateBindingsMap` 끝에서 그 표 셋을 내보내던 부분 |
| `Rebuild/ConditionText.lua` | `MEASURED_BY`부터 `UnitExpression`까지 |
| `Rebuild/KeyRecords.lua` | `UNITGROUPCELL_NAMES`, `ROLE_NAMES`, `NEVER`, `mergeUnitConditions`, `CONDITION_AXES`, `field`부터 `EmitRecord`까지 |
| `Rebuild/CastChords.lua` | `CHORD_MODIFIERS`부터 `CastKeyModifiers`까지, 조합키 루프와 그것만 쓰는 표(`_boundBare`, `_hasSelfTwin`, `_hasFocusTwin`, `_castChords`, `_tierItems`) |
| `Rebuild/JudgeLoop.lua` | `JudgmentItems`부터 `BuildJudgeSnippet`까지, 판정 출력 다섯 |
| `UpdateBindings.lua`에 남는 것 | 리빌드 진행(`CanBuildBindings`부터 `UpdateBindings`까지, `ApplyOptions` 포함), `UpdateBindingsMap`의 키 순회, `UpdateAttrChangedHandler` |

**`UpdateBindingsMap`은 남긴다.** 키 레코드, 시전 조합키, 판정 루프를 다 부르는 허브라서, 떼면 남의 이름만 부르는
파일이 된다.

**조건식 글은 따로 선다.** 키 레코드와 판정 루프가 둘 다 쓰고, 순수한 글 생성이라 헤드리스 스펙이 그 파일만 실어 시험할
수 있다.

**판정 루프 안은 이번에 안 가른다.** 1,770줄이지만 최상위 local이 50개 안팎이다. 이번 목적은 local 한도와 덩어리
경계다.

## 4. 덩어리 사이의 얽힘

바이트코드로 센 것이다(2026-10-08). 최상위 함수 95개가 각각 어느 최상위 local을 upvalue로 잡고 `SETUPVAL`로 쓰는지,
최상위 문장이 무엇을 읽고 쓰는지, 앞으로 선언된 local이 어디서 정의되는지를 뽑았다.

### 4-1. 의존은 한 방향이다

```
Rebuild.lua → ButtonAttributes → ConditionText → KeyRecords → CastChords → JudgeLoop → UpdateBindings.lua
```

- `ButtonAttributes`는 `addMacrotextBinding`만 쓴다.
- `ConditionText`는 아무 덩어리도 안 부른다.
- `KeyRecords`는 `SetBindingAttributes`, `StateExpression`, `UnitExpression`, `addSwitch`를 쓰고 `readsRole`을 쓴다.
- `JudgeLoop`는 `ConditionText`의 `ANSWERS_AS_THE_WORD`, `StateAlternatives`, `_stateTokens`, `UnitAsksExists`,
  `UnitAlternatives`와 `KeyRecords`의 `BLOCKS`를 쓴다.
- `UpdateBindingsMap`만 셋을 다 부른다.

이 순서로 실으면 파일마다 머리에서 `local X = Rebuild.X`로 잡는 관례가 선다. `Menus/`의 네 파일이
`DebindPrivate.ActionMenu`를 나눠 쓰는 것과 같은 모양이다.

### 4-2. 테이블은 넘어가도 되고 스칼라는 안 된다

이 파일은 테이블을 비우고 다시 채우지 새로 만들지 않는다. 그래서 다른 파일이 로드 때 local로 잡아도 같은 테이블이다.
local 스칼라는 다른 파일에서 못 쓴다.

| 이름 | 어디로 |
|---|---|
| `_readsRole` | `Rebuild.readsRole`. `ResetContext`와 `BuildKeyRecord`가 쓰고 진행이 읽는다 |
| `_judgePassBody`, `_judgeWakeBodies`, `_judgeWatchCheckBody`, `_judgeBeats`, `_judgeBeatSignal` | `JudgeLoop`에 남는다. 진행은 `FillJudgePlan`과 `ClearJudgeBodies`로 채우고 비운다(7절) |
| `_chordsYielded` | `CastChords` 안에 갇힌다. 거짓으로 되돌리던 것이 조합키 루프였고, 그 루프가 그리로 간다 |
| `_beatRegistered` | 그대로. 쓰는 쪽과 읽는 쪽이 다 진행에 남는다 |

### 4-3. 조합키 루프는 표 다섯을 데리고 간다

`_boundBare`, `_hasSelfTwin`, `_hasFocusTwin`은 키 순회가 채우고 조합키 루프만 읽는다. `_castChords`, `_tierItems`는
조합키 루프만 쓴다. 그래서 다섯 다 `CastChords`의 것이 되고, 키 순회는 그 파일의 함수로만 말한다.

- 키 순회 시작에서 셋을 비우는 것
- 키 하나를 맨 키로 묶었다고 적는 것
- 루프 뒤에 조합키를 내보내는 것. `judgmentItems`와 `_chordEntries`를 인자로 받는다

`_chordEntries`는 키 순회가 채우고 조합키 루프가 읽는 판정 항목이라 키 순회에 남는다.

### 4-4. 스크래치 배열은 파일마다

`_sortedA/B/C`는 키 레코드, 판정 루프, 키 순회가 나눠 썼다. `UpdateBindingsMap`이 `_sortedA`로 키를 도는 중에
`EmitRecord`가 `_sortedB`와 `_sortedC`를 썼다. 파일마다 자기 스크래치를 두면 겹침은 파일 안에서만 따지면 된다.
`sortedKeys`는 매번 비우고 채우므로 출력은 안 바뀐다.

## 5. 같이 움직이는 것

- **`Debind/Debind.xml`과 `tests/run.lua`의 `DEBIND_FILES`.** 같은 순서로 같이 고친다. `CheckLoadList`가 어긋남을
  잡는다. 새 파일은 `UpdateBindings.lua` 바로 앞에 4-1의 순서로 선다.
- **`tools/check-reload-options.js`.** `UpdateBindings.lua`의 `ApplyOptions`를 경로로 읽는다. `ApplyOptions`는 남는다.
- **인용.** 옮긴 이름을 "`UpdateBindings.lua`의 X"로 든 것을 옮긴 파일로 고친다. `legacy/`, `0-DIARY.md`,
  `0-DECISION-LOG.md`는 그때의 기록이라 안 고친다.

## 6. 단계

뗀 파일은 `UpdateBindings.lua`보다 먼저 실리므로, 아직 원래 파일에 있는 것을 로드 때 잡을 수 없다. 그래서 의존의 뿌리부터
뗀다.

1. `Rebuild.lua`
2. `ButtonAttributes.lua`
3. `ConditionText.lua`
4. `KeyRecords.lua`
5. `CastChords.lua`
6. `JudgeLoop.lua`

## 7. 들어간 자리 (2026-10-08)

여섯 단계를 6절의 순서로 했다. 단계마다 `npm test`의 두 패스가 초록이었고 emit 골든 두 벌이 바이트 그대로였다. 스니펫
골든도 그대로였다. 옮긴 파일마다 원래 `UpdateBindings.lua`(HEAD)에 없는 줄을 뽑아 봤고, 나온 것은 새 머리, 내보내기,
아래에 적은 자리뿐이었다.

| 파일 | 줄 수 | 최상위 local (`luac5.1 -l -l`) |
|---|---|---|
| `UpdateBindings.lua` | 1,011 | 73 |
| `Rebuild/Rebuild.lua` | 365 | 35 |
| `Rebuild/ButtonAttributes.lua` | 703 | 44 |
| `Rebuild/ConditionText.lua` | 282 | 30 |
| `Rebuild/KeyRecords.lua` | 772 | 45 |
| `Rebuild/CastChords.lua` | 262 | 35 |
| `Rebuild/JudgeLoop.lua` | 1,847 | 80 |

### 계획과 달라진 자리

- **판정 출력 다섯은 표가 아니라 함수 둘로 건넌다.** `JudgeLoop.lua`가 다섯을 자기 local로 두고, `FillJudgePlan(plan)`이
  plan에 이름으로 써 넣고 `ClearJudgeBodies()`가 비운다. 표로 바꾸면 `BuildJudgeSnippet` 안에서 다섯을 쓰는 줄을 다
  고쳐야 했다. 함수 둘이면 판정 루프 본문은 한 줄도 안 바뀐다. 처음에는 다섯을 위치로 돌려주는 `JudgeBodies()`였는데,
  리뷰가 짚었다. 순서가 하나 어긋나면 엉뚱한 beat 드라이버가 말없이 걸린다. `plan.beats`가 `plan.judges`를 읽으므로
  `FillJudgePlan`은 그 뒤에 부른다.
- **`IsSwitchTracked`는 `Rebuild.lua`에 갔다.** 원래 파일에서 조합키 덩어리 바로 앞에 있어서 처음에는 `CastChords.lua`로
  쓸려 갔다. 하는 일은 `_switches`를 읽는 것이다(리뷰).
- **`_record`는 `UpdateBindings.lua`에 남는다.** 그 표를 채워 두 독자(`CollectRecordNeeds`, `EmitRecord`)에게 건네는
  것이 `UpdateBindingsMap`이다. 처음에는 `KeyRecords.lua`가 내보내고 진행이 받아 되돌려 넘기는 왕복이었다(리뷰). 그
  주석이 없는 이름 `CollectRecordAxes`를 들고 있어서 같이 고쳤다.
- **조합키 루프는 함수 셋으로 갈렸다.** `BeginCastChords`(키 순회 앞에서 맨 키 표 셋을 비운다), `NoteBareKey`(키 하나를
  맨 키로 적는다), `EmitCastChords`(루프 뒤에 조합키를 건다). 4-3이 말한 대로 표 다섯이 다 `CastChords.lua`의 것이 됐다.
- **버튼 표 셋을 내보내는 부분은 `EmitStampedButtons`가 됐다.** "키 순회 뒤에 낸다"는 순서의 이유는 부르는 자리에
  남겼고, "통째로 낸다"는 이유는 함수로 갔다.
- **`addMacrotext`도 내보낸다.** 진행의 `BuildSwitchesSnippet`이 부른다. 바이트코드 집계는 덩어리 밖에서 쓰는 이름만
  셌는데, 진행과 공용 바닥이 원래 한 덩어리(1–1030행)였어서 빠졌다. luacheck의 W113(정의 안 된 전역)이 잡았다.
- **`MEASURED_BY`는 내보내지 않는다.** `Constants.MEASURED_BY`의 별칭이라 쓰는 파일마다 머리에서 잡는다.
- **`MeasureGates` 주석에서 local 한도를 든 문장을 뺐다.** "`DebindPrivate`를 거치는 것은 파일에 local을 안 쓰려고서다,
  한도 200에 닿아 있었다"였다. 가른 뒤로는 참이 아니다. 함수는 `DebindPrivate`에 그대로 있다. 스펙이 그 이름으로 부른다.
- **`UpdateBindings.lua`에는 스크래치가 하나만 남았다.** 이 파일의 걷기는 이제 서로 안에서 돌지 않는다.

### 인용

옮긴 이름을 "`UpdateBindings.lua`의 X"로 든 자리, 그리고 파일 이름만 들었지만 가리키는 내용이 옮겨 간 자리를 새 파일로
고쳤다. `Debind/`, `DebindDev/`, `DebindStorage/`, `tests/`, `CLAUDE.md`, `0-IDEAS.md`, `restricted-environment.md`,
`working/`의 문서 셋이다. 고치면서 손댄 한국어 주석은 통째로 영어로 다시 썼다. `KeyRecords.lua`의 `known` 주석은 처음에
영어 줄 하나만 고쳐 두 언어로 남겼다가 리뷰가 짚어 통째로 다시 썼다. `macrotext_spec.lua`의 것은 "헤드리스 러너가
`UpdateBindings.lua`를 안 싣는다"는 문장이 이미 거짓이라 뺐다. 그 시험이 진짜 함수를 안 재는 것은 이번 범위 밖이라
`need-fixing.md`의 6에 적었다.

**그대로 둔 것.** 그때 있었던 일을 적은 자리(`DebindTest.lua` 머리, `normalize_spec.lua`, `SecureBindings.lua`의 "옛 경로",
`handing-the-rest-of-a-key-to-the-game.md`의 태그 인용, `giving-keys-back-when-no-action-runs.md`의 미커밋 작업 기록)와,
여전히 `UpdateBindings.lua`에 있는 것을 가리키는 자리(`CanBuildBindings`, `ClearPreviousBindings`, `UpdateBindingsMap`,
`SetSwitch` 줄, 역할 맵, `ApplyOptions`)다. `migration_spec.lua`의 dbver 5 주석도 뒀다. 이번 작업으로 이해하게 된 주석이
아니다.

## 8. 확인

헤드리스가 이 변경의 실패를 다 본다. 로드 순서가 틀리면 nil을 잡은 자리가 스펙에서 터지고, 방출이 바뀌면 emit 골든이
움직인다. 게임에 닿는 것은 같은 바이트의 스니펫이다.

## 9. 폴더 기준 (2026-10-08, 소유자)

**맨 위 폴더는 층으로 가른다.** 기능 폴더는 한 층 안에서, 다른 것과 엮이지 않는 묶음에만 쓴다. `Conditions/`와 `Menus/`가
그 예다.

- **층 폴더 하나가 로드 단위 하나와 맞는다.** `Debind.xml`과 UI XML이 이미 층으로 갈려 있고, 헤드리스 스펙은 "프레임이
  필요한가"를 기준으로 싣는다(`testing-a-change.md`). 기능 폴더에서는 한 기능의 파이프라인 조각과 UI 조각이 서로 다른
  XML 자리에서 실린다.
- **꼬리 키는 닫힌 기능이 아니다.** 판정 루프는 키 레코드의 `BLOCKS`, 조건식 글, 시전 조합키, `UpdateBindingsMap`,
  키 돌려주기와 엮여 있다. `Conditions/`가 기능 폴더로 맞았던 것은 조건 파일끼리 서로를 모르기 때문이다.
- **흩어 두는 대가가 작다.** 파일은 이름으로 인용되고 이름은 겹치지 않는다.

그래서 꼬리 키의 세 조각은 각자 자기 층에 둔다. `Judgment.lua`는 순수 모델(`Ordering.lua`, `Solver.lua` 곁), 판정 루프는
`Rebuild/`, `BeatSignal.lua`는 실행 중 측정이다.

**뒤집을 조건.** 꼬리 키를 한 단위로 끄거나 들어낼 수 있게 되면, 즉 다른 덩어리가 그것을 부르지 않게 되면 기능 폴더로
모을 이유가 생긴다.

**`UpdateBindings.lua`는 지금 자리에 둔다.** "파이프라인의 중심 파일은 맨 위에 남는다"(`preparing-the-code-for-camelot.md`
5절)가 아직 서 있고, 옮기면 스니펫 골든 키가 바뀐다. 전체 폴더 정리 때 다른 파이프라인 파일과 같이 옮긴다.
