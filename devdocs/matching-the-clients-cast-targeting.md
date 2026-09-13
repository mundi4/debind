# 클라이언트의 대상 규칙과 우리 키를 맞추기 (2026-09-11 시작)

> 상태: **넷 다 들어갔다.** `checkmouseovercast`를 껐고(§2), 개체창 클릭에는 시전 수식 키 셋을
> 안 걸며(§2-1), 대상을 지목한 주문·아이템이 자동 자가시전을 끄고 나가고(§2-2), 도움말 한 편이
> 붙었다(§3-1). 남은 것은 하나, **유지·시전 주문은 아직 옛 동작 그대로다** - 매크로 한 겹이
> 누름과 뗌을 못 나른다(§2-2).
>
> **이 트랙은 지금 나가고 있는 것을 고친다.** 새 기능은
> `legacy/adding-hover-and-mouseover-cast.md`가 들었고, 2026-09-12에 닫혔다.

와우에는 액션이 어느 유닛에게 가는지를 트는 장치가 넷 있다. 우리 키도 그 장치를 지나가는데,
둘은 제자리에서 돌았고 둘은 어긋나 있었다.

| | 무엇 | 어긋나 있던 것 | 지금 |
|---|---|---|---|
| Mouseover Cast | 마우스 밑 유닛으로 튼다 | 액션바 1번 칸으로 판정받았다 (§2) | 껐다 |
| Self Cast | 수식 키를 누르면 자신에게 | 키 누름은 제자리 (§2-1) | 개체창 클릭에서는 안 건다 |
| Focus Cast | 수식 키를 누르면 포커스에게 | 키 누름은 제자리 (§2-1, §2-3) | 개체창 클릭에서는 안 건다 |
| 자동 자가시전 | 못 쓸 대상이면 자신에게 | 절반만 돌았다 (§2-2) | 지목한 대상에서 끈다 |

## 1. 블리자드의 것이 어떻게 되어 있나

Lua로 되어 있다. `SecureTemplates.lua`의 `SecureButton_GetModifiedUnit` 안이다.

```lua
if ( SecureButton_GetModifiedAttribute(self, "checkmouseovercast", button) ) then
    local useMouseoverCasting = GetCVarBool("enableMouseoverCast") and (GetModifiedClick("MOUSEOVERCAST") == "NONE" or IsModifiedClick("MOUSEOVERCAST"));
    if ( useMouseoverCasting and UnitExists("mouseover") ) then
        local action = self:CalculateAction(button);
        local targetIsFriendly = UnitIsFriend("player", "mouseover");
        local useNeutral = true;
        if ( (targetIsFriendly and C_ActionBar.IsHelpfulAction(action, useNeutral)) or (not targetIsFriendly and C_ActionBar.IsHarmfulAction(action, useNeutral)) ) then
            ...
            return "mouseover";
        end
    end
end
```

읽어둘 것 셋.

- **수식 키는 필수가 아니다.** `MOUSEOVERCAST`의 값 넷 중 하나가 `NONE`이고 그것이 기본값이다
  (`Bindings_Standard.xml`). 켜 두면 수식 키 없이 모든 키보드 단축키에 걸린다.
- **`unit` 속성이 있으면 이 자리에 오지 않는다.** `SecureButton_GetModifiedUnit`이 맨 앞에서
  그 속성을 돌려주고 끝낸다. 대상을 지정한 액션이 영향을 안 받는 이유가 이것이다.
- **이로움과 해로움은 배타가 아니다.** 그래서 블리자드는 유닛을 아군이냐 아니냐로 먼저 가르고
  그쪽 성향만 묻는다. 둘 다 참인 주문은 어느 쪽에서도 튼다.

**자동 자가시전만 Lua에 없다.** `reference` 안에서 `autoSelfCast`를 읽는 곳은 설정 패널 둘뿐이고
시전 경로에는 한 줄도 없다(`Blizzard_SettingsDefinitions_Frame/Combat.lua`). 시전이 나간 **뒤**
엔진이 대상을 고치는 것이라, 우리가 볼 수 있는 마지막 값은 `unit`까지다.

## 2. Mouseover Cast가 액션바 1번 칸을 본다

`DefaultClickFrame`이 `checkmouseovercast`를 켜 두고 있고(`Debind.lua`), 클릭 래퍼가 매 클릭
`unit`을 지운다(`SecureBindings.lua`의 `SetAttribute("unit", nil)`). 그래서 대상을 안 지정한
액션은 위 블록까지 간다.

