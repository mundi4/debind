# 레코드 꼴만 남기기 (2026-10-06 계획)

> 상태: 1~3 지음(2026-10-06), 리뷰와 커밋 전. 다음은 단계 A.
> 소유자 결정(2026-10-06, debind-af를 거쳐): 소유자 모양(키 30 × 액션 10 × 조건 5)의 리빌드 30초는 영역 꼴 자체에서 나온다.
> `SubtractBoxes`와, 합칠 때마다 처음부터 다시 도는 `MergeBoxes`다. 그리고 그 모양은 평범한 프로필이라, 이것은 나가는 코드에서
> 접속할 때마다 멈추는 문제다. 합치기를 빠르게 하면 알고리즘이 남고, 영역 꼴을 없애면 비용이 사라진다.
> `merging-regions-without-restarting.md`(거둠)의 측정이 근거다. `MergeBoxes` 30.56 s / `bind` 31.53 s, 30키 모두 레코드 꼴,
> 레코드 꼴만이면 `bind` 0.31 s.
>
> 쓴 세션: `debind-c7` (세션 ID `fa45b806-e7ef-4e55-beb0-be4b2200e87b`). 물을 세션: `debind-af` (세션 ID
> `2edb81bb-2da9-4d6b-817d-e1fe81e5cade`).

## 바꾸는 것

### 1. `Judgment.Build`는 레코드 꼴만 만든다

- 남는 것은 지금의 `RecordsItem` 그대로다.
  - 상자가 빈 레코드는 뺀다.
  - 어디서나 맞는 첫 레코드에서 끊고, 그것을 `rest`로 둔다.
  - `rest` 바로 앞에서 `rest`와 같은 답을 내는 entry는 뺀다(R6).
  - entry 안의 check는 싼 것부터 둔다(`CHECK_RANK`).
- `item.columns`는 남긴 entry가 읽는 컬럼으로 다시 짠다. 지금 작업 트리에 들어간 고침(리뷰 지적 8)을 그대로 쓴다.
- 없애는 것은 이렇다.
  - `Judgment.lua`에서: 영역 꼴, `MergeBoxes`, `Cost`, `MAX_WORK`, `OutcomeKey`, 두 꼴 견주기(`PricePoints`, `LoopPrice`),
    `item.form`, `DebindPrivate.JudgmentForm`. 리뷰 지적 2·5로 들어간 `JudgeFormCap`도 함께 사라진다.
  - `Solver.lua`의 `subtractBoxes`와 그 내보내기(`DebindPrivate.SubtractBoxes`). 솔버 자신은 `isCovered`만 쓰고, 이것은
    `Judgment`만 불렀다.
- `Judgment.LOOP_ENTRY`·`LOOP_CHECK`는 `Judgment`를 떠나 `BundleAnswers`의 `JUDGING_PRICE`로 옮긴다. 값을 매기는 쪽이 그것
  하나만 남는다. 아래 3의 결과에 따라 표가 사라지면 단가도 함께 사라진다.

### 2. `WatchGates`: 앞 entry의 부정을 게이트에 넣는다

- 레코드 꼴의 entry는 앞 레코드들의 부정을 잃는다. `[combat] A; [flyable] B`의 둘째 entry는 맨 `[flyable]`이다. 그래서 지금
  게이트(entry마다 다른 check들의 AND를 모은 OR)는 전투 중에도 열리고, beat마다 파싱 5(`advflyable`이면 24)가 든다. R6이
  `flyable`을 읽는 item을 영역 꼴로 지킨 까닭이 이것이고, 그 규칙은 영역 꼴과 함께 사라진다.
