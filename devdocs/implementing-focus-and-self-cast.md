# 주시 대상 시전과 자기 자신 시전을 우리가 처리하기 (2026-09-13 시작)

> 상태: **§3이 들어갔다.** 쌍둥이, 조합키 칸, 누를 때 재기, 루프가 쌍둥이를 건너뛰기,
> 블리자드 쪽 판단 끄기, §3-6까지다. **§4(`@@`)는 아직이다.**
>
> **조합키 쌍둥이를 거르는 대상은 `none` 하나로 시작했다** (2026-09-13, 소유자). 써 보면서
> 맞춰 간다. `player`와 `focus`는 거르지 않는다(§3-4).

지금 두 조합키는 블리자드가 처리한다. 우리 클릭 프레임에 `checkselfcast`와 `checkfocuscast`를
켜 두고(`Debind.lua`), 액션에 대상이 없을 때 `unit`을 비워 `SecureButton_GetModifiedUnit`이
판단하게 둔다. 이 문서는 그 판단을 우리 쪽으로 가져오는 설계다.

`matching-the-clients-cast-targeting.md` §2-3의 "포커스 시전을 우리가 만들 것이 없다"는 이
문서로 뒤집혔다.

## 1. 왜 가져오나

**블리자드 순서는 가리킨 유닛이 조합키를 이긴다.** `SecureButton_GetModifiedUnit`은 버튼의 `unit`,
마우스오버 시전, 자기 자신 시전, 주시 대상 시전 순으로 본다(`SecureTemplates.lua:143-199`, 12.1.0).
딜러는 마우스를 적 선택에 쓰고 능력은 키보드로 쓰니 커서가 늘 3D 월드의 적 위에 있다. 그 상태에서
주시 대상에게 발차기를 하려고 `ALT-C`를 누르면 커서 아래 적에게 나간다. 조합키는 누르는 순간의
명시적인 의도이고, 커서 위치는 우연이다. 의도가 이겨야 한다 (2026-09-13, 소유자).

**우리 코드에도 같은 일이 있다.** hover 조건에서 따라 나온 대상, Hover Cast와 Mouseover Cast
쌍둥이는 스니펫이 `unit`을 채운다. `unit`이 있으면 블리자드 함수는 첫 줄에서 돌아가므로 조합키가
아예 닿지 않는다.

**Smart Cast가 판정한 유닛과 시전 유닛이 갈린다.** 대상이 없는 액션에서 Smart Cast는
`unit or "target"`을 보고 갈래를 고르는데(`SMART_CAST_SNIPPET`), 그 뒤 블리자드가 `focus`로
돌린다. 대상이 죽은 아군이고 주시 대상이 산 아군이면 주시 대상에게 부활이 나간다.

**마우스오버 시전은 이미 우리 것이다.** `checkmouseovercast`는 모든 경로에서 꺼져 있다. 순서를
블리자드에 맞출 이유가 없다.

## 2. 잰 것

### 2-1. 스니펫 안의 `IsModifiedClick` (2026-09-13, 소유자)

`IsModifiedClick`은 제한 환경 허용 목록에 있다(`RestrictedEnvironment.lua:89`). 클릭 래퍼에서 직접
읽어 `CallMethod`로 찍었다. 게임 설정은 `FOCUSCAST = ALT`, `SELFCAST = CTRL`.

| 도착한 버튼 | 누른 것 | alt | ctrl | FOCUSCAST | SELFCAST |
|---|---|---|---|---|---|
| `@ALT-1` | `ALT-1`, 정확히 걸린 키 | F | F | F | F |
| `@1` | `CTRL-1`, `1`로 떨어짐 | F | T | F | T |
| `@ALT-1` | `CTRL-ALT-1`, `ALT-1`로 떨어짐 | **F** | T | F | T |
| `@2` | `ALT-2`, `2`로 떨어짐 | T | F | T | F |

**클라이언트는 도착한 바인딩 이름에 든 조합키를 가리고, 그 위에 더 누른 것만 보여 준다.** 그래서
`ALT-C`로 건 키는 `IsModifiedClick("FOCUSCAST")`가 거짓이다. 키 이름의 조합키와 시전 의도를 우리가
가를 필요가 없고, `GetModifiedClick`을 넘겨받을 필요도 없다. 스니펫이 `IsModifiedClick`을 물으면
그 답이 곧 의도다.