**그런데 성향을 우리 주문에 대해 묻지 않는다.** `CalculateAction`은 `GetID()`가 0이고 `action`
속성이 없으면 `1`을 돌려준다. 그 `1`은 1번 칸을 뜻하는 값이 아니라 아무것도 없을 때 하나 돌려주려
둔 기본값이고, 액션바 버튼에서는 절대 안 밟히는 가지다. 우리 버튼은 `SetID`도 `action` 속성도
안 쓰므로 늘 그 가지를 밟는다.

결과는 이렇다. Mouseover Cast를 켜 둔 사람의 Debind 키는 **액션바 1번 칸에 무엇이 있느냐**에 따라
마우스오버로 틀리거나 안 틀린다. 누른 주문과 무관하다. 1번 칸이 비어 있으면 아무 일도 안 난다.

**끈다.** 우리 버튼에서 이 판정이 옳은 답을 내는 경우가 없다. `action` 속성을 채워 고치는 길도
없다. 그러려면 이긴 액션이 이로운지 해로운지를 이미 알아야 하는데, 그걸 알면 칸이 필요 없어진다.

**`false`로 박는다.** 바로 위 두 줄이 `checkselfcast`와 `checkfocuscast`를 참으로 걸고 있어서,
셋째 줄이 없으면 빠뜨린 것으로 읽히고 다음 사람이 대칭을 맞추려고 도로 넣는다. 안 켜는 이유가
주석에 있어야 한다.

`legacy/adding-hover-and-mouseover-cast.md`가 우리 쪽 Mouseover Cast를 만들었다. 그 트랙을 하든
안 하든 이 줄은 꺼야 했다.

## 2-1. 개체창 클릭에는 셋 다 안 건다

그 둘은 액션바 칸을 안 본다. `IsModifiedClick("SELFCAST")` / `("FOCUSCAST")` 하나만 읽으므로
우리 버튼에서도 답이 맞다. 기본 수식 키는 `SELFCAST`가 `ALT`, 나머지 둘이 `NONE`이다
(`Bindings_Standard.xml`).

**닿는 것은 대상을 안 고른 액션뿐이다.** `unit`이 있으면 `SecureButton_GetModifiedUnit`이 첫
줄에서 반환해서 이 둘까지 안 온다. 그러니 대상을 고른 액션에는 수식 키 시전이 안 걸리고, 그것이
§2-2가 자동 자가시전을 끄는 쪽으로 맞추는 것과 같은 방향이다. 사람이 대상을 지목했으면 그 액션은
거기로만 간다.

**키 누름에서는 그대로 둔다.** 대상을 안 고른 액션이 수식 키 시전을 받는 것은 액션바에서 늘 하던
동작이고, 우리가 뺄 이유가 없다.

**위 두 문단의 키 누름 쪽은 2026-09-13에 뒤집혔다.** 대상을 고른 액션도 조합키를 따르고, 판단은
블리자드가 아니라 우리 래퍼가 한다(`implementing-focus-and-self-cast.md` §3-1). 아래의 개체창 클릭 결정은
그대로다.

### 개체창 클릭은 다르다 (2026-09-11, 소유자)

**블리자드는 개체창 클릭에 셋을 안 준다.** 개체창은 맨이름 `unit`을 늘 들고 있어서
`SecureButton_GetModifiedUnit`이 첫 줄에서 반환하고, 세 갈래는 **밟히지 않는 코드**다. 그래서
블리자드 쪽에는 "쥔 ALT가 바인딩 몫이냐 시전 몫이냐"를 정할 일 자체가 없었다.

**그런데 우리 경로는 거기서 한 번 더 묻는다.** `SECURE_ACTIONS.click`이 `delegate:Click(button)`
한 줄이라([SecureTemplates.lua:560-567]) 1홉에서 구한 프레임의 유닛을 버리고, 2홉에서
`DefaultClickFrame`의 맨이름 `unit`으로 다시 판정한다. ignore hovered면 그 자리가 비어 있으니,
**클라이언트가 프레임 클릭에 한 번도 안 준 갈래가 우리 버튼에서만 살아난다.**

**안 주는 쪽으로 맞춘다** (2026-09-11, 소유자). 근거 둘이다. 살리려면 일이 너무 커지고(아래),
블리자드가 개체창 클릭에 안 주는 것이 이미 답이다.

구현은 2026-09-13에 옮겨 갔다. 세 속성은 모든 경로에서 꺼져 있고, 클릭캐스팅 갈래는 조합키 칸을 묻지
않고 [없음]으로 둔다(`implementing-focus-and-self-cast.md` §3-10).

### 접기는 안 만든다 (2026-09-11, 소유자)

**수식 키를 쥔 프레임 클릭은 정확히 맞는 바인딩이 있을 때만 우리에게 온다.** `ClickCastKeys[n][mod]`
조회가 정확 일치고, 안 맞으면 클릭이 그대로 프레임으로 흘러간다. `BUTTON2`만 걸어둔 사람이 알트를
쥐면 아무 일도 안 일어난다.

