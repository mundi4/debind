# 주시 대상 시전과 자기 자신 시전을 우리가 처리하기 (2026-09-13 시작)

> 상태: **§3이 들어갔다.** 모든 액션의 쌍둥이와 키를 네 층으로 펼치기(§3-4), 조합키 칸, 누를 때
> 재기, 루프가 쌍둥이를 건너뛰기, 블리자드 쪽 판단 끄기, §3-6까지다. **§4(`@@`)도 2026-09-16에 들어갔다.**
>
> **2026-09-15에 §3-1이 뒤집혔다.** 고른 유닛은 조합키도 Hover Cast도 안 따른다. 그에 따라 바뀐 §3-4의
> 쌍둥이가 싣는 유닛, §3-6의 `none`, §3-12의 액션 칸 잠금은 들어갔다. **§7의 도움말 본문은
> 아직이다.** 지금 `HELP_TARGETING_BODY`는 옛 구성 그대로 뒤집기와 부딪치는 문장만 고쳤다.
>
> **§3-13은 2026-09-21에 다시 열렸고 이 문서를 떠났다.** 액션마다 정하는 값이 자가시전 하나가
> 아니라 넷이 되고 세 값을 가지므로, 설계는
> `setting-the-clients-cast-automatics-per-action.md`가 든다. 여기 남은 §3-13은 그 결정의
> 앞자리이고 더 안 움직인다. **그래서 이 문서에 남은 것은 §7 하나다.**

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

**이 순서가 틀린 자리는 커서가 채운 유닛뿐이다** (2026-09-15, 소유자). 사용자가 적어 둔 유닛이 첫
줄에서 돌아가는 것은 블리자드가 맞고, §3-1이 그렇게 돌아갔다. 블리자드는 `unit`이 커서가 채운 것인지
사람이 적은 것인지 못 가르지만, 사용자 쪽에서는 둘이 다른 것이다. 하나는 적었고 하나는 아니다.

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
결과 없음. 쉼표로 시작하는 조건절도 조건을 그대로 읽는다.

### 2-3. `@`와 `@@` (2026-09-16, 소유자)

- `[@,help]`는 `@`를 무시한다. 우호 대상을 잡았을 때만 참이다. `@`가 그룹 뒤에 있어도, 쉼표가 뒤에 붙어도
  같다. **`@` 하나는 안 적은 것과 같다.**
- `[@@,help]`는 `@`라는 유닛으로 판정한다. raid41처럼 없는 유닛이라 `dead`, `help`, `harm`은 거짓이고
  `nodead`, `nohelp`, `noharm`은 참이다. **`@@`는 `UnitExists`가 거짓인 유닛과 같다.**
  `/cast [@@] Moonfire`는 적법하지만 아무것도 안 나가고, `/cast [@@,exists] Moonfire;Regrowth`는
  Regrowth가 나간다.
- `@@`가 든 매크로도 아이콘을 뽑는다.

§4가 이것에 기댄다.

## 3. 결정

### 3-1. 고른 유닛은 조합키도 Hover Cast도 안 따른다 (2026-09-15, 소유자)

**대상을 고른 액션은 그 유닛으로만 나간다.** `player`, `focus`, `target`, `@healer`, `@tank`, 사용자
정의 유닛, `hover`, `mouseover` 전부다. 조합키를 쥐어도, 유닛을 가리켜도 그 유닛이다. 조합키와 Hover
Cast가 닿는 것은 **대상이 빈 액션과 `none`뿐이다.** `none`은 시전이 어차피 안 움직이니 닿는 것은
`@`가 묻는 유닛이다(§3-6).

**사용자가 고른 것은 "고정"이라고 읽기로 한 결정이다.** 사용자가 그렇게 말한 적은 없고, 유닛을 고른
것을 그렇게 읽는다. `none`은 반대로 "누르기 전엔 정하지 않는다"라 고른 유닛 쪽이 아니다.

**2026-09-13의 결정은 반대였다.** 모든 대상이 조합키를 따랐다. 근거는 "누르는 순간의 조합키가 지금의
의도이고 저장된 대상은 설정할 때의 의도"였고, 고른 대상을 고정하는 안은 "조합키도 명시적이고 더
나중이라 이긴다"와 "`[@mouseover]` 매크로가 조합키를 안 따르는 것은 틀린 블리자드 순서다"로 버렸다.
"실수로 발동할 걱정도 없다"고 적었다. 바인딩 이름에 든 조합키는 클라이언트가 가리므로(§2-1) 조합키가
참인 것은 일부러 더 누른 누름뿐이라고.

**움직인 것은 그 마지막 줄이다.** `ALT-1`, `2`, `ALT-3`을 이어 누르면 `2`를 누를 때 ALT가 아직
눌려 있다. 클라이언트는 `ALT-2` 바인딩이 없으면 `2`로 떨어뜨리면서 `IsModifiedClick("FOCUSCAST")`를
참으로 준다. 조합키 참이 곧 의도라는 읽기는 키를 하나씩 누를 때만 참이고, 이어 누르면 조합키가 뜻
없이 묻어온다. 대상 빈 액션은 블리자드도 같은 사고를 겪으니 감수하는 값이지만, `@healer`를 적은
키에서는 적은 것이 우연에 진다. 블리자드는 `unit`이 있는 버튼을 첫 줄에서 돌려보내 그 사고를 안
겪는다. 잰 값(§2-1)은 그대로다.

**두 번째 근거도 살아 있었다.** `[@focus]` 매크로가 조합키에 안 움직이는 것은 §1이 틀렸다고 한
"커서가 조합키를 이기는" 자리가 아니다. 매크로를 써 본 사용자는 적어 둔 대상이 조합키에 안 움직이길
이미 기대한다. Target 메뉴에서 유닛을 고르는 것은 그 자리에 `@`를 적는 것이다.

**Hover Cast도 같다.** `legacy/adding-hover-and-mouseover-cast.md`의 첫 문장이 "액션에 대상을 안
지정했을 때"이고, 대상 있는 액션에 닿게 한 결정은 없었다. 커서는 쥐는 것이 아니라 늘 어딘가에 있는
상태다. 힐러는 개체창 위에서 살아서, `@tank` 키에 Hover Cast가 닿으면 매 누름이 가리킨 사람에게
가고 탱커 키가 아니게 된다. Unit Frames 모드는 그걸 완화하지 않는다. 힐러의 커서가 개체창을 떠나는
일이 더 드물다.

**값.** "평소엔 힐러, CTRL을 쥐면 나"를 원하면 `CTRL-2`에 같은 주문을 `player`로 한 번 더 건다.
조합키 붙은 키가 다른 키라는 것이 이 애드온의 모델이고, 그 키에서는 CTRL이 조합키로 안 보인다(§2-1).
자가시전을 끄려고 `target`을 골랐던 사용자는 조합키와 Hover Cast를 잃는다. 그 사람에게는 §3-13이
갈 길이다.