### 2-2. 앞에 붙은 쉼표 (2026-09-13, 소유자)

`SecureCmdOptionParse("[,dead]dead[,nodead]nodead")`는 `nodead`, `SecureCmdOptionParse("[,dead]dead")`는
결과 없음. 쉼표로 시작하는 조건절도 조건을 그대로 읽는다. §4가 이것에 기댄다.

## 3. 결정

### 3-1. 모든 대상이 조합키를 따른다

대상이 없든, hover 조건에서 따라 나왔든, Hover Cast 쌍둥이든, 사용자가 `@tank`처럼 골랐든 조합키가
이긴다 (2026-09-13, 소유자). **누르는 순간의 조합키가 지금의 의도를 표현한다.** 저장된 대상은
설정할 때의 의도다.

**사용자가 고른 대상은 조합키를 무시하게 두는 안을 먼저 세웠다가 버렸다.** 근거는 "고른 대상도
명시적인 의도"와 "`[@mouseover]` 매크로는 주시 대상 조합키를 안 따른다"였다. 앞의 것은 조합키도
명시적이고 더 나중이라 이기지 못한다. 뒤의 것은 블리자드 동작인데, 그 순서가 틀렸다는 것이 이
문서의 출발이다. 실수로 발동할 걱정도 없다. 바인딩 이름에 든 조합키는 클라이언트가 가리므로(§2-1)
조합키가 참인 것은 일부러 더 누른 누름뿐이다.

### 3-2. 주시 대상으로 고정한다

`FOCUSCAST`를 누르면 주시 대상이 없거나 조건에 안 맞아도 원래 대상으로 돌아가지 않는다.
블리자드도 `IsModifiedClick("FOCUSCAST")`가 참이면 `"focus"`를 돌려주고 끝내며, 주시 대상이
없으면 `UnitExists` 가드에서 조용히 끝난다(2026-09-11에 `ALT-F9`로 잼). 돌아가는 길을 두면
조합키를 누른 사람의 의도가 그 자리에서 깨진다.

조건에 맞는 쌍둥이가 없으면 그 키는 그 누름에서 아무것도 안 한다. 액션 바가 원래 그렇게 동작한다.

### 3-3. 둘 다 눌렸으면 자기 자신

블리자드 순서다. `checkselfcast`를 먼저 보고 참이면 끝낸다(`SecureTemplates.lua:190-199`).

### 3-4. 솔버에는 쌍둥이로 넣는다

`GetBindingsForAction`이 hover 쌍둥이를 만드는 자리에서 쌍둥이를 둘 더 만든다. 한 액션이 최대 넷이 되고, 이 순서로 선다 (2026-09-13, 소유자).

| 순서 | 바인딩 | 조합키 칸 | `unit` |
|---|---|---|---|
| 1 | self 쌍둥이 | self | `player` |
| 2 | focus 쌍둥이 | focus | `focus` |
| 3 | Hover Cast, Mouseover Cast 쌍둥이 | 없음 | `hover` / `mouseover` |
| 4 | 원본 | 없음 | 원래 대상 |

**흑마 해제의 probe가 쌍둥이마다 붙어 한 액션이 여덟까지 된다** (`GetBindingsForAction`의 probe).
우리 코드가 그만큼은 견딘다고 보고, 솔버를 줄이는 것은 이번에 안 한다 (2026-09-13, 소유자).

**hover 쌍둥이는 조합키로 나뉘지 않는다.** 조합키를 누른 누름은 1, 2가 맡으므로 3이 설 자리가
[없음]뿐이다.

**대상이 이미 `player`나 `focus`여도 쌍둥이를 만든다** (2026-09-13, 소유자). 그 쌍둥이를 빼면 원본의
조합키 칸을 [없음, focus]처럼 넓혀야 조합키를 누른 누름을 받는다. 빼고 넓히는 분기 둘보다 레코드
하나가 싸다. 늘어난 쌍둥이는 원본과 조합키 칸이 겹치지 않아 솔버에서 첫 노드에 서로 걸러진다.
`hover`, `mouseover` 대상에 hover 쌍둥이가 안 생기는 것은 그대로다(`TwinUnitFor`). 넓힐 조합키 칸이
없어서다.