**그게 블리자드와 같다** (2026-09-11 게임에서 잼, 소유자). 애드온을 전부 끄고 블리자드 클릭
바인딩에 가운데 버튼으로 주문을 걸면, `CTRL-버튼3`·`ALT-버튼3`·`SHIFT-버튼3`은 하나도 안 받는다.
키 경로가 접히는 것(§2-3)은 바인딩 시스템이 해주는 것이고 클릭캐스팅은 속성 시스템이라 그 접기가
없다.

**접으려 하면 커진다.** 쥔 수식 키가 하나가 아닐 수 있어서 후보가 부분집합 위를 걷게 되고(셋이면
정확 일치 말고 7개), 같은 크기끼리 순서를 정할 근거가 없다. 뜻으로 풀려면 쥔 것 중 어느 키가 시전
수식 키인지를 알아야 하는데 제한 환경에 `GetModifiedClick`이 없다. 남의 것을 뺏지 않으려면 칸마다
`<접두사>type<접미사>`를 읽어 양보해야 하고, 개체창 클릭에는 속성보다 앞서는 `C_ClickBindings`가
또 하나 있는데 그쪽은 스니펫이 물어볼 수도 없다. 전부 접기 하나를 위해 서는 것들이라 같이 없어진다.

## 2-2. 대상을 지정하면 자동 자가시전이 절반만 돈다

`UnitExists` 가드([SecureTemplates.lua:721-723](../reference/wow-ui-source/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua))가
`unit`이 붙었는데 그 유닛이 없는 클릭을 **시전 핸들러에 닿기 전에** 버린다. 자동 자가시전은 시전이
일어난 뒤의 일이라 낄 자리가 없다.

**같은 설정 안에서 답이 갈린다** (2026-09-11 게임에서 잼, 소유자).

| 액션의 대상 | 그 유닛의 상태 | 이로운 주문을 누르면 |
|---|---|---|
| `Target` | 적을 잡고 있다 | 시전이 나가고 자동 자가시전이 고친다 |
| `Target` | 대상 없음 | 아무 일도 안 난다 |
| `Focus` | 포커스가 적이다 | 시전이 나가고 자동 자가시전이 고친다 |
| `Focus` | 포커스 없음 | 아무 일도 안 난다 |

**어느 쪽이 옳으냐 이전에 둘이 다른 것이 잘못이다** (소유자). 돌든 안 돌든 하나여야 한다.

**꺼지는 쪽으로 맞춘다** (2026-09-11, 소유자). 사람이 대상 메뉴에서 대상을 직접 골랐으면 그 액션은
거기로만 간다. 그게 그 항목을 고른 뜻이고 문장 하나로 설명된다. 반대 방향은 "`Target`을 골라
놨는데 왜 나한테 나가느냐"를 설명해야 한다.

**끄는 길은 매크로 몸통이다** (2026-09-11, 소유자). 구운 모양은 이렇다.

    /run DebindAutoSelfCast=GetCVar("autoSelfCast");SetCVar("autoSelfCast","0")
    /click DebindCastButton deb101
    /run SetCVar("autoSelfCast",DebindAutoSelfCast)

시전은 그대로 그 버튼이 한다. `*type-deb101`과 `*spell-deb101`이 이미 구워져 있어서 보안 경로가
안 바뀐다.

**버튼마다 쌍둥이를 하나 더 굽는다.** 이름은 `deb101-nosc`이고 `*type-`이 `macro`, `*macrotext-`가
위 세 줄이다. 클릭 순간에 문자열을 만들거나 속성을 쓰는 대신 리빌드가 미리 굽는 것이라 핫패스가
조회 하나로 끝나고, 몸통이 스펙이 읽을 수 있는 값이 된다. 어느 쪽으로 내보낼지는 클릭 경로가
정한다(`SELFCAST_OFF_SNIPPET`).

**안쪽 `/click`은 `DebindClickButton`으로 못 보낸다.** 그 프레임에는 래퍼가 걸려 있고, 래퍼의
서두가 도착하자마자 맨이름 `unit`을 지운다. 방금 확정한 대상을 그 클릭이 지워버리는 것이라,
이 절이 지키려던 것이 정확히 깨진다. 그래서 래퍼가 안 걸린 자식 프레임 `DebindCastButton`을
따로 세우고 그쪽으로 보낸다. `useparent*`로 구운 속성을 그대로 물려받으므로 시전은 같은 것이
나간다.

