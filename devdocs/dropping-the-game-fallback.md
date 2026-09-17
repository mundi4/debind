# 게임으로 돌려주는 길을 없앤다

> 상태: 구현 중. BLOCK과 상태 루프의 키 몫 걷어내기(§9-4의 답), 계산식 스위치를 누를 때 재기와 박자 좁히기, 스위치 알림
> 전역 옵션, `GetHoveredUnit`, 대전 키 양보(§5-1), 행동 단축키 액션과 행동 칸 `COMMAND`의 마이그레이션(§4)은 들어갔다.
> 타입 메뉴와 카탈로그에서 두 타입을 뺐고 README를 고쳤다. 남은 것은 저장된 두 타입의 이슈 표시(§3)다. 걷어내기로 했다 (2026-09-14, 소유자). 막히는 곳은 없다는 데까지 쟀다 (2026-09-14, retail과
> xptr, `DebindDev/Probe_ActionBars.lua`). 바뀐 액션 바는 행동 단축키 액션이 칸을 계산해 쏘고(§4), 애완동물 대전은
> 대전 동안 행동 단축키 1~5의 키만 놓는다(§5). `UNUSED`와 옮길 곳이 없는 `COMMAND`는 BLOCK이 된다(§3). 계산식
> 스위치는 누를 때 재고, 박자는 `displayMessage`가 켜진 계산식 스위치에만 남아 전역 옵션으로 끈다(§3). 쓸 수 있는
> 전략은 §7, 바마다 켜지는 이벤트와 판별은 §8, 구현 세션이 먼저 알아야 할 것은 §9다. 고칠 자리(§3)는 코드를 세어 본
> 것이 아니라 읽은 자리로 적었다. 범위는 손대기 전에 다시 센다.

## 1. 왜 나온 이야기인가

`UNUSED`와 `COMMAND`는 클릭 래퍼로 오지 않는다. `UNUSED`는 키를 놓고(`ClearBinding`), `COMMAND`는 키를 명령에
건다(`SetBinding`). 조건이 끝나는 자리의 틈도 같다. 마지막 액션 뒤에는 조건 없는 `UNUSED`가 암묵적으로 있고,
`IsKeyAlwaysOurs`의 센티넬이 그것이다. 그래서 키마다 "지금 잡느냐, 놓느냐, 명령에 거느냐"를 누르기 전에
정해야 하고, 상태 루프가 그 일을 한다.

쌍둥이와 층이 들어오면서 이것이 두 구멍이 됐다(`devdocs/implementing-focus-and-self-cast.md` §3-9). 루프는
조합키를 모르니 층을 못 가르고 첫 매치로 키를 정한다.

- **A.** 조합키 층의 `UNUSED`·`COMMAND` 쌍둥이가 맞으면 키를 놓거나 명령에 걸어, 뒤 액션의 클릭 쌍둥이가
  받을 조합키 누름이 래퍼에 안 온다.
- **B.** 조합키 층의 클릭 쌍둥이가 맞으면 키를 클릭으로 잡아, 조합키 없는 누름에서 뒤의 `COMMAND`가 안 나가고
  `UNUSED`나 틈이 게임에 돌려주지 못한다.

없애면 §3-9가 감수한 대가(쌍둥이만 맞아 키를 잡는 동안 조합키 없는 누름이 먹힌다)도 따로 떠안을 것이 아니게
된다. "맞는 것이 없으면 아무것도 안 한다" 하나로 액션 바와 같다.

**얻는 것은 주기적인 루프가 없어지는 것이다.** `COMMAND`, `UNUSED`, 틈에서 흘려주는 것을 내주는 값이 그것이라, 이
이득을 되돌리는 안은 받지 않는다. 남는 박자는 `displayMessage`가 켜진 계산식 스위치 하나이고, 전역 옵션으로 끄면
그것도 없다(§3의 스위치 이야기).

## 2. 전제

**Debind 액션이 하나라도 걸린 키는 늘 우리 것이다.** 명시적 `UNUSED`, `COMMAND` 타입, 틈에서 블리자드 바인딩으로
떨어지는 것을 모두 없앤다. 어떤 레코드도 안 맞는 누름은 아무것도 안 한다.

**지금 동작을 전역 옵션 뒤에 남기는 안은 안 한다** (2026-09-14, 소유자). 옵션을 켜면 `COMMAND`, `UNUSED`, 틈이 지금처럼
돌고, 끄면 이 문서대로 도는 안이었다. 기능은 그쪽이 많고 §6에서 잃는 것이 없다. 안 하는 이유는 넷이다.
- 옵션을 끈 쪽이 곧 이 문서라 BLOCK, §4, §5는 그대로 다 만들어야 한다. 그 위에 키를 걸고 놓는 루프
  (`StateDrivenBindings`, `DirtyKeys`, `_commandKeys`, `GetSettledBinding`, `IsKeyAlwaysOurs`와 센티넬, 키 몫의 측정
  축)를 통째로 더 짊어진다.
- 옵션을 켠 쪽에는 §1의 A와 B가 남는다. 고치든지 알고 내보내든지 해야 한다.
- 레코드, 층, 쌍둥이, 조건을 손볼 때마다 클릭 시점 판정과 루프 판정 두 벌이 맞아야 하고, 틀려도 오류가 안 난다.
- 가져온 프로필이 받는 쪽의 옵션에 따라 다르게 돈다.

런타임 비용은 판단에 안 들었다. 옵션을 끈 사람은 이 문서와 같고 켠 사람만 지금의 비용을 낸다.

## 3. 고칠 자리

**타입.**
- `Constants`의 `UNUSED`, `COMMAND`는 남는다. 저장된 액션과 가져온 문자열이 계속 들고 오고, 파생이 그것을 보고
  BLOCK을 만든다(아래 "저장된 프로필과 가져오기").
- 새로 만드는 길만 막는다. 타입 메뉴와 카탈로그에서 뺀다. 행이 그 이름을 그리니 로케일 문자열(`TYPE_COMMAND`,
  `TYPE_UNUSED`)과 행 표시(`ActionDisplay.lua`)는 남기고, 이슈 문구가 더해진다. README는 두 타입이 더는 안 나간다는 것을
  적는다.
- 지우는 갈래는 키 배선 쪽뿐이다(아래 "리빌드"). 행 표시, 가져오기, 액션 쪽 이슈 검사는 두 타입을 계속 읽는다.
- BLOCK을 새로 둔다. 바인딩에만 서는 타입이고 저장되지 않는다.
- 행동 단축키 액션을 새로 둔다(§4).

**저장된 프로필과 가져오기** (2026-09-14, 소유자).
- **옮길 곳이 있는 액션만 마이그레이션한다.** 행동 칸을 누르는 `COMMAND`는 §4의 액션으로 옮긴다.
  `ACTIONBUTTON1`~`12`는 바뀐 바를 따르는 주 바, `MULTIACTIONBARkBUTTONn`은 페이지가 고정된 바(§4-3),
  `EXTRAACTIONBUTTON1`은 기타 행동 버튼(§4-2)이다. 마이그레이션 단계 하나와 가져오기(`Import.lua`)가 같은 대응표를
  쓴다. 공유 레이어에 든 것도 같다. 나머지 명령 중 대응표에 더할 것이 있는지는 아직 안 봤다(`VEHICLEEXIT`은
  `/leavevehicle` 매크로가 된다, §4-7).
- **`UNUSED`와 옮길 곳이 없는 `COMMAND`는 저장된 그대로 둔다.** 액션에서 바인딩을 파생할 때(`FillBinding`) 바인딩의
  타입만 BLOCK으로 만든다. 그 키에서 뒤 액션이 대신 나가는 일이 없고, 누르면 아무것도 안 한다. 흐름이 액션에서
  바인딩으로 한 방향이라 저장된 값은 안 바뀐다.
- **행은 액션 그대로 그리고, 이슈 마크로 알린다.** "월드 지도"나 "사용 안 함"이 그대로 보이니 사용자가 무엇이었는지
  보고 매크로로 다시 만들지 지울지 고른다. 이슈 등급은 WARNING이어야 한다. `BuildKeyMap`은 ERROR만 키에서
  빼므로(`IssueKeepsKey`), ERROR면 BLOCK이 키에 안 올라가 뒤 액션이 나간다.
- **이렇게 두는 이유.** 명령 이름을 잃지 않고, `dbver`를 안 올리니 같은 SavedVariables를 옛 버전이 읽어도 그대로 돌고,
  마이그레이션이 BLOCK을 저장된 액션으로 넣었을 때 목록에 어떻게 보일지라는 물음이 없어진다. 가져오기도 두 타입을
  받아 그대로 저장한다.
- **액션의 `type`을 읽는 곳을 가른다.** 파생 뒤에도 액션 쪽은 `COMMAND`·`UNUSED`다. 본 곳은 `IsKeyInvalidForAction`의
  `action.type == Constants.COMMAND`(`Misc.lua`) 하나다. 나머지는 구현 전에 찾아 액션을 읽는지 바인딩을 읽는지
  인자를 따라가며 가른다.

