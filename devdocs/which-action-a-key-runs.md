# 키 하나가 무엇을 실행하나: Hover Cast, Focus Cast Key, Self Cast Key의 스펙 (2026-09-16 시작)

> 상태: **스펙이다. 코드는 아직 이 문서대로가 아니다.** 2026-09-15 문답으로 세우고 2026-09-16에 이름과
> 조건 축을 합쳤다. 구현 순서와 각 단계가 건드리는 자리는 `implementing-the-casting-spec.md`가 든다.
> 인게임 도움말 "Which action a key runs"와 "Which unit an action is used on"은 이 문서보다 낡았고,
> 이 문서에서 다시 쓴다(§9).
>
> **코드는 근거가 아니다** (2026-09-15, 소유자). 이 문서는 사용자가 무엇을 적었고 무엇을 눌렀는지로만
> 쓴다. 지금 구현이 어떻게 되어 있는지는 `implementing-focus-and-self-cast.md`가 들고, 둘이 갈리면
> 이 문서가 맞고 코드가 틀린 것이다.

한 키에 여러 액션이 걸린다. 키를 누르면 그중 하나가 나간다. 어느 것이 나가고 어느 유닛에게 가는지를
정하는 규칙 전부가 여기 있다.

## 0. 이름

코드와 문서가 쓰는 이름은 넷이다 (2026-09-16, 소유자).

| 이름 | 뜻 |
|---|---|
| `unitframe` | 가리키고 있는 개체창의 유닛. 유닛 이름이자 유닛 조건의 키. 화면 이름은 "Unit Frame" |
| `mouseover` | 게임의 mouseover 유닛. 개체창, 명판, 월드의 유닛 위에서 선다. 개체창을 가리키면 `unitframe`과 같은 유닛이다 |
| `hover` | 그 액션의 Hover Cast 모드가 고른 유닛. Unit Frames면 `unitframe`, Mouseover면 `mouseover`로 풀린다. 액션의 모드가 "전역 모드"면 설정 탭의 모드다 |
| Hover Cast (`hoverCast`) | 기능. 가리킨 누름에 쌍둥이를 세우는 것 |

`hover`가 유닛 이름과 기능 이름을 겸하던 것을 여기서 끝낸다. `hover`는 유닛 하나만 뜻한다. **`hover`는
저장에만 있는 이름이다.** 빌드 때 그 액션의 모드로 `unitframe`이나 `mouseover`로 풀리고, 바인딩과 솔버와
스니펫에는 그 둘만 실린다. 솔버에 `hover` 축은 없다.

**Unit Frame은 특별한 조건 축이 아니다.** `unitframe`, `mouseover`, `hover`는 `focus`나 `target`과 같은
보통 유닛이고, [있음], [없음], 반응, 생사가 같은 유닛 조건 메뉴에서 걸린다. 개체창에서만 잴 수 있는
것 둘, 역할과 프레임 종류는 유닛 조건 값의 항목이 되고, 메뉴는 `unitframe`과 Resolved Unit(`"@"`)에서만
그 둘을 보여 준다 (2026-09-16, 소유자). 그 유닛이 개체창의 유닛일 때만 재고, 잴 수 없으면 참이다. 지금
역할이 그룹 프레임에서만 재이고 그 밖에서는 참인 것과 같다. 툴팁은 Hover Cast 모드가 Unit Frames일
때만 검사되고 그 밖에서는 무시된다고 말한다.

## 1. 누름의 종류

키 하나의 누름은 다섯 가지다. 어느 것인지는 누르는 순간에 정해진다.

| 누름 | 언제 |
|---|---|
| Self Cast Key를 쥔 누름 | 설정의 Self Cast Key가 켜져 있고 그 키를 쥐고 있다 |
| Focus Cast Key를 쥔 누름 | 설정의 Focus Cast Key가 켜져 있고 그 키를 쥐고 있다. 둘 다 쥐면 Self Cast Key다 |
| 가리킨 누름 | 조합키를 안 쥐었고 그 액션의 `hover`가 있다. Unit Frames면 개체창 위, Mouseover면 개체창이나 명판이나 월드의 유닛 위. 액션마다 모드가 다를 수 있으니(§6) 한 누름이 어떤 액션에는 가리킨 누름이고 어떤 액션에는 아니다 |
| 보통 누름 | 위 셋이 아니다 |
| 개체창 클릭 | 마우스 버튼을 개체창 위에서 눌렀다 |

