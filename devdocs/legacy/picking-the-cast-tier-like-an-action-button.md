# 누름의 층과 조합 키를 블리자드 액션 버튼처럼 정한다 (2026-10-07 설계)

> 상태: 구현했다. 5절의 1~6이 다 들어갔다. 블리자드 액션 버튼이 어디로 시전하는지는 2026-10-07에 쟀고(9절 F14),
> 4절의 "블리자드" 칸은 그 측정이다. 열려 있던 질문(10절)은 그 측정으로 닫았다. 구현이 설계와 다르게 간 자리는 11절이다.
>
> 쓴 세션: `debind-56` (세션 ID `8a70b5af-30d5-4f9e-b943-6fd0a2c17be0`). `debind-99`가 검토했다(2026-10-07).
> 구현한 세션: `debind-d6` (세션 ID `0c061eb0-3fd2-4a42-be06-f2283594a377`).
>
> `debind-99`가 같은 일로 쓴 계획 둘과 그 커밋 안 된 코드를 대신한다. 그 계획들은 근거로 쓰지 않았다. 거기 적힌 사실은 원본에서
> 다시 확인한 것만 옮겼다(9절). 버린 것과 까닭은 6절이다. 그 계획 둘과 코드, 시험, 프로브는 커밋되지 않은 채 2026-10-07에
> 걷었다(소유자). 6절이 그 기록이다.

## 요약

- 조합 키는 그 층에 쌍둥이가 있을 때만 건다.
- 누름이 조합 키로 오면 그 조합의 층이다. 하나만 다르다. 주시 대상 조합(`ALT-X`)으로 왔는데 자기 자신 시전 키가 보이면, 그 키에
  self 쌍둥이가 있을 때 self 층이다. 와우 액션 버튼이 그렇게 한다(측정).
- 누름이 맨 키로 오면, 그때 보이는 Cast Key를 블리자드 순서로 묻는다.
- 받을 층이 없는데 Cast Key가 보이면 아무것도 안 한다.
- 누를 때와 뗄 때 같은 규칙을 쓴다. 그래서 "뗄 때 시전"도 블리자드와 같아진다.

이 문서에서 쓰는 말:

- **S**: 그 키의 self 층에 쌍둥이가 하나라도 있다.
- **F**: 그 키의 focus 층에 쌍둥이가 하나라도 있다.
- **켜진 Cast Key**: 설정 탭에서 켜 두었고, 게임 설정이 ALT·CTRL·SHIFT 가운데 하나인 것.
- 출처 표시: (결정) 소유자, (코드) 코드에서 읽음, (측정) 게임에서 잼, (추론) 확인하지 않음.

## 1. 정해진 것 (소유자, 2026-10-07)

1. self·focus 층의 조합 키는 그 층에 쌍둥이가 있을 때만 건다. 걸지 않은 조합은 클라이언트의 것이다.
2. `castKeyChordsOverGame`은 우리 쌍둥이와 바깥 바인딩 가운데 누가 이기느냐만 정한다. 옵션을 끄면 우선순위 `true`, 켜 두면
   `false`로 건다. 쌍둥이가 없으면 그 조합을 쥐지 않는다.
3. 3층(원본과 hover 쌍둥이)은 켜진 Cast Key를 쥔 누름을 받지 않는다.
4. 블리자드에 맞춘다. 블리자드는 `checkselfcast`가 켜진 버튼에서만 SELFCAST를 묻고, 그다음 FOCUSCAST를 묻는다. 어느 액션도
   Self Cast Key를 안 쓰는 키는 `checkselfcast`가 꺼진 버튼과 같다. 조합 키로 온 누름은 그 조합의 층이다.
5. "뗄 때 시전"도 블리자드 액션 바와 같아야 한다. 쌍둥이가 있는 키에서 X 누름 → CTRL 누름 → X 뗌은 self 쌍둥이를 낸다.

## 2. 층을 고르는 규칙

누름 하나, 엣지 하나마다 아래를 차례로 본다. 개체창 클릭은 지금처럼 층이 없다.

1. S이고, self 조합으로 왔거나 SELFCAST가 보이면 → self 층.
2. 아니면, focus 조합으로 왔거나, F이고 FOCUSCAST가 보이면 → focus 층.
3. 아니면, 켜진 Cast Key가 하나라도 보이면 → 아무 층도 안 돈다.
4. 아니면 → 3층.

**수식키를 읽는 것은 두 경우뿐이다.**

- **self 조합(`CTRL-X`, `CTRL-ALT-X`)으로 왔을 때는 읽지 않는다.** 들어온 것 자체가 self 쌍둥이를 쓰라는 뜻이다. 뗄 때도 누를 때
  들어간 바인딩으로 오므로(F7), 그 사이에 CTRL을 놓아도 self다.
- **focus 조합(`ALT-X`)으로 왔을 때는 SELFCAST 하나를 읽는다.** 뗄 때 시전에서 ALT를 쥐고 X를 누르고 CTRL을 더 쥔 뒤 떼면, 블리자드
  액션 버튼은 자기 자신에게 시전한다(측정, F14). 그 누름은 우리 `ALT-X`로 오고, 떼는 엣지에서 CTRL이 보인다(F8). 그래서 S인 키는
  self 층으로 간다.