`useOnKeyDown`은 그 프레임에 거짓으로 박는다. 안쪽 `/click`이 엣지를 안 실어서 언제나 up으로
도착하는데, 사용자의 `ActionButtonUseKeyDown`이 켜져 있으면 게이트가 거짓이 되어 **아무 일도 안
나고 아무 말도 안 난다.** 클릭캐스팅 갈래가 같은 이유로 같은 값을 박는다.

**우리가 속성으로 넣은 몸통 안에서 Lua가 돈다.** `DevSeed.lua`의 hover 행들이 이미
`/script print(...)`를 그렇게 굽고 있고 게임에서 돌고 있다. 이 길이 열려 있다는 증거가 리포 안에
있었다.

**`SetCVar`는 전투 중에 된다** (2026-09-11, 소유자). 블리자드 매크로가 이미 그렇게 쓰고 있고,
매크로텍스트에서만 막힐 이유가 없다.

**주문과 아이템만이다.** 매크로 타입은 바깥이 매크로가 되면 안쪽 매크로가 안 돈다. 그리고 자동
자가시전이 걸리는 것도 그 둘뿐이다.

**유지·시전 주문은 뺐다.** 매크로는 한 번 돌고, 누를 때 시작해 뗄 때 놓는 게이트의 두 엣지를 그
한 번이 못 나른다. 감싸면 대상을 지킨 대신 주문이 안 끝난다. 그래서 그 주문들은 지금 동작 그대로
두고, 이 절이 고친 "같은 설정 안에서 답이 갈린다"가 거기서만 남는다. 감싸려면 엣지 두 번을 태우는
설계가 따로 필요하다. 스마트캐스트 갈래는 어느 host를 달고 있든 평범한 주문이라 감싼다.

**`autoSelfCast` 값을 굽지 않아도 된다.** 매크로 안의 `/run`이 그 자리에서 읽고 그 자리에서
되돌린다. 전투 중에 값이 바뀌어도 다음 클릭이 새 값을 읽는다. 한때 이 절은 값을 구워 두고 전투 중
변경을 대화창에 알리는 설계를 들고 있었는데, 스니펫이 CVar를 못 읽는다는 것만 보고 세운 것이었고
매크로 쪽 길을 안 봤다.

`RESOLVE_UNIT_SNIPPET`의 `unit or "raid41"`은 그대로 둔다. 지목한 유닛이 없을 때 아무 일도 안
일어나게 하는 것이 이 결정과 같은 방향이다.

**포커스 수식 키로 들어온 경우는 여기서 안 고친다.** 그 `"focus"`는 우리 스니펫이 끝난 뒤
블리자드가 넣는 값이라 우리가 보지도 고치지도 못한다. 그리고 그것은 클라이언트가 자기 기능에서 늘
하던 동작이고 액션바에서 겪던 것과 같다. 이 절이 문제 삼은 것은 **우리 대상 메뉴**가 같은 설정
안에서 답이 갈리는 것이다.

## 2-3. 수식 키가 붙은 누름은 게임이 알아서 떨어뜨린다

**잰 것** (2026-09-11, 소유자). `SetOverrideBinding`으로 `F9`에 걸어 두면 `ALT-F9`를 눌러도 그것이
돈다. 그런데 `ALT-F9`가 실제로 걸려 있으면 안 잡는다. 정확한 것이 먼저고, 없을 때만 떨어진다.

**그래서 우리가 `MOD-X`를 집을 이유가 없다.** 게임이 이미 우리가 원하던 우선순위대로 보내 준다.
사람이나 게임이 `MOD-X`에 무언가를 걸어 두었으면 그쪽이 이기고, 비어 있으면 우리 `X`가 받는다.

**포커스 시전은 우리 키에서 이미 돈다** (2026-09-11 게임에서 잼, 소유자). `F9`에만 걸어 두고
`ALT-F9`를 눌렀더니 액션이 안 나갔는데, 안 나간 이유가 우리가 못 받아서가 아니었다. `ALT`가 그
사람의 포커스 시전 수식 키라 블리자드가 그 갈래를 태웠고, 포커스가 없어서 `UnitExists` 가드에
걸린 것이다. 같은 자리에서 `SHIFT-F9`를 누르니 액션이 정상으로 나갔다.

**그러니 포커스 시전을 우리가 만들 것이 없다.** 2026-09-13에 뒤집혔다. 가리킨 유닛이 조합키를 이기는
블리자드 순서가 틀렸다고 보고 우리가 처리한다(`implementing-focus-and-self-cast.md`).

