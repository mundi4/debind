# 줄인 꼬리 키 beat 구현 순서 (2026-10-05 계획)

> 상태: 진행 중. P0, P1, P2(누름의 상태 낱말과 유닛 낱말을 파싱으로)가 들어갔다. P3은 묶음을 식으로 굽는 경로를
> 만들어 재 본 뒤 뺐고(소유자), 루프가 상태와 유닛을 누름처럼 파싱으로 잰다. change detector(P3-7)가 3개까지로
> 들어갔다. P4(계산식 스위치의 글은 참조하는 값이 바뀔 때만 조립)와 P5(펫 대전은 비보안 쪽이 넣음)는 루프의
> 컬럼으로 다시 짜서 들어갔다. P6(매니저 이벤트)은 바꾸지 않고 닫았다. 8-3의 계산식 스위치 쪽은 보류다("보류한 것").
> `trimming-the-tail-key-beat.md`가 정한 것과 제안한 것을 단계로 내린다. 무엇을
> 왜 하는지는 그 문서가 갖고, 이 문서는 어떤 순서로 무엇을 고치는지와 단계마다 무엇이 실패해야 하는지를 갖는다.
> 이 문서의 절은 `P0`~`P6`으로 부르고, 괄호 안의 맨 번호(7-1, 8-6, C5 …)는 그 계획 문서의 절과 표의 행이다.
>
> 쓴 세션: `debind-e6` (세션 ID `227f6025-3103-4343-a53f-52f642072b5a`). 계획 문서를 쓴 세션은 `debind-ac`
> (세션 ID `1361cd24-6aad-48a3-9a06-643d7caa65ad`). P2b와 P3은 `debind-15` (세션 ID
> `7c6f4074-9f5b-45cc-9de9-ca5e8ccf8dd3`). P4와 P5는 `debind-05` (세션 ID `679ed88b-7690-4b7b-bbb7-1f7f48ead365`).

## 기대는 것

### beat와 누름은 같은 식을 파싱한다 (소유자)

지금 누름(`EVAL_SNIPPET`)은 API로 잰다(`PlayerInCombat()`, `IsFlyableArea()`, `UnitIsDead or UnitIsGhost`). beat만
파싱으로 바꾸면 beat와 누름이 같은 답을 내는 것이 매크로 조건과 API가 같은 것을 잰다는 근거에 기대고, 7-1에서 그
근거가 선 낱말은 일부다. 7-1은 파싱 한 번이 C 함수 하나를 부르는 값과 같은 자리이고 ENV 래퍼보다 싸다고도 쟀다
(`[combat]` 0.21, `PlayerInCombat()` 0.91). 그래서 **누름도 파싱으로 바꾼다.** 같은 식을 파싱하니 같은 답은 만든
그대로 나오고, 낱말마다의 근거가 필요 없다.

`trimming-the-tail-key-beat.md`의 7의 4는 "8-2가 서면 근거는 낱말이 컬럼으로 옮겨지는 자리에서만 필요하다"고
적고 있다. debind-e6의 검토에서 나온 말이고, 누름이 API로 잰다는 것을 빠뜨렸다. 누름도 파싱하면 그 말이 맞게 된다.

**대가.** 매크로 조건과 API가 실제로 다르게 답하는 낱말이 있으면, 그 낱말을 쓴 키에서 이기는 액션이 기존 사용자에게
달라진다. 7-1에서 같이 움직인 낱말(`combat`, `mounted`, `flying`, `indoors`, `bonusbar:n`, 유닛의
`exists`·`help`·`harm`·`dead`)은 달라지지 않는다. 같은 날 17:08의 `/debgw`(xptr 120105, 약 14000프레임)에서
`stealth`, `form`, `group`(파티↔공격대), `flyable`, `advflyable`도 움직였고 어긋나지 않았다. `[dead]`는 유령인 대상에도
`UnitIsDead or UnitIsGhost`와 같았다. 17:20의 상시 `/debgw`(`gw-standing-1`, 드루이드)에서 유령인 대상 1140프레임,
유령인 마우스오버 242프레임 동안 `dead`는 어긋나지 않았다. 리테일(120100, 17:27부터)의 상시 `/debgw`에서 `extrabar`
네 번, `overridebar` 네 번, `specialbar` 여섯 번이 움직였고 어긋남은 하나도 없었다. 그 사이 `[possessbar]`가 참이 된
빙의 장면이 있었고 `[vehicleui]`는 참이 된 적이 없다. `[@u,help]`가
거짓이었던 것은 모두 로딩 화면 안이나 그 직후였다(나를 대상으로 잡은 것 둘, 파티원 둘). 사용자가 그 조건을 매크로의 뜻으로 쓴다면 파싱이 기대에
맞는 답이다.

### 파싱으로 가지 않는 것

- `known`의 주문책 조회. 덮어쓰기로 바뀐 주문 때문에 파싱 뒤에 `FindSpellBookSlotBySpellID`가 남는다.
- `unitgroup`. `[@u,party]`·`[@u,raid]`는 나 자신에게서 `UnitPlayerOrPetInParty`·`UnitPlayerOrPetInRaid`와 갈린다
  (2026-10-05, 소유자). 파티에서도 공격대에서도 `player`와 나를 가리키는 `raidN`에 API는 파티 참, `[party]`는
  거짓이었다. 다른 사람은 파티에서도, 공격대의 내 소그룹에서도 둘이 같았다(공격대에서 둘 다 참). 펫은 안 쟀다.
  나일 때의 API 답은 `[group:party]`·`[group:raid]`와 같았다(파티 T F, 공격대 T T; `[group:party]`는 공격대에서도 참).
  그래서 식으로 쓰려면 나면 `[group:party]`·`[group:raid]`, 아니면 `[@u,party]`·`[@u,raid]`여야 한다. 그런데 "u가
  나인가"는 매크로 조건으로도 물을 수 없고 보안 환경에서도 물을 수 없다(소유자). 그래서 `unitgroup`은 유닛 종류와
  상관없이 beat의 지역 변수로 남는다.
- 역할과 개체창 종류. 와우에 없는 조건이다. 다만 가리킨 프레임이 정해지면 상수라 식에 끼워 넣는다(P3-2).

### 보류한 것은 자리를 남기지 않는다

3-1(그룹마다 게이트), 4-1(닿을 때만 구하기), `[combat]` 넣기는 보류다. 나중에 붙이게 되면 다시 짜는 것을 감수하고,
지금의 꼴은 지금 가장 잘 줄어드는 쪽으로 정한다(소유자: *"나중일 생각하면 최적화를 못해"*).

**8-3의 계산식 스위치 쪽도 보류다** (소유자, 2026-10-05). 8-3(`flyable`·`advflyable`은 beat에서 한 번만 판정)은 P3-1의
묶음 식 경로 안에 있었고, 그 경로를 빼면서 어느 단계에도 남지 않았다. 루프의 상태 컬럼으로는 지켜진다. `flyable` 컬럼은
하나이고 키가 몇 개든 beat마다 한 번 파싱한다. 지켜지지 않는 곳은 사용자 글에 그 낱말이 든 계산식 스위치다(`[flyable]`
컬럼 옆의 `$s = [flyable,combat]`이면 두 번 판정한다).