**클릭할 때 `unit`만 바꿔 끼우는 방법은 안 된다.** 솔버가 조합키를 모르면 조합키 없는 상태에서만
덮임을 판단해, 조합키를 눌렀을 때만 살아나는 바인딩을 지운다.

- A(우선): 대상 없음, `@.help`
- B(다음): `units.target.help`

조합키가 없으면 둘 다 [대상이 우호]라 솔버가 B를 지운다. `ALT`를 누르면 A는 [주시 대상이 우호]가
되고, [대상은 우호, 주시 대상은 적대]인 누름에서는 B가 이겨야 하는데 B는 이미 없다. 조합키를
따르는 바인딩을 솔버가 덮는 쪽으로 못 쓰게 막으면 지우는 힘을 통째로 잃는다.

`@`를 칸 하나로 따로 두는 방법도 안 된다. 레코드마다 `@`가 가리키는 유닛이 달라서, 대상 없는 액션의
`@.help`와 `@tank`의 `@.help`가 같은 칸에 놓이면 솔버가 서로 덮는다고 본다. "칸 하나는 축 하나"를
어긴다.

쌍둥이로 가면 스니펫이 할 일도 가장 적다. 이긴 레코드의 `unit`으로 쏘기만 하면 되고, 조합키는
상태 칸 하나를 더 재는 것으로 끝난다.

### 3-5. 조합키는 세 값을 가진 칸 하나다

없음, self, focus는 서로 겹치지 않으므로 반응 조건처럼 마스크 칸 하나로 둔다. 불리언 둘로 두면
"둘 다 참"이라는 없는 조합이 생긴다. 스니펫은 클릭마다 `IsModifiedClick("SELFCAST")`를 먼저,
아니면 `IsModifiedClick("FOCUSCAST")`를 물어 값 하나를 정한다.

**hover 쌍둥이와 원본에 [없음]이 붙어야 한다.** 안 붙이면 focus 쌍둥이가 조건에서 떨어진 누름에서
그 둘이 가리킨 유닛이나 대상으로 나가 §3-2가 깨진다.

**레코드에 "조합키를 따르나" 플래그가 없다.** 모든 대상이 따르므로(§3-1) 가를 것이 없고, 사용자가
고른 hover와 따라 나온 hover를 가르던 필요도 같이 사라졌다.

### 3-6. `@`는 대상과 따로 고른다

지금은 액션에 대상이 있을 때만 `units["@"]`가 뜻이 있고, UI도 그렇게만 넣을 수 있다. 바꾼 뒤에는
대상을 고르는 것과 별개로 `@` 조건을 고를 수 있다. 그래야 대상이 없는 액션도 "이 누름이 겨누는
유닛"에 조건을 걸 수 있고, 그 조건이 쌍둥이마다 `player`나 `focus` 칸으로 간다.

**구울 때 `@`를 그 바인딩의 `unit` 칸에 접는 것은 그대로 둔다**(`UpdateBindings.lua`,
`k = binding.unit`). 쌍둥이마다 `unit`이 정해져 있으니 접어도 뜻이 안 바뀐다.

**`@`가 지워지는 대상은 `none` 하나다** (2026-09-13, 소유자). 그 시전은 대상을 입력받으므로 누름이
정하는 유닛도 쌍둥이도 없다. `player`는 `player` 칸에 산다.

**대상 없는 원본의 `@`는 판정할 때만 `target`에 검사한다** (2026-09-13, 소유자). 원본은 조건을
지우지 않고, 시전은 그대로 둔다. `unit`은 비운 채라 `SELFCAST_OFF_SNIPPET`을 안 거치고, 게임이 대상과
Auto Self Cast로 정한다. 가리킨 유닛을 안 쓰겠다고 끈 `""`도 같다.

**`@`가 얹히는 칸은 그 원본이 누를 때 겨누는 곳이다**(`Misc.lua`의 `ResolvedUnitOf`). `binding.unit`이
있으면 그 칸이고, hover 조건에서 채워진 `"hover"`도 여기 든다. nil이거나 `""`이면 `target`이다. 유닛
상태, 구운 레코드, 이슈 검사, 매크로 변환이 이 하나를 같이 쓴다. 대상을 받지 않는 타입과 `none`은
지운다.