- **맨 키(X)로 왔을 때는 둘 다 읽는다.** 뗄 때 시전에서 누른 뒤 Cast Key를 쥐면 그 쌍둥이를 내고(결정 5), 쌍둥이가 없어 조합을 안
  건 층의 Cast Key가 보이면 아무것도 안 한다(결정 3).

**누를 때 쥔 키를 우리가 기억할 필요는 없다.** 떼는 순간 클라이언트가 보여 주는 키가 이미 "누를 때 쥔 것 + 지금 쥔 것"이다(F7,
F8, F14). 블리자드도 떼는 순간 그 값을 읽어 시전 대상을 정한다.

**조합의 층을 "그 키가 보인다"로 읽는 까닭.** 클라이언트는 바인딩 이름에 든 수식키를 가린다(측정). `CTRL-X`로 온 누름에서
CTRL은 안 보이지만, 그 누름은 CTRL을 쥔 누름이다.

**엣지를 가르지 않는 까닭.** 블리자드는 실제로 시전하는 엣지에서 수식키를 읽는다(코드). 우리도 엣지마다 같은 규칙을 돈다.
떼는 엣지에서 클라이언트가 무엇을 보여 주는지는 쟀다(9절 F7, F8). 그래서 결과가 블리자드와 같다.

예: "뗄 때 시전"에서 X 누름 → CTRL 누름 → X 뗌. 떼는 엣지는 맨 X로 오고 CTRL이 보인다. S면 1번으로 self 층이다.

**`IsModifiedClick`으로 읽는다.** 블리자드가 읽는 것이 그것이다. 두 Cast Key가 같은 수식키여도 따로 묻지 않아도 된다. 계정에서
끈 키와 NONE은 리빌드가 구운 값이 거르고, 아예 묻지 않는다.

**비용.** 맨 키 누름마다 전역 하나와 `IsModifiedClick` 한두 번이다. self 조합으로 온 누름은 아무것도 안 읽는다. focus 조합으로
온 누름은 SELFCAST 하나를 읽는다. `debind-99`의 가드도 맨 키 누름마다 비슷하게 읽었다. 재지는 않았다.

### 2-1. 본문의 모양

```lua
local castModifier
if (clickCast) then
	castModifier = CONSTANTS.CASTMOD_NONE
elseif (castTier == CONSTANTS.CASTMOD_SELF) then
	castModifier = castTier
else
	castModifier = CONSTANTS.CASTMOD_NONE
	local castKeysOn = CastKeysOn
	if (castKeysOn) then
		local selfHeld = castKeysOn.self and PROBE.IsModifiedClick("SELFCAST")
		if (selfHeld and bindings.checkSelfCast) then
			castModifier = CONSTANTS.CASTMOD_SELF
		elseif (castTier == CONSTANTS.CASTMOD_FOCUS) then
			castModifier = castTier
		else
			local focusHeld = castKeysOn.focus and PROBE.IsModifiedClick("FOCUSCAST")
			if (focusHeld and bindings.checkFocusCast) then
				castModifier = CONSTANTS.CASTMOD_FOCUS
			elseif (selfHeld or focusHeld) then
				castModifier = false
			end
		end
	elseif (castTier) then
		castModifier = castTier
	end
end
PROBE.MockState(castModifier)
-- false: no tier takes the press (first, last = 1, 0)
```

- `PROBE.IsModifiedClick`은 새 프로브다. 배포판에서는 그냥 `IsModifiedClick(...)`이 되어 golden이 안 움직인다. 킷에서는 수식키를
  쥔 것처럼 답하게 할 수 있다. 킷이 실제 제한 환경에서 이 갈래를 돌릴 길은 이것뿐이다.
- `PROBE.MockState(castModifier)`는 그대로 둔다. 킷의 펼침은 걸어 둔 값이 없으면 손대지 않으므로(`DebindTest.lua` 933)
  `false`를 덮지 않는다.

## 3. 어느 조합 키를 거나

키 X, self 수식키 s, focus 수식키 f.

| 조합 | 층 | 거는 때 |
|---|---|---|
| X+s | self | S |
| X+s+f | self | S |
| X+f | focus | F |
| s와 f가 같을 때의 X+s | S면 self, 아니면 focus | S 또는 F |

- **X+s+f는 S가 아니면 걸지 않는다.** 그 누름은 클라이언트가 떨어뜨린다. 수식키를 ALT, CTRL, SHIFT 순으로 하나씩 떼어 보고
  처음 걸린 곳으로 간다(측정). s=CTRL, f=ALT면 먼저 X+s를 보고(바깥 바인딩이 있으면 거기), 없으면 X+f(우리 focus 조합)로 간다.
  결정 4의 예가 이것이다.