가리킨 누름과 보통 누름은 사람이 부르는 이름이고, 키는 둘을 같은 길로 받는다(§3). **개체창 클릭은
다른 넷과 다른 길이다** (§7). 나머지 넷은 키보드 키와 개체창 밖의 마우스 버튼에 같은 규칙으로 선다. **개체창 밖의 마우스 클릭은 키보드 누름과 같다** (2026-09-15, 소유자).

**계정 설정.** Self Cast Key와 Focus Cast Key는 설정 탭에서 끌 수 있고, 끄면 그 키를 쥔 것은 안 쥔
것과 같다. 액션 값은 그때 뜻이 없다. **Hover Cast는 설정 탭에서 못 끈다.** 설정 탭에는 모드(Unit
Frames, Mouseover)만 있고, 끄는 것은 액션마다 한다(§6). 계정에서 못 끄는 이유는 옮기기다(§8). 옛
개체창 조건 액션은 Hover Cast를 켠 적 없는 사람의 것이라도 가리킨 누름에서 서야 하고, 계정을 이기는
액션 값을 두느니 계정에 끔을 안 두는 것이 값 하나 적다.

## 2. 키의 목록과 순서

키에 걸린 액션은 화면의 개요 탭이 보여주는 순서로 한 줄로 선다. 그 순서는 중요도, 조건 유무, 층, 그리고
사용자가 옮긴 자리로 정해진다. 도움말이 말하던 "Unit Frame" 물음은 없어진다. 그 조건은 보통 유닛
조건이 되어 조건 유무 물음에 든다(§0). **이 문서에서 "원본 순서"는 화면의 그 순서다.** 화면이 보여주는
순서가 사용자가 아는 유일한 순서이고, 그것과 다르게 서는 순서는 전부 틀린 순서다 (2026-09-15,
소유자).

## 3. 쌍둥이와 층

액션 하나는 누름의 종류마다 바인딩 하나를 갖는다. 원본 하나와 쌍둥이 셋이다.

| 바인딩 | 받는 누름 | 조건 | 나가는 유닛 |
|---|---|---|---|
| self 쌍둥이 | Self Cast Key를 쥔 누름 | 원본 그대로 | `player`. 대상을 골랐으면 그 대상 |
| focus 쌍둥이 | Focus Cast Key를 쥔 누름 | 원본 그대로 | `focus`. 대상을 골랐으면 그 대상 |
| hover 쌍둥이 | 가리킨 누름 | 원본에 [`hover` 있음]을 더한 것 | `hover`. 대상을 골랐으면 그 대상 |
| 원본 | 보통 누름 | 원본 | 원본의 대상 |

키는 네 층으로 선다. 1층 self 쌍둥이 전부, 2층 focus 쌍둥이 전부, 3층 hover 쌍둥이 전부, 4층 원본
전부. **층은 바인딩의 종류로만 정한다. 원본은 조건이 무엇이든 4층이다** (2026-09-16, 소유자). **각 층
안은 원본 순서 그대로다.** 3층도 같다. 조합키를 쥔 누름은 제 층만 돌고, 승자가 없으면 거기서
끝난다. **조합키 없는 누름은 3층부터 4층까지 한 번에 본다.** 가리킨 누름과 보통 누름을 가르는 것은 3층
바인딩의 조건([`hover` 있음])이지 누름의 종류가 아니다. 조건이 맞는 첫 바인딩이 나간다.

**층이 뜻하는 것.** Self Cast Key와 Focus Cast Key는 가리킨 유닛을 이긴다. 개체창을 가리키며 Self Cast
Key를 쥐면 자기 자신에게 나간다. 의도된 것이다 (2026-09-15, 소유자). 가리킨 누름은 보통 누름을 이긴다.
`hover`가 있을 때 앞 순서 액션의 원본이 뒤 순서 액션의 hover 쌍둥이를 이기지 않는다.

**쌍둥이 셋은 모든 액션에 있다.** 대상을 실을 수 없는 액션(매크로, 탈것, 대상 없는 소환수 명령)도
같다. 유닛을 실어 주되 그것을 쓸 수 있는지는 그 액션의 몫이다 (2026-09-15, 소유자). 쌍둥이가 없는
액션은 그 누름에서 차례가 없다는 뜻이고, 그것은 §6의 Off로만 만든다.