- 나온 꼴(debind-05): body 맨 앞에 `local fly`·`advfly`를 nil로 두고, 처음 필요한 자리에서 `[flyable]` 파싱으로 채운다.
  리빌드가 그 스위치 글에서 참 판(토큰을 지운 식)과 거짓 판(토큰이 든 그룹을 지운 식, 비면 `[known:0]`)을 굽고 beat는 판을
  고른다. 쪼개는 깊이는 E2만큼이고 못 알아듣는 글은 통째로 파싱한다. 조립하는 스위치는 `JudgeSwitchTexts`에 글이 둘이 된다.
- 걸리는 것: 사용자 글은 원래 게을러서 `[combat,flyable]`은 전투 밖에서 `flyable`을 판정하지 않는다. local을 먼저 채우면
  판정이 0번에서 1번으로 느는 beat가 생긴다. 그래서 그 낱말이 한 body에 두 군데 이상 나오고, 그중 하나가 컬럼이거나 그룹
  맨 앞이라 어차피 판정되는 자리에서만 굽는 것까지 이야기했다. 그 밖의 경우는 "그룹의 나머지를 먼저 파싱하고 참일 때만
  채운다"는 게이트가 하나 더 든다.

## P0. 헤드리스 바탕

다음 단계의 시험이 고치기 전 코드에서 실패하는 것을 보려면 이것이 먼저다.

### P0-1. `restricted.lua`의 파싱

지금의 `parseCondition`은 맞으면 늘 `""`를 돌려주고, `; 값`을 무시하고, `@unit`을 판정 없이 넘기고,
`help`·`harm`·`dead`·`exists`·`bonusbar`·`group:x` 등에서 "no answer"로 멈춘다. 고칠 것:

- 절 `[…] 값; […] 값; 값`을 읽고 맞은 절의 값을 돌려준다. 값 없는 절은 지금처럼 `""`.
- 그룹의 `@unit`이 그 그룹의 유닛 낱말이 묻는 유닛을 정한다.
- 묶음 식과 누름이 쓸 낱말을 모두 받는다. **답은 API 목과 같은 상태에서 낸다.** 유닛 낱말은 env가 이미 감싸는
  `_G.UnitExists` 등에서 답한다.
- **낱말 하나를 API와 다르게 답하게 하는 갈래**를 둔다. P3의 시험이 P2 없이 실패하는 것을 보는 데 쓴다.

### P0-2. 개발 빌드의 파싱 주입

`/debtest`의 "Tail: the beat takes the key and hands it back to the command"는 `PROBE.MockState(combat)`로 전투를
넣는다. 파싱에는 그 주입이 닿지 않는다. 개발 빌드(`PROBE_DEV`)에서는 `SecureCmdOptionParse`를 목 상태를 먼저 보는
감싸개로 펼친다. 배포 빌드의 바이트는 그대로다.

### P0-3. beat 비용 벤치

헤드리스에서 시계로 재면 안 된다. 보안 환경이 비싼 까닭은 클라이언트의 프록시 테이블과 ENV 래퍼인데, 헤드리스는
본문을 `loadstring`과 `setfenv`로 그냥 돌린다. 7-1의 전역 테이블 필드 읽기가 보안 0.228, 비보안 0.027이다.

그래서 **연산을 세고 7-1의 값을 곱한다.** `tests/run.lua --bench`에 beat 갈래를 둔다.

| 세는 것 | 어떻게 | 값(µs, 7-1) |
|---|---|---|
| 전역 읽기 / 쓰기 | 벤치 모드의 `env`를 세는 프록시로 | 0.154 / 0.497 |
| 보안 테이블 필드 읽기 / 쓰기 | `newtable`이 세는 프록시를 돌려준다 | 0.074 / 0.443 |
| 함수 호출 | 이름마다 감싼다 | `PlayerInCombat` 0.912, `IsMounted` 0.182, `FindSpellBookSlotBySpellID` 0.563, `RunAttribute` 3.092 … |
| 파싱 | 바탕에 판정된 토큰 수만큼 더한다. `parseCondition`이 첫 거짓에서 멈추니 판정된 것만 센다 | 바탕 0.19쯤, 토큰 0.05쯤, `flyable` 5.15, `advflyable` 23.98 |
| 지역 변수 연산 | `debug.sethook`의 count 훅으로 VM 명령 수 | 명령 하나의 값은 "지역 변수 마스크 연산 0.026"에서 거꾸로 맞춘다 |
| beat의 고정 비용 | beat마다 | 9.21 |

- 시나리오는 상태를 바꿔 가며 beat N번이다. 조용한 beat, 무언가 움직인 beat, 스위치가 뒤집히는 beat(다시 조립하는
  2~5가 그때만 든다, 8-6)의 비율을 시나리오가 정한다.
- 가비지 컬렉션, 캐시, 문자열 길이에 따른 값은 모형에 없다. 절대값은 어긋날 수 있고, **같은 모형으로 두 설계를
  견주는 데 쓴다.** 모형은 생성된 본문 하나를 `Probe_BeatCost`에 넣어 게임에서 잰 값과 한 번 맞춰 본다.
- **실사용 프로필은 입력으로 쓰지 않는다** (소유자, 2026-10-05: *"실사용 데이터는 벤치용으로 적합하지 않아"*).
  처음 계획은 소유자의 SavedVariables를 읽어 판 수 상한과 C5가 이기는 자리를 정하는 것이었다. 그 자리는 모양을
  바꿔 가며 만든 합성 프로필로 정한다(P3-6).
- 들어간 것: `restricted.lua`의 meter(`{ meter = true }`로 만든 인터프리터만 센다), `tests/beatbench.lua`
  (`lua5.1 tests/run.lua --bench-beat`). 지금 설계의 첫 값(2026-10-05): 꼬리 키 4·12·30개, 조용한 beat 12.95·13.48·13.48µs,
  세상이 움직이는 beat 13.48·14.37·14.71µs. 그중 약 9µs가 핸들러 진입 둘과 `SetAttribute` 둘이고, 컬럼을 나눠 쓰니 키
  수에 거의 늘지 않는다. 프로필은 상태 낱말만 쓰는 합성 프로필이다.

## P1. beat 신호와 깨움 배관

들어갔다. 정한 것 5-1(`"a"` 드라이버)과 5-2(`RunAttribute` 깨움)를 드라이버 프레임에서 했다. 판정은 그대로다.

- beat: `RegisterUnitWatch(driver, true)`를 `RegisterAttributeDriver(driver, "judgebeat", "a")`로 바꿨다. 핸들러의
  beat 갈래가 그 속성을 `0`으로 되돌린다. 매니저는 속성의 지금 값과 다를 때만 쓴다(`SecureStateDriver.lua`,
  `resolveDriver`). 드라이버의 `unit` 속성과 낡은 주석(Debind.lua)은 지웠다.