**저울** (2026-09-15, 소유자). 이해시키는 값: "대상을 고르면 거기로만 간다"는 한 문장이고 매크로와
같아 새로 배울 게 없다. 반대쪽은 "고른 대상은 커서에는 안 움직이는데 조합키에는 움직인다"라 왜
그런지를 동작 원리로 설명해야 한다. 받아들이는 값: 이쪽은 키를 하나 더 거는 것이고 설정할 때 한 번
겪는다. 반대쪽은 묻어온 ALT가 전투 중에 소리 없이 주문을 엉뚱한 데로 보내고, 겪는 사람이 원인을 못
찾는다. 둘은 같은 저울에 안 올라간다.

### 3-2. 주시 대상으로 고정한다

`FOCUSCAST`를 누르면 주시 대상이 없거나 조건에 안 맞아도 원래 대상으로 돌아가지 않는다.
블리자드도 `IsModifiedClick("FOCUSCAST")`가 참이면 `"focus"`를 돌려주고 끝내며, 주시 대상이
없으면 `UnitExists` 가드에서 조용히 끝난다(2026-09-11에 `ALT-F9`로 잼). 돌아가는 길을 두면
조합키를 누른 사람의 의도가 그 자리에서 깨진다.

조건에 맞는 쌍둥이가 없으면 그 키는 그 누름에서 아무것도 안 한다. 액션 바가 원래 그렇게 동작한다.
고른 유닛의 쌍둥이는 그 층에서 제 유닛으로 나가니(§3-1), 그런 액션이 앞에 서 있으면 그 누름은 거기로
간다.

### 3-3. 둘 다 눌렸으면 자기 자신

블리자드 순서다. `checkselfcast`를 먼저 보고 참이면 끝낸다(`SecureTemplates.lua:190-199`).

### 3-4. 솔버에는 쌍둥이로 넣는다

**모든 원본이 모든 쌍둥이를 가진다** (2026-09-13, 소유자). 대상을 받지 않는 타입(매크로, 탈것, 대상
없는 소환수 명령)도, `none`도, 대상이 이미 `player`나 `focus`인 액션도 예외가 없다. **쌍둥이가 있느냐와
무엇으로 나가느냐는 따로다** (`GetBindingsForAction`, `TwinUnitFor`).

| 바인딩 | 조합키 칸 | 조건 | 나가는 유닛 |
|---|---|---|---|
| self 쌍둥이 | self | 원본 그대로 | `player`. 원본이 유닛을 골랐으면 그 유닛, `none`이면 `none` |
| focus 쌍둥이 | focus | 원본 그대로 | `focus`. 원본이 유닛을 골랐으면 그 유닛, `none`이면 `none` |
| hover 쌍둥이 | 없음 | 원본에 [가리킨 유닛 있음]을 더한 것 | 설정의 `hover` / `mouseover`. 아래 경우는 원본의 `unit` |
| 원본 | 없음 | 원본 | 원래 대상 |

**self와 focus 쌍둥이가 원본의 유닛으로 나가는 것은 §3-1이다.** 고른 유닛은 조합키를 안 따르므로 그
쌍둥이는 조합키 층에 서서 제 유닛으로 나간다. `ignoreSelfCastKey`/`ignoreFocusCastKey`를 켠 액션과 같은
모양이다(§3-12의 AIM). 대상 빈 원본의 쌍둥이만 `player`/`focus`를 싣는다.

**hover 쌍둥이가 원본의 `unit`으로 나가는 경우는 넷이었고, 2026-09-16에 둘로 줄었다**
(`which-action-a-key-runs.md` §4, §5). 원본이 유닛을 골랐을 때(§3-1, `ActionHasPickedUnit`), 그리고 그
액션의 Hover Cast가 Cast as usual일 때다. 나머지 둘은 없어졌다: 타입으로 가르는 것이 없어져 매크로와
탈것도 가리킨 유닛을 싣고(§3), 개체창 조건은 원본의 대상을 안 채운다(§5). `none`은 여기 안 든다 -
가리킨 유닛을 겨누고 `none`으로 나간다.
[가리킨 유닛 있음]은 모드가 가리키는 유닛 칸에 선다. 원본과 조건이 같거나 더 좁으므로 원본이 그 누름에서
대신 이기는 일은 없고, 솔버가 원본을 덮인 것으로 지워도 된다.

**쌍둥이를 만들지 않는 경우는 둘뿐이다.** 그 액션의 Hover Cast가 Skip this action이면 쌍둥이가 없고,
가리킨 유닛에 [없을 때]를 건 액션에도 없다. 가리킨 유닛이 있는 누름에서 절대 맞지 않으니 둘 자리가 없다.
그 유닛에 사용자가 건 다른 조건은 [있음]과 만나는 자리로 좁혀 들어간다.

**마우스 버튼도 hover 쌍둥이를 받는다** (2026-09-16, `which-action-a-key-runs.md` §7). 2026-09-13에는
Unit Frames 모드의 마우스 버튼에서 원본 `unit`으로 나가는 쌍둥이를 안 만들었다. 조건 없는 마우스 버튼
원본이 암묵적으로 [가리키지 않음]이라(`BuildUnitStates`) 그 쌍둥이가 개체창 클릭 레코드밖에 될 수 없고,
개체창 클릭은 정확한 조합으로만 오니 순서를 겨룰 일이 없다는 것이 근거였다. 뒤집힌 이유는 그 레코드가
개체창 클릭이 3층에서 만나는 바로 그 레코드이기 때문이다 - 옛 개체창 조건 액션이 쌍둥이만 있는 액션으로
옮겨 오면서(§8), 마우스 버튼에서 그 쌍둥이를 빼면 옮긴 액션이 클릭에서 통째로 사라진다.

**`none` 쌍둥이는 이기면 `none`으로 나간다.** 블리자드 코드로 보면 `none`은 `checkfocuscast`가 꺼진 버튼이라
조합키가 무시되고 커서가 뜬다. 쌍둥이는 층 안의 순서에서 경쟁하려고 있다. `@`는 대상 빈 원본의 쌍둥이와 같은
칸에 선다. self 쌍둥이는 `player`, focus 쌍둥이는 `focus`, hover 쌍둥이는 가리킨 유닛이다(§3-6). 나머지 조건은
원본 그대로다.

**대상을 받지 않는 타입의 쌍둥이도 `unit`을 싣는다** (`FillBinding`). 블리자드 액션 바도 조합키를 쥐면 액션
종류를 안 보고 `"focus"`/`"player"`를 돌려주고(`SecureTemplates.lua:190-199`), 주시 대상이 없으면
`UnitExists` 가드가 끊는다(같은 파일 722줄). 있으면 액션이 유닛을 쓰거나 무시하고 나간다. 소유자가 액션
바에서 조합키를 쥔 채 자기 전용 주문을 눌러 안 나가는 것을 확인했다. 원본은 지금처럼 유닛을 지운다.