- **s와 f가 같을 때가 새로 바뀐다.** 지금 코드는 이 조합을 늘 self에 둔다. 그래서 self를 건너뛴 키는 focus 쌍둥이에 닿을 수 없다.
- 키 이름에 이미 든 수식키로는 조합을 만들지 않는다. 지금과 같다.
- 거는 곳은 지금 규칙 그대로다. 조합을 안 걸었을 때 그 누름이 이 키로 떨어지는 경우만 건다(`LandingOf`).
- **우선순위.** 옵션 켬(기본)이면 `false`, 끔이면 `true`. 리빌드, 박자, 돌려주기 복귀가 모두 같은 값 하나를 읽게 한다. 박자는
  따로 구운 `j.priority` 대신 `row.slot.priority ~= false`를 읽는다. 한 결정을 두 곳에서 셈하면 한쪽만 고치게 된다.
- `_chordCandidates`에는 만든 조합을 다 넣는다. 걸지 않은 조합도 다른 조합이 떨어지는 길에 있기 때문이다. 대가는 리빌드가
  한 번 더 도는 것뿐이다.
- 리빌드는 `CastKeysOn`과, 키마다 `bindings.checkSelfCast`·`bindings.checkFocusCast`를 굽는다. 이름은 블리자드 속성에서 따왔고
  뜻도 같다.

## 4. 누름마다 무엇이 나가나

설정: SELFCAST=CTRL, FOCUSCAST=ALT, 두 계정 칸 켬, 옵션 켬(기본). 키 X에 대상 없는 주문 `a` 하나.

### 4-1. 누를 때 시전 (기본)

| # | 쥔 것 | 키 | 나가는 것 | 지금과 다른가 |
|---|---|---|---|---|
| P1 | 없음 | | 원본 | 같음 |
| P2 | CTRL | S | self 쌍둥이 | 같음 |
| P3 | CTRL | S 아님 | 바깥 `CTRL-X`가 있으면 그것, 없으면 아무것도 | 결과 같음, `CTRL-X`를 안 건다 |
| P4 | ALT | F | focus 쌍둥이 | 같음 |
| P5 | ALT | F 아님 | P3과 같은 모양 | 결과 같음 |
| P6 | CTRL+ALT | S | self 쌍둥이 | 같음 |
| P7 | CTRL+ALT | S 아님, F | 바깥 `CTRL-X`가 있으면 그것, 없으면 **focus 쌍둥이** | **다름**: 지금은 아무것도 |
| P8 | CTRL+ALT | 둘 다 아님 | 바깥 `CTRL-X`나 `ALT-X`, 없으면 아무것도 | 결과 같음 |
| P9 | ALT (s=f=ALT) | S | self 쌍둥이 | 같음 |
| P10 | ALT (s=f=ALT) | S 아님, F | **focus 쌍둥이** | **다름**: 지금은 아무것도 |
| P11 | ALT (s=f=ALT) | 둘 다 아님 | 바깥 `ALT-X`, 없으면 아무것도 | 결과 같음 |
| P12 | ALT+SHIFT | F | `SHIFT-X`가 걸려 있으면 그것, 없으면 focus 쌍둥이 | 같음 |
| P13 | ALT, 키가 `ALT-X` | | 원본. 이름의 ALT는 가려진다 | 같음 |
| P14 | CTRL, 게임 SELFCAST가 NONE | | 원본 | 같음 |
| P15 | CTRL, 설정 탭 Self Cast Key 끔 | | 원본 | 같음 |
| P16 | CTRL, 개체창을 가리킴 | S 아님 | 아무것도 | 같음 |
| P17 | CTRL, 개체창을 가리킴 | S | self 쌍둥이 | 같음 |
| P18 | 개체창 클릭, 수식키 아무거나 | | 층 없음, 지금과 같은 길 | 같음 |
| P19 | CTRL | S, self 층에 맞는 것 없음 | 아무것도 | 같음 |
| P20 | CTRL | S, 판별 아이템이 X를 놓은 동안 | self 층이 맞으면 self 쌍둥이, 아니면 와우의 X | 같음 |
| P20a | CTRL | S, 바뀐 단축바·애완동물 대전·집 편집기로 X를 돌려준 동안 | 와우의 X. 조합 키도 같이 넘어간다 | 같음 |
| P21 | CTRL | S 아님, X가 놓인 동안 | 와우의 X | 같음 |
| P22 | CTRL | S, X가 `COMMAND` 꼬리 | self 층이 맞으면 self 쌍둥이, 아니면 명령 | 같음 |
| P23 | CTRL, 옵션 끔, 바깥 `CTRL-X` | S | self 쌍둥이(우선순위 `true`) | **다름**: 지금은 `false` |
| P24 | CTRL, 옵션 끔, 바깥 `CTRL-X` | S 아님 | **바깥 `CTRL-X`** | **다름**: 지금은 우리가 쥐고 아무것도 |
| P25 | CTRL, 옵션 켬, 바깥 `CTRL-X` | S | 바깥 `CTRL-X` | 같음 |

블리자드 액션 버튼이었다면 P3, P5, P8, P11, P16은 평소 대상에게 나간다. 우리가 아무것도 안 하는 것은 결정 3 때문이다.

누를 때 시전에서는 누르는 순간 쥔 키만 결과를 정한다. 주문이 그 순간 나가므로, 그 뒤에 쥐거나 놓은 키가 바꿀 것이 없다.

### 4-2. 뗄 때 시전