- 첫 패스와 깨움: 핸들러에는 beat 갈래만 남았다. 리빌드의 첫 패스는 `JudgePass`, 깨움은 `judge-<이름>` 속성 본문이고,
  깨우는 여섯 곳과 리빌드가 `RunAttribute`로 부른다. `JudgeWakeSerial`은 없어졌다.
- **B3(beat 전용 프레임)는 하지 않았다. 지금 구조에서 서지 않는다.** 이 문서는 처음에 B3를 정한 것으로 적었지만 계획
  문서 5-3에서 B3는 논의 중이었다(debind-e6의 잘못 옮김). 프레임마다 보안 환경이 따로라 전용 프레임의 본문에서는
  `JudgeBundles`·`BoundKeys` 같은 드라이버의 전역이 안 보인다. 그 본문의 `self:SetBindingClick`은 바인딩 주인을 전용
  프레임으로 만들어 리빌드의 `ClearOverrideBindings(BindingDriver)`와 Keys Given Back이 그 키를 못 다룬다. 드라이버로
  넘어가는 `RunAttribute`(3.09)는 B3가 아끼려던 진입(약 3.2)을 다 먹는다. 다시 꺼낸다면 루프의 표 전부와 바인딩 주인을
  전용 프레임으로 옮기는 구조 변경이 전제다.
- 시험: `judgmentloop_spec`의 "a wake of ours runs the handler once"는 "does not run the handler"가 됐다(깨움은
  핸들러를 열지 않는다). `emit_spec` 골든과 스니펫 골든을 다시 기록했다. 키트의 "The driver is off Blizzard's beat"는
  꼬리가 없으면 beat 속성이 두 번의 매니저 틱 동안 안 쓰이고, 꼬리를 붙이면 쓰이는지를 본다(틱은 키트 자신의 `"a"`
  드라이버로 센다).
- 벤치(같은 `beatbench.lua`를 바꾸기 전 커밋 a40dfc3과 이 단계에서): beat 하나 14.89 → 13.30µs(꼬리 키 4개, 조용한
  beat. 12·30개도 1.59씩), 손으로 켜는 스위치의 깨움 하나 17.88 → 15.61µs. beat에서 준 것은 매니저 쪽 unit watch(1.94)가
  `"a"` 드라이버(0.37)가 된 몫이고, 보안 본문 쪽은 같다(핸들러 진입 둘과 `SetAttribute` 둘).

## P2. 누름을 파싱으로

beat보다 먼저다. 누름이 API로 재는 동안 beat를 파싱으로 바꾸면 둘이 갈릴 수 있다. 상태 낱말(P2a)도 유닛 낱말(P2b)도
들어갔다.

- **P2a, 들어갔다.** 리빌드가 레코드의 상태 축을 식 하나로 굽고(`UpdateBindings.lua`의 `StateExpression`,
  `PARSED_STATE_AXES`), 레코드는 축마다의 필드 대신 `t.expr`을 싣는다. `EVAL_SNIPPET`은 그 식을 한 번 파싱한다.
  축마다의 꼴: 불리언은 `[w]`/`[now]`, `skyriding`은 `bonusbar:5`, `groups`는 `nogroup`·`group:party,nogroup:raid`·
  `group:raid`(공격대에서도 `[group:party]`가 참이라서), `forms`는 `form:a/b`, `bonusbars`는 `bonusbar:a/b`와 오프셋
  0의 `nobonusbar:1/2/3/4/5`, `specialbar`는 `[vehicleui][possessbar][overridebar][shapeshift][petbattle]`. 축 여럿은
  그룹의 곱이고, `flyable`·`advflyable`은 그룹 끝에 둔다. `known`과 스위치, 개체창 종류, 유닛은 그대로다.
- `check:state-eval`은 방향을 바꿨다. 누름이 `STATE_EVAL_EXPRESSIONS`의 꼴을 하나도 안 싣는지를 본다. 그 표는 이제
  beat만 쓴다.
- 시험: `judgment_spec`의 "모든 칸 조합에서 항목이 누름과 같다"는 그대로 선다. `eval_spec`에 "a state axis at the press
  follows the parse where the API says otherwise"를 넣었다(P0-1의 `diverge`). P2a 앞의 코드에서 실패하는 것을 봤다.
- **P2b, 들어갔다.** 유닛 조건 하나가 식 하나다(`UnitExpression`). `t.expr`에 합치지 않고 유닛마다 따로 파싱한다.
  고정 유닛은 식을 통째로 굽고(`u.expr`), 별칭과 가리킨 프레임은 `@` 뒤를 구워(`u.tail`, 그룹이 둘이면 `u.tail2`)
  누름이 그때의 유닛을 앞에 붙인다. 반응은 beat의 칸 읽기(돕기 먼저, 다음 공격)대로 쓴다: 돕기 `help`, 적대
  `nohelp,harm`, 그 밖 `nohelp,noharm`, 돕기+적대 `[help][harm]`, 돕기+그 밖 `[help][noharm]`, 적대+그 밖 `nohelp`.
  존재·반응·생사의 클릭 메모는 없어졌고 `ClickUnitGroup`은 남았다. `unitgroup`과 역할은 그대로다.
- **`exists`는 beat가 `UnitExists`를 부르는 유닛에만 쓴다** (debind-e6와 정함). 맵만 보는 별칭(tank, healer,
  maintank, mainassist)과 가리킨 프레임은 맵에 유닛이 없으면 파싱 없이 없는 것이고, 있으면 `exists` 없이 파싱한다. 그래야
  beat의 "맵에 있으면 있다"와 같은 답이다. 고정 유닛과 custom1·2는 `exists`를 쓴다. P3-2에서 맵만 보는 별칭에 `exists`를
  넣을 때는 beat와 누름에 함께 넣는다.
- **`player`는 `exists`를 묻지 않고, beat도 늘 있는 것으로 읽는다.** P3-4의 xptr 차량에서 `[@player,exists]`가 내내
  거짓이었다. 물으면 차량 안에서 나에게 건 조건이 다 꺼진다. `UnitExists("player")`가 거짓인 때는 없으니 beat의 측정도
  `exists = true`로 바꿨고, `judgment_spec`은 플레이어가 없는 상태를 만들지 않는다.
- 시험: `eval_spec`의 "a unit condition at the press follows the parse where the API says otherwise"(`exists`·`help`·
  `harm`·`dead`를 대상과 가리킨 프레임에서 하나씩 갈라 본다)는 P2b 앞의 코드에서 일곱 경우 모두 실패하는 것을 봤다.
  "a condition on the player holds where the parse says the player is gone"은 `player` 예외를 뺀 코드에서 실패하는 것을
  봤다. 키트의 `player-dead`는 `PROBE.ParseUnit`의 개발 꼴이 `MockUnitWords[unit]`으로 낱말을 바꿔 잡는다.

## P3. 묶음을 식으로 굽는다

C2, C4, C6. 이 일의 본체였다.

### 결과: 묶음을 식으로 굽는 경로는 뺐다 (소유자, 2026-10-05)