**`F9`와 `ALT-F9`가 같은 문을 지난다.** 게임이 그 누름을 `F9`의 바인딩으로 보내고(위 측정),
`SetBindingClick`으로 건 키는 **버튼 이름**으로 우리 버튼을 클릭하며, 래퍼는
`ClickTimeKeys[button]`으로 목록을 찾는다. 키 문자열이 아니다. 그래서 `ALT-F9`로 들어와도 `F9`의
목록이 나오고, 우리 쪽 승자 선택은 수식 키를 아예 안 본다.

**그래서 수식 키 조합마다 따로 세울 것이 없다.** 키 하나만 걸어 두면 그 키의 수식 키 조합 전부가
그 문으로 들어온다. 갈래를 고르는 코드도 한 벌이면 된다. 프레임 클릭에서 래퍼 하나가
`ALT-BUTTON2`와 `BUTTON2`를 같이 받는 것과 같은 모양이다.

**사람이 `ALT-F9`를 직접 걸면 그건 다른 문이다.** 그때는 게임이 `ALT-F9`의 바인딩으로 보내므로
`F9`의 목록이 안 나온다. 두 조합에 각각 액션을 걸어 둔 사람에게 그것이 맞는 동작이고, 우리가
가를 것이 없다.

**한때 반대로 적혀 있었다.** `MOD-X`가 `X`와 다른 키라 누름이 우리에게 오지 않는다고 보고, 그
위에 "포커스 시전은 우리가 구현해야 돈다", "전역으로 켜면 남의 키를 뺏는다", "액션마다 켜는
체크박스를 둔다"를 세웠다. 위의 측정이 그 전제를 무너뜨렸고 셋 다 필요 없어졌다.

## 3. 규칙 하나로 선다

**우리가 `unit`을 채우는 자리는 전부 사람이 대상을 지목한 자리고, 거기서는 게임의 대상 보정이
꺼진다.** 수식 키 시전은 `unit`이 있으면 그 자리에 못 오고(§2-1), 자동 자가시전은 우리가
끈다(§2-2).

**문이 둘이다.**

- **대상 메뉴에서 골랐다.** `Target`, `Focus`, `Tank` 같은 것들이다.
- **개체창을 가리켰다.** 클릭캐스팅과 개체창 조건이 붙은 액션이 여기다. 가리킨 행위 자체가
  지목이다.

**지목을 거두면 보정이 돌아온다.** `Don't use the action on the hovered frame's unit`을 켜면
`unit`이 비고, 그때는 게임이 정한다. 대상 메뉴의 `Disable`도 같은 자리다.

이 한 문장이 대상 메뉴의 뜻을 또렷하게 만든다. `Disable`은 게임이 정하게 두는 것이고, 대상을
고르는 것은 거기로만 보내는 것이다.

### 3-1. 도움말이 이걸 자세히 말한다 (2026-09-11, 소유자)

**우리가 하루 종일 헷갈린 자리다.** 만든 쪽이 이만큼 헷갈렸으면 읽는 쪽은 알 길이 없다. 그래서
언제 자가시전이 서고 언제 안 서는지를 도움말이 **자세히** 말한다. 한 편에 안 들어가면 여러 편으로
나눈다. 짧게 줄이는 것이 목표가 아니다.

**코드의 말로 쓰면 안 된다.** `unit`이니 속성이니 하는 것은 읽는 사람에게 없는 말이다. 사람이
화면에서 한 일로 적어야 한다. 대상을 골랐는가, 개체창을 가리켰는가, 아무것도 안 했는가.
`writing-user-facing-text.md`가 그 규칙이다.

**자가시전이 둘이라는 것부터 갈라야 한다.** 수식 키를 누르는 것과, 못 쓸 대상일 때 저절로 자기한테
가는 것은 다른 물건인데 이름이 비슷하다. 클라이언트도 설정 패널에서 그 둘을 한 줄에 묶어 네 상태로
보여준다(`Blizzard_SettingsDefinitions_Frame/Combat.lua`). 그 묶음을 그대로 따라가면 읽는 사람이
우리 화면과 게임 설정을 이어 붙일 수 있다.

**말해야 하는 갈래.**

- 대상을 안 골랐다. 게임 규칙이 그대로 돈다. 수식 키도 서고 자동 자가시전도 선다.
- 대상을 골랐다. 둘 다 안 선다. 그 액션은 고른 대상에게만 간다.
- 개체창을 가리켜 쓰는 액션. 위와 같다. 가리킨 것이 곧 고른 것이다.
- 개체창의 유닛을 안 쓰겠다고 껐다. 첫 줄로 돌아간다.

**들어간 자리는 `HELP_TARGETING_*`이고, 옵션창 도움말 페이지의 둘째 문이다.** Mouseover Cast는
"안 돈다"가 답인데도 이름을 적었다 - 같은 설정 패널의 네 줄 중 하나라, 빼면 나머지처럼 도는 줄로
읽히고 켜 둔 사람이 키가 고장 났다고 본다.