떼는 엣지는 누를 때 간 바인딩으로 온다. 그때 보이는 수식키는 "누를 때 쥔 것 + 뗄 때 쥔 것"에서 바인딩 이름에 든 것을 뺀
것이다(측정). ↓는 누름, ↑는 뗌.

"블리자드" 칸은 와우 액션 버튼이 실제로 시전한 대상이다(F14). 그 버튼은 자기 자신 시전과 주시 대상 시전을 둘 다 켜 둔 버튼이라,
S이고 F인 키와 견준다.

| # | 순서 | 키 | 나가는 것 | 블리자드(측정) | 지금 |
|---|---|---|---|---|---|
| R1 | X↓ CTRL↓ X↑ | S | **self 쌍둥이** | 자기 자신 | 원본 |
| R2 | X↓ ALT↓ X↑ | F | **focus 쌍둥이** | 주시 대상 | 원본 |
| R3 | X↓ CTRL↓ X↑ | S 아님 | **아무것도** | (그런 버튼은 재지 않았다) | 원본 |
| R4 | CTRL↓ X↓ CTRL↑ X↑ | S | self 쌍둥이 | (재지 않았다) | 같음 |
| R5 | ALT↓ X↓ CTRL↓ X↑ | S, F | **self 쌍둥이** | 자기 자신 | focus |
| R6 | CTRL↓ ALT↓ X↓ CTRL↑ X↑ | S, F | self 쌍둥이. `CTRL-ALT-X`로 들어온다 | 자기 자신 | 같음 |
| R6a | 같음 | S 아님, F | **focus 쌍둥이**. `ALT-X`로 떨어진다 | (S인 버튼에서는 자기 자신) | 아무것도 |
| R8 | CTRL↓ X↓ ALT↓ X↑ | S, F | self 쌍둥이. `CTRL-X`로 들어온다 | 자기 자신 | 같음 |
| R9 | CTRL↓ ALT↓ X↓ X↑ | S, F | self 쌍둥이 | 자기 자신 | 같음 |
| R7 | X↓ CTRL↓ X↑, 누를 때 이긴 것이 유지·시전 주문 | | 누를 때 시작한 주문을 놓는다 | 같음 | 같음 |

`debind-99`의 코드는 R1, R2에서도 아무것도 안 낸다. 가드가 막기 때문이다. R6a는 블리자드와 다르다. 자기 자신 시전을 안 쓰는 키는
주시 대상 시전 키만 본다고 정했기 때문이다(결정 4).

**누를 때 시전에서 떼는 엣지.** 래퍼는 떼는 엣지에서도 판정을 돌지만, 게이트가 실행하지 않는다(코드). 층이 바뀌어도 결과가 없다.

**R7을 거꾸로 하면.** 뗄 때 시전에서, 누를 때 이긴 것은 평범한 주문이고 뗄 때 이긴 것은 다른 액션의 유지·시전 주문인 경우다.
그 주문은 평범한 시전으로 나간다. `pressAndHoldAction`을 누를 때만 켜기 때문이다(코드). 블리자드는 한 슬롯이 한 주문이라 이런
일이 없다. 손대지 않는다.

**범위 밖, 본 것만.** 누를 때 시전에 `ActionButtonUseKeyHeldSpell` CVar가 켜져 있으면, 떼는 엣지가 놓기 갈래로 들어가 앞 누름이
남긴 `*typerelease-`를 읽을 수 있다(코드, `SecureTemplates.lua` 815). 이 변경 전에도 있던 길이고 층과는 상관없다.

### 4-3. 사용자에게 달라지는 것

- **P10은 게임의 기본 설정에서 일어난다.** SELFCAST와 FOCUSCAST는 기본값이 둘 다 ALT다(측정). 설정을 안 바꾼 사용자가 액션
  하나에서 Self Cast Key를 건너뛰면, 그 키의 ALT 누름이 주시 대상에게 나가기 시작한다. 결정 4가 정한 그대로다.
- **P7, R6a**: self를 건너뛴 키에서 두 Cast Key를 다 쥐면 focus 쌍둥이가 나간다.
- **R5**: 뗄 때 시전에서 ALT를 쥐고 누른 뒤 CTRL을 더 쥐고 떼면 self 쌍둥이가 나간다. 지금은 focus 쌍둥이다.
- **P23, P24**: 옵션을 끈 사용자. 쌍둥이 있는 조합은 `true`로 쥐고, 쌍둥이 없는 조합은 바깥에 준다.
- **R1, R2**: 뗄 때 시전에서 누른 뒤 Cast Key를 쥐면 그 쌍둥이가 나간다.
- **R3**: 같은 순서인데 그 층에 쌍둥이가 없으면 아무것도 안 한다. 지금은 원본이 나간다.
- **P3, P5, P8, P11**: 결과는 같다. 게임의 바인딩 표에서 조합 키가 사라질 뿐이다.

## 5. 구현 순서

1. 헤드리스 셈을 클라이언트처럼 고친다(7-1). 새 시험이 지금 코드에서 빨간 것을 본다.
2. `UpdateBindings.lua`
   - `CastModifier` 계산을 키 루프 앞으로 옮긴다. 키 루프가 그 답을 써야 한다.
   - 키마다 `checkSelfCast`, `checkFocusCast`를 굽고, `CastKeysOn`을 굽는다.
   - `CastChordsOf`를 3절의 표대로 다시 쓴다. `_twinless`와 두 번째 패스는 걷는다.
   - 우선순위를 값 하나에서 쓴다.