**대상이 이미 `player`나 `focus`여도 쌍둥이를 만든다.** 그 쌍둥이를 빼면 원본의 조합키 칸을 [없음, focus]처럼
넓혀야 조합키를 누른 누름을 받는다. 빼고 넓히는 분기 둘보다 레코드 하나가 싸다.

**키 전체를 네 층으로 펼친다** (`Debind.lua`의 `UnrollIntoTiers`). 층은 바인딩 종류만으로 정한다.

1. self 쌍둥이 전부
2. focus 쌍둥이 전부
3. hover 쌍둥이 전부
4. 원본 전부

**네 층 안이 전부 정렬된 액션 순서다** (2026-09-16 뒤집힘, `which-action-a-key-runs.md` §3). 3층 안만은
쌍둥이를 **사용자가 손으로 만들었을 두 번째 액션**으로 본 순서 기록으로 넣었는데, 그러면 화면이 보여주는
순서와 3층의 순서가 갈린다. 화면의 순서가 사용자가 아는 유일한 순서다.

**흑마 해제의 probe는 자기 바인딩 바로 앞에 붙은 채 층을 옮긴다.** probe가 바인딩마다 붙어 한 액션이 여덟까지
된다. 우리 코드가 그만큼은 견딘다고 보고, 솔버를 줄이는 것은 이번에 안 한다 (2026-09-13, 소유자).

**기존 사용자에게.** self와 focus 쌍둥이는 층끼리 조합키 칸이 겹치지 않아, 층을 나눠도 이기는 것이 안 바뀐다.
대상을 받지 않는 타입과 `none`이 조합키를 쥔 누름에서 쌍둥이 층으로 옮겨 가는 것은 이 결정의 의도다. 달라지는
나머지는 hover 쌍둥이의 자리인데, 아직 안 나간 기능이다.

**hover 쌍둥이는 조합키로 나뉘지 않는다.** 조합키를 누른 누름은 1, 2층이 맡으므로 3층이 설 자리가
[없음]뿐이다.

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

**모든 hover 쌍둥이와 모든 원본에 [없음]이 붙는다.** 타입도 대상도 안 가린다. 이 칸을 읽는 것은
솔버다. self와 focus 쌍둥이는 원본과 조건이 같고 원본보다 앞에 서므로, 조합키 칸이 없으면 쌍둥이 상자가
원본 상자를 통째로 품어 솔버가 원본을 지운다. 칸이 갈리면 둘은 겹치지 않는다. 클릭 경로는 이 칸을
레코드마다 읽지 않는다. 아래의 구간 나누기가 조합키를 쥔 누름을 그 층에 가둔다.

**클릭 경로는 그 층만 돈다** (2026-09-13, 소유자). 리빌드가 목록마다 층이 시작하는 자리
(`bindings.focusFrom`, `bindings.noneFrom`)를 굽고, 스니펫은 조합키 값을 먼저 정한 뒤 그 구간만 돈다.
조합키가 없으면 3·4층만 본다. 조합키 층에서 승자가 없으면 거기서 끝난다. 모든 액션이 쌍둥이를 가지므로 통째로
돌면 조합키 없는 평범한 누름마다 액션 수의 두 배를 헛돌고 나서 본체에 닿는다. 클릭 핫패스라 레코드마다 칸을
비교하는 대신 구간으로 가른다.

**레코드에 "조합키를 따르나" 플래그가 없다.** 따르느냐는 쌍둥이를 만들 때 싣는 유닛으로 이미 정해져
있고(§3-4), 클릭 경로는 이긴 레코드의 `unit`으로 쏘기만 한다. 사용자가 고른 hover와 따라 나온 hover를
가르는 것도 같은 자리에서 끝난다.

### 3-6. `@`는 대상과 따로 고른다

지금은 액션에 대상이 있을 때만 `units["@"]`가 뜻이 있고, UI도 그렇게만 넣을 수 있다. 바꾼 뒤에는
대상을 고르는 것과 별개로 `@` 조건을 고를 수 있다. 그래야 대상이 없는 액션도 "이 누름이 겨누는
유닛"에 조건을 걸 수 있고, 그 조건이 쌍둥이마다 `player`나 `focus` 칸으로 간다.

**구울 때 `@`를 그 바인딩의 `unit` 칸에 접는 것은 그대로 둔다**(`UpdateBindings.lua`,
`k = binding.unit`). 쌍둥이마다 `unit`이 정해져 있으니 접어도 뜻이 안 바뀐다.

**`none`의 `@`는 대상 빈 액션과 같은 칸에 선다** (2026-09-15, 소유자). 원본은 `target`, self 쌍둥이는
`player`, focus 쌍둥이는 `focus`, hover 쌍둥이는 가리킨 유닛이다. 시전은 어느 쌍둥이든 `none`으로 나가고
조건만 그 유닛에 묻는다. 2026-09-13에는 `none`에서 `@`를 지웠다. 시전이 대상을 입력받으니 누름이 정하는
유닛이 없다고 봤다. 뒤집은 이유는 `none`이 "안 겨눈다"가 아니라 "겨누어진 유닛에게 안 쏘고 나에게 묻는다"라는
것이다. 겨누어진 유닛은 대상 빈 액션과 똑같이 정해지고, "내가 겨눈 것이 적이면 나에게 물어라"에서 Focus Cast
Key를 쥐면 겨눈 것은 주시 대상이다. `@`를 `target`에 고정하는 안은 그 사이에 세웠다가 버렸다. "Always Ask의
Resolved Unit이 `target`이다"는 우리가 정해 넣는 규약이라 사용자 문장으로 못 쓴다. `player`는 `player` 칸에
산다.

**대상 없는 원본의 `@`는 판정할 때만 `target`에 검사한다** (2026-09-13, 소유자). 원본은 조건을
지우지 않고, 시전은 그대로 둔다. `unit`은 비운 채라 `SELFCAST_OFF_SNIPPET`을 안 거치고, 게임이 대상과
Auto Self Cast로 정한다. 가리킨 유닛을 안 쓰겠다고 끈 `""`도 같다.

**`@`가 얹히는 칸은 그 원본이 누를 때 겨누는 곳이다**(`Misc.lua`의 `ResolvedUnitOf`). `binding.unit`이
있으면 그 칸이고, hover 조건에서 채워진 `"hover"`도 여기 든다. nil이거나 `""`이면 `target`이다. 유닛
상태, 구운 레코드, 이슈 검사, 매크로 변환이 이 하나를 같이 쓴다. `none`을 지우던 것은 2026-09-15에
빠졌다(위).