## 4. hover 쌍둥이의 규칙 하나

**쌍둥이는 사용자가 건 조건을 전부 물려받고, 그 위에 [`hover` 있음]을 더해서 `hover`에 나간다.
사용자 조건은 넓히지 않는다.** Hover Cast는 끄지 않는 한 자동으로 생기는 쌍둥이고, 사용자가 직접
건 조건은 그보다 우선한다 (2026-09-15, 소유자). "우선"은 넓힘에 대한 우선이지 순서가 아니다. 3층
안에서는 모든 쌍둥이가 원본 순서로 겨룬다.

**유닛 조건은 그 유닛에 그대로 선다.** `unitframe`에 건 조건은 쌍둥이에서도 `unitframe`에 묻고,
`mouseover`에 건 조건은 `mouseover`에 묻는다. 옮겨 타는 것은 Resolved Unit 조건(`"@"`)뿐이다(§5).
그래서 특례가 없다. 아래 표는 규칙 하나를 `unitframe`과 `mouseover`에 건 조건마다 편 것이다.

아래 표의 모드는 그 액션의 Hover Cast 모드다(§6). "전역 모드"면 설정 탭의 것이다.

| 액션의 조건 | Unit Frames 모드 쌍둥이 | Mouseover 모드 쌍둥이 |
|---|---|---|
| 없음 | [`unitframe` 있음], `unitframe` | [`mouseover` 있음], `mouseover` |
| `unitframe` [C] | C 그대로. 원본과 같다 | C + [`mouseover` 있음], `mouseover`. 개체창 위에서만 서고, 거기서 `mouseover`는 그 개체창의 유닛이다 |
| `unitframe` [없음] | 없음. 만날 자리가 없다 | [`unitframe` 없음] + [`mouseover` 있음], `mouseover`. 월드 유닛과 명판 위에서만 |
| `mouseover` [C] | C + [`unitframe` 있음], `unitframe` | C 그대로. 원본과 같다 |
| `mouseover` [없음] | 없음 | 없음 |
| 그 밖의 조건 | 그대로 물려받고 위 행대로 | 같음 |

[없음]이 아닌 유닛 조건(반응, 생사 등)은 그 유닛이 있다는 것을 품고 있다 (2026-09-15, 소유자). 그래서
"C 그대로"인 행이 나온다. `unitframe`에 건 조건은 어느 모드에서든 개체창 위에서만 선다. 개체창에는
mouseover로 잴 수 없는 것(역할, 프레임 종류)이 있고, mouseover에서 나가게 하고 싶었으면 사용자가
`mouseover`에 조건을 걸었을 것이다 (2026-09-15, 소유자). `unitframe` [없음]과 Mouseover 모드는 말
그대로다. 개체창 위에서는 안 나가고 월드 유닛 위에서는 나간다. 끄려면 그 액션의 Hover Cast를 끈다
(2026-09-15, 소유자).

**원본과 같은 쌍둥이.** 표에서 "원본과 같다"인 쌍둥이는 3층에 서고, 4층의 원본은 그것에 덮여 지워진다.
쌍둥이를 만드는 것이지 원본을 3층으로 옮기는 것이 아니다. 층은 바인딩의 종류로만 정한다(§3).

## 5. 대상

액션의 Target 메뉴에서 고른 것이 쌍둥이의 대상을 정한다. 규칙은 하나다. **대상을 골랐으면 그 대상,
안 골랐으면 그 누름의 유닛.**

| 액션의 대상 | 쌍둥이의 대상 | 보통 누름 |
|---|---|---|
| 안 고름 | `player`, `focus`, `hover` | 게임이 놓는 대상. Auto Self Cast 포함 |
| 고른 유닛(`target`, `focus`, `player`, 역할 유닛, 사용자 유닛) | 그 유닛 | 그 유닛 |
| `unitframe`, `mouseover`, `hover` | 그 유닛 | 유닛이 없어 아무 일도 안 일어난다. 누름을 삼킨다 |
| `none` | 조건은 그 누름의 유닛에 묻고, 시전은 `none` | 조건은 `target`에 묻고, 시전은 `none` |
| 대상을 못 싣는 타입 | 그 누름의 유닛을 실어 준다. 처리는 액션의 몫 | 원래대로 |