**BLOCK: 아무것도 안 하는 내부 타입** (2026-09-14, 소유자).
- **키마다 맨 끝에 BLOCK을 붙이면 상태 루프의 키 몫이 멎는다.** `IsKeyAlwaysOurs`가 키를 돌려준다고 보는 것은
  `UNUSED`, `COMMAND`, 센티넬(아무것도 안 맞음)뿐이다(`Solver.lua`의 `handsBack`). 조건 없는 BLOCK이 끝에 서면
  센티넬이 덮여 키가 `alwaysOurs`가 되고 `stateDriven`이 거짓이다. 루프 코드는 남고 키에 대해서는 할 일이 없어진다.
- **self와 focus 쌍둥이는 있어야 한다.** 원본에는 조합키 칸 [없음]이 붙어서(`implementing-focus-and-self-cast.md`
  §3-5) 원본만으로는 센티넬의 self, focus 영역을 못 덮는다. 다른 액션과 같은 쌍둥이 생성(§3-4)을 타면 세 층의 합이
  센티넬을 덮는다. 조합키 누름은 원래 떨어지지 않으니(§3-2) 쌍둥이가 동작을 바꾸지 않는다.
- **hover 쌍둥이는 없어도 된다.** 원본의 [없음]이 가리킨 유닛이 있든 없든 덮는다. 있으면 3층 순서에서 사용자의
  hover 쌍둥이 앞에 설 수 있다. 각 층의 맨 끝에 선다.
- **키에 걸려야 한다.** `PrepareKeyBindings`는 걸 수단이 없는 레코드를 떨구고 `holdsKey`를 안 준다. BLOCK은
  이긴 순간 키 래퍼가 `false`를 돌려주는 클릭 레코드로 둔다.
- **래퍼의 `false`는 클릭을 통째로 끊는다.** `Wrapped_Click`이 그 자리에서 돌아가서 감싼 버튼의 원래 `OnClick`도
  post 본문도 안 돈다(`SecureHandlers.lua:272-290`). 키 누름은 이미 오버라이드로 우리 프레임에 왔으니 거기서 끝나는
  것이 맞다. 개체창 클릭에서 `false`면 개체창의 대상 잡기와 메뉴까지 끊긴다. 아무것도 안 돌려주면(`return`) 프레임의
  원래 동작으로 흘러간다(`SecureBindings.lua`의 `UnitFrameClickPre` 본문).
- **키 누름에서는 `false`, 개체창 클릭에서는 흘려준다. 출처로 가를 필요가 없다** (2026-09-14, 소유자). 소유자는
  `COMMAND`를 대신한 BLOCK은 개체창 클릭에서도 `false`, `UNUSED`나 틈을 대신한 BLOCK은 예전처럼 흘려주도록 가르자고
  했다가, `COMMAND`가 개체창 래퍼에 올 길이 없다는 것을 보고 거뒀다. 지금 코드와 맞춰 본 것이다.
  - **`COMMAND`는 개체창 래퍼에 안 온다.** `isClickCast`가 `COMMAND`를 빼고(`UpdateBindings.lua`의
    `PrepareKeyBindings`), hover가 걸린 `COMMAND`를 마우스 버튼에 걸면 ERROR 이슈
    (`BINDING_ISSUE_NOT_SUPPORTED_HOVER_CLICK_COMMAND`, `Misc.lua`의 `IsKeyInvalidForAction`)라 키에 안 오른다.
    그 예외와 이 ERROR는 지웠다 (2026-09-14, 소유자). ERROR가 액션을 키에서 빼면 BLOCK이 안 서고 뒤 액션이
    나가기 때문이다. 이제 hover가 걸린 저장된 `COMMAND`는 `UNUSED`와 같이 `clickbutton` 없는 클릭캐스팅 BLOCK이
    되어 개체창 클릭을 흘려준다.
  - **`UNUSED`는 이미 흘려준다.** hover가 걸린 `UNUSED`는 클릭캐스팅 레코드가 되고, 개체창 래퍼에서 이기면
    `clickbutton`이 없어 `return`이다. 그것을 대신한 BLOCK은 `isClickCast`를 물려받고 같은 답을 낸다.
  - **틈도 이미 흘려준다.** 맞는 것이 없으면 `return`이다. 덧댄 BLOCK은 hover 조건이 없어 클릭캐스팅 레코드가 안 된다.
- **활성 레이어의 액션이 걸린 키는 빌드에서 빠진 액션뿐이어도 잡는다** (2026-09-15, 소유자). 전문화 조건,
  `known`, 걸 수단 없음, 액션 쪽 ERROR로 빠지는 것은 리빌드가 답을 미리 안 것이라, 구웠다면 누름마다 지고 키는
  아무것도 안 했다. 빠진 채로 키를 놓으면 블리자드 바인딩이 나가서 최적화가 동작을 바꾼다. `BuildKeyMap`이 거르기
  전에 `KeysToHold`에 적고, `UpdateBindingsMap`이 그 키를 BLOCK만으로 건다. Cast Options를 넷 다 꺼 바인딩이
  하나도 없는 액션도 같다(2026-09-17, 소유자). 놓는 것은 셋이다. hover가 걸린 마우스
  버튼 액션(개체창으로 나가고 키를 안 잡는다. 맨 왼쪽/오른쪽 클릭은 늘 이것이다), 양보 중인 키, `key` 갈래 이슈(게임 메뉴 키는
  잡으면 ESC가 죽는다). 받아들이기 전의 가져온 액션은 원래대로 키에 안 닿는다. 잡혔는지는
  `IsKeyOurs`가 답한다.
- **덮기 판정이 실패해도 동작은 맞다.** 작업 예산이 끝나면 `IsKeyAlwaysOurs`가 아니라고 답하고 그 키는 루프에
  남는다. 루프에서도 BLOCK이 마지막에 맞아 키를 클릭으로 잡고, 누름은 아무것도 안 한다.

**리빌드.**
- `ClassifyKey`: 키 레코드가 있는 키는 전부 클릭 시점이면서 배선 고정(`alwaysOurs`)이 된다. `stateDriven`은
  늘 거짓이다.
- `IsKeyAlwaysOurs`와 센티넬은 물을 것이 없어져 지운다. BLOCK으로 가는 동안에는 그대로 두고 BLOCK이 덮게 한다.
- `GetSettledBinding`과 명령 오버라이드 경로(`_commandKeys`)를 지운다.
- `PrepareKeyBindings`의 두 타입 예외(걸 수단이 없어도 안 떨구는 것, `COMMAND`는 클릭캐스팅이 못 되는 것)를
  지운다.
- `DescribeBinding`의 "self-bound" 갈래를 지운다.

**상태 루프.**
- 키를 걸고 놓는 부분(`StateDrivenBindings`, `DirtyKeys`, 결과 셋으로 갈리는 분기)을 지운다.
- 키 때문에 재던 축(`_measuredStates`, `_measuredUnitAxes` 중 키 레코드 몫)도 같이 빠진다.
- **매크로 본문과 계산식 스위치도 루프가 구울 필요가 없다** (2026-09-14, 소유자). 실행이 안 되면 쓰이는 데가 없고,
  실행이 되면 클릭 래퍼가 그 자리에서 할 수 있다. 버튼의 매크로 본문은 이미 `DeferredMacroTexts`로 클릭 때
  굽는다(`UpdateBindings.lua`의 `EmitMacroTextEntries`). 루프에 남은 것은 계산식 스위치의 식(`MacroTextsMap`의
  `$` 이름)과 그 값을 재는 "Update Switches"다. 스위치 값을 읽는 것은 조건(`t.switches`)과 매크로 인자(`arg.state`)라
  둘 다 클릭 때다.
- **계산식 스위치는 누를 때 잰다** (2026-09-14, 소유자). 지금 클릭 판정은 조건(`t.switches`)도 매크로 인자
  (`arg.state`)도 `States`의 값을 읽고, 계산식 스위치의 그 값을 채우는 것이 박자다. 다른 축과 같이 `EVAL_SNIPPET`의
  클릭 1회 메모에 스위치를 더한다. 식에 유닛 인자가 있으면 `COMPOSE_MACROTEXT_SNIPPET`로 조립하고, `@hover`는 그
  클릭이 읽은 `hoverUnit`을 쓴다(`BAKE_WINNER_MACROTEXT_SNIPPET`과 같은 길). 값이 바뀌었으면 `SetSwitch`로 알린다.
- **클릭 때만 재면 두 가지가 따라온다.** 스위치 탭은 `definition.value`를 그리는데(`SwitchesUI.lua`) 그 값을
  채우는 것이 `OnSwitchChanged` 보고라, 누르기 전까지 옛 값이 보인다. 바뀔 때 알리는 옵션(`displayMessage`)도 누를
  때 뜬다. 알림은 아래 박자가 맡고, 탭의 값은 알림이 꺼진 스위치에서 누를 때 따라온다.