**`none`은 바인딩의 `unit`을 비우고 `castsAtNone`을 든다** (`FillBinding`). `unit`은 겨누는 유닛만 뜻하고,
쏘는 유닛은 `CastUnitOf`가 따로 답한다. 레코드의 `unit` 필드, 버튼 속성, 매크로 변환이 그쪽을 읽는다.
`unit`에 `none`을 남기면 `@`와 hover 조건의 채워 넣기가 설 유닛이 없는 칸에 선다. 매크로 변환은 `none`의
`@`를 옮기지 않는다. 본문의 `[@none]`은 물을 유닛이 아니고, 변환된 매크로도 대상 빈 액션처럼 겨눈다.
Hover Cast가 켜져 있고 `@`가 있으면 변환 항목이 안 뜬다. 원래 hover 쌍둥이는 `@`를 가리킨 유닛에게 묻는데
변환된 매크로의 hover 쌍둥이는 `target`에게 물어, 가리킨 누름의 승자가 바뀐다.

**`unit = "target"`을 실제로 쓰지 않는 이유.** 그러면 `@`를 건 순간 Auto Self Cast가 꺼져 Target에서
`target`을 고른 것과 같아진다.

**갈리는 경우 하나는 받아들인다.** 반응 조건 없이 생사나 소속만 건 우호 주문을 적대 대상에게 쓰면,
판정은 대상에게 했는데 게임은 자기에게 돌린다. `@.harm`은 해로운 주문에 Auto Self Cast가 없으니 판정과
시전이 같고, `@.help`는 대상이 우호일 때만 맞으니 역시 같다.

`target`이 못 쓸 대상이면 `player`로 넘기는 흉내는 버렸다. 주문이 이로운지를 알아야 하는데, 그 성향은
아무 데서도 안 읽기로 했다(`legacy/adding-hover-and-mouseover-cast.md` §0).

**메뉴는 `Target` 아래에서 `Units` 아래로 옮겼다.** `Units` 맨 위의 `Resolved Unit` 줄이고, 모든 액션에
그린다. 대상을 못 받는 액션도 쌍둥이가 유닛을 겨누고, 그 액션이 유닛을 쓰는지는 알 수 없어서다
(2026-09-15, 소유자). `none`도 잠그지 않는다(위). 이름을 따로 둔 것은 같은 메뉴에 사용자가 고르는
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

### 3-9. 상태 루프는 쌍둥이도 센다

루프가 정하는 것은 키 `X`를 잡느냐 놓느냐뿐이고, 무엇이 나갈지는 클릭할 때 정한다. **파생 중 하나라도
조건이 맞으면 그 키를 잡는다** (2026-09-13, 소유자). self와 focus 쌍둥이도 센다. 루프는 조합키를 모르므로
조합키 칸은 빼고 나머지 조건으로 센다(`SecureBindings.lua`의 상태 루프, 루프를 깨우는 축을 모으는
`CollectRecordAxes`).

**우리는 조합키 조합을 잡지 않는다.** `ALT-X`는 게임이 `X`로 떨어뜨려 줄 때만 우리에게
온다(`matching-the-clients-cast-targeting.md` §2-3). 블리자드 단축키나 다른 애드온이 `ALT-X`를
잡았으면 그쪽이 이긴다. **그래서 쌍둥이를 안 세면 조합키 누름이 안 온다.** 원본이 안 맞아 `X`를 놓으면
쌍둥이가 받을 누름도 같이 게임으로 간다. 대상 없이 `@.harm`을 건 공격은 대상이 적대가 아니면 적대 주시
대상에게 주시 대상 시전을 할 수 없었다(2026-09-13, 소유자가 게임에서 봄).

**감수하는 것** (2026-09-13, 소유자). 쌍둥이만 맞아 키를 잡고 있는 동안 조합키 없이 누르면 3·4층에
승자가 없어 아무것도 안 나간다. 원래라면 게임 쪽 `X` 바인딩으로 갔을 누름이다. 클릭 경로에는 누름을 게임에
돌려줄 길이 없다(`RunBinding`이 제한 환경에 없다). self 쌍둥이의 `player` 칸에 선 `@.help`처럼 거의 늘 참인
조건이면 거의 늘 그렇다. 루프가 쥔 조합키에 맞는 층만 세면 이 대가가 없지만, 루프는 누르기 전에 키를 잡아
둬야 하고 조합키가 바뀌는 순간에 루프를 깨울 길은 확인하지 않았다.

**`holdsKey`와는 다른 이야기다.** `holdsKey`는 "이 레코드가 키 누름 경로에 쓰인다"는 뜻이고, 쌍둥이도
참이다. 거짓이면 클릭 래퍼가 키 누름에서 쌍둥이를 아예 평가하지 않아 조합키를 눌러도 쌍둥이가 이길 수
없다.

**솔버는 원본과 파생을 따로 지운다.** 원본은 덮여 지워지고 쌍둥이만 살아남을 수 있다. 살아남은 바인딩은
원본이든 파생이든 `PrepareKeyBindings`에서 각자 `holdsKey`를 받고, 루프에서 각자 키를 잡는다.

### 3-10. 개체창 클릭에는 조합키 칸이 늘 [없음]이다

**개체창 클릭은 조합키 시전이 원래 안 된다** (2026-09-13, 소유자). 수식 키를 쥔 클릭은 정확히
그 조합으로 건 바인딩이 있을 때만 오고(`ClickCastKeys[n][mod]`), 떨어져 들어오는 누름이 없다.
쥔 `ALT`는 사람이 고른 `ALT-BUTTON1`의 일부다. 블리자드 개체창도 같다
(`matching-the-clients-cast-targeting.md` §2-1, §5-3).

`IsModifiedClick`에 맡기면 안 된다. 클릭에는 가려 줄 바인딩 이름이 없어서 쥔 키가 그대로 참으로
읽힌다. 클릭캐스팅 갈래는 묻지 않고 [없음]을 넣는다. §3-7이 지우는 줄들이 하던 일을 이 자리가
넘겨받는다.

### 3-12. 조합키를 끄는 칸 (2026-09-14, 소유자)

설정 탭 General에 `Self Cast Key`, `Focus Cast Key` 체크박스가 있다. 저장은 `Options.selfCast`,
`Options.focusCast`이고 없으면 켜진 것이다(`SelfCastEnabled`, `FocusCastEnabled`).

**끄면 그 조합키는 우리에게 없는 키다.**

- 그 조합키의 쌍둥이를 안 만든다(`GetBindingsForAction`). 그 층을 닫는 BLOCK도 없다(`WithBlocks`).
- 누를 때 그 조합키를 `IsModifiedClick`에 묻지 않는다. 리빌드가 `SelfCastKeyOn`, `FocusCastKeyOn`을
  쌍둥이와 같은 스니펫에 굽고 `EVAL_SNIPPET`이 읽는다. 묻는다면 쌍둥이가 없는 층을 돌고 거기서 끝나,
  누름이 아무것도 안 한다.