**2026-09-12에 그 문단의 답이 바뀌었다.** 게임의 Mouseover Cast는 여전히 우리 키에서 안 돌지만,
우리 것이 그 자리에 섰다(`legacy/adding-hover-and-mouseover-cast.md`). 그래서 도움말은 "안 된다,
대신 `Unit Frame` 대상을 써라"에서 "게임 것은 안 되고 애드온 설정의 `Mouseover Cast`와
`Hover Cast`가 그 일을 한다"로 바뀌었고, `Unit Frame` 대상은 액션 하나에만 걸고 싶을 때의 답으로
남았다. 다섯째 문단도 그때 붙었다. 스위치 둘이 무엇에 걸리고 성향을 안 가린다는 것을 말하는
자리다.

## 4. 커버리지: 헤드리스가 원리상 못 재는 것

여기 적힌 것은 **테스트가 무엇을 덮고 무엇을 못 덮는가**이지 누가 해야 할 일의 목록이 아니다.
못 덮는 이유가 구현으로 없어지지 않는 종류라, 이 절은 구현이 끝나도 그대로 선다.

**헤드리스가 덮는 것.** 우리가 내놓는 값까지다. `checkmouseovercast`가 꺼져 있고 나머지 둘이
켜져 있는가, 대상을 지목한 주문이 쌍둥이 버튼을 답하는가, 그 몸통이 어떤 문자열로 구워졌는가,
대상 없는 주문과 유지·시전 주문이 자기 버튼 그대로 나가는가, 시전 프레임의 `unit`에 무엇이
들어갔는가. 전부 값을 견주는 일이라 `tests/eval_spec.lua`가 잠근다.

**헤드리스가 못 덮는 것과 이유.**

- **자동 자가시전.** 엔진 쪽이고 Lua에 없다(§1). 우리가 볼 수 있는 마지막 값은 `unit`뿐이다.
- **`UnitExists` 가드가 클릭을 버리는 것.** `GetConvertedButtonUnitAndActionType` 안이고 스펙은
  거기까지 안 간다. "아무 일도 안 일어났다"와 "시전이 나갔는데 효과가 없다"를 값으로 못 가른다.
- **수식 키 시전.** `IsModifiedClick`이 실제 키 상태를 읽는다. 수식 키가 붙은 누름이 안 걸린
  조합에서 떨어지는 것(§2-3)도 클라이언트의 바인딩 조회라 우리 쪽에 재현이 없다.
- **매크로 몸통이 실제로 무엇을 하는가.** 문자열이 맞게 구워졌는지는 스펙이 보지만, 그 문자열을
  게임이 돌렸을 때 무엇이 나가는지는 못 본다. CVar를 껐다 되돌리는 두 줄이 여기 걸린다.
- **안쪽 `/click`이 시전 프레임에 도착해 물려받은 `*type-`으로 시전하는 것.** 보안 템플릿이
  속성을 받은 뒤의 일이라 스펙이 안 간다.
- **개체창 클릭에 수식 키가 붙은 경우.** 쥔 키를 클라이언트가 읽는 것이라 스펙에 재현이 없다.
  조회가 정확 일치라는 것까지는 값으로 보지만, 실제로 알트를 쥔 클릭이 안 온다는 것은 못 본다.

## 5. 조사 기록

**두 트랙이 같이 쓰는 사실 창고다.** 다시 조사하지 않으려고 남긴다. 중요해 보이든 아니든 이
세션(2026-09-11)에 나온 것을 다 적고, **읽었거나 잰 것**과 **아직 모르는 것**을 갈라 둔다.

### 5-1. 읽은 것 (클라이언트 코드와 문자열)

- `checkmouseovercast` 블록은 `SecureTemplates.lua`의 `SecureButton_GetModifiedUnit`
  [:176-188]. `checkselfcast`가 [:189-194], `checkfocuscast`가 [:195-199]. 순서가 그대로
  우선순위다.
- 수식 키 기본값은 `Bindings_Standard.xml` [:1770-1772]. `SELFCAST`=`ALT`,
  `FOCUSCAST`=`NONE`, `MOUSEOVERCAST`=`NONE`.
- `CalculateAction`은 `GetID() > 0`이 아니면 `GetModifiedAttribute("action") or 1`
  [SecureTemplates.lua:670-688].
- `UnitExists` 가드는 `GetConvertedButtonUnitAndActionType` 안 [:721-723]. `nil`을 돌려주면
  `PerformAction`의 `if button and actionType`에서 멈춘다 [:733].