`BundleExpression`(묶음마다 절 `[…] 1; […] 2; 3`을 굽고 beat마다 파싱하는 경로, P3-1~P3-3)을 만들어 벤치로 쟀다(P3-6).
대부분의 beat에서 루프보다 느려서 뺐다. 남은 것은 루프(`JudgeColumns`)이고, 루프가 상태와 유닛을 누름과 같은 글로
파싱해 잰다(debind-e6와 정함, F1).

- 상태 컬럼은 `StateCellText`가 쓰는 글을 파싱한다. 불리언은 누름의 `StateAlternatives`가 쓰는 "켜짐" 글,
  `groups`·`forms`·`bonusbars`는 값마다 칸 번호를 붙인 절이다.
- 유닛 칸은 `ClassifyPieces`의 글 하나를 파싱한다. 값은 `UNITSTATE_*` 번호다. `exists`는 P2b의 규칙대로
  (`UnitAsksExists`) 묻는다. 별칭과 가리킨 개체창의 유닛은 토큰이 바뀔 때 그 글에 넣어 두고(`JudgeClassify`,
  `JUDGE_COMPOSE_SNIPPET`), 토큰이 없으면 파싱하지 않고 없음으로 정한다.
- 누름의 `UnitExpression`도 같은 `UnitAlternatives`(7칸 마스크)에서 글을 만든다.
- 가리킨 개체창은 body마다 처음에 한 번 읽고(`prepare`), beat에서는 가리키는 동안만 읽는다(F3).
- API에 남은 것은 `unitgroup`, 역할, 개체창 종류, `known`의 주문책이다. `STATE_EVAL_EXPRESSIONS`는 이제 아무 본문도
  쓰지 않고, 루프와 누름이 다시 쓰면 안 되는 API 꼴의 목록으로 남는다. 개발 빌드의 `PROBE.MockUnitDead`는 없어졌다.

아래 P3-1~P3-3과 P3-5의 앞 세 줄은 뺀 경로의 계획이다. 다시 꺼낼 때를 위해 남긴다.

### P3-1. 식에 들어가는 것과 beat의 지역 변수

리빌드가 `Judgment.Build`의 항목(`columns`, `entries`, `rest`)에서 묶음마다 식을 굽는다.

- **식에 들어가는 것**: 상태 낱말, 묶음 항목의 첫 유닛의 낱말.
- **beat의 지역 변수**: 파싱으로 가지 않는 것(`known`의 주문책, `unitgroup`)과
  한 항목에 둘째로 나오는 유닛. 측정은 테이블(`JudgeColumns[i].cell`)이 아니라 지역 변수에 담는다. 쓰기 0.443과
  비교가 빠진다.
- 지역 변수의 값으로 그 묶음의 **판**을 고른다. 판은 그 값을 넣어 항목을 미리 줄인 식이다. 맞는 검사는 지우고, 틀린
  검사가 든 항목은 뺀다. 리빌드가 굽는다.
- 비싼 낱말(`flyable`·`advflyable`)과 `known`은 8-3대로 지역 변수에 한 번 담아 판을 고른다. 그 판을 골라야 하는
  분기 안에서 처음 한 번만 잰다(`if fly == nil then`). 비싼 낱말은 `[flyable]` 파싱으로 잰다. 누름도 파싱하니 같은
  답이다.

### P3-2. 식에 끼워 넣는 것

8-6(정함): 식은 참조하는 값이 바뀔 때만 다시 조립하고, beat는 파싱만 한다. 조립은 지금 있는
`COMPOSE_MACROTEXT_SNIPPET`의 치환을 쓴다.

- **별칭 유닛**(tank, healer, custom1·2). `SetUnit`·`SetRoleUnits`가 별칭이 가리키는 실제 유닛을 끼워 넣는다
  (`[@party2,help,nodead]`). 유닛이 없으면 없는 유닛(`raid41`)을 끼운다. 지금 beat는 tank·healer 같은 별칭을 맵에
  유닛이 있으면 있는 것으로 보는데(`UnitExists`를 안 부른다), 파싱의 `exists`는 실제로 있는지를 묻는다. 누름도 같은
  식을 파싱하니 둘은 같은 답이고, 맵과 실제가 어긋나는 틈에서는 실제를 묻는 쪽이 맞다. P2b의 누름은 맵만 보는
  별칭에 `exists`를 쓰지 않으니, 이 단계에서 beat와 누름 양쪽에 함께 넣는다.
- **가리킨 프레임**(`@hover`). enter·leave가 이미 풀린 프레임 유닛을 끼워 넣는다. **역할과 개체창 종류도 같은
  자리에서 상수로 끼워 넣는다.** 지금도 `judge-unitframe` 깨움이 `READ_UNITFRAME_SNIPPET`으로 둘을 읽어
  컬럼에 담는다(SB:1151-1161, UB:2701-2709). 담는 자리가 컬럼에서 식으로 바뀌고, beat는 둘을 읽지도 판정하지도
  않는다. 커서가 멈춘 채 프레임이 다시 배치되면(F3) beat가 유닛을 다시 읽어 토큰이 바뀌었을 때 다시 조립하고,
  역할과 개체창 종류도 그때 다시 읽는다.
- **손으로 켜는 스위치**. `SetSwitch`가 다시 조립한다. 조립은 레코드에서 하니 검사의 방향을 안다. 켜져 있어야 하는
  검사는 참이면 `""`, 아니면 `known:0`. 꺼져 있어야 하는 검사는 거짓이면 `""`, 참이거나 켜지지 않았으면 `known:0`.
  지금의 `COMPOSE_MACROTEXT_SNIPPET`(SB:306-315)은 켜지지 않은 것을 거짓으로 끼워 넣어, "꺼져 있어야 한다"는 검사가
  켜지지 않은 때 맞는다. 누름은 켜지지 않은 것을 어느 쪽에도 맞지 않게 본다. 이 꼴을 그대로 쓰면 beat와 누름이
  갈린다. 역할과 개체창 종류도 같은 꼴로 끼운다.
- 같은 토큰 뒤에서 유닛만 바뀌면 다시 조립하지 않는다. 파싱이 그때의 유닛을 본다.

### P3-3. 넘어야 할 것

- **그룹 하나에는 `@unit` 하나다.** 우리 조건은 한 레코드가 여러 유닛을 볼 수 있다. 둘째 유닛부터는 **값이 붙은 절로
  칸을 가려내는 식**을 한 번 파싱해 지역 변수에 담는다.

  ```lua
  focus = SecureCmdOptionParse("[@focus,noexists] none; [@focus,help,dead] helpDead; [@focus,help] help; [@focus,harm,dead] harmDead; [@focus,harm] harm; [@focus,dead] dead; alive")
  ```

  API로 재면 `UnitExists` 0.29, `UnitIsDead` 0.28, `PlayerCanAssist` 0.84 등으로 1.5 남짓이다. 이 식의 값은 안
  쟀고, 7-1의 "값이 붙은 절 3개" 0.37과 "그룹 4개" 0.52로 보아 그보다 싸다고 본다. 벤치에서 잰다. 칸 이름은
  `UNITSTATE_*`와 하나씩 맞춘다. 가려내는 식도 별칭이면 P3-2대로 끼워 넣어 조립한다. 매크로로 쓸 수 있는 여러 칸짜리
  컬럼(`form`, `group`)도 같은 꼴로 가려낼 수 있다.