- 블리자드에 넘기지 않는다. `checkselfcast`와 `checkfocuscast`는 `false` 그대로다(§3-7).

그래서 끈 조합키를 쥔 누름은 안 쥔 누름과 같다. 하나만 끄면 남은 쪽은 그대로이고, self를 끄고 둘 다
쥐면 focus다. 원본과 hover 쌍둥이의 [없음]은 그대로 둔다. 솔버가 원본을 지키는 칸이고(§3-5), 끈
조합키에는 막을 쌍둥이가 없다.

**액션마다 끄는 칸** (2026-09-14, 소유자). **2026-09-16에 값 둘이 한 줄이 되었다**
(`which-action-a-key-runs.md` §6): `casting.selfCastKey`, `casting.focusCastKey`이고, `mode = "skip"`이
옛 DROP, `aim = "usual"`이 옛 AIM이다. 둘 중 하나를 상수로 고르던 `Constants.CAST_KEY_IGNORE`는
없어졌다 - 사용자가 액션마다 고르는 값이 되어 고를 사람이 코드가 아니다. 대상을 안 받는 액션에도 선다.
쌍둥이는 모든 액션에 있기 때문이다.

| 값 | 쌍둥이 | 조합키를 쥔 누름에서 |
|---|---|---|
| `mode = "skip"` | 안 만든다 | 이 액션은 빠지고 뒤 액션이 나나 주시 대상으로 나간다. 뒤에 아무것도 없으면 BLOCK에서 끝난다 |
| `aim = "usual"` | 원본이 겨누는 것을 겨눈다 | 이 액션이 조합키 층의 제 순서에 서서 자기 대상으로 나간다 |

**계정 칸이 이긴다.** 계정에서 끈 조합키는 쌍둥이 자체가 없으므로 액션 칸이 할 일이 없고, 메뉴의
체크박스는 잠긴다. **Cast as usual에서 조합키를 쥔 동안 이 액션에는 Hover Cast가 안 닿는다.** 쌍둥이가
가리킨 유닛의 층(3층)이 아니라 조합키 층에 서기 때문이다.

**유닛을 고른 액션은 두 칸이 켜진 것과 같다** (2026-09-15, 소유자). Cast as usual이면 "대상을 골랐다"와
"두 무시 칸을 켰다"가 같은 누름을 만든다. 조합키를 쥐어도 원래 대상으로 나간다. 그래서 유닛을 고른 액션에서는 두
칸을 켜진 것으로 보고 잠근다. 두 칸이 사용자 손에 남는 자리는 대상이 빈 액션과 `none`뿐이다. `none`에서
켜면 `@`가 `target`에 고정된다(§3-6).

**끄는 것과 지우는 것은 다르다.** 계정에서 끄거나 대상을 골라 칸이 잠겨도 액션에 적힌 값은 남고, 다시
열리면 그대로 산다.

### 3-13. 자가시전을 끄는 칸 (2026-09-15, 소유자). 보류 (2026-09-19, 소유자)

**액션에 Auto Self Cast를 끄는 체크박스를 둔다.** 대상이 빈 액션에서만 뜻이 있고 그 밖에서는 잠긴다.
켜면 원본을 `target`에 고정하고, 쌍둥이는 대상 빈 액션 그대로다. 곧 조합키와 Hover Cast는 그대로 닿고
평범한 누름만 게임의 Auto Self Cast를 안 거친다.

**이유.** 지금 자가시전을 끄는 길은 Target에서 `target`을 고르는 것뿐이라(§3-6), `target`이 "현재
대상에 고정"과 "자가시전만 끄기" 두 뜻을 지고 있고 사용자가 어느 쪽으로 골랐는지 아무도 모른다. §3-1이
고른 유닛을 고정하면 뒤엣 뜻으로 고른 사람이 조합키와 Hover Cast를 잃는다. 칸이 생기면 `target`은
다른 유닛과 같은 고른 대상이 되고, 자가시전 끄기는 자기 이름을 가진다. Auto Self Cast는 클라이언트가
쓰는 이름이라 설명이 필요 없다.

**메뉴 값은 있지만 매 액션에 읽히는 칸이 아니다.** 원하는 사람만 찾는 자리다.

## 4. 커스텀 매크로의 `@@`

`/cast [@@] Regrowth`의 `@@`를 이 누름이 겨누는 유닛으로 바꿔 넣는다. 조합키를 누르면 `player`나
`focus`, 아니면 원래 겨누는 유닛이다.

- **이미 있는 장치에 올라간다.** `ParseMacroText`가 `@hover` 같은 유닛을 인자 칸으로 떼어 두고, 클릭한
  순간 이긴 레코드의 본문만 조립한다(`DeferredMacroTexts`, `COMPOSE_MACROTEXT_SNIPPET`). `@@`는 인자
  종류 `MACROTEXT_ARG_PRESS_UNIT`이고, `@tank`처럼 `@`는 글자로 남고 뒤의 이름만 칸이 된다.
  `@@target` 같은 접미사도 `@tank`와 같은 자리에 받는다 (2026-09-18, 소유자). **겨누는 유닛이 없을 때
  붙일 곳이 없다며 막아 뒀던 것인데, 그 값이 `target`이 되면서 근거가 사라졌다.** 겨눈 것이 없으면
  `@@target`은 `@targettarget`이고, 가리킨 누름이면 `@party1target`이다.
- **넣는 값은 이긴 레코드가 나가는 유닛이다** (`RESOLVE_UNIT_SNIPPET`의 `unit`). 매크로텍스트는 대상을
  못 고르는 타입이라 원본은 nil, self와 focus 쌍둥이는 `player`와 `focus`, hover 쌍둥이는 가리킨 유닛이다.