- 액션 버튼의 마우스 클릭도 `SecureActionButton_OnClick` → `OnActionButtonClick` →
  `GetConvertedButtonUnitAndActionType`을 지난다 [:762, :805]. 키 누름과 갈리는 것은
  `useOnKeyDown` 판정뿐이다.
- 개체창은 `SecureUnitButtonTemplate`이고 `SecureUnitButton_OnClick`을 쓴다
  [SecureTemplates.xml:21, SecureTemplates.lua:844].
- 속성 이름 규칙: 접두사는 `alt-`, `ctrl-`, `shift-` 순 [SecureTemplates.lua:70-90],
  접미사는 오른쪽 버튼이 `2` [:101-113]. 프레임에 `modifiers` 속성이 있으면 접두사 규칙이
  그쪽으로 갈린다.
- **`SecureButton_GetModifiedAttribute`에 수식 키 폴백이 없다** [:118-137]. 접두사를 한 번 만들고
  (`alt-`/`ctrl-`/`shift-` 순, [:70-92]) 조회를 한 번 한다. 없으면 같은 접두사로 부모만 타고
  올라간다. `alt-ctrl-type2`가 `ctrl-type2`나 `type2`로 내려가는 일은 없다. (와일드카드와
  맨이름으로 가는 폴백은 C 쪽에 있다 - 우리 `*type-debind1`이 수식 키를 쥐어도 잡히는 게 그것이다.)
- **개체창 클릭은 속성보다 `C_ClickBindings`가 먼저다** [:844-878]. 주문/매크로/소환수면 거기서
  시전하고 반환한다. `type`이 target/menu/togglemenu인데 클릭 바인딩이 없으면 아무것도 안 하고
  반환한다.
- **`SECURE_ACTIONS.click`은 받은 `unit`을 안 쓴다** [:560-567]. `delegate:Click(button)` 한 줄이
  전부라, 1홉에서 구한 프레임의 유닛이 버려지고 2홉에서 다시 판정된다. 개체창의 유닛이 대상이
  되는 것은 우리가 2홉에서 써 넣기 때문이다.
- `autoSelfCast`를 읽는 곳은 설정 패널 둘뿐이다
  [Blizzard_SettingsDefinitions_Frame/Combat.lua:70, :85-102]. 시전 경로에는 없다.
- `FOCUSCAST`를 읽는 곳은 위 갈래와 설정 패널 둘뿐이다. 개체창 클릭 처리에는 없다.
- `OPTION_TOOLTIP_ENABLE_MOUSEOVER_CAST`는 "mousing over a unit frame and casting a spell using
  a keyboard hotkey". `OPTION_TOOLTIP_AUTO_SELF_CAST`는 "friendly target spells ... while you
  have a non friendly target **or no target**".
- `C_Spell.IsSpellHelpful` / `IsSpellHarmful`은 인자가 `spellIdentifier` 하나다
  [SpellDocumentation.lua:831-861]. `C_ActionBar.IsHelpfulAction`의 `useNeutral`에 대응하는
  것이 없다.
- `C_Spell.GetOverrideSpell`은 `spec`과 `onlyKnown`을 받는다 [SpellDocumentation.lua:165-181].
  문서가 "overrides may vary by Spec"이라고 적는다.
- 제한된 환경에 **있는** 것: `IsSpellHelpful`, `IsSpellHarmful`, `IsHelpfulItem`,
  `IsHarmfulItem`, `PlayerCanAssist`, `PlayerCanAttack`, `IsModifiedClick`, `IsAltKeyDown`
  계열, `UnitExists`, `UnitIsDead`, `UnitIsGhost`, `UnitPlayerOrPetInParty`,
  `UnitPlayerOrPetInRaid`, `FindSpellBookSlotBySpellID`
  [RestrictedEnvironment.lua:84-95, :154-158, :184-190].
- 제한된 환경에 **없는** 것: `GetCVar` 계열 전부, `UnitIsFriend`, `RunBinding`.
- 전투 중에 보호 안 된 프레임의 핸들은 `HANDLE:GetAttribute`에서 **오류를 낸다**
  [RestrictedFrames.lua의 `GetPossiblyForbiddenHandleFrame`]. `SecureHandlerSetFrameRef`는
  `GetFrameHandle(value)`를 보호 표시 없이 부른다 [SecureHandlers.lua:581].
- `@none`은 자동 자가시전을 끊고 조준 커서를 강제한다. 시전에만 있는 개념이고 소환수 명령은 안
  받는다 (`ActionDisplay.lua`의 `none` 주석, 2026-08-05 게임에서 잼).

### 5-2. 읽은 것 (우리 코드)