- **보안 쪽은 창이 떠 있는지 묻지 않고, 스위치가 바뀔 때마다 `CallMethod`로 알린다** (2026-09-14, 소유자). 지금의
  `SetSwitch`가 이미 `OnSwitchChanged`를 부른다. 보여 줄지는 비보안이 정한다. 창의 상태를 제한 환경에 넘기는 길은
  둘 다 버렸다. Debind 창은 전투 중에도 열리고 닫힌다.
  - **전투 시작에 기록.** `PLAYER_REGEN_DISABLED`에는 아직 잠금이 아니라 창의 `IsShown()`을 드라이버 속성에 쓸 수
    있지만, 전투 중에 창을 열고 닫는 것이 안 따라온다.
  - **창에 보호 프레임 자식을 둔다.** 보호 프레임 핸들의 `IsVisible()`은 전투 중에도 읽히지만, 보호 자식을 가진
    창은 암묵적으로 보호되어 전투 중 `Show`/`Hide`가 막힌다(클라이언트 동작으로 알려진 것).
  - 보호되지 않은 프레임을 참조로 넘긴 핸들의 `IsShown`은 전투 중 `Invalid frame handle`로 멈춘다
    (`RestrictedFrames.lua:79-85`의 `not InCombatLockdown()` 조건). 밖에서 미리 넘겨도 부를 때마다 검사한다.
- **클릭이 없는 동안 전투 중에 스위치를 계산할 주체가 없다.** 계획은 UI가 떠 있는 동안 비보안이 주기적으로 제한
  환경에서 당겨 오는 것이었는데, `SecureHandlerExecute`가 전투 중 막혀서 안 된다(`SecureHandlers.lua:435-440`).
  비보안이 `SecureCmdOptionParse`로 식을 직접 조립해 재는 길은 안 한다. 식 조립이 두 벌이 되어 탭에 보이는 값과 누를
  때 쓰는 값이 갈릴 수 있다.
- **계산식 스위치가 있으면 박자(`RegisterUnitWatch`)를 통째로 남기는 안은 버렸다** (2026-09-14, 소유자). §1의 이득을
  반토막 낸다.
- **박자는 `displayMessage`가 켜진 계산식 스위치에만 일단 남긴다** (2026-09-14, 소유자). 알림은 누르지 않아도 스위치가
  바뀔 때 떠야 하는데, 그 순간을 아는 것이 박자뿐이다. 루프는 그 스위치의 식만 굽고, 알림이 꺼진 계산식 스위치는
  루프에 안 들어간다.
- **그 스위치가 식에서 읽는 계산식 스위치도 박자에 오른다** (`PutOnBeat`). 누름 사이에 값을 새로 내는 것이 박자뿐이라,
  누를 때만 새로 나는 값을 읽으면 지난 누름의 답을 읽는다.
- **스위치 알림을 완전히 끄는 전역 옵션을 둔다** (2026-09-14, 소유자). 끄면 `displayMessage`가 켜진 스위치도 루프에서
  빠지고, 박자를 원하는 것이 남지 않는다.
- **박자를 켜는 조건(`WantsStatePoll`)에서 지금 코드가 괜히 켜는 두 가지를 뺀다** (2026-09-14, 소유자). 둘 다 이번
  변경과 무관하게 지금도 박자가 할 일이 없다.
  - **수동 스위치.** 값은 `SetSwitch`가 `States`에 바로 쓰고, 리빌드의 `BuildSwitchesSnippet`이 저장된 값으로 채우며,
    루프는 이 이름에 대해 굽는 줄이 없다. 그런데 `stateDriven`이 아닌 키에서도 `_switches[k]`이면 `_measuredStates`에
    들어가 `next(_measuredStates)`만 참으로 만든다. 계산식 스위치가 아니면 넣지 않는다.
  - **hover.** `units["hover"]`를 든 레코드는 `stateDriven`와 상관없이 `_unitsSeen.hover`를 세우고, 그것이 박자를 켠다.
    박자를 켜는 조건은 알림이 켜진 계산식 스위치의 `@hover` 인자로 좁힌다.
- **별칭 유닛과 hover는 루프 없이 선다** (2026-09-14, 코드로 읽음).
  - `UnitAliasMap`을 쓰는 곳은 `SetUnit` 하나이고, 부르는 쪽은 `UnitWatch.lua`(로스터와 역할 이벤트), 개체창
    enter/leave 래퍼(`SecureBindings.lua`의 `setup_onenter`/`setup_onleave`), 그리고 루프의 hover 폴링이다.
  - 클릭 판정은 캐시를 안 믿는다. `UnitStates`는 루프가 채우는 캐시라 클릭은 유닛마다 다시 재고
    (`SecureBindings.lua`의 "The cache is not trusted here"), 별칭은 `UnitAliasMap`을 그 순간 읽는다. hover는
    `States.unitframe`(enter/leave가 씀)의 프레임에서 유닛을 직접 읽는다.
  - 루프의 hover 폴링(`UpdateBindings.lua`의 `if (States.unitframe)` 블록)이 하는 일은 커서가 멈춘 채 프레임의
    유닛이 바뀔 때 `UnitAliasMap["hover"]`를 따라잡는 것이다. 클릭은 그 값을 안 쓰니, 이 폴링에 기대는 것은 루프에
    남은 계산식 스위치의 `@hover` 인자뿐이다. 위의 스위치 이야기와 같은 자리다.
  - **폴링은 유닛이 사라진 슬롯(`unitframe.unit`, `reaction`, `role`)도 비우는데, 누를 때 그 캐시를 믿는 곳은
    `GetHoveredUnit` 하나다.** SETCUSTOM의 "hover"가 이것으로 대상을 정한다(`UnitWatch.lua`). `EVAL_SNIPPET`처럼
    부르는 순간 `unitframe.frame`의 `unit`과 `UnitExists`를 다시 읽게 고친다 (2026-09-14, 소유자). 그러면 비우는 일
    때문에 박자를 둘 이유도 없다.

**클릭 래퍼.**
- 이긴 레코드에 `clickbutton`이 없는 경로가 사라진다. 승자가 없거나 BLOCK이 이기면 `false`를 돌려주는 것 하나만
  남는다.
- 층 구간(`focusFrom`, `noneFrom`)은 그대로 쓴다. 모든 레코드가 클릭이니 A와 B는 없어진다.
- §3-9는 "루프는 키를 안 건다"로 줄어든다. 쌍둥이를 세느냐는 물음 자체가 없어진다.

**솔버.** `CheckUnreachableBindings`는 남는다. 행의 도달 불가 표시와 레코드 수를 줄이는 일은 그대로다.

**문서.** `0-IDEAS.md`에서 움직일 항목은 없다. 둘 다 Smart Cast에 딸린 것이었고, Smart Cast는
빠졌다(`adding-spec-resolved-actions.md` §10).

**테스트.**
- 루프 스윕(`eval_spec`의 "the state loop binds the exact record out of seven")과 킷의 "Multi-axis: poll and
  press agree on a key with a gap"은 `COMMAND`·`UNUSED` 레코드로 짜여 있어 다시 쓰거나 지운다.
- `alwaysours_spec`, `clicktime_spec`, `boundkey_spec`, 이미션 픽스처의 두 타입 항목과 골든이 따라간다.

## 4. 행동 단축키 액션

**`ACTIONBUTTON1`~`12` 바인딩이 하던 일을 클릭 래퍼 안에서 한다** (2026-09-13, 소유자). 이것이 없으면 우리 키를
잡은 동안 바뀐 액션 바(탈것, 오버라이드, 빙의)의 기술을 쓸 길이 없다. 지금은 틈이나 `UNUSED [specialbar]`로
풀어 두는 것이 그 길이다.

### 4-1. 주 바: 칸을 계산해 쏜다

블리자드 바인딩은 `ActionButtonDown(id)`를 부르고, 대전이 아니면 `GetActionButtonForID`로 버튼을 골라 누른다
(`Blizzard_ActionBar/Shared/ActionButton.lua:97-148`). 우리는 버튼을 고르지 않고 그 버튼이 가리키는 칸을 직접
정한다.

페이지는 `ActionBarController_UpdateAll`과 같은 순서로 정한다(`ActionBarController.lua:154-165`).

| 판별 | 페이지 |
|---|---|
| `HasVehicleActionBar()` | `GetVehicleBarIndex()` |
| `HasOverrideActionBar()` | `GetOverrideBarIndex()` |
| `HasTempShapeshiftActionBar()` | `GetTempShapeshiftBarIndex()` |
| `HasBonusActionBar()`이고 `GetActionBarPage() == 1` | `GetBonusBarIndex()` |
| 나머지 | `GetActionBarPage()` |

칸은 `N + (page - 1) * 12`이고 `type=action`으로 쏜다. 블리자드 버튼도 이 식으로 칸을 구한다
(`SecureTemplates.lua:674-684`, `NUM_ACTIONBAR_BUTTONS = 12`). 판별과 페이지 함수는 전부 제한 환경 허용
목록에 있다(`RestrictedEnvironment.lua:140-153`).

**스킨을 가를 필요가 없다.** 스킨 없는 바는 `MainActionBar`의 `actionpage`를 바꾸고(`ActionBarController.lua:155-164`),
스킨 있는 `OverrideActionBar`는 같은 두 값을 자기 `actionpage`로 받는다(`OverrideActionBar.lua:147-151, 249`).
버튼은 갈려도 칸은 같다. 스킨을 읽는 `UnitVehicleSkin`, `GetOverrideBarSkin`은 허용 목록에 없다.