- **바꾸는 것**: 비싼 컬럼을 읽는 entry의 그룹에 **그보다 앞선 entry 가운데 check가 하나뿐이고 그 check의 낱말이 토큰
  하나인 것의 부정**을 더한다. `[combat] A; [flyable] B`라면 `flyable`의 게이트는 `[nocombat]`이다.
  - **맞는 까닭**: 루프는 첫 일치에서 멈춘다. 그러니 entry k에 닿는 것은 앞 entry가 모두 실패한 곳뿐이고, 앞 entry의 부정을
    AND로 더해도 entry k가 답을 정하는 곳은 하나도 빠지지 않는다.
  - **더하지 않는 것**: check가 둘 이상인 앞 entry(부정이 OR가 된다), 낱말이 토큰 여럿인 check(같은 까닭), 낱말이 없는 check
    (유닛, 스위치, `known`, 비싼 낱말 자신). 이것들은 아무것도 보태지 않는다. 그만큼 게이트가 넓어질 뿐 틀리지는 않는다.
  - `CheckWords`가 `false`를 내는 앞 entry는 어디서도 맞지 않는다. 그 부정은 어디서나 참이니 보탤 것이 없다. `{}`를 내는 앞
    entry는 말로 적을 부정이 없으니 역시 보태지 않는다.
- 지금 작업 트리에 들어간 고침이 여기에 함께 간다: items를 `sortedKeys` 순서로 모으기(지적 7), `EXPENSIVE` 한 벌을
  `Judgment`에 두기(지적 4), `Negated` 부르기(지적 3).

### 3. Q4의 표는 이 커밋에 남긴다

- `BundleAnswers`, `JudgeTableCap`, 글자, `J.outcomes`는 그대로다.
- 벤치에서 긴 키 줄과 소유자 모양 줄의 묶음마다 루프 값과 표 값(`DebindPrivate.JudgeBundleCosts`)을 나란히 찍는다. **표가
  어디서든 판정한 묶음 하나당 1µs보다 적게 아끼면 그렇다고 보고**하고, 표를 없애는 둘째 커밋은 소유자가 정한다.

## 시험

- `judgment_spec`의 실행(run)에서 `records`·`regions` 둘을 뺀다(꼴을 강제할 것이 없다). sweep은 그대로이고, 답은 어느 꼴에서나
  정확하니 바뀌지 않아야 한다.
- 이름을 바꾸는 시험: "an item reading flyable keeps its regions, and its gate"는 **"the gate closes behind a single-check
  earlier entry"**가 된다. `[combat] A; [flyable] B; 닫기`에서 watch 글에 `[nocombat,`가 있고, 전투 중 `flyable`이 뒤집혀도
  watch 말고는 아무것도 파싱되지 않으며, sweep이 맞는다.
- 손볼 시험: "a gate holds every entry that reaches the column"(`EveryEntry`)은 `form`으로 갈라 놓은 기대 그룹을 레코드 꼴
  하나로 정한다. 지적 2의 시험("an item's form does not follow the table's cap")은 꼴이 하나뿐이니 뺀다. 지적 7·8의 시험은 남는다.
- **망가뜨려 실패를 볼 판**:
  - 닫는 `rest` 없는 레코드 꼴: 아무것도 맞지 않는 점에서 nil이 나오고 sweep이 떨어진다.
  - 앞 entry의 부정이 없는 게이트: 새 이름의 시험이 떨어진다.
  - 둘 다 이 단계의 코드에 일부러 넣어 떨어지는 것을 본 뒤에 되돌린다.
- emission golden(`tests/emit-golden.txt`, `tests/emit-shipped-golden.txt`)은 꼴이 바뀌는 item만큼 움직일 것이다.
  `--update-golden`으로 다시 쓰고, 그 diff가 레코드 꼴로 바뀐 entry뿐인지 읽는다.
- 키트: 새 케이스 없음. 있는 "Tail:" 케이스와 "Tail: flyable in combat waits behind nocombat"이 새 게이트를 탄다.

## 관문

- `npm run check` 통과. `judgment_spec`의 sweep에 바뀐 기대가 없다.
- `--bench-beat` 소유자 모양 세 줄의 리빌드가 약 30 s에서 수백 ms 이하로(그 줄의 "the rebuild … ms headless").
- 소유자 모양의 움직인 줄은 156.36 / 156.36 / 83.26 그대로.
- 조용한 줄은 하나도 오르지 않는다. 움직인 줄은 초당 3번 움직일 때의 1초 값("a second, 3 moves")이 0.2 ms 넘게 오르지 않는다.
  처음에는 "움직인 줄 +1µs 이내"였다. 큰 모양이 그것을 넘은 뒤 소유자의 기준으로 바꿨다(2026-10-06, debind-af). 리빌드
  31.9 s → 0.3 s와 영역 코드가 없어지는 것에 견주면, 초당 몇 번 움직이는 beat에 몇 µs가 붙는 것은 기준이 묻는 값이 아니다.