- **겨누는 유닛이 없으면 `target`을 넣는다** (2026-09-18, 소유자). `[@@,help]`는 `[@target,help]`가 된다.
  쓴 사람이 적은 것은 유닛을 하나 지정한 절이고, 그것을 지우면 절이 유닛을 잃는 것이 아니라 게임이 기본으로
  겨누는 곳으로 옮겨 붙는다. `/target [@@]`처럼 유닛을 인자로 받는 명령에서는 지운 쪽이 `/target`이 되어
  가장 가까운 적을 잡는다.

  **여기 빈 문자열이 서 있었고, 근거는 `@target`이 자동 자기 자신 시전을 죽인다는 것이었다.**
  2026-09-18 측정(소유자. 자기 자신 시전 키 ctrl, 주시 대상 시전 키 alt, `/cast [@target] Regrowth`):
  적대 대상에 베어 클릭도 컨트롤 클릭도 나한테 왔고, 우호 대상에 컨트롤 클릭도 나한테 왔다. **자기 자신 시전
  키가 매크로에 적힌 유닛을 덮는다.** 우호 주시를 두고 적대 대상에 알트 클릭은 나한테 왔다 - **주시 대상 시전
  키는 적힌 유닛을 못 덮는다.** 우호 대상에 베어 클릭만 대상으로 갔다.

  대상이 아예 없을 때는 안 쟀고, 거기서는 옛 근거대로 조용히 안 나갈 수 있다. **그래도 `target`이다**
  (2026-09-18, 소유자): `[@@]`를 적은 사람은 유닛을 지정한 매크로를 적은 것이고, 그 자리에서 자동 자기 자신
  시전이 빠지는 것은 `[@target]`을 손으로 적은 매크로와 같다. 되찾고 싶으면 `[@@][]`처럼 빈 절을 붙이면
  되는데, 빈 문자열 쪽은 쓴 사람이 되돌릴 방법이 없다.
- **조립은 유닛이 정해진 뒤다.** 세 래퍼 모두 `RESOLVE_UNIT_SNIPPET`을 `BAKE_WINNER_MACROTEXT_SNIPPET`
  앞에 붙인다.
- **스위치 식에서는 `@@`가 적힌 그대로 나간다** (2026-09-16, 소유자). 식은 누름마다 한 번, 승자가 정해지기
  전에 계산되고(`COMPUTE_SWITCHES_SNIPPET`), 같은 누름의 레코드마다 겨누는 유닛이 달라서 넣을 값이 하나로
  안 정해진다. `@@`는 없는 유닛이라 그대로 두어도 게임이 받는다(§2-3). 누름의 값을 넣으려면 레코드마다
  스위치를 다시 계산해야 하고, 그건 이번에 안 했다.

  본문이 `target`이 되면서 같은 `@@`가 두 곳에서 다른 뜻이 됐다. **식에는 쓸 수 없다고 말하는 쪽으로
  정했고, 검사는 안 세운다** (2026-09-18, 소유자): 이 상자는 게임 조건문을 그대로 받는 자리라 지금 어떤
  문법도 안 보는데, `@@` 하나만 걸러 내면 오타도 없는 조건도 통과하면서 이것만 막는 검사가 되어 "여기는
  검사한다"는 잘못된 신호가 된다. 말은 상자의 툴팁이 한다.

**`@@`는 유닛을 넘기는 새 방법이지 변환의 조건이 아니다** (2026-09-16, 소유자). 매크로로 바꾼 액션도
쌍둥이를 갖고 유닛을 받아 가며, 본문이 그것을 읽느냐는 그 액션의 몫이다 - 유닛을 안 쓰는 주문과 같은
자리다. 그래서 `@@`가 없다고 변환을 막지 않는다(`ConditionsSurviveMacroText`에서 그 갈래를 없앴다).
`@@`가 들어오면 본문이 그 유닛을 읽을 수 있게 되고, **변환은 대상을 안 고른 액션을 `[@@]`로 적는다**
(`ConvertToMacroText`). 유닛을 받는 타입만이다(`ActionTakesUnit`). 안 적으면 변환하는 순간 조합키와 Hover
Cast가 그 키에서 빠진다. 고른 유닛과 `none`은 전처럼 그 이름을 적는다.

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
따로 고칠 것이 없다. 3층 안의 순서만은 쌍둥이의 조건으로 정한다(§3-4). 원본 층의 순서와는 따로 도는 줄이라
기존 순서를 안 건드린다.

**쌍둥이를 어느 액션에 만들고 어떻게 세우나**도 같은 날 뒤집혔다.

**처음 구현한 것** (2026-09-13, 소유자). self와 focus 쌍둥이를 대상을 받는 타입에만, `none`은 빼고 만들었다.
조합키 칸 [없음]도 그 원본에만 붙었다. hover 쌍둥이는 `ignoreHoverUnit`, `hover`/`mouseover`/`none` 대상,
Hover Cast가 닿지 않는 타입에서 안 만들었다. 한 액션의 바인딩은 self, focus, hover 쌍둥이, 원본 순으로 붙어서
정렬된 액션 순서대로 섰다.

**뒤집은 이유** (2026-09-13, 소유자).

- **액션별로 붙여 세우면 hover 쌍둥이가 자기 원본보다만 앞선다.** [적대] 액션 1이 [우호] 액션 2보다 앞이고
  둘 다 대상이 없으면, 적대 대상을 잡고 우호 프레임을 가리킨 누름에서 1의 원본이 대상에게 공격을 내고 2의
  hover 쌍둥이는 차례가 없다. 우호 대상을 잡고 적대 프레임을 가리키면 1의 hover 쌍둥이가 가리킨 적에게 나간다.
  같은 키인데 가리킨 유닛의 반응에 따라 규칙이 갈린다. 원본 옆에 쌍둥이를 붙이는 정렬로는 안 풀린다.
- **조합키 칸 없는 원본이 조합키 누름을 가로챈다.** 앞에 선 매크로, 탈것, 대상 없는 소환수 명령, `none`
  액션이 `ALT`를 쥔 누름에서도 맞아서 뒤 액션의 focus 쌍둥이가 차례를 못 받는다.
- **필요한 쌍둥이만 만들면 순서가 답을 못 한다.** 쌍둥이가 없는 액션은 4층에만 서서, 앞에 두었어도 조합키를
  쥐었거나 유닛을 가리킨 누름에서 뒤 액션의 쌍둥이에게 밀린다. 중요도 Very High로 맨 앞에 세운 액션도 못
  이긴다. "이 쌍둥이가 순서상 어디까지 앞지를 수 있나"의 답이 안 나온다.
- **`none`에 쌍둥이를 안 두면 같은 구멍이 `none`에 남는다.** 쌍둥이는 순서에서 경쟁하려고 있고, 무엇으로
  나가느냐는 따로 정하면 된다.

**원본이 겨누는 곳으로 층을 옮기는 안도 버렸다** (2026-09-13, 소유자). `unit`이 `hover`나 `mouseover`로
풀린 원본을 3층에 두자는 것이었다. 모든 원본이 hover 쌍둥이를 가지면 그 자리는 쌍둥이가 맡으므로, 층을
바인딩 종류 하나로 정할 수 있다.

**hover 층 안을 원래 액션 순서로 두는 안을 버렸다가, 2026-09-16에 그것으로 돌아갔다.** 버린 근거는
조건 없는 D의 쌍둥이가 늘 개체창 조건 액션 H 뒤에 서서 사용자가 D를 앞에 두어도 안 뒤집힌다는 것이었다.
되돌린 근거는 화면이다: 개체창 조건이 보통 유닛 조건이 되면서 그 순서는 화면의 순서 그대로가 되었고,
화면이 보여주는 순서와 다르게 서는 순서는 사용자가 고칠 수 없다 (`which-action-a-key-runs.md` §2, §3).