**다른 액션과 똑같이 클릭 래퍼를 지난다.** focus와 self 쌍둥이, Hover Cast가 그대로 붙는다.

**구현** (2026-09-14). 타입은 `Constants.ACTIONBUTTON`이고 값은 바인딩 명령 이름(`ACTIONBUTTON3`,
`MULTIACTIONBAR1BUTTON5`, `EXTRAACTIONBUTTON1`)이다. 행 이름이 게임의 `BINDING_NAME_*` 그대로이고, 저장된 `COMMAND`는
타입만 바꾸면 옮겨진다. 명령마다 칸이 어디인지는 `Constants.ACTION_BUTTON_COMMANDS` 하나가 들고, 마이그레이션
단계(`MigrateLayer`의 아직 안 나간 단계)와 가져오기의 `IsUsableAction`, 카탈로그, 리빌드가 그것을 읽는다. 가져온 옛
문자열은 같은 단계를 타고 들어온다. 누를 때 칸을 정하는 것은 `SecureBindings.lua`의 `ACTION_SLOT_SNIPPET`이다.

**블리자드와 갈리는 곳 하나.** 스킨 있는 바에서 7~12를 누르면 블리자드는 아무것도 안 하지만
(`NUM_OVERRIDE_BUTTONS = 6`) 우리는 그 페이지의 7~12번 칸을 쏜다.

### 4-2. 기타 행동 버튼 (2026-09-14, 소유자)

`EXTRAACTIONBUTTON1` 바인딩은 `ExtraActionButtonKey(1, down)`이고, `HasExtraActionBar()`가 거짓이면 아무것도 안 하고
참이면 `ExtraActionButton1`에 `TryUseActionButton`을 부른다(`ExtraActionBar.lua:63-80`). 그 버튼은 `isExtra`라서
칸을 `GetExtraBarIndex()` 페이지에서 구한다(`SecureTemplates.lua:678-679`).

**페이지 번호는 리빌드가 굽는다.** `HasExtraActionBar`는 제한 환경 허용 목록에 있지만 `GetExtraBarIndex`는 없다
(`RestrictedEnvironment.lua:139-159`). 칸은 구워 둔 페이지로 `1 + (page - 1) * 12`다.

**블리자드 바인딩이 누를 때 거는 판별은 우리도 걸고, 걸리면 `return false`로 끊는다** (2026-09-14, 소유자). 판별은
승자가 정해진 뒤에 돌아서 다음 액션으로 넘기지 않는다. 다음 액션으로 넘기는 것은 사용자가 건 조건뿐이다
(`EVAL_SNIPPET`). 그래서 `HasExtraActionBar()`가 거짓이면 아무것도 안 한다. 한때 이 판별을 뺐는데, 판별이 액션을
건너뛰어 다음으로 넘기는 것으로 읽혔기 때문이고 실제 코드는 끊기만 했다.

**개체창 클릭도 같다** (2026-09-14, 소유자). hover를 건 그 액션이 개체창 클릭에서 이기고 판별에 걸리면 아무것도 안
하고, 개체창의 원래 동작(대상 잡기, 메뉴)으로도 흘려주지 않는다. 사용자 조건에서 막힌 것이 아니면 그 클릭은 그
바인딩이다. 사용자 조건이 안 맞아 승자가 없을 때 흘려주는 것은 그대로다.

### 4-3. 페이지가 고정된 바

`MULTIACTIONBARkBUTTONn` 바인딩은 `MultiActionButtonDown(바 이름, n)`이고 그 바의 `actionButtons[n]`에
`TryUseActionButton`을 부른다(`MultiActionBars.lua:35-41`). 이 바들은 `actionpage`가 XML에 박혀 있고 탈것이나
빙의로 안 바뀐다(`MultiActionBars.xml:45-236`). 칸은 리빌드 때 정해진다.

| 명령 | 버튼 | `actionpage` |
|---|---|---|
| `MULTIACTIONBAR1BUTTONn` | `MultiBarBottomLeftButtonN` | 6 |
| `MULTIACTIONBAR2BUTTONn` | `MultiBarBottomRightButtonN` | 5 |
| `MULTIACTIONBAR3BUTTONn` | `MultiBarRightButtonN` | 3 |
| `MULTIACTIONBAR4BUTTONn` | `MultiBarLeftButtonN` | 4 |
| `MULTIACTIONBAR5`~`7BUTTONn` | `MultiBar5`~`7ButtonN` | 13, 14, 15 |

`ActionButtonN`이라는 이름은 주 바의 12개뿐이고, 나머지 바의 버튼은 `<바 이름>ButtonN`이다(`ActionBar.lua:19-28`).

### 4-4. 플라이아웃 칸

**`type=action`으로 쏘면 죽는다** (2026-09-14, 소유자가 게임에서 봄). `SECURE_ACTIONS.action`이 플라이아웃을
`SpellFlyout:Toggle(self, ...)`로 열고, 그 안에서 쏜 버튼의 `GetPopupDirection`을 불러 `SpellFlyout.lua:260`에서
nil 호출이 난다. 맨몸 `SecureActionButtonTemplate`에는 그 메서드가 없다. Debind의 플라이아웃 타입이
`*type-flyout`을 안 쓰는 것과 같은 이유다(`UpdateBindings.lua`).

제한 환경의 `GetActionInfo`가 `"flyout"`을 돌려주므로(`RestrictedEnvironment.lua:161-174`) 래퍼가 가를 수 있다.
프로브는 그 칸을 진짜 바 버튼(`ActionButton1` 또는 `OverrideActionBarButton1`)에 넘겼고 오류 없이 돌았다. 소유자가
게임에서 보니 왼쪽, 가운데, 오른쪽 버튼과 `/abp bind right` 뒤의 키 누름 모두에서 플라이아웃이 토글됐다
(2026-09-14).

**구현은 S2다.** 래퍼가 `GetActionInfo(slot) == "flyout"`이면 그 칸을 보여 주는 바 버튼을 누르는 이름을 돌려준다.
주 바는 `OverrideActionBar:IsShown()`이면 `OverrideActionBarButtonN`(1~6), 아니면 `ActionButtonN`이고, 고정 페이지 바와
기타 행동 버튼은 자기 버튼이다.

### 4-5. 잰 것 (2026-09-14, retail, `Probe_ActionBars.lua`)

프로브는 Debind의 `DefaultClickFrame`과 같은 모양이다. 버튼을 두 엣지로 등록하고, `OnClick`을 헤더로 감싸고,
경로마다 `*type-<이름>`을 비보안 쪽에서 걸어 두고, 래퍼는 이름만 돌려준다. 래퍼가 쏠 버튼을
`OverrideActionBar:IsShown()`으로 고르고 세 길로 눌렀다. 로그는 `DebindDevDB.actionBarProbe`에 남는다.

- 왼쪽: `type=click`으로 `ActionButton1` 또는 `OverrideActionBarButton1`
- 가운데: 매크로 `/click <버튼> LeftButton true`와 `/click <버튼> LeftButton`
- 오른쪽: §4-1이 계산한 칸에 `type=action`

| 상황 | 로그 | 세 길 |
|---|---|---|
| 스킨 있는 오버라이드 바(두 종류) | `hasOverride=T`, 페이지 18, 칸 205~210. `OverrideActionBarButtonN.action`과 계산한 칸이 같다 | 모두 `UseAction 205`가 한 번씩 |
| 빙의 | `hasVehicle=T`, `[possessbar]=T`, `[vehicleui]=F`, 페이지 16. 스킨 없이 `MainActionBar.actionpage=16`, `ActionButton1.action=181` | 모두 `UseAction 181`이 한 번씩 |
| 기타 행동 버튼 | `extraIndex=19`, `ExtraActionButton1.action=217` = `1 + (19 - 1) * 12`. 로그인 때 구운 칸도 217 | 별도 버튼으로 잼. 모두 `UseAction 217`이 한 번씩 |
| 탈것 조수석 | 바는 안 바뀌고 `vehicleSkin`, 좌석 수만 바뀐다 | 해당 없음 |

- **한 누름에 한 번 나간다.** 래퍼는 두 엣지에 다 돌지만 `UseAction`은 한 번 찍힌다. 가운데 길은 두 번 클릭하고 뗄
  때 한 번 나갔다.
- **제한 환경의 판독과 비보안 쪽이 늘 같았다.** 페이지, 칸, 고른 버튼 모두. 상태 드라이버는 `overridebar`,
  `possessbar`, `extrabar`, `none`에서 불렸다.
- **바가 바뀐 동안 주 바 버튼은 옛 칸을 가리킨다.** 스킨 있는 오버라이드 바 동안 `ActionButton1`~`12`는 칸
  1~12다. 스킨 있는 바가 자기 버튼을 쓰기 때문이다.
- **오버라이드 바가 끝나는 순간** `OverrideActionBar`가 `IsShown` 거짓, `IsVisible` 참인 틈이 있다. 래퍼는
  `IsShown`으로 골라 이미 `ActionButton1`을 골랐다.
- **페이지 번호는 바가 없어도 읽힌다**: `vehicleIndex=16`, `overrideIndex=18`, `tempShapeIndex=17`,
  `extraIndex=19`, `multiCastIndex=12`. 보너스 바가 없을 때 `bonusIndex=0`이다.