**고른 유닛은 고정이다.** 조합키를 쥐어도, 유닛을 가리켜도 그 유닛이다. 그러면서 쌍둥이는 있으므로
그 액션은 세 누름 모두에서 제 차례를 지킨다.

**"가리킨 누름에서도 게임이 놓는 대상에"는 대상 고르기로는 못 만든다.** `target`을 고르면 고정이 되어
Auto Self Cast가 꺼진다. 그래서 그것은 §6의 "Cast as usual"이 든다.

**`unitframe`, `mouseover`, `hover`를 대상으로 고르고 조건을 안 건 액션**은 유닛만 고른 다른 액션과
똑같이 다룬다. 주시 대상이 없을 때 `focus` 액션이 누름을 삼키는 것과 같다. 이 셋에만 예외를 두지
않는다. **툴팁이 이것을 말해야 한다** (2026-09-15, 소유자): 조건 없이 대상만 고르면 가리키지 않을 때
키가 죽는다는 것, 뒤 액션으로 넘기려면 그 유닛에 [있음] 조건을 걸라는 것. "가리킬 때만"은 그 유닛의
[있음] 조건이고, "가리키지 않을 때만"은 [없음] 조건이다 (2026-09-16, 소유자).

**Resolved Unit 조건(`"@"`)은 그 바인딩이 겨누는 유닛에 묻는다.** 안 고른 원본은 `target`,
self 쌍둥이는 `player`, focus 쌍둥이는 `focus`, hover 쌍둥이는 `hover`, 고른 유닛은 그 유닛이다. 같은 유닛에 유닛 조건과 `"@"`
조건이 함께 서면 둘 다 맞아야 한다.

## 6. 액션 메뉴의 Casting

**네 누름이 액션 메뉴의 한 하위 메뉴에 선다** (2026-09-16, 소유자).

```
Casting
  Self Cast Key   ▸  ( ) Cast on yourself     ( ) Cast as usual  ( ) Skip this action
  Focus Cast Key  ▸  ( ) Cast on your focus   ( ) Cast as usual  ( ) Skip this action
  Hover Cast      ▸  ( ) Skip this action  ( ) Account mode  ( ) Unit Frames  ( ) Mouseover
                     ---
                     ( ) Cast on pointed unit  ( ) Cast as usual
  [x] Normal Cast
```

**값은 "이 키를 쥐면(유닛을 가리키면) 이 액션이 무엇을 하나"로 적는다** (2026-09-16, 소유자). "On, keep
original target"이라고 적으면 사용자가 "Focus Cast 기능인데 focus가 아닌 대상을 고른다고?"라고 읽는다.
"Cast as usual"은 대상을 고르는 것이 아니라 이 키를 무시하고 차례를 지키는 것이다. 문구는 제안이고
`writing-user-facing-text.md`를 따른다.

**Self Cast Key와 Focus Cast Key는 값 셋이다.** 기본은 첫째. "Skip this action"이면 그 누름의 쌍둥이를
만들지 않는다. 그 액션은 그 누름에서 빠지고 다음 액션이 받는다. 뒤에 아무것도 없으면 키는 그 누름에서
아무것도 안 한다. 계정에서 끈 키는 이 값이 뜻이 없다. Use Setting은 없다. 계정을 끄면 층이 통째로
없어서 액션 값이 무의미하고, 계정이 켜져 있으면 액션 값이 전부다 (소유자).

**Hover Cast는 모드 넷에 겨눔 둘이다.** 모드의 기본은 Account mode, 겨눔의 기본은 Cast on pointed unit.
"Skip this action"이면 쌍둥이가 없다. Account mode는 설정 탭의 모드를 물려받는다. Unit Frames와
Mouseover는 이 액션만 그 유닛을 쓴다. 액션이 자기 가리킨 유닛을 말하니 "Unit Frames 모드인데 이 액션만
mouseover에서"가 설정 하나로 된다. 그 전에는 대상을 `mouseover`로 고르는 길뿐이었는데, 그러면 Unit
Frames 모드에서 그 쌍둥이의 조건이 [`unitframe` 있음]이라 월드 유닛 위에서 3층에 못 서고 4층에서
앞 순서 액션에 졌다 (소유자). 겨눔 둘은 대상을 고른 액션에서 같은 일이라 둘째를 잠그고, 첫째의 툴팁이
"대상을 골랐으니 그 대상에"라고 말한다.