- 우리 코드 전체에 `SetID(` 호출이 없고 `SetAttribute("action", ...)`도 없다.
- 우리가 남의 프레임에 쓰는 속성은 셋뿐이다. `debind_frametype`, `*type-debind1`,
  `*clickbutton-debind1` [FrameRegistry.lua:832, :926-927]. 수식 키 접두사가 붙은 이름은 안
  쓴다.
- 프레임 다툼을 아는 길은 `SecureHandlerWrapScript` 훅 안의 `ContestedNow`뿐이다
  [FrameRegistry.lua:661]. 남이 건 **속성**은 그 그물에 안 걸린다.
- `EvalClickCastFrame`이 `nil`을 답하면 래퍼가 버튼 이름을 그대로 두고 클릭이 프레임 자기
  핸들러로 간다 [SecureBindings.lua의 그 주석].
- 클릭 경로의 승자 조회는 `ClickTimeKeys[button]`이다. 키 문자열이 아니라 버튼 이름이다.
- `[@유닛]`을 매크로 몸통에 굽는 것은 소환수 명령에서만 한다
  [Misc.lua의 `GetPetActionMacroText`]. 주문과 아이템은 `unit` 속성으로 나간다.
- 클릭캐스팅 경로에서 `unit`은 안 빈다 (소유자).

### 5-3. 게임에서 잰 것 (2026-09-11, 소유자)

- `SELFCAST`를 `CTRL`로 두고 `CTRL-3`에 공격 주문을 걸어 누르면 정상으로 나간다. 해로운 주문에
  붙은 `"player"`를 게임이 무시한다. **지금 설계는 이 사실에 기대지 않는다.** 한때 `"player"`로
  바꿔치는 안을 받치던 값이고, 그 안이 빠진 뒤에도 사실이라 여기 남긴다.
- 자신에게 못 쓰는 이로운 주문을 `@player`로 누르면 **오류 문구가 안 뜬다.** 조용히 안 나간다.
- 대상 `Target`/`Focus`의 네 경우는 §2-2의 표 그대로다.
- `SetOverrideBinding`으로 `F9`에 걸면 `ALT-F9`도 그것이 돈다. `ALT-F9`가 실제로 걸려 있으면
  안 잡는다.
- `F9`에만 걸고 `ALT-F9`를 누르면 액션이 안 나가는데, 그 사람의 포커스 수식 키가 `ALT`여서
  포커스 시전 갈래를 타고 포커스가 없어 가드에 걸린 것이었다. 같은 자리에서 `SHIFT-F9`는
  정상으로 나갔다.
- `DevSeed.lua`의 hover 행들이 `/script print(...)`를 매크로 몸통으로 굽고, 게임에서 돈다.
  **우리가 속성으로 넣은 몸통 안에서 Lua가 실행된다.**
- 애드온을 전부 끄고 블리자드 클릭 바인딩에 가운데 버튼으로 주문을 걸면 **정확히 가운데 버튼만
  받는다.** `CTRL-버튼3`, `ALT-버튼3`, `SHIFT-버튼3`은 하나도 안 받는다.

### 5-4. 아직 모르는 것

- ~~**`IsSpellHelpful`이 주문 대체를 풀고 답하는가.**~~ 안 묻기로 하면서 물음 자체가 없어졌다
  (2026-09-12). 성향을 아무 데서도 안 읽는다
  (`legacy/adding-hover-and-mouseover-cast.md` §0).
- **`IsModifiedClick`이 수식 키가 `NONE`일 때 거짓인가.** 문서에 없다. 블리자드가 마우스오버
  시전에서만 `GetModifiedClick(...) == "NONE" or IsModifiedClick(...)`으로 따로 받아 준 것이
  근거다. 두 군데가 같은 꼴이라 거짓일 것으로 본다.
- **자동 자가시전이 아이템에도 걸리는가.** 클라이언트 문구는 주문만 말한다. 소유자는 걸릴
  것으로 본다.
- **매크로 조건절의 `@유닛`이 그 유닛이 없을 때 어떻게 되는가.** `UnitExists` 가드는 `unit`
  속성을 보는 것이라 매크로 경로는 안 지날 것으로 읽었지만, 안 쟀다.

### 5-5. 곁가지로 확인된 것

- `TOGGLEAUTOSELFCAST` 바인딩이 `lockActionBars`를 쓴다 [Bindings_Standard.xml:391-394].
  블리자드 쪽 실수로 보이고 우리와 무관하다.
- `HelpTip:IsShowingAnyInSystem`이 `frame.info.system`을 바로 읽어서, 풀에 `info` 없는 프레임이
  섞이면 터진다 [HelpTip.lua:314-320]. 가방을 여는 길에서 나온 오류가 그것이고 우리 스택은 한
  줄도 없다.