- 프로브를 돌린 곳은 모두 전투 밖이었다.

### 4-6. 버튼을 누르는 방법은 안 했다

- **`/click ActionButtonN` 매크로텍스트, `ActionButton1`~`12` 클릭.** 잰 곳에서는 둘 다 나갔다(§4-5). 그래도 안
  쓰는 이유는 둘이다. 스킨 있는 바에서는 `OverrideActionBarButton1`~`6`이 따로 필요하다. 그리고
  `ActionBarActionButtonMixin:OnClick`은 이 누름을 키 누름이 아니라 보안 마우스 누름으로 넘긴다(`isKeyPress = false`,
  `isSecureAction = true`, `ActionButton.lua:1363-1365`). 그러면 `useOnKeyDown`이 거짓이 되어
  `ActionButtonUseKeyDown`과 무관하게 뗄 때 나가고, `treatAsKeyPress`가 늘 거짓이라 누르고 있기 주문이 누른 채
  유지되지 않는다(`SecureTemplates.lua:811-821`). 바인딩 경로는 `TryUseActionButton`에서 `isKeyPress = true`로 간다.
  칸을 쏘면 우리 버튼의 게이트를 따른다.
- **잠긴 바에서 `PICKUPACTION`(기본 Shift)을 쥐어도 액션은 나간다** (2026-09-14, 소유자). `lockedBarDoNothing`은
  `down`일 때만 참이라(`ActionButton.lua:1357`) 누르는 엣지만 건너뛰고 떼는 엣지에서 나간다. `type=click`은
  `delegate:Click(button)`이 늘 `down` 거짓으로 오니 이 조건에 아예 안 걸린다. 누르는 엣지를 건너뛰는 것은 Shift를
  쥔 채 드래그하면 실행 대신 집어 들게 하려는 것이다(`OnDragStart`의 `IsModifiedClick("PICKUPACTION")`,
  1370-1374줄). 우리 누름은 드래그가 없으니 해당이 없다. 버튼을 누르는 길을 안 쓰는 이유가 아니다.
- **핸들은 `clickbutton`이 못 된다** (2026-09-14, 소유자가 게임에서 봄). 제한 환경의 `SetAttribute`는 핸들을
  받지만, `SECURE_ACTIONS.click`이 돌려받은 핸들에 `HasAccessConstraints`를 불러 `SecureTemplates.lua:564`에서
  오류가 난다. 누를 프레임은 비보안 쪽에서 `*clickbutton-<이름>`으로 걸고 래퍼는 이름만 돌려준다. Debind가 이미
  그렇게 한다.

### 4-7. 대신할 수 없는 명령

- **점프와 이동.** `MovePadJump`는 `OnClick`이 없고 `OnMouseDown`/`OnMouseUp`에서 `RunBinding("JUMP", ...)`을
  부른다(`Blizzard_MovePad.lua:200-211`). `Click()`은 거기 닿지 않는다. 이동 버튼은 `OnClick`이 있지만
  `movePadInPressAndHoldMode`가 꺼졌을 때만 돌고, 누를 때마다 켜고 끈다(115-127줄). `Blizzard_MovePad`는
  `LoadOnDemand: 1`이라 설정을 켜기 전에는 프레임도 없다.
- **탈것에서 내리기는 대신할 것이 없다.** `VEHICLEEXIT` 바인딩은 `VehicleExit()` 한 줄이고 `/leavevehicle`이
  있어 커스텀 매크로로 된다.

### 4-8. 소환수 바와 태세 바 (2026-09-14, 소유자)

**행동 단축키 종류는 모두 우리가 대체한다.** 소매 바인딩 목록에서 앞의 것들 말고 남은 둘이다. 둘 다 칸이 번호 하나로
고정이라 누를 때 고를 것이 없다. 블리자드 바인딩의 판별은 §4-2의 규칙대로 따른다.

- **소환수 바.** `BONUSACTIONBUTTONn`은 `PetHasActionBar()`이면 `PetActionBar:PetActionButtonDown(n)`이고, 결국
  `CastPetAction(n)`이다(`PetActionBar.lua:191-209`). 우리는 `type=pet`, `action=n`을 고정으로 건다.
  `SECURE_ACTIONS.pet`이 `CastPetAction(action, unit)`이다(`SecureTemplates.lua:368`). `PetHasActionBar`는 제한 환경에
  없어서 `UnitExists("pet")`로 가른다. 조종할 수 없는 소환수는 `pet`이 아니라서 답이 같다 (2026-09-14, 소유자).
- **태세 바.** `SHAPESHIFTBUTTONn`은 `StanceBar:Select(n)`, 곧 `CastShapeshiftForm(n)`이고 판별이 없다
  (`StanceBar.lua:104-124`). 우리는 `StanceButtonN`을 `type=click`으로 누른다(S2). 태세는 대상을 받지 않으므로 대상 메뉴가
  안 열린다.
- **태세를 리빌드가 주문으로 푸는 길은 안 한다.** `GetShapeshiftFormInfo(n)`의 주문을 `type=spell`로 굽는 길이다.
  블리자드 바인딩과 같은 함수를 불러야 이미 그 태세일 때 해제되는 동작이 갈리지 않고, 태세 목록이 바뀌어도 리빌드에
  기대지 않는다.
- `StanceButtonTemplate`은 보안 행동 버튼이 아니고 `OnClick`이 일반 Lua다. 보안 클릭에서 그 안의 `CastShapeshiftForm`이
  나가는지는 킷이 누를 수 없어 `Probe_ActionBars.lua`의 태세 버튼이 잰다.

## 5. 애완동물 대전

**행동 단축키 칸으로는 안 닿는다.** 대전 기술은 행동 칸이 아니고 `C_PetBattles.UseAbility`로 나간다. 대전으로
돌리는 `CheckPetActionButtonEvent`는 `ActionButtonDown`/`ActionButtonUp` 두 곳에서만 불리고, 둘 다
`ACTIONBUTTONn` 바인딩이 부른다(`ActionButton.lua:123-164`). 버튼의 `OnClick`에는 없다. 대전 중
`/click ActionButton1 LeftButton`은 기술을 안 쓴다 (2026-09-13, 소유자가 게임에서 봄).

**대전 UI는 키를 되찾지 않는다.** `Blizzard_PetBattleUI`에서 바인딩을 읽는 곳은 단축키 글자를 그리는
`GetBindingKey("ACTIONBUTTON"..id)` 하나이고(939줄) `SetOverrideBinding`이 없다. 우리 오버라이드가 키를 잡으면
블리자드 경로가 통째로 안 돈다.

**대전 중에는 전투 잠금이 아니다.** `InCombatLockdown()`이 거짓 (2026-09-13, 소유자가 잼).

### 5-1. 대전 동안 행동 단축키 1~5의 키만 놓는다 (2026-09-13, 소유자)

`PET_BATTLE_OPENING_START`에 `GetBindingKey("ACTIONBUTTON"..i)`가 돌려주는 키 전부를 우리 오버라이드에서 빼고,
`PET_BATTLE_CLOSE`에 다시 건다. 블리자드 경로가 그대로 돌아 4가 교체 창을 여는 것까지 같다.

**같은 장치가 이미 있다: 바인딩 컨텍스트 양보** (`BindingContexts.lua`). 집 편집기가 켜진 바인딩 컨텍스트의 키를
게임에 물어(`C_KeyBindings.GetBindingContextForAction`, `IsBindingContextActive`, `GetBindingKey`) `YieldedKeys`에
담고, 바뀌면 `QueueUpdateBindings`로 리빌드한다. 리빌드는 `RefreshYieldedKeys` 뒤에 `BuildKeyMap`을 돌고, 양보 중인
키는 `KeyMap`에 안 넣어 오버라이드를 안 건다(`Debind.lua`의 `IsKeyYielded`). 액션의 `keepInBindingContext`가 켜져
있으면 예외다. 대전은 이 장치에 "대전 중이면 `ACTIONBUTTON1`~`5`의 키"라는 출처 하나를 더하면 되고, 대전 중
리빌드가 그 키를 건너뛰는 것과 닫힐 때 다시 거는 것이 그대로 따라온다. 트리거는 `PET_BATTLE_OPENING_START`와
`PET_BATTLE_CLOSE`다. 닫힐 때 잠금이면 리빌드는 기존 경로대로 풀린 뒤로 밀린다.

**구현** (2026-09-14). 대전 키는 `YieldedKeys`와 따로 `PetBattleKeys`에 담는다. `keepInBindingContext`는 사용자에게
"주택 편집기보다 우선"으로 보이는 옵션이라 대전 키는 붙들지 않는다. 대전 중인지는 두 이벤트로 정하고, 로드할 때만
`C_PetBattles.IsInBattle()`로 시작값을 읽는다.