## 절차

- 이 계획을 debind-af에 보고한 뒤에 짓는다.
- 지은 뒤에 `/code-review high`를 돌린다.
- 결과와 수치를 debind-af에 보고한다. 커밋은 debind-af의 말에 따라 소유자가 한다.
- 질문은 debind-af에만 한다.

## 결과 (2026-10-06, 260e10c 위 작업 트리, 헤드리스)

- **지은 것**: 위 1~3 그대로. 계획과 다른 점은 하나다. `Solver.lua`의 `subtractBoxes`는 솔버가 안 써서 함수째 뺐다.
- **시험**: `npm run check` 통과. 망가뜨려 실패를 본 판:
  - 앞 entry의 부정을 뺀 판에서 "the gate closes behind a single-check earlier entry"가 세 판 모두 떨어졌다.
  - 닫는 `rest`를 비운 판에서 208개가 떨어졌다.
- **emission golden**: 묶음 하나만 움직였다(두 golden 각 3줄). 영역 꼴의 "칸 2이면 release, 나머지 ours"가 레코드 꼴의
  "칸 1이면 ours, 나머지 release"가 되었고, 두 칸짜리 컬럼이라 같은 답이다.
- **리빌드**: 앞서 잰 것은 `bind` 31.53 s(`MergeBoxes` 30.56 s)였다. `--bench-beat` 소유자 모양 세 줄은 이렇게 바뀌었다.

  | 소유자 모양 | 앞 | 뒤 |
  |---|---|---|
  | 리빌드(help만 0% / 50% / 100%) | 31874 / 31554 / 29512 ms | 294 / 268 / 281 ms |
  | 움직인 줄 | 156.36 / 156.36 / 83.26 | 156.36 / 156.36 / 83.26 |
  | 조용한 줄 | 8.88 / 8.88 / 8.73 | 8.88 / 8.88 / 8.73 |

- **바뀌지 않은 줄**: 12키, 계산식 스위치, 모양별 표(`shared`/`distinct`/`units`/`flyable`/`bars`), `mounts`, 긴 키, 깨움,
  조용한 beat 전부.
- **오른 줄: 큰 모양**(키 24개, 컬럼 24개). R6이 영역 꼴을 고른 모양이다. 처음 관문(+1µs)은 넘었고, 바뀐 관문은 지킨다.
  - 초당 3번 움직일 때 가장 많이 오른 것은 전투 움직임 24 lead의 291 → 403 µs/s(0.112 ms)다. 상태와 대상이 움직이는 줄은
    92 → 111 µs/s(0.019 ms).
  - **까닭**: 영역 꼴은 가장 비싼 결과의 영역을 쓰지 않고 `rest`로 비웠다. 그래서 짧은 키는 걷는 entry가 적었다. 레코드 꼴은
    레코드를 차례로 다 쓰고, 닫는 레코드만 `rest`다.
  - 어느 프로필에서 이 차이가 문제가 되면 `0-IDEAS.md`의 항목에서 다시 꺼낸다.

  | 큰 모양, 폼 없는 직업 | 앞 | 뒤 |
  |---|---|---|
  | 0 lead: 상태 움직임 / 폼 움직임 / 대상 움직임 | 33.15 / 26.66 / 36.08 | 39.50 / 31.78 / 42.29 |
  | 전투 움직임 본문, 0 / 12 / 24 lead | 17.83 / 71.91 / 90.92 | 22.83 / 76.35 / 128.26 |
  | beat 신호 줄, attribute 움직임 | 33.15 | 39.50 |
  | 상한별 표(cap none, 8칸 중 첫과 끝) | 24.81 … 101.81 | 31.16 … 127.06 |

  폼 있는 직업(드루이드) 줄도 같은 폭(+5~+37)으로 올랐다.
- **표가 아끼는 것**(묶음마다 루프 값과 표 값):
  - 긴 키: 묶음 1개가 표를 골랐고 1.02µs를 아낀다.
  - 소유자 모양: 표 값을 매긴 묶음이 없다. 모든 묶음의 joint state가 `JudgeTableCap`을 넘어서 표를 만들지 않는다.