**상태 루프가 쌍둥이를 세느냐**도 같은 날 뒤집혔다.

**처음 정한 것: 안 센다** (2026-09-13, 소유자). 루프는 키를 잡느냐만 정하니 원본만 보면 된다고 봤다.
쌍둥이를 세면 `player`에게 묻는 `@.help`처럼 거의 늘 참인 조건이 키를 잡아, 조합키 없는 누름이 아무것도 안
하게 된다는 것이 근거였다.

**뒤집은 이유** (2026-09-13, 소유자). 조합키 누름은 우리가 잡은 키로만 온다. 원본만 세면 원본이 안 맞는
동안 쌍둥이의 누름이 통째로 게임으로 가서, 대상 없는 `@.harm` 공격을 적대 주시 대상에게 주시 대상 시전하려면
대상까지 적대여야 했다. 게임에서 그렇게 동작했다. 파생 중 하나라도 맞으면 키를 잡아야 하고, 조합키 없는
누름이 먹히는 쪽은 감수한다(§3-9).

## 6. 테스트가 닿는 곳

**헤드리스가 덮는 것.** 쌍둥이의 모양(`normalize_spec`, `hovertwin_spec`: 겨누는 유닛, 조합키 칸, `@`가
옮겨 가는 칸, `none`과 대상을 받지 않는 타입의 쌍둥이가 싣는 유닛, 원본의 `unit`으로 나가는 hover 쌍둥이,
Mouseover 모드에서도 `hover`로 나가는 `hover` 원본의 쌍둥이, [없을 때]에서 안 생기는 hover 쌍둥이)와 키의
층(`keymap_spec`, probe가 자기 바인딩 앞에 붙은 채 층을 옮기는 것은 `specspells_spec`). Unit Frames
모드의 마우스 버튼에 매크로만 건 키가 hover 쌍둥이도 개체창 클릭 레코드도 안 갖고, 같은 모드의 마우스 버튼
주문은 Hover Cast 쌍둥이가 개체창 레코드인 것도 `keymap_spec`이 본다. 층이 시작하는 자리가 목록마다 구워지는
것은 이미션 골든이 든다. 누름과 루프가 고르는
것(`eval_spec`: self가 `player`에게, focus가 원래 대상으로 안 돌아가는 것, 둘 다 눌렸을 때 self, 개체창
클릭이 조합키를 무시하는 것, 원본이 안 맞아도 쌍둥이가 맞으면 루프가 키를 잡고 그 조합키 누름이 주시 대상에게 나가는 것, 블리자드의 세 속성이 꺼져 있는 것). 층에서
나오는 누름 여섯도 `eval_spec`이 본다. §5의 [적대] 1과 [우호] 2가 가리킨 유닛의 반응을 따라 갈리는 것, hover
층 안이 저장 순서를 따르는 것, 앞에 선 매크로 뒤의 주문이 focus 누름을 받고 안 맞으면 매크로의 focus 쌍둥이가
`focus`를 싣고 이기는 것, 대상 없는 소환수 명령이 focus 누름에서 `focus`를 싣는 것, 중요도 맨 앞의 `none`이
focus 누름과 가리킨 누름에서 `none`으로 나가는 것, 중요도 맨 앞의 `ignoreHoverUnit` 주문이 가리킨 누름에서
원래 대상으로 나가는 것이다. `IsModifiedClick`은 인터프리터가 이름마다
답을 넣는다. `@`가 대상 `player`와 쌍둥이의 칸에 서고, 대상 없는 원본과 `""`에서 `target` 칸에,
hover로 채워진 원본에서 `hover` 칸에 서는 것도 `normalize_spec`이 본다. 그 원본이
조건부로 서서 조건 없는 액션보다 앞인 것은 `keymap_spec`이, 판정은 대상에 하고 누름은 유닛 없이
나가는 것은 `eval_spec`이, 툴팁이 그 조건을 `Units` 아래에 그리는 것은 `display_spec`이 본다.

**헤드리스가 덮는 것(§3-1의 고른 유닛).** `target`, `focus`, `player`, `tank`, `healer`, `custom1`, `hover`,
`mouseover`를 고른 액션의 self와 focus 쌍둥이가 그 유닛을 싣고 `@`가 그 유닛 칸에 남는 것, 고른 유닛의
hover 쌍둥이가 그 유닛으로 나가는 것, 옛 프로필이 매크로에 남긴 유닛과 hover 조건이 채운 `hover`는 고른
유닛이 아니라 조합키를 따르는 것(`normalize_spec`, `hovertwin_spec`). 조합키를 쥐어도 고른 대상으로 나가고
조건이 안 맞으면 뒤의 대상 빈 액션이 조합키대로 받는 것, 가리킨 누름에서 고른 대상으로 나가는 것
(`eval_spec`).

**헤드리스가 덮는 것(`none`).** `none`의 원본이 `unit`을 비우고 `@`를 `target` 칸에, self와 focus 쌍둥이가
`player`와 `focus` 칸에, hover 쌍둥이가 가리킨 유닛 칸에 세우고 셋 다 `none`으로 나가는 것
(`normalize_spec`, `hovertwin_spec`). Unit Frames 모드의 마우스 버튼에 건 `none`은 hover 쌍둥이가 없고 키보드
키에서는 있는 것(`hovertwin_spec`). 아무것도 안 쥐었을 때 대상, self에서 나, focus에서 주시 대상,
가리킨 누름에서 가리킨 유닛의 반응으로 승자가 갈리고 이긴 쪽이 시전 프레임에 `none`을 싣는 것
(`eval_spec`). 변환해도 `@`가 그대로이고 본문이 `[@none]`인 것, hover 조건이 있어도 같은 것, Hover Cast가 켜져 있으면
`@`가 없을 때만 변환이 서는 것(`convert_spec`). 툴팁이 `none`의 `@` 줄을 그리는 것(`display_spec`).

**헤드리스가 덮는 것(끄는 칸).** 끈 조합키를 쥔 누름이 원본으로 가고 그 조합키의 레코드가 키에 없는 것,
켜 둔 다른 조합키는 그대로인 것(`eval_spec`). 조합키를 무시하는 액션이 그 조합키를 쥔 누름에서 DROP이면
빠지고 AIM이면 자기 순서에 자기 대상으로 나가는 것, 조건이 안 맞으면 둘 다 뒤 액션이 나나 주시 대상으로
나가는 것(`eval_spec`).