**Normal Cast는 체크박스다.** 기본은 체크. 끄면 원본을 만들지 않는다.

**넷을 다 끈 액션은 어느 층에도 안 굽는다.** 막지 않는다. 바인딩을 하나도 안 만들고, 이슈 검사가
WARNING 등급 이슈를 돌려주어 행에 경고로 표시된다 (2026-09-16, 소유자). WARNING이라 키에서 빠지지는
않는다(`Constants.BINDING_ISSUE_GRADES`). 키에는 그 액션이 없는 것과 같다. 이슈 검사의 갈래 이름은
`"casting"`이고, Casting 메뉴가 그 이름으로 묻는다. `"hover"`와 `"frameTypes"` 갈래는 Unit Frame 축과
함께 없어지고 `"units"` 갈래가 그 조건을 본다.

**설정 탭에는 모드만 남는다.** Unit Frames와 Mouseover. 기본은 Unit Frames다. 이전 버전의 개체창 조건이
그것이라 새 액션이 옛날과 같은 곳에서 선다 (2026-09-16, 소유자).

한 번 정하면 다시 안 여는 자리이고 여러 액션을 골라 한 번에 고칠 수 있어서
(`editing-many-actions-at-once.md`), 한 층 더 들어가는 값은 작다 (소유자).

**Normal Cast를 끄면 쥐거나 가리킬 때만 나간다.** 원본이 없으니 그냥 누르면 다음 액션이 받는다. 옛
"Unit Frame [있음]" 조건이 하던 "가리킬 때만"을 이것이 대신한다. 유닛의 [있음] 조건과 다른 점은 누름을
삼키지 않고 넘긴다는 것이다.

**"차례를 넘긴다"가 끄기의 뜻이다.** "이 액션은 그 누름에서도 차례를 지키고 자기 대상에 나간다"는
대상을 고르는 것이다. 이 결정은 생각할 때마다 답이 달라진 자리라 그때의 근거를
`.zzz/hover-twin-wrong-2026-09-15.md`에 남겼다.

**"Cast as usual"은 대상을 안 고른 액션에서만 뜻이 있다.** 그 누름의 쌍둥이를 만들되 게임이 놓는
대상에 나간다. 차례를 지키고 그 누름의 유닛을 안 쓴다. Auto Self Cast 포함. 게임이 놓는 대상을 대상
고르기로는 못 만들기 때문에 있다(§5). 옛 "Don't use the action on the unit you are pointing at"
(`ignoreHoverUnit`)이 Hover Cast의 이 값으로 온다. 조합키 둘의 설명은 지금 `_AIM_DESC` 문구다.
"가리킬 때 시전 안 함"이라는 값은 안 둔다. `hover` [없음] 조건과 같은 말이다 (2026-09-16).

**옛 "Unit Frame 조건이 앞선다"를 이것으로 대신한다.** 옛날에는 개체창 조건 액션이 보통 액션보다 앞이되
중요도로 보통 액션을 앞세울 수 있었고, 그러면 개체창 위에서 보통 액션이 자기 대상에 나갔다. 이제 그
액션의 Hover Cast를 "Cast as usual"로 두면 쌍둥이가 3층의 제 자리에 서서 같은 일을 한다. 개체창 조건은 보통 조건이
되어 조건 없는 액션보다는 앞이지만 다른 조건 액션과는 층과 자리 번호로 갈린다. 사용자가 정한다.

**Hover Cast를 Skip this action으로 둔 액션.** 쌍둥이가 없으니 원본이 4층의 제 자리에서 돈다. 조건도 대상도 사용자가
적은 그대로다. 2026-09-15에 "개체창 조건이 있는 원본은 3층 자리"로 정했던 것은 2026-09-16에 뺐다.
옛 "Unit Frame 조건이 먼저"를 이름만 바꿔 다시 들이는 것이고, 설명할 규칙을 하나 줄일 기회를 잃는다
(소유자).

**Auto Self Cast를 끄는 체크박스**는 `implementing-focus-and-self-cast.md` §3-13이다. 대상 없는
액션의 보통 누름에서만 뜻이 있고, 쌍둥이는 안 건드린다.

## 7. 개체창 클릭