**`unit = "target"`을 실제로 쓰지 않는 이유.** 그러면 `@`를 건 순간 Auto Self Cast가 꺼져 Target에서
`target`을 고른 것과 같아진다.

**갈리는 경우 하나는 받아들인다.** 반응 조건 없이 생사나 소속만 건 우호 주문을 적대 대상에게 쓰면,
판정은 대상에게 했는데 게임은 자기에게 돌린다. `@.harm`은 해로운 주문에 Auto Self Cast가 없으니 판정과
시전이 같고, `@.help`는 대상이 우호일 때만 맞으니 역시 같다.

`target`이 못 쓸 대상이면 `player`로 넘기는 흉내는 버렸다. 주문이 이로운지를 알아야 하는데, 그 성향은
아무 데서도 안 읽기로 했다(`legacy/adding-hover-and-mouseover-cast.md` §0).

**메뉴는 `Target` 아래에서 `Units` 아래로 옮겼다.** `Units` 맨 위의 `Resolved Target` 줄이고, 대상을 받는
타입에만 그린다. 잠그는 것은 대상 `none`뿐이다. 이름을 따로 둔 것은 같은 메뉴에 사용자가 고르는
`Target`이 있어서다. 이 줄은 그 선택이 누를 때 무엇으로 정해지는지를 가리킨다.

### 3-7. 블리자드 쪽 판단은 끈다

클릭마다 `not clickCast`로 다시 쓰던 두 줄(`SecureBindings.lua`)은 지웠다. `DefaultClickFrame`을 만들 때
켜던 두 줄(`Debind.lua`)은 **`false`로 박았다.** 안 써도 꺼진 채지만, `checkmouseovercast`만 `false`로
서 있으면 둘이 빠진 것으로 읽혀 다음 사람이 도로 켠다. 판단하는 곳을 한 곳으로 둔다.

### 3-8. 설정에서 조합키를 `NONE`으로 두면

`IsModifiedClick`이 거짓을 낸다고 보고 따로 처리하지 않는다. 잰 것이 아니라 블리자드 코드에서 읽은
것이다. 액션 바는 `checkfocuscast`를 켜고 `IsModifiedClick("FOCUSCAST")`만 묻는데, `NONE`이 참을
낸다면 설정을 끈 사람의 액션 바가 전부 주시 대상으로 시전된다. 마우스오버 시전은 `NONE`을
"항상"으로 쓰려고 `GetModifiedClick(...) == "NONE"`을 따로 묻는다(`SecureTemplates.lua:177`).

### 3-9. 상태 루프는 조합키 쌍둥이를 안 본다

루프가 정하는 것은 키 `X`를 잡느냐 놓느냐뿐이고, 무엇이 나갈지는 클릭할 때 정한다. 그러니 키를
잡을지 판단할 때 self와 focus 쌍둥이는 세지 않는다 (2026-09-13, 소유자). 조합키 칸이 [없음]인
레코드, 즉 원본과 hover 쌍둥이만 센다.

**`holdsKey`와는 다른 이야기다.** `holdsKey`는 "이 레코드가 키 누름 경로에 쓰인다"는 뜻이고, 쌍둥이도
참이다. 거짓이면 클릭 래퍼가 키 누름에서 쌍둥이를 아예 평가하지 않아 조합키를 눌러도 쌍둥이가 이길 수
없다. 루프가 쌍둥이를 거르는 것은 `holdsKey`가 아니라 `castModifier`로 한다(`SecureBindings.lua`의
상태 루프, 그리고 루프를 깨우는 축을 모으는 `CollectRecordAxes`).

**솔버는 원본과 파생을 따로 지운다.** 원본은 덮여 지워지고 쌍둥이만 살아남을 수 있다. 살아남은
바인딩은 원본이든 파생이든 `PrepareKeyBindings`에서 각자 `holdsKey`를 받는다. 원본이 지워진 키에서
살아남은 self와 focus 쌍둥이는, 같은 키의 다른 [없음] 레코드가 루프에서 키를 잡고 있는 동안에만 나간다.