**잰 것** (2026-09-14, xptr, `Probe_ActionBars.lua` 로그). 대전 세 번 모두 같았다.
- 열릴 때 `ACTIONBUTTON1`의 키 둘(`BUTTON3`, `1`)을 놓았다. `GetBindingKey`가 키를 여럿 돌려주는 경우다.
- 놓인 동안 `1`을 누르자 래퍼를 안 거치고 `C_PetBattles.UseAbility(1)`이 나갔다.
- `PET_BATTLE_CLOSE`에 잠금이 아니었고 곧바로 다시 걸었다.
- 제한 환경은 대전 중 `[petbattle]`을 참으로 읽었고 상태 드라이버가 `petbattle`에서 불렸다.

### 5-2. 대전 버튼을 참조로 누르는 길도 된다

`PetBattleFrame_ButtonDown(id)`는 버튼을 골라 `Click()`할 뿐이다(`Blizzard_PetBattleUI.lua:378-402`). 1~3은
`abilityButtons[id]`, 4는 `SwitchPetButton`(교체 창을 연다), 5는 `CatchButton`이다(8-10줄). 전역 이름이 없어서
`/click`으로는 못 부르고(330줄, XML의 `parentKey`), 1~3은 첫 대전에서 `PetBattleFrame_Display`가 만든다(101-103,
171줄).

**잰 것** (같은 로그).
- 보호되지 않은 프레임도 `SetFrameRef`로 넘어간다. `PET_BATTLE_OPENING_START` 다음 프레임에 `abilityButtons[1]`을
  넘긴 `pcall`이 성공했고, 그때 버튼은 이미 있었다. 대전은 전투 잠금이 아니다. 전투 중이면 그 핸들은 §3의
  `Invalid frame handle`에 걸린다.
- 턴이 시작된 뒤 프로브 버튼을 누르자 래퍼가 `*clickbutton-abpPB`의 이름을 돌려준 순간 `C_PetBattles.UseAbility(1)`이
  나갔다. 기술을 쓴 뒤 턴이 재생되는 동안의 누름 세 번은 안 나갔다. 버튼이 꺼져 있던 때로 본다.

### 5-3. 5-1로 가는 이유와 안 한 방법

- **대전 버튼을 참조로 누른다(5-2).** 되지만 1~3이 첫 대전에 만들어져 넘기는 시점을 맞춰야 하고, 대전이 끝날 때
  참조를 치울지 정해야 하며(닫힐 때 잠금이면 못 치운다), 4와 5까지 블리자드 동작을 따로 옮겨야 한다. 키를 놓으면
  블리자드 경로가 그대로 돈다.
- **대전 동안 오버라이드를 통째로 푼다.** 사용자는 대전에 안 쓰는 키에도 액션을 건다 (2026-09-13, 소유자).

## 6. 사용자가 잃는 것

**조건으로 게임과 키를 나눠 쓰던 사람.** 예를 들어 `Space`에 [탈것 탔을 때]만 건 액션은 지금은 내리면 점프가
나가지만, 바꾼 뒤에는 늘 우리 키라 점프가 안 된다. 틈을 게임에 돌려주던 모든 키가 이렇게 된다.

**`BUTTON1`·`BUTTON2`는 키로 못 잡는다.** 이 문서의 앞 판은 그렇게 잡는 사람을 따로 챙기지 않는다고 적었는데
(2026-09-13, 소유자), 그런 설정이 애초에 안 된다. 두 버튼에 건 액션은 Cast Options가 무엇이든 개체창 클릭으로만
나가고 키를 안 잡는다(2026-09-17, 소유자, `which-action-a-key-runs.md` §7). 그 전에는 개체창 조건 없이 걸면 ERROR
이슈로 키에서 빠졌다. 월드 클릭과 카메라 조작이 막히는 일은 없다.

**개체창 클릭은 여기 안 든다.** 유닛 프레임 래퍼는 맞는 레코드가 없으면 아무것도 돌려주지 않고, 클릭은 프레임의
원래 동작으로 간다(`SecureBindings.lua`의 `UnitFrameClickPre` 본문). 키 바인딩을 거치지 않으니 이번 변경과 무관하게
지금처럼 흘려준다. 막히는 것은 키로 잡은 마우스 버튼뿐이다.

**블리자드 키 바인딩 창에서 명령을 거는 것으로 대신할 수 없다.** 같은 키를 Debind가 늘 잡고 있으니 게임 쪽 바인딩은
안 나간다. `COMMAND`가 하던 "Debind 조건에 따라 게임 명령" 자체가 없어진다. 행동 단축키(§4)와 커스텀 매크로로
되는 것을 뺀 나머지, 점프와 이동이 여기 든다.

## 7. 우리에게 있는 전략

키를 늘 잡은 채 블리자드 바 버튼이 할 일을 내는 방법이다. "잼"은 `Probe_ActionBars.lua` 로그로 확인한 것이다.

| 전략 | 어디서 | 닿는 곳 | 잼 | 걸리는 것 |
|---|---|---|---|---|
| **S1. 칸을 계산해 `type=action`** | 클릭 래퍼 | 주 바와 그 위의 탈것·오버라이드·임시 변신·보너스 바, 기타 행동 버튼(페이지를 구움), 고정 페이지 바 | 오버라이드(스킨), 빙의, 기타 행동 버튼, 일반 바 | 플라이아웃 칸이면 오류(§4-4). 페이지 번호 중 `GetExtraBarIndex`만 제한 환경에 없다 |
| **S2. 진짜 버튼을 `type=click`** | 비보안이 `*clickbutton-<이름>`을 걸고 래퍼가 이름을 돌려줌 | `ActionButtonN`, `OverrideActionBarButtonN`, `ExtraActionButton1`, 고정 페이지 바 버튼 | 오버라이드(스킨), 빙의, 기타 행동 버튼, 일반 바 | 버튼을 골라야 한다(`OverrideActionBar:IsShown()`은 참조로 읽는다, 보호 프레임이라 전투 중에도 된다). 보안 마우스 누름으로 처리되어 늘 뗄 때 나가고 누르고 있기가 안 된다(§4-6). 핸들을 값으로 넣으면 오류 |
| **S3. 매크로 `/click <이름> LeftButton true` + `/click <이름> LeftButton`** | 래퍼가 `*macrotext-<이름>`을 씀 | 전역 이름이 있는 버튼 | 오버라이드(스킨), 빙의, 기타 행동 버튼, 일반 바 | S2의 조건에 더해, 바깥이 매크로라 누른 칸이 또 매크로면 안 나간다(`UpdateBindings.lua`의 옛 경로 주석) |
| **S4. 보호되지 않은 프레임을 참조로 넘겨 `type=click`** | 비보안이 열릴 때 `SetFrameRef`와 `*clickbutton-<이름>` | 대전 기술 버튼처럼 이름 없는 프레임 | 대전 기술 1 | 프레임이 늦게 생기면 넘기는 시점을 맞춰야 한다. 버튼이 꺼져 있으면 클릭이 먹힌다. 전투 중에는 핸들 판독이 막힌다 |
| **S5. 그 순간만 키를 놓는다** | 비보안, 이벤트에서 | 블리자드 경로 전부(대전 포함) | 대전 동안 `ACTIONBUTTON1`의 키. 집 편집기의 바인딩 컨텍스트 양보가 이미 이 방식이다(`BindingContexts.lua`) | 전투 잠금 중에는 못 한다. 대전은 잠금이 아니라 되지만, 탈것과 오버라이드는 전투 중에 바뀐다 |
| **S6. 상태 루프가 키를 놓는다** | 제한 환경 루프 | 블리자드 경로 전부 | 지금 코드 | 이 문서가 없애는 것(§1) |

고른 것은 바뀐 바와 기타 행동 버튼, 고정 페이지 바에 S1(§4), 대전에 S5(§5-1)다. 플라이아웃 칸은 S1이 못 쏘니
S2로 넘기는 것이 프로브가 한 방법이고, 결정은 아니다.

## 8. 버튼이 켜지는 이벤트와 판별 함수

블리자드 코드에서 읽은 것이다. "잰 이벤트"는 로그에 한 틱으로 묶여 찍힌 이벤트다.

### 8-1. 주 바의 페이지와 `OverrideActionBar`

`ActionBarController`가 `PLAYER_ENTERING_WORLD`, `ACTIONBAR_PAGE_CHANGED`, `UPDATE_BONUS_ACTIONBAR`,
`UPDATE_VEHICLE_ACTIONBAR`, `UPDATE_OVERRIDE_ACTIONBAR`에서 `ActionBarController_UpdateAll`을 부른다
(`ActionBarController.lua:11-24, 57-67`). 그 안의 판별 순서가 곧 상태다(143-176줄).

1. **스킨 있는 바.** `HasVehicleActionBar()`이고 `UnitVehicleSkin("player")`가 빈 문자열이 아니거나,
   `HasOverrideActionBar()`이고 `GetOverrideBarSkin()`이 0이 아니면 `OverrideActionBar:UpdateSkin()`, 상태는
   `LE_ACTIONBAR_STATE_OVERRIDE`. `OverrideActionBar`의 `actionpage`는 탈것이면 `GetVehicleBarIndex()`, 아니면
   `GetOverrideBarIndex()`다(`OverrideActionBar.lua:147-151, 249`).
2. **스킨 없는 바.** `HasBonusActionBar() or HasOverrideActionBar() or HasVehicleActionBar() or
   HasTempShapeshiftActionBar() or C_PetBattles.IsInBattle()`이면 `MainActionBar`의 `actionpage`를 §4-1의 표대로
   정하고 모든 바 버튼에 `UpdateAction`.