- **마스크가 칸의 합이면 그룹 여럿으로 펼쳐진다.** 유닛 칸 7개(`UNITSTATE_*`)의 마스크 127가지마다 가장 짧은 그룹
  목록을 표로 미리 만든다. 마스크가 "없음" 칸을 빼면 `exists`를 꼭 넣는다. `[@raid41,nodead]`는 참이다. 항목 안의
  여러 컬럼은 그 목록의 곱이다.
- **판의 수와 그룹의 수에 상한을 둔다.** 넘는 묶음은 지금의 컬럼 판정 루프에 남는다. 그 루프는 이미 있고 시험도
  있다. 상한의 값은 P0의 벤치가 정한다.

### P3-4. 식의 꼴

- `bonusbars`의 오프셋 0은 `[nobonusbar:1/2/3/4/5]`로 쓴다. `[bonusbar:0]`은 보너스 바가 없을 때 맞지 않고(7-1),
  맨 `[nobonusbar]`는 늘 참이다. `[nobonusbar:1/2/3/4/5]`는 맞게 답했다(2026-10-05, 소유자가 게임에서 확인). 드루이드
  변신으로 오프셋이 여덟 번 움직이는 동안 `[nobonusbar:1/2/3/4/5]`와 `[bonusbar:n]`은 오프셋과 어긋나지 않았다(상시
  `/debgw`). 오프셋이 5를 넘는 장면이 있으면 그 값도 넣어야 한다.
- `specialbar`는 `[vehicleui][possessbar][overridebar][shapeshift][petbattle]`로 쓴다. Keys Given Back의 드라이버
  (`GIVE_BACK_REPLACED_BAR`, `GIVE_BACK_PET_BATTLE`)가 이미 같은 낱말로 "단축바가 바뀌었다"를 읽는다. 지금 측정식의
  `HasVehicleActionBar()`는 `[vehicleui]`와도 `[possessbar]`와도 같지 않고(빙의 중 `[possessbar]` 참, `[vehicleui]`
  거짓, 바는 차량 바, UB:634-636), 드라이버가 깨는 순간 아직 거짓으로 답한 적이 있다(UB:638-642). 두 기능이 같은 식을
  읽게 되니 "단축바가 바뀌었다"의 답이 하나가 된다. 누름의 `specialbar`도 P2에서 같은 식을 파싱한다. 리테일에서 빙의를
  포함해 여섯 번 움직이는 동안 이 식은 지금의 API 측정식과 어긋나지 않았다(2026-10-05, 상시 `/debgw`). xptr(120105,
  마법사, 차량)에서는 다섯 번 어긋났는데, 모두 식이 1~2프레임 먼저 참이 되고 API가 따라온 것이다. UB:638-642가 적은
  "드라이버가 깰 때 `HasVehicleActionBar()`가 아직 거짓"과 같은 꼴이다.
- 같은 xptr 차량에 타고 있는 동안 `[@player,exists]`는 내내 맞지 않았다(소유자, `/dump`; 상시 `/debgw`의 매 프레임
  짝으로 한 번 탈 때마다 867~11881프레임, 차량 안에서 리로드한 뒤에도 같았다). `UnitExists("player")`는
  참이고, `[@player,unithasvehicleui]`도 API와 갈렸다. 그때 `[@vehicle,exists]`는 참이었다(소유자). 같은 실행에서
  `pet`의 유닛 낱말은 매 프레임 API와 같았고, `vehicle`의 `exists`·`help`(아홉 번)와 `player`의 `help`(열여섯 번)도
  어긋나지 않았다. 갈린 것은 `player`의 `exists`와 `unithasvehicleui`뿐이다. Units에는 `player`가 없지만 대상·별칭이 나로 풀린 채 차량에 타면
  같은 일이 생기는지는 안 쟀다.

- 절은 항목 순서대로 둔다. 파싱도 첫 일치가 이기니 `MAX_WORK`로 끊겨 레코드 순서로 떨어진 경우에도 같다.
- `rest`는 맨 끝의 값이다. `"base"`는 값으로 내보내고 파싱 뒤에 `base.want`로 푼다. 묶음 순서는 지금처럼 기본
  키가 조합 키보다 앞이다.
- 그룹 안은 싼 토큰을 앞에 둔다(C6). 묶음 식은 우리가 처음부터 만드니 순서는 우리 것이다. 사용자 스위치 글은 순서를
  바꾸지 않는다(8-5).
- 결과는 지금처럼 `bundle.want`에 둔다. 값의 뜻(`"ours"`, `"release"`, 명령 이름)이 그대로라 `UpdateGivenBackKeys`는
  손대지 않는다. beat 본문은 첫머리에서 `JudgeBundles`를 지역 변수로 받아 묶음마다 필드 하나를 견준다(7-1, +0.085).

### P3-5. 시험

- `judgment_spec`의 "모든 칸 조합에서 항목이 누름과 같다"를 새 경로의 beat에도 건다. 따로 두는 것: 유닛 둘을
  보는 항목, 합 마스크, 상한을 넘어 루프에 남는 묶음, `base`, 켜지지 않은 스위치를 꺼져 있어야 한다고 보는 레코드,
  맵에는 있고 실제로는 없는 별칭 유닛, 커서 밑에서 다시 배치된 프레임.
- 켜지지 않은 스위치의 경우는 P3-2의 방향 구분이 없는 코드에서 실패해야 한다.
- P0-1의 "낱말 하나를 API와 다르게 답하게 하는 갈래"로 beat와 누름이 같은지를 본다. P2 없이 이 단계만 들어가면
  실패해야 한다.
- 남은 시험(`judgment_spec`): 낱말이 API와 갈린 beat(API로 재는 루프에서 실패), 계산식 스위치 옆의 상태 컬럼이 갈린
  beat(`mounted`를 API로 잰 루프에서 실패), 루프의 본문에 API 꼴이 없음(같은 변경에서 실패), 유닛 둘(`ClassifyPieces`에서
  `help,dead` 절을 뺀 코드에서 실패), 별칭(`custom1`·`tank`), 맵만 보는 별칭(그 별칭에 `exists`를 묻게 한 코드에서 실패),
  커서 밑에서 다시 배치된 프레임(beat의 프레임 읽기를 뺀 코드에서 실패). 실패를 본 것은 묶음 식 경로가 있던 때다.

### P3-6. 관문