**우리는 조합키 조합을 잡지 않는다.** `ALT-X`는 게임이 `X`로 떨어뜨려 줄 때만 우리에게
온다(`matching-the-clients-cast-targeting.md` §2-3). 블리자드 단축키나 다른 애드온이 `ALT-X`를
잡았으면 그쪽이 이긴다. [없음] 레코드가 하나도 안 맞아 `X`를 놓았을 때 `ALT-X`가 게임으로 가는 것도
같은 방침이다.

**쌍둥이를 세면 키가 먹힌다.** `player`에게 묻는 `@.help`는 거의 늘 참이라 대상이 적인 동안에도
루프가 `X`를 잡고, 조합키 없이 누르면 승자가 없어 아무것도 안 나간다. 원래는 게임으로 갔을 누름이다.

### 3-10. 개체창 클릭에는 조합키 칸이 늘 [없음]이다

**개체창 클릭은 조합키 시전이 원래 안 된다** (2026-09-13, 소유자). 수식 키를 쥔 클릭은 정확히
그 조합으로 건 바인딩이 있을 때만 오고(`ClickCastKeys[n][mod]`), 떨어져 들어오는 누름이 없다.
쥔 `ALT`는 사람이 고른 `ALT-BUTTON1`의 일부다. 블리자드 개체창도 같다
(`matching-the-clients-cast-targeting.md` §2-1, §5-3).

`IsModifiedClick`에 맡기면 안 된다. 클릭에는 가려 줄 바인딩 이름이 없어서 쥔 키가 그대로 참으로
읽힌다. 클릭캐스팅 갈래는 묻지 않고 [없음]을 넣는다. §3-7이 지우는 줄들이 하던 일을 이 자리가
넘겨받는다.

### 3-11. Smart Cast

focus와 self 쌍둥이는 `unit`을 들고 이기므로 `SMART_CAST_SNIPPET`의 `unit or "target"`이 실제 시전
유닛과 같아진다. §1의 어긋남은 따로 손대지 않아도 사라진다.

## 4. 커스텀 매크로의 `@@`

`/cast [@@] Regrowth`의 `@@`를 이 누름이 겨누는 유닛으로 바꿔 넣는다. 조합키를 누르면 `player`나
`focus`, 아니면 원래 겨누는 유닛이다.

- **이미 있는 장치에 올라간다.** `ParseMacroText`가 `@hover` 같은 유닛을 인자 칸으로 떼어 두고, 클릭한
  순간 이긴 레코드의 본문만 조립한다(`DeferredMacroTexts`, `COMPOSE_MACROTEXT_SNIPPET`). `@@`는 인자
  종류를 하나 더 두는 것이다. 지금 파서는 `[a-zA-Z0-9_]+`만 떼므로 갈래가 하나 필요하다.
- **겨누는 유닛이 없으면 `@@`를 지운다.** `[@@]`는 `[]`, `[@@,help]`는 `[,help]`가 되고 둘 다 맨
  `/cast`처럼 읽힌다(§2-2). `@target`을 넣으면 대상이 없을 때 자동 자기 자신 시전 대신 조용히 안
  나가서 맨 `/cast`와 달라진다. 그래서 `@@`는 `@`까지 통째로 인자 칸에 든다.
- **조립은 유닛이 정해진 뒤다.** 지금 `BAKE_WINNER_MACROTEXT_SNIPPET`은 `RESOLVE_UNIT_SNIPPET`보다
  앞에 붙어 있다. 순서를 바꾼다.
- **클릭 없이 조립하는 본문에는 못 쓴다.** `MacroTextsMap`으로 도는 본문(전환기 식)에는 누름이
  없어 넣을 값이 없다. 거기서는 `@@`를 거부한다.

`@@`로 쓴 매크로는 시전 대상을 우리가 넣으므로, 매크로가 대상을 몸통 안에 숨겨서 빠졌던 Hover
Cast와 Smart Cast에 들어갈 수 있다.

## 5. 뒤집힌 결정

**대상 없는 원본의 `@`를 어느 칸에 얹나**는 열린 물음이었고, 같은 날 두 번 정해졌다.