3. **그 밖.** `actionpage = GetActionBarPage()`.

버튼의 `.action`은 `actionpage` 속성이 바뀔 때 `OnAttributeChanged`에서 `CalculateAction()`으로 다시 구해진다
(`ActionButton.lua:524-557`).

**보이고 숨는 것은 `ValidateActionBarTransition`이 한다**(205-232줄). 상태가 OVERRIDE면 `MainActionBar:Hide()`와
`OverrideActionBar`를 미끄러져 들어오게, MAIN이면 반대로 한다. `OverrideActionBar.slideOut`이 도는 동안이나
대전 중(`ActionBarBusy`)에는 판단을 건너뛴다. 대전이 열리면 보이던 `OverrideActionBar`를 내보낸다(113-115줄).
내보내는 애니메이션 동안 `IsShown`은 거짓, `IsVisible`은 참인 틈이 잰 로그에 있다(§4-5).

| 상황 | 잰 이벤트 | 잰 판별 |
|---|---|---|
| 스킨 있는 오버라이드 바 켜짐/꺼짐 | `UPDATE_EXTRA_ACTIONBAR`, `UPDATE_OVERRIDE_ACTIONBAR` | `hasOverride`, `[overridebar]`, `overrideSkin`이 같이 바뀐다 |
| 빙의 켜짐 | `UPDATE_POSSESS_BAR`, `UPDATE_VEHICLE_ACTIONBAR`, `VEHICLE_UPDATE` 다음 틱에 `UPDATE_VEHICLE_ACTIONBAR` | `possessVisible`이 먼저, 다음 틱에 `hasVehicle`, `[possessbar]`, 페이지 16. `[vehicleui]`는 거짓 |
| 빙의 꺼짐 | `VEHICLE_UPDATE`, `UPDATE_POSSESS_BAR`, `UPDATE_VEHICLE_ACTIONBAR` 둘 | 한 틱에 전부 |
| 탈것 조수석 | `UNIT_ENTERED_VEHICLE`/`UNIT_EXITED_VEHICLE` | `inVehicle`, `canExitVehicle`만. 바는 안 바뀐다 |
| 주 바 페이지 넘김 | `ACTIONBAR_PAGE_CHANGED` | `page`, `MainActionBar.actionpage` |

**빙의 바 페이지는 한 틱 늦게 선다.** 첫 틱에 `IsPossessBarVisible()`은 참인데 `HasVehicleActionBar()`가 아직
거짓이었다. 그 사이의 누름은 주 바 칸을 쏜다.

### 8-2. 빙의 바 (`PossessActionBar`)

`UPDATE_POSSESS_BAR`와 `ActionBarController_UpdateAll`에서 `PossessActionBar:Update()`(`ActionBarController.lua:85-88,
144`). `MainActionBar.busy`가 아니고 `UnitHasVehicleUI("player")`가 거짓일 때 `C_ActionBar.IsPossessBarVisible()`로
보이고 숨는다(`PossessActionBar.lua:10-22`).

**`PossessButton1`, `PossessButton2`는 행동 칸 버튼이 아니다.** 전역 이름은 `ActionBar.lua:25-26`이 붙이고, 템플릿은
`SecureFrameTemplate, SmallActionButtonTemplate`이라 `SecureActionButtonTemplate`이 아니다
(`Mainline/PossessActionBar.xml:3-11`). `.action`도 `actionpage`도 없고 `GetPossessInfo(i)`로 아이콘만 그린다(24-46줄).
`OnClick`은 비보안 Lua 한 벌이고 `POSSESS_CANCEL_SLOT`(2)일 때만 일을 한다(71-90줄).

- **1번은 누르면 아무것도 안 한다.** 잰 로그에서 `GetPossessInfo(1)`은 주문 179892였다. 빙의 기술은 이 버튼이 아니라
  주 바의 탈것 페이지 칸(16페이지)으로 나갔다(§4-5).
- **2번은 취소다.** 택시면 `TaxiRequestEarlyLanding`, 탈것을 몰고 내릴 수 있으면 `VehicleExit`, 아니면
  `CancelPetPossess`다.
- **바인딩 명령이 없다.** `Bindings_Standard.xml`에 빙의 버튼 명령은 없다. 키로 빙의를 풀려면 `/click PossessButton2`나
  (탈것이면) `/leavevehicle`을 매크로로 건다. `CancelPetPossess`가 보호 함수인지는 이 소스의 API 문서에 없다.

### 8-3. 기타 행동 버튼 (`ExtraActionBarFrame`)

`UPDATE_EXTRA_ACTIONBAR`에서 `ExtraActionBar_Update()`(`ActionBarController.lua:91-93`). `HasExtraActionBar()`가 참이면
보이고 스킨은 `GetOverrideBarSkin()` 또는 기본값이다(`ExtraActionBar.lua:10-30`). 바인딩은 같은 판별로 막는다(63-80줄).
잰 이벤트는 `UPDATE_EXTRA_ACTIONBAR`와 `UPDATE_OVERRIDE_ACTIONBAR`가 함께이고, 그때 `overrideSkin`도 바뀌었다.

**잰 것** (2026-09-14, retail, `Probe_ActionBars.lua`의 두 번째 버튼).
- 래퍼는 `HasExtraActionBar()`로만 갈랐다. 켜진 동안 제한 환경에서 `HasExtraActionBar`, `[extrabar]`,
  `ExtraActionBarFrame`과 `ExtraActionButton1`의 `IsShown`/`IsVisible`이 모두 참이었고, 구운 칸 217에 주문이 있었다.
- 세 길(`ExtraActionButton1` 클릭, 매크로 `/click`, 칸 `type=action`)이 모두 `UseAction 217`을 한 번씩 냈다.
- **`GetOverrideBarSkin()`은 기타 행동 버튼만 떠도 0이 아니다.** 스킨 있는 오버라이드 바가 없는데 629480, 796702가
  읽혔다. 버튼 스킨으로 쓰기 때문이다(10-30줄). 오버라이드 바 판별은 `HasOverrideActionBar()`가 먼저여야 한다.
- **꺼질 때 판별이 프레임보다 먼저 꺼진다.** `HasExtraActionBar()`가 거짓이 된 뒤 약 0.7초 동안
  `ExtraActionBarFrame`이 보였다(`outro` 애니메이션). 칸 217에는 꺼진 뒤에도 주문이 남아 있었다. 그 사이 판별로
  가르면 누름이 막히고, 보이는지로 가르면 이미 끝난 기타 행동 버튼의 칸을 쏜다. 블리자드 바인딩은 판별로 가른다.

### 8-4. 고정 페이지 바

보이는지는 설정 `PROXY_SHOW_ACTIONBAR_2`~`8`이고 `SETTINGS_LOADED` 뒤 값이 바뀔 때 `MultiActionBar_Update()`
(`ActionBarController.lua:117-140`). 페이지는 안 바뀌고 바인딩(`MultiActionButtonDown`)은 보이는지를 안 본다
(`MultiActionBars.lua:35-41`).

### 8-5. 탈것 내리기 버튼 (`MainMenuBarVehicleLeaveButton`)

`UPDATE_BONUS_ACTIONBAR`, `UPDATE_MULTI_CAST_ACTIONBAR`, `UNIT_ENTERED_VEHICLE`, `UNIT_EXITED_VEHICLE`,
`VEHICLE_UPDATE`에서 `Update`(`VehicleLeaveButton.lua:4-9, 25-52`). `CanExitVehicle()`이고 컨트롤러 상태가 MAIN일 때
보인다(29-35줄). 스킨 있는 바에서는 그 바의 내리기 버튼이 대신한다.

### 8-6. 애완동물 대전

`PET_BATTLE_OPENING_START`에서 `PetBattleFrame_Display`가 기술 버튼을 만들고 보인다(`Blizzard_PetBattleUI.lua:101-103,
171`). `PET_BATTLE_CLOSE`에서 컨트롤러가 바를 되돌린다(`ActionBarController.lua:108-110`). 바인딩 쪽 판별은
`C_PetBattles.IsInBattle()`과 `PetBattleFrame`이 있는지다(`ActionButton.lua:122-134`). 대전 중에는
`ActionBarController_UpdateAll`의 스킨 없는 갈래에 `IsInBattle`이 들어 있어 주 바 페이지는 `GetActionBarPage()`로
남는다.

### 8-7. 제한 환경에서 쓸 수 있는 판별

- **함수** (`RestrictedEnvironment.lua:139-174`): `HasVehicleActionBar`, `HasOverrideActionBar`,
  `HasTempShapeshiftActionBar`, `HasBonusActionBar`, `HasExtraActionBar`, `GetActionBarPage`, `GetBonusBarOffset`,
  `GetVehicleBarIndex`, `GetOverrideBarIndex`, `GetTempShapeshiftBarIndex`, `GetBonusBarIndex`, `HasAction`,
  `GetActionInfo`.
- **없는 것**: `GetExtraBarIndex`, `UnitVehicleSkin`, `GetOverrideBarSkin`, `IsPossessBarVisible`,
  `C_PetBattles.IsInBattle`. 스킨은 `OverrideActionBar`를 참조로 넘겨 `IsShown()`으로 대신 읽는다.