3. `SecureBindings.lua`: `EVAL_SNIPPET`의 층 고르기를 2-1로, `JUDGE_BUNDLES_SNIPPET`은 `row.slot.priority ~= false`로.
4. `Snippets.lua`에 `IsModifiedClick` 프로브, `DebindTest.lua`의 `PROBE_DEV`에 그 짝.
5. golden 셋을 갱신하고 diff를 읽는다.
6. 문서(8절). `npm run check`.

## 6. 앞 세션의 계획과 코드에서

| 무엇 | 어떻게 | 까닭 |
|---|---|---|
| 쌍둥이 있는 층에만 조합 키 | 다시 짠다. 뜻은 같다 | 결정 1. `#tiers[tier] > 1`로 읽는 것은 코드로 맞다 |
| 두 번째 패스(`_twinless`) | 버린다 | 쌍둥이 없는 `ALT-CTRL-X`를 self BLOCK에 걸었다. 결정 4가 focus로 보내라고 한 바로 그 누름이다 |
| 3층 가드(`CastKeys`, `Is…KeyDown`) | 2절로 바꾼다 | 어느 층의 키인지 몰라 결정 4의 순서를 못 쓴다. R1, R2를 막는다 |
| 옵션 끔이면 `true` | 남기고 한 곳에서 읽게 한다 | 결정 2 |
| "도착한 층 + 보이는 Cast Key, self 먼저" 규칙 | 버린다 | S인지 안 봐서 P7, R6을 self BLOCK으로 보낸다 |
| 정답표 N21, N22 | 뒤집는다 | P7, P10 |
| N18, N19, N20, N23, N24 | 결과는 남는다 | P8, P16, P24, P15, P13 |
| `withHeldModifiers` | 다시 짠다 | `IsModifiedClick` 흉내가 이름의 수식키를 안 가리고, 엣지가 하나뿐이다 |
| 킷 "a tier with no twin…" | 걷었다. 7-3대로 새로 쓴다 | `applies`가 계정 칸을 안 봤다 |
| `Probe_ReleaseEdge.lua`, `Probe_CastKeyEdges.lua`(이 세션)와 TOC 줄 | 걷었다 | 답이 나왔다. 값은 9절과 SavedVariables에 있다 |

`debind-99`는 검토에서 "이 설계가 깨는 경우를 자기 코드가 막고 있던 것은 없다"고 답했다.

## 7. 시험

### 7-1. 헤드리스 셈을 클라이언트처럼

`tests/restricted.lua`에 엣지 둘을 가진 누름을 넣는다.

- 입력: 키, 누를 때 쥔 수식키, 뗄 때 쥔 수식키, `ActionButtonUseKeyDown`.
- 어느 바인딩으로 가나: 누를 때 쥔 것으로 정한다. 떼는 엣지도 같은 바인딩이다.
- 무엇이 보이나: 누를 때는 쥔 것, 뗄 때는 둘의 합. 둘 다 바인딩 이름의 수식키를 뺀다. `Is…KeyDown`과 `IsModifiedClick`이 같은
  표에서 답한다. 지금 shim은 `IsModifiedClick`이 이름의 수식키를 안 가려서, 조합 키로 온 누름에서도 참이다. 클라이언트와 다르다.
- 진짜 래퍼를 엣지마다 돌리고, 게이트를 블리자드의 식으로 흉내 낸다. 게이트는 래퍼의 post 본문보다 먼저 읽어야 하므로,
  `runWrapped`의 사슬 끝에 그 자리를 둔다.

### 7-2. 헤드리스 시험

새 시험은 넣기 전에 빨간 것을 본다. 지금 코드(HEAD)에서 빨갛지 않은 것은, 그 줄만 일부러 틀리게 만든 코드에서 본다.
`debind-99`의 코드는 걷었으므로, 아래 표의 그 칸은 그 코드가 어떻게 답했는지의 기록이다.