**개체창 클릭도 조합키 없는 누름과 같이 3층부터 4층까지 본다.** 조건 없는 마우스 버튼
원본은 개체창 위에서 서지 않는다(마우스 버튼은 개체창 조건이 없으면 [가리키지 않음]이다. 그것은 키의
규칙이고 유닛 조건이 아니다). 옮긴 개체창 조건 액션은 Hover Cast가 Unit Frames라 3층에 쌍둥이가
있고, 개체창 클릭이 거기서 만난다(§8).

**개체창 위 마우스 클릭은 Self Cast Key와 Focus Cast Key를 지원하지 않는다** (2026-09-15, 소유자).
조합키를 쥔 클릭은 그 조합 그대로의 클릭이고, self나 focus 쌍둥이가 끼지 않는다.

## 8. 옮길 것

이 문서로 오면서 저장값이 바뀐다. **계정 설정은 하나도 안 건드린다.** 기존 액션은 뜻이 그대로 남게
옮긴다. 새 필드 이름은 제안이다.

| 옛 것 | 값 | 새 것 |
|---|---|---|
| `Options.hoverCast` | 켬/끔 | 없어진다. 계정에는 끔이 없다(§1). 아직 안 나간 기능이라 옮길 사람이 없다 |
| `Options.hoverCastMode` | `"hover"` | `"unitframe"`. 없으면 `"unitframe"` |
| `Options.hoverCastMode` | `"mouseover"` | 그대로 |
| `Options.selfCast`, `Options.focusCast` | 켬/끔 | 그대로 |
| `unit` | `"hover"` | `"unitframe"`. 옛 값은 개체창의 유닛을 뜻했다. 새 `"hover"`(모드를 따름)는 새로 고르는 사람만 받는다 |
| `unit` | 비어 있고 `units.hover`가 `false`가 아니고 `ignoreHoverUnit`이 아님 | 빈 채로. 쌍둥이가 `hover`에 나간다 |
| `unit` | `"mouseover"`, 그 밖 | 그대로 |
| `conditions.units.hover` | `{}` [있음] | 조건은 안 적는다. 아래 Casting 줄이 대신한다 |
| `conditions.units.hover` | `{ reaction = R }` | `conditions.units.unitframe = { reaction = R }` |
| `conditions.units.hover` | `false` [없음] | `conditions.units.unitframe = false` |
| `conditions.units.hover.role` | 역할 마스크 | `conditions.units.unitframe.role` |
| `conditions.frameTypes` | 프레임 종류 마스크 | `conditions.units.unitframe.frameTypes` |
| `units.hover`가 `{}`(빈 [있음])이고 `ignoreHoverUnit`이 아님 | | 조건은 안 적고 `casting.hoverCast.mode = "unitframe"`, `casting.normalCast = false`. "가리킨 누름에서만"을 조건이 아니라 Casting으로 적는다 |
| `units.hover`가 `{ reaction = R, role = ... }`이고 `ignoreHoverUnit`이 아님 | | `units.unitframe`에 같은 값, 그리고 `casting.hoverCast.mode = "unitframe"`, `casting.normalCast = false` |
| `units.hover`가 `false`가 아니고 `ignoreHoverUnit`이 참 | | `units.unitframe`에 같은 값(빈 [있음]이면 안 적음), `casting.hoverCast = { mode = "unitframe", aim = "usual" }`, `casting.normalCast = false` |
| 그 밖의 액션 | | `casting.hoverCast.mode = "skip"`. 옛 액션은 설정 탭의 모드가 무엇이든 그대로다 |
| `ignoreSelfCastKey` | 참 | `casting.selfCastKey.mode = "skip"` |
| `ignoreFocusCastKey` | 참 | `casting.focusCastKey.mode = "skip"` |
| 없음 | | `action.casting` 표 하나 (2026-09-16, 소유자). 아래 모양 |

```lua
action.casting = {
    selfCastKey  = { mode = nil | "skip",                              aim = nil | "usual" },
    focusCastKey = { mode = nil | "skip",                              aim = nil | "usual" },
    hoverCast    = { mode = nil | "skip" | "unitframe" | "mouseover",  aim = nil | "usual" },
    normalCast   = nil | false,
}
```

키 이름은 메뉴 행 이름 그대로다. `mode`가 없으면 조합키는 켬, Hover Cast는 설정 탭 모드다. `aim`이
없으면 그 누름의 유닛에. `mode = "skip"`이면 `aim`은 뜻이 없어 `CleanUpDB`가 지우고, 빈 표도 지운다.
한 필드에 불리언과 문자열을 섞지 않는다. 셋이 같은 모양인 것은 메뉴가 같은 모양이기 때문이다.
`Options.selfCast`, `Options.focusCast`는 설정 탭의 켜고 끄기라 그대로 둔다.
| 발동 순서의 hover 단계 | | 없어진다. 같은 층 안 순서는 키 묶음마다 `seq`를 옛 순서대로 다시 매겨 지킨다 |