- **매크로 조건** (`SecureCmdOptionParse`, 상태 드라이버): `[vehicleui]`, `[overridebar]`, `[possessbar]`,
  `[shapeshift]`, `[bonusbar]`, `[extrabar]`, `[petbattle]`, `[canexitvehicle]`. 잰 값은 §8-1의 표와 같다.

## 9. 구현 세션에게

이 문서를 만든 세션이 헛돈 자리와, 코드에 손대기 전에 알면 시간이 줄어드는 것이다.

### 9-1. 새로 짜기 전에 베낄 곳

- **버튼, 래퍼, 속성 라우팅은 Debind에 이미 게임에서 도는 모양이 있다.** `Debind.lua`의 `DefaultClickFrame`과
  `CastFrame`, `SecureBindings.lua`의 `SecureHandlerWrapScript(DefaultClickFrame, "OnClick", BindingDriver, pre, post)`,
  `UpdateBindings.lua`의 `*type-<이름>`/`*clickbutton-<이름>` 스탬프다. 프로브를 새로 짜다가 핸들을 `clickbutton`에
  넣는 오류(§4-6)와 선언 순서 실수를 밟았다. 둘 다 이 모양을 따랐으면 안 났다.
- **제한 환경에서 쏠 것은 이름으로 돌려준다.** 래퍼가 속성을 새로 쓰는 것은 누를 때마다 바뀌는 값뿐이다
  (`*action-<이름>`, `*macrotext-<이름>`). Debind가 이긴 매크로 본문을 클릭 때 굽는 자리와 같다.
- **대전 키 양보는 `BindingContexts.lua`에 출처를 더한다**(§5-1). 새 이벤트 프레임과 오버라이드 조작을 따로 만들 일이
  아니다.
- **스니펫 본문을 고치기 전에 `devdocs/restricted-environment.md`를 읽는다.** 틀리면 오류 없이 키 하나가 죽는다.
  `tools/snippet-golden.txt`가 구운 바이트를 잠그고 있다.
- **블리자드 코드는 `reference/wow-ui-source`에 있다**(`devdocs/dev-setup.md`). 이 문서의 줄 번호는 거기 기준이다.

### 9-2. 코드가 틀리기 쉬운 자리

- **플라이아웃 칸을 `type=action`으로 쏘지 않는다**(§4-4). 래퍼에서 `GetActionInfo(slot) == "flyout"`으로 먼저
  가르고 바 버튼을 누른다.
- **기타 행동 버튼의 페이지는 리빌드가 굽는다**(§4-2). 판별은 `HasExtraActionBar()`로 하고, 걸리면 다음 액션으로 넘기지 않고 끊는다. `GetOverrideBarSkin()`은
  기타 행동 버튼만 떠도 0이 아니라서 판별로 못 쓴다(§8-3).
- **페이지 순서는 `ActionBarController_UpdateAll` 그대로다**(§4-1). 보너스 바는 `GetActionBarPage() == 1`일 때만이다.
- **BLOCK은 self, focus 쌍둥이를 갖고 hover 쌍둥이는 안 갖는다**(§3). 각 층 맨 끝에 서고, 키 누름에서 이기면 래퍼가
  `false`를 돌려준다. 개체창 래퍼에서 이기면 `false`가 아니라 `return`으로 흘려준다. `false`면 개체창의 대상 잡기와
  메뉴까지 끊긴다(§3).
- **`GetBindingKey`는 키를 여럿 돌려준다.** xptr에서 `ACTIONBUTTON1`이 `BUTTON3`과 `1` 둘이었다.
- **보호되지 않은 프레임의 핸들은 전투 중 판독이 막힌다**(§3). 전투 중 도는 스니펫에서 `IsShown` 같은 판독을 기대면
  그 자리에서 멈춘다. `OverrideActionBar`, `ActionButtonN`은 보호 프레임이다.
- **`PICKUPACTION`은 누르는 길을 막지 않는다**(§4-6). 이 문서의 앞 판이 틀리게 적었다가 고쳤다.

### 9-3. 이미 정한 것과 안 정한 것

- 정한 것: 걷어낸다(§2), BLOCK과 대응표(§3), 행동 칸 `COMMAND`만 마이그레이션하고 나머지는 저장된 채 파생에서 BLOCK과
  WARNING 이슈로 둔다(§3), 스위치는 바뀔 때 알린다(§3), 바뀐 바는 S1(§4), 대전은 S5를 바인딩
  컨텍스트 양보에 얹는다(§5-1), 지금 동작을 옵션으로 남기지 않는다(§2), 계산식 스위치는 누를 때 잰다(§3), 박자는
  `displayMessage`가 켜진 계산식 스위치에만 남기고 전역 옵션으로 끈다(§3), 수동 스위치와 hover가 박자를 켜지 않게
  하고 `GetHoveredUnit`은 프레임을 다시 읽는다(§3), BLOCK만으로 루프가 꺼지는지를 코드로 먼저 보인다(§9-4).
- 안 정한 것: 행동 칸 말고 대응표에 더할 `COMMAND`가 있는지(§3), 이슈 문구와 행 아이콘, 대전에서 키를 지키고 싶은
  액션의 예외를 둘지(지금은 `keepInBindingContext`가 대전 키를 안 붙든다, §5-1).

### 9-4. BLOCK만으로 루프가 꺼지는지를 코드로 보인다 (2026-09-14, 소유자)

**`UNUSED`와 `COMMAND`를 전부 BLOCK으로 바꿔 끼우고 키 끝에 BLOCK을 덧대는 것만으로 상태 루프가 100% 꺼지는지를
확인하는 코드를 구현 세션이 먼저 만든다.** 걷어내는 나머지 작업은 이 답 위에 선다. 확인해야 하는 것은 셋이다.

- **모든 키가 `alwaysOurs`인가.** `IsKeyAlwaysOurs`는 틀리면 한쪽으로만 틀린다. opaque 조건(축이 없는 조건)과 작업
  예산 소진이 "안 덮임"으로 센다(`Solver.lua`의 `IsKeyAlwaysOurs` 주석). BLOCK이 덮어도 이 둘에 걸린 키는 루프에 남는다. 그런
  키가 실제 프로필 모양에서 나오는지, 나온다면 무엇이 원인인지를 코드가 답해야 한다.
- **`StateDrivenBindings`와 `DirtyKeys`가 비는가.** `ClassifyKey`의 `stateDriven`이 모든 키에서 거짓이면 두 표에
  아무것도 안 들어간다(`UpdateBindings.lua`의 `UpdateBindingsMap`).
- **박자가 꺼지는가.** 0.2초 박자를 원하는지는 키가 아니라 따로 정한다(`UpdateBindings.lua`의 "Does this rebuild
  want the 0.2s beat at all?"). 측정하는 상태, 유닛 행, 계산식 스위치, hover가 있으면 박자가 남는다. 키가 전부
  `alwaysOurs`여도 이 판단이 참이면 루프는 돈다. 지금 코드에서는 수동 스위치와 hover 조건만으로도 참이 된다.
  §3대로 고친 뒤 참이어야 하는 것은 `displayMessage`가 켜진 계산식 스위치가 있고 전역 옵션이 알림을 허용할 때뿐이다.

**답** (2026-09-14). 방출 픽스처에 BLOCK만 넣고 돌렸을 때 루프에 남은 키는 `SHIFT-BUTTON2` 하나였다. 원인은 마우스 버튼
키의 BLOCK에도 붙던 [가리키지 않을 때] 좁히기(`BuildUnitStates`)였다. 그 반쪽은 개체창이 클릭을 먹어 키 바인딩에 오지
않으므로 BLOCK은 좁히지 않는다. 층마다 끝에 BLOCK이 서면 덮기가 구조로 보장되니 `IsKeyAlwaysOurs`와 센티넬은 지웠고,
BLOCK은 솔버를 거치지 않는다.

### 9-5. 테스트가 닿는 곳

- **헤드리스가 덮을 수 있는 것.** 페이지 선택 표(§4-1)는 판별 함수 값만 넣으면 칸이 나오는 순수 계산이다. 기타
  행동 버튼과 고정 페이지 바의 칸, 키 기록이 있는 모든 키가 우리 버튼에 걸리고 틈의 누름이 아무것도 안 내는 것
  (`tests/loopoff_spec.lua`), 대응표, 대전 출처가
  `YieldedKeys`에 넣는 키도 헤드리스로 된다.
- **킷이 덮을 수 있는 것.** 스니펫이 제한 환경에서 컴파일되고 이긴 레코드가 이름을 돌려주는 것, 기타 행동 버튼의
  구운 칸이 `GetExtraBarIndex()`와 맞는 것.
- **원리상 못 덮는 것.** 실제 키 누름으로 바뀐 바의 칸이 나가는 것. 킷은 키를 누를 수 없고, 탈것·빙의·오버라이드
  바·대전은 킷이 만들어 낼 수 없는 게임 상태다. 이 문서의 §4-5, §5는 그 자리를 `Probe_ActionBars.lua` 로그로 잰
  기록이다.