새 경로는 조용한 beat에도 묶음마다 파싱한다. 지금 경로는 조용한 beat에 컬럼을 재고 견주기만 한다. 묶음이 많고
컬럼을 많이 나눠 쓰는 프로필에서는 지금 경로가 이길 수 있다(7-1: 컬럼 여섯을 재고 견주기 3.99, 묶음 하나 파싱
0.34~0.60). P0의 벤치로 두 경로를 견준다. 입력은 묶음 수, 묶음이 컬럼을 나눠 쓰는 정도, 유닛 조건의 몫을 바꿔
가며 만든 합성 프로필이고, 어느 모양에서 지금 경로가 이기는지가 답이다. 그 자리가 판 수 상한과 그룹 수 상한이 되고,
상한 안에서도 지면 C5(공통 부분을 한 번 파싱)를 이 단계에 붙인다.

**잰 것** (2026-10-05, `lua5.1 tests/run.lua --bench-beat`의 P3-6 표, beat 하나 µs). `shared`는 6가지 상태 조합을
돌려 쓰는 키, `distinct`는 키마다 다른 `forms`·`bonusbars`·`combat`, `units`는 `combat` 옆에 `target`·`focus`, `flyable`은
모든 키에 `flyable`. 루프 / 식, 상태가 그대로인 beat | 네 beat마다 상태가 바뀔 때:

| 모양 | 키 4 | 키 12 | 키 30 |
|---|---|---|---|
| shared | 12.40/12.35 \| 15.61/14.65 | 12.98/13.53 \| 17.56/16.59 | 12.98/13.53 \| 19.27/18.30 |
| distinct | 12.88/12.42 \| 15.23/12.40 | 12.88/17.14 \| 19.56/17.14 | 12.88/27.76 \| 29.24/27.76 |
| units | 12.63/13.46 \| 15.59/14.84 | 12.63/14.70 \| 17.52/17.15 | 12.63/14.70 \| 19.23/18.87 |
| flyable | 16.76/17.53 \| 19.24/15.20 | 16.76/18.18 \| 19.93/18.44 | 16.76/18.18 \| 19.93/18.44 |

루프가 아직 API로 재던 때(같은 벤치, 루프를 파싱으로 바꾸기 전)의 상태가 그대로인 beat는 키 30에서 `units` 15.05,
`flyable` 17.36이라 `units`는 식이 이겼다. 루프가 파싱으로 재게 되자 상태가 그대로인 beat는 거의 모든 모양에서
루프가 이긴다. 식은 상태가 바뀐 beat에서만 1µs쯤 빨랐다. 손으로 켜는 스위치의 깨움은 조립 때문에 15.61에서 17.76이
됐다.

**뺀 까닭.** 식 경로는 상태가 그대로인 beat에도 묶음마다 다시 파싱하니 값이 묶음 수를 따른다. 루프는 컬럼마다 한 번
재고, 바뀐 컬럼이 없으면 아무 묶음도 판정하지 않으니 값이 컬럼 수를 따른다. 대부분의 beat는 상태가 그대로다.
**8-1의 "열 배 남짓 싸다"는 견줄 것을 잘못 골랐다.** 컬럼이 움직인 beat의 루프 값(컬럼 여섯을 재고 견주기 3.99,
판정 루프 2.07)을 묶음 하나의 파싱(0.34~0.60)과 견줬다. 상태가 그대로인 beat에서 견줄 것은 컬럼을 재는 값과 묶음을
파싱하는 값이다. 다시 꺼낸다면 이 표를 넘는 근거가 있어야 한다.

### P3-7. change detector (debind-e6가 냄)

불리언 컬럼 몇 개를 파싱 하나로 묶어 번호로 받고(`[a,b] 3; [a] 1; [b] 2; 0`) 지난 번호와 견준다. 같으면 그 컬럼들을
재지 않고 넘어간다. 절의 수가 2^k라 k가 작을 때만 이긴다. 상태가 그대로인 beat에서 이길 때만 넣고, 지면 값을 적고
뺀다.

**들어갔다, 3개까지** (`JUDGE_DETECT_MAX`). "켜짐"이 낱말 하나인 불리언 컬럼만 들어가고 `flyable`·`advflyable`은
빠진다(절 안에서 앞 낱말이 맞으면 판정되므로). 번호는 `JudgeDetect`에 두고, 리빌드가 지운다. 벤치, 키 12개, beat 하나
µs, 상태 변화 없음 | 네 beat마다 `combat`·`mounted`가 뒤집힘, 묶는 컬럼 수별:

| 모양 | 0 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| shared | 12.98 \| 17.46 | 12.61 \| 17.38 | 12.16 \| 17.04 | 11.86 \| 16.82 | 11.83 \| 16.93 |
| flyable | 16.76 \| 19.83 | 16.39 \| 19.73 | 16.39 \| 19.73 | 16.39 \| 19.73 | 16.39 \| 19.73 |

`distinct`와 `units`는 불리언 컬럼이 `combat` 하나라 바뀌지 않는다. 벤치는 파싱 값을 판정한 낱말 수로 매기고 글의
길이는 매기지 않는다. 7-1은 첫 낱말이 거짓이어도 긴 글이 더 든다고 쟀으니, 절이 15개인 4는 벤치만큼 이기지 못할 수
있다. 그래서 3으로 두었다. 시험: 번호의 비트를 거꾸로 읽은 코드에서 B4·B5·B6과 "the bars, skyriding and pet battles"가,
리빌드에서 `JudgeDetect`를 지우지 않은 코드에서 B6과 같은 케이스가 실패하는 것을 봤다.

## P4. 계산식 스위치

8-6과 D6(정함). **들어갔다.** 조립(`COMPOSE_MACROTEXT_SNIPPET`, 2~5)은 beat에서 돌지 않는다. 처음 글은 묶음 식에
표시하는 꼴이었고, 묶음 식이 빠져서 루프의 스위치 컬럼으로 다시 짰다(debind-05).

전에는 루프가 컬럼이 읽는 계산식 스위치와 그것이 읽는 것을 body마다 `SwitchesToWorkOut` 순서로 조립하고 파싱했다
(`workOutSwitches`). 조립할 인자는 별칭과 가리킨 개체창의 유닛, 손으로 켜는 스위치, 다른 계산식 스위치다.

- **조립된 글은 `JudgeSwitchTexts[이름]`에 둔다. 비어 있으면 다시 조립할 차례다.** body는 순서대로 글을 읽고, 없으면
  조립해 넣은 뒤 파싱한다. 표시는 글을 지우는 것이라 조용한 beat에는 글을 읽는 값 말고 더 드는 것이 없다. 글이 여럿을
  참조해 같은 beat에 둘이 바뀌어도 조립은 한 번이다. 리빌드가 표를 지우니 첫 패스가 다 조립한다.