| 시험 | 줄 | 빨간 것을 볼 코드 |
|---|---|---|
| self 건너뜀, CTRL+ALT → focus 쌍둥이, `ALT-CTRL-X`는 우리 것 아님 | P7 | HEAD, `debind-99` |
| 위에서 와우에 `CTRL-X` → 와우의 것 | P7 | `ALT-CTRL-X`를 focus로 거는 코드 |
| s=f=ALT, self 건너뜀, ALT → focus 쌍둥이 | P10 | HEAD, `debind-99` |
| s=f=ALT, 둘 다 건너뜀 → `ALT-X` 안 걸림, 아무것도 | P11 | HEAD |
| 쌍둥이 없는 층의 조합 안 걸림, 쥔 누름 아무것도 | P3, P5, P8 | HEAD. 결과는 2절 3번을 걷은 코드에서 |
| 개체창을 가리킨 채 쌍둥이 없는 층 → 아무것도 | P16 | 2절 3번을 걷은 코드 |
| 옵션 끔, 쌍둥이 없는 층의 와우 조합 → 와우 | P24 | HEAD |
| 우선순위가 리빌드·박자·돌려주기 복귀에서 모두 같다(옵션 끔 `true`, 켬 `false`) | P23, P25 | HEAD, 박자만 따로 셈하는 코드 |
| 뗄 때 시전 R1 → self 쌍둥이, 대상 `player` | R1 | HEAD, `debind-99` |
| R2 → focus 쌍둥이 | R2 | HEAD, `debind-99` |
| R3 → 아무것도 | R3 | HEAD |
| 누를 때 시전, X↓ CTRL↓ X↑ → 누를 때의 원본, 떼는 엣지는 실행 안 함 | P1 | 떼는 엣지를 실행하는 게이트 흉내 |
| R6a → focus 쌍둥이 | R6a | HEAD, `debind-99` |
| R6 → self 쌍둥이, `CTRL-ALT-X`로 들어온다 | R6 | 두 Cast Key를 쥔 조합을 안 거는 코드(HEAD는 통과한다) |
| R7 → 누른 주문을 놓음 | R7 | `HeldButtons`를 안 읽는 코드 |
| 계정에서 끈 Cast Key, 게임 설정 NONE → 원본 | P15, P14 | 계정 칸을 안 보는 코드, NONE을 묻는 코드 |
| 키 이름의 수식키는 가려짐 | P13 | 이름의 수식키를 안 가리는 셈 |
| 개체창 클릭에 수식키 → 층 없음 | P18 | 개체창 클릭에도 2절을 돌리는 코드 |
| 뗄 때 시전, ALT↓ X↓ CTRL↓ X↑ → self 쌍둥이 | R5 | HEAD, `debind-99` |

s=f 시험은 shim의 Cast Key 설정을 바꾸므로 실패해도 되돌린다. `debind-99`의 N22는 통과할 때만 되돌렸다.

### 7-3. 킷

- **"a tier with no twin leaves its chord to fall onto the key"를 고친다.** 묻는 것은 그대로다. 쌍둥이 없는 층의 조합이 게임의
  바인딩 표에 없는지, 맨 키 누름이 원본을 내는지(본문이 실제로 컴파일되는지). **`applies`는 계정 칸도 본다.** 지금은 게임
  설정만 봐서, 계정에서 둘 다 끄면 아무것도 안 묻고 통과한다.
- **새로: 맨 키로 온 누름에서 Cast Key가 보이면 쌍둥이 층을 고르는지.** `IsModifiedClick` 프로브로 SELFCAST가 보이게 하고 맨 키
  버튼을 판정한다. S인 키는 self 쌍둥이, 아닌 키는 아무것도.
- s=f는 킷에서 안 다룬다. 게임 설정은 시험이 쓸 수 없다.

### 7-4. 시험이 닿지 않는 것

- **실제 손 누름.** 킷은 키를 누를 수도 수식키를 쥘 수도 없다. 클라이언트가 어디로 보내고 무엇을 보여 주는지는 측정(9절)이 들고,
  헤드리스 셈이 그대로 흉내 낸다.
- **우선순위.** 게임이 읽어 줄 API가 없어 헤드리스만 본다.
- **개체창 밖 마우스 버튼 키**(`BUTTON4` 등)의 떼는 엣지. 재지 않았다. 게이트는 키보드와 같다(코드). 나머지는 키보드와 같다고
  보고 짠다.

## 8. 고칠 문서

- `which-action-a-key-runs.md`: S1의 "둘 다 쥐면 Self Cast Key 누름이다"에 결정 4의 예외. §S4와 §3의 2026-10-07 문단을 2절로.
  §S5에 4절의 새 줄. 뗄 때 시전도 같은 답을 낸다는 문장.
- `handing-the-rest-of-a-key-to-the-game.md`: 2-3을 3절의 표로. 8-1에 R1-R3, R5, R6, R6a를 줄로. 결정 1, 2와 N21, N22를 뒤집은
  것은 2026-10-07에 들어갔다.
- 인게임 도움말은 이 세션의 일이 아니다. 다른 세션의 수정이 그 파일들에 걸려 있다. 바뀌는 결과는 4-3이다.

## 9. 사실과 출처