**처음 정한 것: 검사하지 않는다** (2026-09-13, 소유자). 조합키도 가리킨 유닛도 없으면 게임이 대상과
Auto Self Cast로 정하므로 미리 검사할 유닛이 없다고 봤다. `target` 칸에 얹으면 `@.help`가 적대
대상에서 거짓이 되어, 맨 주문이면 Auto Self Cast로 자기에게 나갔을 누름이 아무것도 안 한다는 것이
근거였다.

**뒤집은 이유** (2026-09-13, 소유자).

- **원본이 조건을 지우면 조건 없는 액션이 된다.** `@`만 건 대상 없는 액션이 행에 조건 없음으로
  그려지고, 발동 순서의 조건부 단계(`IsConditionalBinding`)에서 무조건 쪽에 선다. 먼저 놓인 조건 없는
  액션의 self 쌍둥이가 제 self 쌍둥이를 덮어, 조합키를 눌러도 차례가 안 온다.
- **`@.harm`은 대상에 검사하면 정확하다.** 해로운 주문에는 Auto Self Cast가 없다. 검사하지 않으면
  `@.harm` 공격 뒤에 `@.help` 치유를 둔 키에서 우호 대상을 잡고 누를 때, 공격이 조건 없이 이겨 헛나가고
  치유는 차례가 안 온다.
- **`@.help`도 판정과 시전이 같다.** 대상이 우호일 때만 맞고, 그때 게임도 대상에 쏜다.

**쌍둥이의 조건까지 세어 조건부를 정하는 안은 안 했다.** hover 쌍둥이는 늘 [유닛 있음]을 들고 있어
Hover Cast가 닿는 모든 액션이 조건부가 되고, 기존 사용자의 키 순서가 조용히 바뀐다. 원본이 조건을 지키면
따로 고칠 것이 없다.

## 6. 테스트가 닿는 곳

**헤드리스가 덮는 것.** 쌍둥이의 모양(`normalize_spec`: 겨누는 유닛, 조합키 칸, `@`가 옮겨 가는 칸,
`none`과 대상 없는 타입에서 안 생기는 것)과, 누름과 루프가 고르는 것(`eval_spec`: self가 `player`에게,
focus가 원래 대상으로 안 돌아가는 것, 둘 다 눌렸을 때 self, 개체창 클릭이 조합키를 무시하는 것, 루프가
쌍둥이로 키를 안 잡는 것, 블리자드의 세 속성이 꺼져 있는 것). `IsModifiedClick`은 인터프리터가 이름마다
답을 넣는다. `@`가 대상 `player`와 쌍둥이의 칸에 서고, 대상 없는 원본과 `""`에서 `target` 칸에,
hover로 채워진 원본에서 `hover` 칸에 서고, `none`에서 지워지는 것도 `normalize_spec`이 본다. 그 원본이
조건부로 서서 조건 없는 액션보다 앞인 것은 `keymap_spec`이, 판정은 대상에 하고 누름은 유닛 없이
나가는 것은 `eval_spec`이, 툴팁이 그 조건을 `Units` 아래에 그리는 것은 `display_spec`이 본다.

**킷이 덮는 것(메뉴).** `Resolved Target` 줄이 `Units` 아래에 서고, 대상 없는 액션에서 `@`를 쓰고,
`none`에서 잠기고, 매크로에는 없고, `Target` 메뉴가 하위 메뉴를 안 여는 것. `DropDownMenus.lua`가
헤드리스 목록에 없어서 여기서만 잰다.

**킷이 덮는 것.** `IsModifiedClick`이 제한 환경에서 불리는 것과, 정해진 유닛이 시전 프레임에 서는 것.
조합키 값은 `SetMockState("castModifier", ...)`로 민다. 주입은 `IsModifiedClick`을 부른 뒤에 걸리므로
실제 호출은 매번 돈다.

**원리상 못 덮는 것.** 클라이언트가 바인딩 이름의 조합키를 가리는 것(§2-1)은 실제 누름에서만
드러난다. 킷도 키를 누를 수 없다. 조합키 조합이 다른 바인딩에 잡혀 있으면 우리에게 안 오는 것도
클라이언트의 바인딩 조회라 둘 다 재현이 없다.

## 7. 도움말 창 본문 초안