- **글을 지우는 곳은 참조하는 값을 바꾸는 쪽이다** (8-6의 1~5).
  - 계산식 스위치: 파싱한 값이 `JudgeSwitches`의 지난 값과 다르면 그 값을 쓰고, 그것을 바로 읽는 글을 지운다. 순서가
    읽히는 쪽을 앞에 두니 같은 body 안에서 사슬이 풀린다. 읽는 글이 그 body의 순서에 없으면 지워진 채 다음 body가
    조립한다. 값이 그대로인 beat에는 `JudgeSwitches`에 쓰지 않는다(전에는 매번 썼다, 쓰기 0.44).
  - 별칭과 손으로 켜는 스위치: 그 이름의 깨움(`judge-<이름>`)이 처음에 지운다. 그 깨움은 그 이름을 거쳐 읽는 계산식
    스위치 컬럼도 잰다. 그래서 계산식 스위치 컬럼의 깨움(`JudgmentWakesOf`)은 그 글이 (다른 계산식 스위치를 거쳐서라도)
    읽는 별칭, 개체창, 손으로 켜는 스위치다. 전에는 그 깨움이 없어서 다음 beat가 받았다.
  - 가리킨 개체창: `prepare`가 개체창의 유닛이 바뀐 것을 보는 자리(enter·leave 깨움과 beat의 F3)에서 지운다.
- 조립은 누름과 같은 `COMPOSE_MACROTEXT_SNIPPET`이고, 켜지지 않은 손 스위치를 끼우는 꼴도 누름과 같다. P3-2의 방향
  구분은 묶음 식에 끼울 때의 일이라 여기에는 없다.
- **고친 결함 하나.** 개체창을 읽는 컬럼이 없고 `[@unitframe,help]` 같은 계산식 스위치만 개체창을 읽으면, 루프는
  개체창을 한 번도 읽지 않았다(`_judgeReadsFrame`이 컬럼의 깨움만 봤다). 누름은 우리, 루프는 놓음이었다. 개체창이 그
  스위치 컬럼의 깨움이 되면서 고쳐졌다.
- 시험(`judgment_spec`), 셋 다 P4 앞의 코드에서 실패하는 것을 봤다.
  - "a computed switch on the pointed frame": 위 결함. P4에서 개체창이 바뀐 자리의 글 지우기를 뺀 코드에서도 실패했다.
  - "a computed switch reading two others": 상태가 그대로인 beat는 아무 글도 조립하지 않고, `$a`·`$b`가 한 beat에 함께
    뒤집히면 둘을 읽는 `$c`를 그 beat에 한 번 조립한다(`table.concat`을 센다). 뒤집힌 스위치의 글 지우기를 뺀 코드에서
    실패했다.
  - "a computed switch reading a switch set by hand, and one reading an alias": `SetSwitch`·`SetUnit`의 깨움만으로, beat
    없이 키가 누름과 같아진다. 깨움의 글 지우기를 뺀 코드에서 실패했다.
  - 키트의 "Tail: a switch set by hand moves the key through two computed switches": 손 스위치 하나를 계산식 스위치 둘이
    차례로 읽는다. 깨움 하나에서 조립, 깨움의 지우기, 뒤집힌 스위치의 지우기가 다 restricted environment에서 돈다. `[combat]` 같은
    낱말로 beat 쪽을 보지 않는 것은 계산식 스위치가 개발 빌드의 목(`PROBE.SecureCmdOptionParse`)이 닿지 않는 맨
    `SecureCmdOptionParse`로 파싱하기 때문이다(누름의 `COMPUTE_SWITCHES_SNIPPET`과 같다).
- 벤치(`--bench-beat`의 "computed switches"): 키 12개가 `$h = [$w,mounted]`, `$u = [@custom1,help]`,
  `$c = [$a,stealth]`, `$a = [combat]`을 돌려 읽는다. `table.concat`은 벤치가 세지 않고 있어서 7-1의 0.54(조각 셋)로
  넣었다. beat 하나 µs, 앞 / 뒤:

  | | P4 앞 | P4 뒤 |
  |---|---|---|
  | 상태가 그대로인 beat | 25.93 | 16.36 |
  | 네 beat마다 `combat`·`mounted`가 뒤집힘 | 29.29 | 20.91 |
  | `custom1`을 옮기는 `SetUnit` | 4.52 | 18.59 |

  앞의 beat는 조립 셋(`$h`, `$u`, `$c`)을 매번 했다. 뒤는 조용한 beat에 조립이 없고, 뒤집히는 beat에 `$c` 하나다.
  `SetUnit`이 오른 것은 새로 생긴 깨움(`RunAttribute` 3.09, 조립, 파싱, 판정)이다. `custom1`은 액션이 누를 때 옮기니
  손 빠르기로 온다. 깨움은 그 이름으로 분류하는 글이 없으면 `JudgeComposeBy`를 찾지 않아서, 처음 넣은 꼴보다
  0.25쯤 싸다(`SetUnit` 18.84, 벤치의 손 스위치 깨움 15.85 → 15.61).
- **리빌드가 `JudgeSwitches`도 지운다.** 조립은 이 표를 `States`보다 먼저 읽는다. 그래서 계산식이던 스위치를 손 스위치로
  바꾸면 루프가 남긴 옛 값이 진짜 값을 가렸다(P4 전부터 있던 결함). `judgment_spec`의 "a computed switch made one set
  by hand"는 이것을 고치기 전 코드에서 실패하는 것을 봤다.
- `SwitchesToWorkOut`은 `ComposedReads`의 간선을 걷는다. 깨움과 `readers`도 같은 간선에서 나온다. 리빌드가 글에
  못 박은 스위치(무시된 것, 자기 자신)는 컬럼이 읽을 때만 일한 차례에 든다.

## P5. `petbattle`·`house:editor`를 비보안 쪽이 넣는다

3-3(정함). **들어갔다** (debind-05). 처음 글은 깨움이 묶음 식을 다시 조립하는 꼴이었고, 루프의 컬럼으로 다시 짰다.

- **열림은 이벤트 이름이 정하고, 닫힘은 파싱이 이미 거짓일 때만 믿는다** (소유자, 2026-10-05). `SecureBindings.lua`의
  이벤트 프레임이 `PET_BATTLE_OPENING_START`면 참을 넣고, `PET_BATTLE_CLOSE`에서는 비보안 쪽 `[petbattle]`이 거짓일
  때만 거짓을 넣는다. 처음 꼴은 닫힘도 이벤트 이름대로 거짓이었는데, 리뷰에서 첫 닫힘부터 둘째 닫힘까지 루프는 키를
  잡고 누름은 꼬리 명령에 닿아 그 키가 아무것도 안 한다는 것이 나왔다. 지금 꼴에서는 루프가 누름과 같은 순간에 놓는다.
  - 잰 것(2026-10-05, 대전 한 번, 프로브는 지웠다): 닫힘은 두 번 왔고 같은 프레임이었다. 첫 닫힘에서 `[petbattle]`
    참, `C_PetBattles.IsInBattle()` 참, 둘째 닫힘에서 둘 다 거짓. 둘 다 잠금이 아니었다. 그러니 둘째 닫힘에서 거짓이
    들어간다. 두 닫힘이 모두 참이었다면 다음 대전까지 참이 남는 꼴이다.
- `SetPetBattle`은 `JudgePetBattle`에 쓰고 `judge-petbattle` 깨움을 부른다. 비보안 쪽은 넣은 값을 기억해 바뀐 값만
  넘긴다(둘째 닫힘 뒤의 닫힘은 넘어가지 않는다). 상태를 묻는 것은 로그인 때(`SeedPetBattle`, 대전 중 리로드에는
  이벤트가 없다)이고, 시작값은 기억과 상관없이 넘긴다. `JudgePetBattle`은 리빌드가 지우지 않는다.