| | 내용 | 출처 |
|---|---|---|
| F1 | 블리자드 버튼은 두 엣지를 다 받고, `useOnKeyDown`에 따라 한쪽에서만 실행한다. `pressAndHoldAction`이 켜져 있으면 누를 때다 | (코드) `SecureTemplates.lua` 805-829 |
| F2 | 시전 대상은 `unit` 속성, 마우스오버 시전, SELFCAST(`checkselfcast`일 때), FOCUSCAST(`checkfocuscast`일 때) 순으로 정한다. 실행하는 엣지에서 읽는다 | (코드) 같은 파일 143-200, 694-731 |
| F3 | 블리자드 액션 버튼은 `checkselfcast`·`checkfocuscast`를 켜 둔다. `ACTIONBUTTONn`은 두 엣지를 다 받아 같은 게이트로 간다 | (코드) `ActionButton.lua` 112, 452-453, `Bindings_Standard.xml` 152 |
| F4 | 제한 환경은 `Is…KeyDown`과 `IsModifiedClick`을 그대로 쓴다 | (코드) `RestrictedEnvironment.lua` 86-89 |
| F5 | 바인딩 이름의 수식키는 가려지고, 더 쥔 것은 보인다. `IsModifiedClick`도 같다 | (측정) `implementing-focus-and-self-cast.md` 2-1 |
| F6 | 걸리지 않은 조합은 ALT, CTRL, SHIFT 순으로 하나씩 떼어 처음 걸린 곳으로 간다 | (측정) `handing-the-rest-of-a-key-to-the-game.md` 6절의 2 |
| F7 | 떼는 엣지는 누를 때 간 바인딩으로 온다. 맨 키에서 이름에 없는 수식키는 누를 때나 뗄 때 쥐었으면 보인다. 조합 키에서 이름의 수식키는 두 엣지 다 가려진다. `ActionButtonUseKeyDown` 0과 1이 같다. `IsModifiedClick`도 같이 적었고 수식키와 늘 같았다 | (측정) `Probe_ReleaseEdge.lua` 첫 판. `_xptr_` 계정 `10179303#4`의 `DebindDev.lua`, `releaseEdge`. 2026-10-07 19:18, build 120105, 24회. 이 세션이 직접 읽었다 |
| F8 | 조합 키로 온 누름도 F7과 같다. CTRL을 먼저 놓아도, 누른 뒤 CTRL을 쥐어도 떼는 엣지에서 CTRL이 보인다 | (측정) 같은 파일 `releaseEdgeTwo`. 19:43, 9회. 이 판은 `Is…KeyDown`만 적었다. `IsModifiedClick`도 같다는 것은 (추론)이고, 근거는 F7에서 둘이 늘 같았다는 것이다 |
| F9 | `ActionButtonUseKeyDown`의 기본값은 1(누를 때 시전)이다 | (측정) F7의 `cvarDefault` |
| F10 | 우리 키 래퍼는 두 엣지 다 판정을 돈다. 누를 때 이긴 것이 유지·시전 주문이면 누를 때 실행하고, 떼는 엣지는 다시 고르지 않고 그것을 놓는다 | (코드) `SecureBindings.lua` 1686-1709, 1761-1820 |
| F11 | 쌍둥이는 원본과 같은 버튼을 누른다. 층마다 BLOCK이 닫는다. 계정에서 끈 층은 BLOCK도 쌍둥이도 없다 | (코드) `UpdateBindings.lua` `WithBlocks`, 4647-4653 |
| F12 | 개체창 클릭은 정확한 수식키 조합으로만 오고 층이 없다 | (코드) `SecureBindings.lua` 1532-1558 |
| F13 | SELFCAST와 FOCUSCAST의 기본값은 둘 다 ALT다 | (측정) `handing-the-rest-of-a-key-to-the-game.md` 6절의 1 |
| F14 | 맨 키를 와우의 `ACTIONBUTTON1`에 덮어쓰기로 걸고 SELFCAST=CTRL, FOCUSCAST=ALT로 잰 것. **뗄 때 시전:** X↓ CTRL↓ X↑ → 자기 자신, X↓ ALT↓ X↑ → 주시 대상, ALT↓ X↓ CTRL↓ X↑ → 자기 자신, CTRL↓ X↓ ALT↓ X↑ → 자기 자신, CTRL↓ ALT↓ X↓ CTRL↑ X↑ → 자기 자신(놓은 CTRL이 떼는 엣지에서 보였다), CTRL↓ ALT↓ X↓ X↑ → 자기 자신. 실행한 엣지는 늘 떼는 엣지였다. **누를 때 시전:** 늘 누르는 엣지에서 실행했고 누를 때 쥔 키만 따랐다. ALT만 쥔 세 번은 주시 대상을 골랐지만 시전이 없었다(주시 대상이 없었던 것으로 보인다) | (측정) `Probe_CastKeyEdges.lua`. `_xptr_` 계정 `10179303#4`의 `DebindDev.lua`, `castKeyEdges`(2026-10-07 20:56, 뗄 때 시전 18회)와 `castKeyEdgesLog`(21:04, 누를 때 시전 18회), build 120105, 순서마다 3회 모두 같음. 블리자드가 `SecureButton_GetModifiedUnit`을 부른 엣지와 `UseAction`에 넘긴 유닛을 훅으로 받았다. 이 세션이 직접 읽었다 |

**아직 재지 않은 것 하나.** focus 조합(`ALT-X`)으로 들어온 누름의 떼는 엣지에서 `IsModifiedClick("SELFCAST")`가 참인지는 재지 않았다.
`IsControlKeyDown`은 참이었다(F8). 맨 키로 들어온 누름에서는 두 값이 늘 같았다(F7, F14). 그래서 같다고 본다(추론).

## 10. 닫은 질문

**focus 조합으로 왔는데 자기 자신 시전 키가 보이면.** R5다. 뗄 때 시전에서 ALT를 쥐고 X를 누르고, CTRL을 더 쥔 뒤 X를 뗀다. 누름은
`ALT-X`로 오고 떼는 엣지에서 CTRL이 보인다.