**옛 개체창 조건 액션은 쌍둥이만 있는 액션으로 옮긴다** (2026-09-16, 소유자). 옛 뜻이 "가리킨 누름에서만,
층을 뛰어넘어"이고, 그것을 새 모양으로 정확히 적으면 Hover Cast를 Unit Frames로 두고 Normal Cast를
끈 것이다. 원본이 없고 쌍둥이만 3층에 서서 층이 어디든 4층 원본을 앞선다. 옛 순서 그대로다. 반응, 역할,
프레임 종류는 `units.unitframe`에 조건으로 남고 쌍둥이가 물려받는다. 설정 탭에 끔이 없어야 하는 이유가
이것이다. 그 쌍둥이는 Hover Cast를 켠 적 없는 사람에게도 서야 한다.

**나머지 옛 액션은 Skip this action으로 옮긴다.** 옮긴 날 아무것도 안 바뀌고, 설정 탭의 모드가 무엇이든
옛 액션은 그대로다. 새 액션만 Account mode다. 옮긴 뒤 한 번 알린다: "기존 액션은 Hover Cast가 꺼진 채
옮겨졌고, 새 액션은 설정 탭의 모드를 따릅니다. 여러 액션을 골라 한 번에 바꿀 수 있습니다." 설정 탭의
모드 기본값은 Unit Frames다. 파급이 개체창 안에 머문다.

**버린 안들.** 옛 개체창 조건을 `units.unitframe = {}` 조건과 `unit = "unitframe"`으로 옮기는 안: 원본이
4층에 서서 층이 다른 조건 액션과의 옛 순서를 못 지키고, 자리 번호는 층 뒤에 비교되어 못 뒤집는다.
개체창 조건 원본을 3층에 세우는 안: 옛 "Unit Frame 조건이 먼저"를 이름만 바꿔 다시 들이는 것이라 설명할
규칙을 하나 줄일 기회를 잃고, 옮기기 하나 때문에 영구 규칙이 생긴다. 계정을 대신 켜 주는 안: 그 사람의
조건 없는 액션 전부가 가리킨 유닛에 나가기 시작한다. 계정 기본값을 켜짐으로 두는 안: 파급력이 큰 옵션은
꺼짐이 기본이다. 계정 켜고 끄기를 두고 액션에 계정을 이기는 On을 두는 안: 값이 넷이 되어 메뉴가 커지고,
Hover Cast에만 두면 조합키 둘과 모양이 다르다. 계정 켜고 끄기를 없애고 액션에 모드까지 두는 것이 값이
가장 적다.

**Hover Cast를 몇 개 액션에만 원하는 사람**은 나머지를 Skip this action으로 둔다. 여러 액션을 골라 한
번에 된다.

## 9. 도움말이 말해야 하는 것

"Which action a key runs"는 §2의 물음 셋에 §3의 층을 더해야 한다. 지금 본문은 층을 모르고 "Unit
Frame" 물음을 든다. "Which unit an action is used on"은 §5와 §6이고, 지금 본문의 "Pointing at a frame
is picking a target" 문단과 "Hover Cast and Mouseover Cast" 문단은 이 문서와 갈린다. 둘 다 이 문서에서
다시 쓴다. 문구는 `writing-user-facing-text.md`를 따른다.

## 10. 커버리지

헤드리스가 재는 것: 쌍둥이의 조건과 대상(§4의 표 전부, §5의 표 전부), 네 층과 각 층 안의 원본 순서,
Casting의 네 값이 바인딩을 넣고 빼는 것, 원본과 같은 쌍둥이가 원본을 덮는 것, §8의 옮기기(표의 줄
하나마다 하나). `/debtest`가
재는 것: 누름 종류마다 어느 바인딩이 이기고 어느 유닛에 나가는지. 원리상 못 재는 것: 게임이 놓는
대상(Auto Self Cast)과 개체창 클릭이 개체창에 닿는 길. 그것은 `matching-the-clients-cast-targeting.md`
§4가 든다.