**헤드리스가 덮는 것(`@@`, §4).** 파서가 `@@`를 칸으로 떼고 `@@target`도 칸 뒤에 접미사를 글자로 남기는 것,
겨누는 유닛이 있으면 그 뒤에 붙는 것(`macrotext_spec`).
누름이 조립한 본문이 원본에서 `[@target,help]`, self에서 `[@player,help]`, focus에서 `[@focus,help]`, 가리킨
누름에서 그 유닛인 것, 스위치 식이 `@@` 그대로인 것(`eval_spec`). 변환이 주문, 착용 칸, 유닛 받는 소환수
명령에 `[@@]`를 적고 유닛 안 받는 명령에는 안 적는 것(`convert_spec`, `castname_spec`).

**킷이 덮는 것(`@@`).** 제한 환경 안에서 조합키 값마다 본문이 `[@player]`, `[@focus]`, `[@target]`으로
구워져 그 버튼에 서는 것.

**킷이 덮는 것(액션 칸).** 액션 메뉴의 두 체크박스가 필드를 쓰고, 대상 빈 액션에서 그 조합키의 쌍둥이가
DROP에서 없고 AIM에서 원본처럼 유닛 없이 겨누는 것. 메뉴 파일이 헤드리스 목록에 없어서 여기서만 잰다. 고른
유닛에서 두 칸과 `ignoreHoverUnit`이 잠기는 것은 한 번 보면 끝나는 배선이라 재지 않는다.

**킷이 덮는 것(메뉴).** `Resolved Unit` 줄이 `Units` 아래에 서고, 대상 없는 액션, `none`, 매크로에서
열려 `@`를 쓰고, `Target` 메뉴가 하위 메뉴를 안 여는 것. `DropDownMenus.lua`가 헤드리스 목록에 없어서
여기서만 잰다.

**킷이 덮는 것.** `IsModifiedClick`이 제한 환경에서 불리는 것과, 정해진 유닛이 시전 프레임에 서는 것.
조합키 값은 `SetMockState("castModifier", ...)`로 민다. 주입은 `IsModifiedClick`을 부른 뒤에 걸리므로
실제 호출은 매번 돈다.

**원리상 못 덮는 것.** 클라이언트가 바인딩 이름의 조합키를 가리는 것(§2-1)은 실제 누름에서만
드러난다. 킷도 키를 누를 수 없다. 조합키 조합이 다른 바인딩에 잡혀 있으면 우리에게 안 오는 것도
클라이언트의 바인딩 조회라 둘 다 재현이 없다. 쌍둥이가 실은 `focus`를 블리자드의 `UnitExists` 가드가 끊는 것과
`none`이 커서를 띄우는 것도 액션 버튼이 실제로 눌려야 돈다. 헤드리스는 이긴 레코드가 그 유닛을 싣는 데까지
본다.

## 7. 도움말 창 본문 초안

`HELP_TARGETING_BODY`(설정 탭의 "Which unit is an action used on?" 버튼이 여는 창)는 설정이 둘로 나뉘어
있던 때 기준이라 새로 쓴다. 아래는 enUS 초안이고, 굵은 글씨는 문자열에서
`|cnHIGHLIGHT_FONT_COLOR:...|r`가 된다.

담아야 하는 것 둘 (2026-09-13, 소유자). **블리자드와 달리 조합키가 가리킨 유닛보다 먼저인 이유**와,
**`Resolved Unit` 조건이 어느 유닛에 검사되는가**다. 동작과 부딪치지 않는 것만으로는 읽는 사람에게 줄
것이 없다.

대상 없음(`unit` nil) 원본은 조합키도 없고 Hover Cast가 유닛을 안 정했으면 `@` 조건을 현재 대상에
검사한다는 전제로 썼다 (2026-09-13, 소유자, §3-6). 시전은 게임이 대상과 Auto Self Cast로 정한다.

> **Which unit an action is used on**
>
> When you press a Debind key, the unit the action goes to is decided in this order. The first one that applies wins.
>
> 1. A unit picked under **Target**: that unit, always.
> 2. **Self Cast Key** held: you.
> 3. **Focus Cast Key** held: your focus.
> 4. **Hover Cast** on and you are pointing at a unit: that unit.
> 5. Nothing picked: the game decides, the same way it does on an action bar.
>
> The two keys are the ones in the game's own settings. Unless you changed it, the Self Cast Key is Alt. A modifier that is part of the key you bound, such as the Alt in Alt-C, does not count as holding one.
>
> **A picked target stays picked.**
>
> When you pick a unit under Target, the action goes there and nothing moves it: not a held key, not the unit under your cursor. It works the way a macro with `[@focus]` in it does. If you want the same spell on yourself while holding Ctrl, bind it once more on the Ctrl key with **Player** as its target.
>
> **Why the keys beat the cursor.**
>
> On the game's action bars, with Mouseover Cast on, the unit under your cursor beats a held Focus Cast Key. That goes wrong exactly when it matters. Your cursor rests on whatever enemy you last clicked, so when you hold the Focus Cast Key to interrupt your focus, the interrupt lands on the enemy under the cursor instead. Holding a key is something you do on purpose at the moment you press. Where the cursor happens to be is not. So on a Debind key with no target picked, the held key wins.
>
> A held key does not fall back. Hold the Focus Cast Key and only an action whose conditions accept your focus can go out, apart from one with a picked target, which goes to its own unit as always. With no focus, or with a focus none of them accepts, the key does nothing. It does not go to your target or to the unit you are pointing at instead. This holds for every action on the key, a macro or a mount included, the same as on an action bar.
>
> **Resolved Unit.**
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
> The action goes to that unit. Auto Self Cast does not apply: a friendly spell aimed at an enemy does not come back to you, it simply does not go out. **Disable** under Target hands the decision back to the game.
>
> **Always Ask** is different. The game asks you to click a unit when you press the key, and neither key nor Hover Cast changes that. A condition on **Resolved Unit** still follows the keys and the cursor, the same as with no target picked: it is checked on the unit you would have hit, and the game then asks you anyway.
>
> **You did not pick a target.**
>
> Auto Self Cast works as it does on an action bar: a friendly spell cast at an enemy, or at nothing, goes to you. **Disable Auto Self Cast** on the action turns that off for this one action and leaves the keys and Hover Cast working.
>
> **Hover Cast.**
>
> The game's own Mouseover Cast is switched off for Debind keys, because the game cannot tell which spell a Debind key is about to cast. **Hover Cast** in Debind's settings takes its place. **Unit Frames** uses the unit frame under your cursor. **Mouseover** also uses nameplates and units in the world.
>
> It reaches any action you can give a target, apart from a pet command, as long as no target is picked for it. A macro or a mount is left alone. It does not ask whether the spell is friendly or harmful, so put a condition on **Resolved Unit** when that matters. **Don't use the action on the unit you are pointing at** leaves one action out of it.
>
> **Clicking a unit frame.**
>
> A click always goes to that frame's unit. A key held on a click picks the binding you made for that exact combination, so neither the Self Cast Key nor the Focus Cast Key moves it.