- 결정 4의 마지막 문장("조합 키로 온 누름은 그 조합의 층")만 따르면 focus 쌍둥이다.
- 결정 4의 머리("블리자드에 맞춘다")와 결정 5를 따르면 블리자드가 하는 대로다.

**블리자드는 자기 자신에게 시전했다**(F14, 2026-10-07). 그래서 self 쌍둥이를 낸다. 2절의 규칙과 2-1의 본문이 이렇게 되어 있다.
처음에는 블리자드 쪽을 재지 않고 추론으로 권했다가, 소유자가 재야 한다고 해서 쟀다.

## 11. 구현이 설계와 다르게 간 자리 (2026-10-07, `debind-d6`)

- **R6의 시험은 들어온 바인딩 이름도 본다.** `ALT-CTRL-X`를 안 걸어도 층은 같다. 클라이언트가 ALT를 먼저 떼어
  `CTRL-X`로 보내고, 그것도 self다. 그래서 층만 보는 시험은 "두 Cast Key를 쥔 조합을 안 거는 코드"에서 빨개지지 않았다.
  4-2의 R6 줄이 적은 "`CTRL-ALT-X`로 들어온다"를 그대로 묻는다. `restricted.lua`의 `press`가 그 이름을 돌려준다.
- **N21a(7-2의 "위에서 와우에 `CTRL-X`")는 옵션 두 값에서 돈다.** 옵션을 켜 두면 `ALT-CTRL-X`를 focus로 거는 코드도 그
  조합을 안 건다. 와우의 `CTRL-X`로 떨어지는 조합이라 `LandingOf`가 먼저 막는다. 옵션을 꺼야 빨개진다.
- **P14(NONE을 묻는 코드)는 shim이 막는다.** 누름이 ALT·CTRL·SHIFT가 아닌 Cast Key로 `IsModifiedClick`을 물으면
  `restricted.lua`가 오류를 낸다. 그때 클라이언트가 무엇을 답하는지는 재지 않았다. 그래서 본문이 그 답에 기대면 안 된다.
- **`_chordsYielded`는 걸 층이 있는 조합만 센다.** 쌍둥이 없는 조합을 남이 쥐었다 놓아도 우리가 걸 것이 없다.
  `_chordCandidates`에는 3절대로 다 넣는다.
- **2-1 본문의 마지막 갈래(`elseif (castTier) then`)는 뺐다.** 닿을 수 없다. 조합 키는 Cast Key가 하나라도 켜져 있을
  때만 걸고, 그때 리빌드가 `CastKeysOn`을 표로 쓴다. 그래서 `castTier`가 있으면 `CastKeysOn`도 있다. 클릭마다 도는
  본문이라 줄였다(코드 리뷰).
- **아무것도 안 하는 누름도 앞 누름이 쥔 주문을 잊는다**(코드 리뷰). 래퍼는 이길 것이 없으면 `HeldButtons`를 정리하는
  자리보다 먼저 끝났다. 그 전에는 BLOCK이 이긴 누름만 그랬는데, 2절 3번으로 Cast Key를 쥔 누름이 다 그 길로 간다. 앞
  누름의 떼는 엣지가 안 왔으면 이 누름의 떼는 엣지가 그 주문을 놓았다. 8-1의 R7a가 그 시험이다.
- **`checkSelfCast`·`checkFocusCast`는 키 이름에 그 수식키가 든 키에는 굽지 않는다**(코드 리뷰). 클라이언트가 그 키의
  누름마다 그 수식키를 가리므로 읽힐 일이 없다.
- **IsModifiedClick을 두 번 묻는 비용은 그대로 두었다.** 리뷰는 두 Cast Key가 같은 수식키일 때 한 번으로 줄이자고 했다.
  2절의 비용 문단이 받아들인 모양이고, 재지 않고 줄일 까닭이 없다.
- **`CastKeysOn`은 끈 상태를 `nil`이 아니라 `false`로 쓴다.** 제한 환경에서 안 쓴 전역은 shim이 오류로 다룬다. 드라이버의
  첫 본문도 `false`로 둔다.
- **우선순위 시험은 새로 만들지 않았다.** `judgmentloop_spec`의 기존 시험을 옵션 두 값으로 넓혔다. 리빌드, 박자, 돌려주기
  복귀를 이미 다 묻고 있었다.
- **표에 더한 줄.** `handing-the-rest-of-a-key-to-the-game.md` 8-1에 N21a, N22a, R0~R7. R0은 4-1의 P1(누를 때 시전의 떼는
  엣지)이고, R7은 4-2의 줄이다. 둘 다 시험이 있어서 줄을 냈다. `which-action-a-key-runs.md` §S5에 68~72.
- **킷의 두 시험은 새로 썼다.** "a tier with no twin…"은 트리에 없었다. 맨 키 시험은 `SetMockModifiedClick`으로 Self Cast
  Key를 세운다. 그 시험은 `LastWinner` 대신 보고 자체를 읽는다. `LastWinner`는 층을 닫는 BLOCK이 이겨도 nil이라, self
  층으로 잘못 간 누름과 아무것도 안 한 누름을 못 가른다.