`HELP_TARGETING_BODY`(설정 탭의 "Which unit is an action used on?" 버튼이 여는 창)는 설정이 둘로 나뉘어
있던 때 기준이라 새로 쓴다. 아래는 enUS 초안이고, 굵은 글씨는 문자열에서
`|cnHIGHLIGHT_FONT_COLOR:...|r`가 된다.

담아야 하는 것 둘 (2026-09-13, 소유자). **블리자드와 달리 조합키가 가리킨 유닛보다 먼저인 이유**와,
**`Resolved Target` 조건이 어느 유닛에 검사되는가**다. 동작과 부딪치지 않는 것만으로는 읽는 사람에게 줄
것이 없다.

대상 없음(`unit` nil) 원본은 조합키도 없고 Hover Cast가 유닛을 안 정했으면 `@` 조건을 현재 대상에
검사한다는 전제로 썼다 (2026-09-13, 소유자, §3-6). 시전은 게임이 대상과 Auto Self Cast로 정한다.

> **Which unit an action is used on**
>
> When you press a Debind key, the unit the action goes to is decided in this order. The first one that applies wins.
>
> 1. **Self Cast Key** held: you.
> 2. **Focus Cast Key** held: your focus.
> 3. **Hover Cast** on and you are pointing at a unit: that unit.
> 4. A unit picked under **Target**: that unit.
> 5. Nothing picked: the game decides, the same way it does on an action bar.
>
> The two keys are the ones in the game's own settings. A modifier that is part of the key you bound, such as the Alt in Alt-C, does not count as holding one.
>
> **Why the keys come first.**
>
> On the game's action bars it is the other way round: with Mouseover Cast on, the unit under your cursor beats a held Focus Cast Key. That goes wrong exactly when it matters. Your cursor rests on whatever enemy you last clicked, so when you hold the Focus Cast Key to interrupt your focus, the interrupt lands on the enemy under the cursor instead. Holding a key is something you do on purpose at the moment you press. Where the cursor happens to be is not. So on a Debind key the held key wins, even over a target you picked for the action.
>
> A held key does not fall back. Hold the Focus Cast Key with no focus, or with a focus the action's conditions do not accept, and the key does nothing. It does not go to your target or to the unit you are pointing at instead.
>
> **Resolved Target.**
>
> This is where you put a condition on the unit the action is about to be used on, such as "only if friendly". It is checked against the unit chosen by the list above:
>
> - **Self Cast Key** held: checked on you.
> - **Focus Cast Key** held: checked on your focus.
> - **Hover Cast** picked a unit: checked on that unit.
> - A target picked under **Target**: checked on that unit.
> - **Nothing picked, no key, nothing pointed at: checked on your current target.** The game still chooses where the action goes, but only once the condition holds there. When it does not, the action does not go out, and Auto Self Cast does not get a turn either.
>
> When the condition does not hold, the action does not go out. The next action on the same key gets its turn.
>
> **You picked a target for the action.**
>
> The action goes to that unit unless a key or Hover Cast comes first. Auto Self Cast does not apply: a friendly spell aimed at an enemy does not come back to you, it simply does not go out. **Disable** under Target hands the decision back to the game.
>
> **Always Ask** is different. The game asks you to click a unit when you press the key, and neither key changes that.
>
> **You did not pick a target.**
>
> Auto Self Cast works as it does on an action bar: a friendly spell cast at an enemy, or at nothing, goes to you.
>
> **Hover Cast.**
>
> The game's own Mouseover Cast is switched off for Debind keys, because the game cannot tell which spell a Debind key is about to cast. **Hover Cast** in Debind's settings takes its place. **Unit Frames** uses the unit frame under your cursor. **Mouseover** also uses nameplates and units in the world.
>
> It reaches any action you can give a target, apart from a pet command, even one that has a target picked. A macro or a mount is left alone. It does not ask whether the spell is friendly or harmful, so put a condition on **Resolved Target** when that matters. **Don't use the action on the unit you are pointing at** leaves one action out of it.
>
> **Clicking a unit frame.**
>
> A click always goes to that frame's unit. A key held on a click picks the binding you made for that exact combination, so neither the Self Cast Key nor the Focus Cast Key moves it.