- 잠금 중이면 넣지 않고 `PLAYER_REGEN_ENABLED`에서 리빌드보다 먼저 넣는다(`FlushPetBattle`). 대전은 잠금 중에 끝나지
  않지만 로그인은 잠긴 채 시작할 수 있다.
- `[petbattle]`을 읽는 계산식 스위치는 beat에서 파싱하고 `petbattle` 깨움에 서지 않는다. 대전이 시작될 때 그 스위치는
  다음 beat에 바뀐다(리뷰, 그대로 두었다). 사용자 글에서 낱말을 찾아 깨움을 거는 것은 E2의 얕은 파싱 일이다.
- 루프: `petbattle` 컬럼은 beat에서 재지 않고(`JudgedOnBeat`) 넣은 값을 읽는다. `specialbar`는 넣은 값이 참이면 참이고,
  아니면 `[vehicleui][possessbar][overridebar][shapeshift]`를 파싱한다. 둘 다 `petbattle` 깨움에 선다. beat 본문에
  `petbattle`이라는 글자가 없다.
- 누름은 지금처럼 `[petbattle]`을 파싱한다.
- 루프 때문에 매니저에 걸던 `PET_BATTLE_*`는 `CollectDriverEvents`에서 뺐다. Keys Given Back의 등록은 그대로다.
- **beat는 재는 컬럼이 있을 때만 건다** (`plan.beats`, 리뷰). 꼬리 조건이 손 스위치나 `petbattle`뿐인 프로필은
  beat가 없다. mouseover가 사라지는 것과 멈춘 커서 밑에서 개체창이 다시 배치되는 것은 이벤트가 없어 beat만 잡는데, 둘
  다 beat가 재는 컬럼(`unit mouseover`, `unit unitframe`, `role`, `frameType`)이라 그 프로필에는 beat가 선다.
  `plan_spec`의 "the beat is asked for only where it measures a column"이 두 방향 다 실패하는 것을 봤다.
- **`house:editor`는 할 일이 없다.** 조건 축(`CONDITION_AXES`)에 없어서 루프의 컬럼이 아니다. 집 편집기는 Keys Given
  Back의 출처(`ContextKeys`)로만 들어온다.
- 시험(`judgment_spec`), 셋 다 P5 앞의 코드에서 실패하는 것을 봤다.
  - "a pet battle told by its events": 로그인 때의 시작값(밖에서 쓴 값 위로도), 열림, 첫 번째 닫힘(세상은 아직 대전
    중, 루프도 누름도 대전), 두 번째 닫힘, 아무것도 안 바꾸는 닫힘은 넘어가지 않음. 닫힘을 이벤트 이름대로 넣는 코드,
    값이 같아도 넘기는 코드, 시작값이 기억을 따르는 코드에서 각각 실패했다.
  - "a pet battle told in a lockdown waits for its end": 잠금 검사를 뺀 코드와 `FlushPetBattle`을 막은 코드에서 각각
    실패했다.
  - "the beat parses no pet battle".
  - "the bars, skyriding and pet battles"의 sweep은 점마다 `SetPetBattle`로 넣는다.
  - 키트의 "Tail: a pushed pet battle moves the key on its wake": `SetPetBattle`과 그 깨움이 restricted environment에서
    `[petbattle]` 키와 `[nospecialbar]` 키를 beat 없이 옮긴다. 대전은 마음대로 열 수 없어서 이벤트가 넣는 꼴로 직접
    넣고, `SeedPetBattle`이 그 위로 세상의 값을 되돌리는지까지 본다. 이벤트 프레임 자체는 헤드리스가 본다.
- 벤치(`--bench-beat`의 `bars` 모양: 짝수 키 `petbattle = false, combat`, 홀수 키 `specialbar = false, mounted`, 키 12개,
  상태가 그대로인 beat | 네 beat마다 `combat`·`mounted`가 뒤집힘, µs), 앞 / 뒤:

  | change detector의 컬럼 수 | 0 | 2 | 3 (`JUDGE_DETECT_MAX`) |
  |---|---|---|---|
  | 앞 | 12.54 \| 17.98 | 12.16 \| 17.88 | 11.72 \| 17.50 |
  | 뒤 | 12.08 \| 17.53 | 11.71 \| 17.43 | 11.71 \| 17.43 |

  지금 설정(3)에서는 거의 그대로다. 앞에서도 change detector가 `petbattle`을 파싱 하나에 묶고 있었기 때문이다. 줄어든
  것은 detector의 자리 하나다. 불리언 컬럼이 넷 이상인 프로필에서는 그 자리를 다른 컬럼이 쓴다. 다른 값어치는
  3-3이 적은 대로 이벤트 순간에 깨운다는 것이다.

## P6. 매니저 이벤트

G. **바꾸지 않고 닫았다** (소유자, 2026-10-05). 처음 글은 "이벤트 하나는 매니저의 전체 패스 한 번이니 `SPELLS_CHANGED`부터
얼마나 자주 오는지와 늦으면 무엇이 틀리는지로 하나씩 본다"였다. 그 전제가 서지 않는다.

- 매니저의 `OnEvent`는 `timer = 0`뿐이다(`SecureStateDriver.lua`). 이벤트는 패스를 얹지 않고 앞당기고, 패스가 돌면 타이머가
  다시 0.2초로 시작한다. 패스 수가 느는 것은 이벤트가 0.2초보다 촘촘할 때뿐이고, 그때 느는 것은 이벤트를 건 이유 그 자체다.
- 이벤트를 빼면 늦어지는 폭은 정해진 값이 아니다. 그 사이 다른 이벤트(매니저 자기 목록, 다른 애드온이 건 것)가 오거나
  인터벌이 얼마 안 남았으면 곧바로이고, 아니면 0.2초까지다(소유자). "0.2초 안의 지연뿐"은 근거가 되지 못한다.
- 그래서 빈도도 늦어지는 폭도 재지 않는다. `SPELLS_CHANGED`를 빼고 싶어지면 `CollectDriverEvents`의 한 줄과 `plan_spec`의
  확인 한 줄이다.

## 순서의 까닭

- P0이 먼저다. P3의 시험은 파싱이 절과 `@unit`을 읽지 못하면 고치기 전 코드에서 실패할 수 없고, P3의 관문은 벤치
  없이는 정할 수 없다.
- P1은 판정을 바꾸지 않으니 따로 서고, 배관이 먼저 바뀌어 있어야 P3의 깨움 본문이 새 꼴로 생성된다.
- P2가 P3보다 먼저다. beat만 파싱하는 동안에는 beat와 누름이 갈릴 수 있다.
- P4는 P3의 깨움과 `prepare`(별칭과 개체창의 글을 조립하는 자리)에 글 지우기를 얹는다.
- P5와 P6은 P3 뒤라면 언제든 선다.
