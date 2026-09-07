# 남의 래퍼 위에 서서 그쪽 본문을 대신 돌린다

> 상태: 계획, 착수 전 (2026-09-07). 게임 PoC는 통과했다(`DebindDev/Probe_WrapSteal.lua`, 워킹 트리).
> 근거와 다툼은 `0-DIARY.md` 2026-09-07 "물러설 이유가 남았나"에 있고, 여기엔 결론과 순서만 둔다.
> `legacy/leaving-unregistered-frames-alone.md`(2026-09-05)가 닫은 문을 다시 여는 문서다.

## 무엇을 하는가

9월 5일에 등록되지 않은 개체창에서 물러선 근거는 둘이었다. 남의 leave 래퍼와 겹치면 어느 한쪽
leave가 죽는다는 것, 그리고 `SecureHandlerUnwrapScript`가 주인을 안 보고 맨 위를 뗀다는 것.
소유자가 "원칙"이라 부른 것도 결국 이것이었다. 우리 때문에 그쪽 동작이 깨질 수 있다는 것.

둘 다 **우리가 항상 맨 위에 서고, 걷어낸 그쪽 본문을 그쪽 헤더 환경에서 우리가 대신 돌려주는**
것으로 닫힌다. 그쪽이 보는 것은 우리가 없을 때와 같아진다. 그래서:

- **재조립 장치가 들어간다.** 프레임을 감쌀 때 이미 붙어 있는 남의 래퍼를 걷어 보관하고 우리
  것을 맨 위에 얹는다. 그 뒤 누가 우리 위에 감싸면 훅이 그 자리에서 같은 일을 한다.
- **찾아내서 집는 문 셋이 돌아온다.** 이름 목록, 헤더 자식, oUF 목록. 3.5.2 그대로다.
- **홀더가 잡은 등록에도 물러나지 않는다.** 물러선 이유가 "두 엔진이 겹치면 hover가 깨진다"였다.
- **`hoverLeaveTaken`(3.5.2)은 돌아오지 않는다.** 우리 leave가 죽는 일이 없어졌다.
- **옵션 하나.** 넘겨받지 않은 프레임까지 집을지. 기본은 켬이라 3.5.2와 같은 범위다. 끄면 지금
  워킹 트리의 동작(블리자드 문과 Clique 문만, 홀더가 잡은 것은 물러남)이다. 재조립 자체는 옵션과
  무관하게 항상 있다. Clique 문으로 온 프레임도 남이 위에 감쌀 수 있다(EUI `allFrames`).
- **경쟁 감지.** 같은 프레임의 재조립 도중에 우리 훅이 다시 들어오면 상대도 되받아치는 것이다.
  그 자리에서 그 프레임에서 물러난다. 이것도 옵션과 무관하다.

## 근거가 되는 사실

전부 `reference/wow-ui-source/.../Blizzard_RestrictedAddOnEnvironment/`에서 읽었고 PoC가 게임에서
확인했다. 다시 조사할 것은 없다.

- `Wrapped_OnLeave`는 프레임 속성 `_wrapentered`가 서 있을 때만 pre 본문을 돌리고, 돌리기 전에
  지운 뒤 아래로 내려간다. leave 래퍼가 여럿이면 **맨 바깥 것 하나만 돈다.** `Wrapped_OnEnter`와
  `Wrapped_Click`에는 그 문이 없어 겹친 본문이 전부 돈다. click은 누가 `false`를 돌리면 끊기고,
  enter도 `false`면 끊긴다.
- `SecureHandlerUnwrapScript(frame, script)`는 맨 위 하나를 떼고 `header, preBody, postBody`를
  돌려준다. 래퍼가 없으면 오류 없이 셋 다 `nil`. 본문을 떼지 않고 읽는 길은 없다. 클로저의
  업밸류이고 열쇠는 파일 안의 `newproxy()`다.
- 헤더 메서드 `:WrapScript`/`:UnwrapScript`는 전역을 부르므로 `hooksecurefunc`가 잡는다.
  단 `SecureHandlerUnwrapScript`의 인자는 `(frame, script)`뿐이라 **누가 뗐는지는 모른다.**
- wrap 본문의 `control`은 헤더의 프레임 핸들이다. `HANDLE:RunFor(otherHandle, body)`는 그 핸들의
  프레임이 가진 관리 환경에서 본문을 돌리고 `control`로 그 핸들 자신을 넘긴다. 그러니 남의 헤더
  핸들에 대고 부르면 남의 환경에서 남의 본문이 돈다. PoC 2와 3이 이것을 확인했다. 그쪽 환경 전역이
  채워지고 비워졌고, 전투 중에도 같았다.
- `HANDLE:SetAttribute`는 `_`로 시작하는 이름을 거부한다. `_wrapentered`를 되살리는 길은 없고,
  그래서 본문을 직접 부르는 것이 유일한 길이다.
- 가드 없이 두 훅이 되받아치면 한 호출 스택 안에서 재귀가 돌아 C 스택 오버플로가 난다(PoC 5,
  깊이 198). 가드가 있으면 셋에서 멈춘다.

## 재조립 규칙

`Reassemble(button, script)`. 세 스크립트(`OnEnter`, `OnLeave`, `OnClick`)가 같은 절차다.

1. `SecureHandlerUnwrapScript(button, script)`를 반복한다. 헤더가 `nil`이면 끝. 헤더가
   `BindingDriver`면 우리 것이니 거기서 멈춘다(우리 것도 떼어진 상태다). 그 사이에 걷은 것을
   순서대로 모은다. 첫 번째가 맨 바깥이다.
2. 우리 것을 만나기 **전에** 걷은 것이 "위", 우리 것을 만나지 못하고 `nil`까지 갔으면 전부
   "위"다(첫 등록). 우리 것을 만난 뒤에는 더 걷지 않으므로 "아래"는 그대로 사슬에 남는다.
3. 붙이는 것: enter와 click은 위에 있던 것 전부, 원래 순서로. **leave는 위에 있던 것 중 맨 처음
   하나만.** 원래 그것만 돌았다. 아래에 남은 것들은 사슬로 원래대로 돈다. enter와 click은 돌고,
   leave는 안 돈다. 우리가 오기 전과 같다.
4. 헤더는 `SecureHandlerSetFrameRef`로 우리 드라이버에 넘기고 본문은 우리 드라이버의 속성으로
   둔다. 제한 환경 안에서는 프레임별 표 하나가 `{ handle, pre, post }` 목록을 스크립트별로 든다.
5. 우리 것을 다시 맨 위에 감싼다. 우리 pre 본문은 그 목록을 먼저 돌린다.
   `h:RunFor(self, pre)`. 하나라도 `false`를 돌리면 우리 몫을 마친 뒤 우리도 `false`를 돌린다.
   click은 그쪽이 돌린 새 버튼 이름을 우리가 안 바꾸면 그대로 넘긴다. post 본문은
   `"local message = ...\n" .. post`로 `RunFor`한다. 원래 순서는 그쪽이 바깥이었으니 그쪽 먼저,
   우리 나중이다. 그래서 같은 키에 override가 둘이면 우리가 나중이라 우리가 이긴다. 사용자가 우리에게
   준 바인딩이 이기는 것이 뜻에 맞다.

트리거는 둘. 등록(`RegisterFrame`이 처음 감싸는 자리)과 `hooksecurefunc("SecureHandlerWrapScript")`.
훅은 헤더가 우리 것이면 지나가고, 행이 없는 프레임이면 지나간다.

`hooksecurefunc("SecureHandlerUnwrapScript")`도 건다. 우리가 든 프레임에서 남이 unwrap을 불렀으면
떨어진 것은 맨 위인 우리 것이다. 누가 뗐는지는 모르므로 **그 스크립트의 보관 목록을 비우고**
다시 `Reassemble`한다. 그쪽은 끄고 싶었던 것이니 그쪽 본문이 멈추는 것이 뜻대로고, 우리는 다시
맨 위다. 잃는 것은 같은 프레임 같은 스크립트에 남의 엔진이 둘 이상 올라와 있고 그중 하나만
끈 경우의 나머지 하나다. 그런 조합은 본 적이 없고, 생기면 그때 `debugstack`으로 부른 쪽을
가리는 방법이 있다.

**재진입 가드가 첫 줄이다.** `_reassembling[button]`이 서 있는데 같은 프레임으로 훅이 들어오면
감싸지 않고 그 프레임의 `ccframes` 행을 지우고 나간다. 판정은 동기다. 타이머로 미루면 그 사이에
스택이 쌓인다. 두 번째 그물로 프레임별 재조립 횟수를 세고 문턱(세션당 프레임당 여덟 정도. 정상
사용은 상대가 켜고 끌 때 하나씩이다)을 넘으면 같은 처리다. 챗창엔 세션에 한 번, 그 프레임의
hover는 다른 애드온이 답한다는 한 줄. 3.5.2의 `WARNING_MESSAGE_HOVER_ANSWERED_ELSEWHERE`가 그
자리였는데 문장은 다시 쓴다.

래퍼는 여전히 우리가 떼지 않는다. 등록 해제는 지금처럼 행을 지우는 것으로 끝이고, 행이 없으면
본문이 물러난다. `Reassemble`이 우리 것을 떼는 것은 바로 다시 얹기 위해서다.

## 하지 않는 것

- **그쪽 본문을 글자로 이어 붙이는 것.** 그쪽 본문의 전역과 `control`은 그쪽 헤더 환경의
  것이라 우리 환경에서는 전부 `nil`이다. `RunFor`만이 길이다.
- **아래에 남은 leave 본문을 되살리는 것.** 우리가 오기 전에도 죽어 있던 것이고 없던 동작을
  만드는 일이다.
- **`hoverLeaveTaken`과 `mouseover` 되묻기(3.5.2).** 우리 leave가 죽는 경우가 없다. 다만
  `UnitWatch`의 `mouseover` 폴백(9월 5일 1단계)은 남긴다. 옵션을 끈 사용자와 Clique가 켜진
  상태에서는 여전히 그 폴백이 답이다.
- **`_wrapentered`를 되살리는 시도.** 제한 환경이 거부한다.
- **재조립을 옵션에 묶는 것.** 옵션은 어느 프레임을 집을지만 정한다.

## 순서

커밋 하나마다 `npm run check`가 통과해야 한다. 스니펫 본문이 바뀌는 단계는 골든을 다시 뜨고
diff를 읽는다. 스니펫 본문을 만지기 전에 `restricted-environment.md`를 읽는다. 재조립 목록 순회는
enter, leave, click 핫패스에 얹히는 것이라 목록이 비었을 때 표 조회 하나로 끝나야 한다.

### 1. 재조립 장치

`Debind/FrameRegistry.lua`와 `Debind/SecureBindings.lua`.

- `Reassemble(button, script)`, 위 규칙대로. `RegisterFrame`의 `_hoverWrapped` 분기와
  `ApplyDebindRouting`의 `_wrapped` 분기가 직접 `SecureHandlerWrapScript`를 부르던 자리를 이것으로
  바꾼다. 이미 감싼 프레임은 지금처럼 다시 안 감싼다.
- 보관: 드라이버에 `SecureHandlerSetFrameRef(BindingDriver, "over_<n>", header)`와
  `SetAttribute("over_pre_<n>", pre)`, `over_post_<n>`. 제한 환경에는 `Overs[button][script]`
  목록. `Execute` 한 번으로 그 프레임 그 스크립트의 목록을 통째로 갈아 쓴다.
- `setup_onenter`, `setup_onleave`, 클릭 pre 본문(`UnitFrameClickPre`)의 앞에 순회를 넣는다.
  `setup_onenter`는 행이 없으면 `setup_onleave`를 부르고 나가는데, 그 앞에서 순회가 돌아야 한다.
  행이 없어도 우리 래퍼는 남아 있고 그 아래 그쪽 본문은 우리 목록 안에 있다. 행을 지울 때 목록도
  지우는지, 아니면 남기는지는 여기서 정한다. **남긴다.** 우리가 물러난 프레임에서도 그쪽 본문은
  돌아야 한다. 목록을 지우면 그쪽이 우리 때문에 멈춘다.
- 훅 둘. `hooksecurefunc("SecureHandlerWrapScript", ...)`, `hooksecurefunc("SecureHandlerUnwrapScript",
  ...)`. `DebindCliqueFake`의 `OnHolderWrap`도 같은 전역에 걸려 있는데 하는 일이 다르니(되묻기)
  그대로 둔다. 순서는 상관없다.
- 재진입 가드, 횟수, 물러남, 챗창 한 줄. 문자열은 `Locales/enUS.lua`, `koKR.lua`.
  `writing-user-facing-text.md`를 먼저 읽는다.
- 헤드리스: `tests/restricted.lua`와 `tests/hover_spec.lua`가 래퍼 사슬을 어떻게 흉내 내는지 먼저
  본다. `_wrapentered` 문이 없으면 심에 넣는다. 그래야 "남이 위에 감싸면 우리 leave가 안 온다"가
  고치기 전에 빨갛게 나온다. 케이스: 남이 위에 감싼 뒤 재조립하면 우리 leave가 온다, 그쪽 본문이
  그쪽 환경에서 돌았다(심의 환경 표로 본다), leave는 위의 첫 것만 붙는다, enter는 전부 순서대로,
  `false`가 전달된다, post의 `message`가 들어간다, 남의 unwrap 뒤에 우리가 다시 맨 위다, 재진입에서
  행이 지워진다. `SecureHandlerUnwrapScript` 심이 없으면 `wow_shim.lua`에 넣는다.
- `/debtest`: `Probe_WrapSteal.lua`의 F 역할과 U 버튼을 킷으로 옮긴다. 케이스는 PoC의 1(대조군은
  빼고), 2, 4, 5g, 그리고 post 본문을 둔 F. 프로브 파일은 그때 지운다. TOC 줄도.
- 골든 셋 다시 뜬다.

#### 계획과 갈린 것

- **`setup_onenter`/`setup_onleave`가 둘로 갈렸다.** 계획은 순회를 그 본문 앞에 넣으라고 했는데,
  `setup_onenter`가 행이 없을 때 `setup_onleave`를 부르므로 진입 한 번에 leave 목록까지 돌게
  된다. 헤더 문의 `clickcast_onenter`도 같은 본문을 쓰는데 그쪽은 걷어온 것이 없다. 그래서
  본문은 `SETUP_ONENTER_SNIPPET` 하나로 두고, 순회를 앞뒤에 **글자로 이어 붙인** 것을
  `setup_onenter_wrap`/`setup_onleave_wrap`으로 따로 두었다. 래퍼에 올라가는 것은 `_wrap` 쪽이다.
  부르지 않고 이어 붙인 이유는 그 사이에 `RunAttribute`가 들어가면 커서가 넘는 프레임마다
  치르게 되기 때문이다.
- **우리도 post 본문을 갖게 됐다.** 계획에 없던 것인데, 블리자드는 pre가 **두 번째 값을 냈을
  때만** post를 부른다(`Wrapped_OnEnter`의 `message ~= nil`). 그래서 걷어온 post가 하나라도
  있을 때만 우리 pre가 `nil, "m"`을 돌려주고, 그 경우에만 우리 post가 불려서 그쪽 post를 돌린다.
  걷어온 것이 없는 프레임은 post 호출을 한 번도 안 치른다.
- **`false`는 순회를 끊는다.** 계획은 "하나라도 `false`를 돌리면 우리 몫을 마친 뒤 우리도
  `false`를 돌린다"였는데, 그러면 원래 안 돌았을 아래 것들이 돈다. 블리자드는 `false`를 만나면
  내려가지 않으므로 거기서 끊고, **끊은 것보다 위에 있던 것들의 post는 그 자리에서 돌린다** -
  원래 그 자리에서 돌았기 때문이다. 끊은 자기 것은 안 돈다.
- **보관은 갈아 쓰기가 아니라 앞에 붙이기다.** 계획의 "목록을 통째로 갈아 쓴다"로는 한 애드온이
  래퍼를 둘째로 얹는 순간 첫째가 사라졌다. 이번에 걷은 것이 앞(더 바깥)이고 전에 걷은 것이
  뒤다. 갈아 쓰기는 두 자리에만 남겼다: `OnLeave`(원래 하나만 도는 자리라 새 것이 옛 것을 묻는다)와
  남이 unwrap한 뒤(그때는 프레임에 남은 것이 전부다).
- **걷어온 post 앞에 붙이는 줄은 `local message, button, down = ...`다.** 계획은 `local message`
  하나였는데, 클릭 post는 블리자드가 셋을 넘긴다. 한 줄이 셋 다 덮으므로 스크립트마다 다른 줄을
  두지 않았다.
- **`Reassemble`이 부르는 unwrap은 `unwrappingOwnScripts`를 세운다.** `DebindCliqueFake`가 같은
  전역을 듣고 있고 인자로는 우리 호출을 못 가른다. 이걸 안 세우면 재조립할 때마다 홀더가 놓았다고
  듣고 프레임을 되묻는다. `holder_spec`이 잡았다.
- **`tools/lib/snippets.js`가 조각 참조만으로 된 본문을 검사에서 빼고 있었다.** `SetAttribute(이름,
  BakeSnippet(A_SNIPPET))`처럼 문자열 리터럴이 하나도 없는 인자를 통째로 건너뛴다. 이번에 그런
  본문이 여섯 생겼고 전부 조용히 검사 밖으로 나갔다. 그 파일 머리말이 막으려던 실패 그 자체라
  게이트를 걷었다. 스니펫 수가 43개에서 58개가 됐다.
- **헤드리스는 새 파일 `tests/reassemble_spec.lua`다.** 그리고 심이 래퍼 사슬을 진짜로 들게
  됐다(`wow_frames.lua`의 `wrappers`/`M.wrapperChain`, `restricted.lua`의 `Interp:runWrapped`).
  `hoverEnter`/`hoverLeave`가 이제 그 사슬을 지나가므로 기존 호버 케이스도 클라이언트와 같은
  순서를 지난다. 커서 없이 슬롯만 비우던 자리는 `Interp:clearHoverSlot`으로 갈랐다.
  여섯 케이스가 고치기 전 코드에서 빨갛게 나오는 것을 봤고, post의 `message` 케이스는 옛 코드에서는
  초록이라 `overMessage` 전달을 빼서 빨간 것을 확인했다.
- **`/debtest`에 전투 중 케이스는 안 세웠다.** 킷은 락다운을 흉내 낼 수 없고, 보호된 프레임을
  전투 중에 감싸는 것은 클라이언트가 거절하므로 몰 것 자체가 없다. 대신 네 케이스가
  `frame:GetScript("OnEnter")(frame, true)`로 **래퍼 사슬을 진짜로 돌린다** -
  `IsWrapEligible`이 보호된 프레임에는 비보안 호출도 통과시킨다(`SecureHandlers.lua`).

### 2. 문 셋을 되살린다

`git show v3.5.2:Debind/FrameRegistry.lua`가 원본이다. 9월 5일 문서의 2단계가 뺀 것을 되돌린다.
그 문서에 이름이 다 적혀 있다.

- `NAMED_UNIT_FRAMES`, `NameOf`, `TakeNamedFrame`, 훅 여섯(`RegisterStateDriver`,
  `RegisterAttributeDriver`, `SecureUnitButton_OnLoad`, `RegisterUnitWatch`, `UnitFrame_Initialize`,
  `SecureHandlerSetFrameRef`). `SecureHandlerWrapScript` 훅은 1단계 것에 `TakeNamedFrame`을 붙인다.
- `CollectHeaderChildren`과 `SecureGroupHeader_OnLoad`/`_Update`, `SecureGroupPetHeader_OnLoad`/`_Update`
  훅, `_headerChildren`, `RegisterFrame`의 `told` 헤더 분기. `UnitWatch.lua`의 `OwnGroupHeaders`.
- `CollectOUFFrames`, `_oufLibraries`, `Events.lua`의 `PLAYER_ENTERING_WORLD` 호출.
- `.luacheckrc` 전역.
- **되돌리지 않는 것.** `MarkWrappedOver`, `OURS_WRAPPED`, `hoverLeaveTaken` 일체(3단계가 뺀 것).
  9월 6일과 7일에 들어간 종류 읽기(`IsGroupHeaderChild`, VuhDo 이름 규칙)는 그대로 두고 헤더 문이
  그 위에 얹힌다. 헤더 자식은 헤더 문이 group으로 답하고, 그 답이 읽기보다 앞선다(3.5.2 규칙).
- 전부 옵션 뒤에 선다(4단계). 옵션이 꺼져 있으면 훅은 걸리되 `TakeNamedFrame`과 헤더 자식
  등록과 oUF 순회는 아무것도 하지 않는다. 옵션 상태는 로그인 때 한 번 읽는다(블리자드 체크박스와 같은 규칙,
  `REQUIRES_RELOAD`).
- 헤드리스: `git show v3.5.2:tests/frames_spec.lua`에서 9월 5일 문서가 지운 아홉 케이스를 되살린다.
  심도 같이(`wow_shim.lua`의 `SecureGroupHeader_*`, `wow_frames.lua`의 `SecureUnitButton_OnLoad`,
  `UnitFrame_Initialize`). `unitwatch_spec.lua`의 헤더 둘도.
- `/debtest`: 9월 5일 문서가 지운 EUI 케이스 셋(단일 개체창, 독립 파티/공대 프레임, 헤더 자식)을
  `git show v3.5.2:DebindDev/DebindTest.lua`에서 되살린다. `applies`는 EUI가 로드됐고 옵션이 켜져
  있을 때. HoverCast 상태는 이제 조건이 아니다.

#### 계획과 갈린 것

- **`SecureHandlerWrapScript` 훅은 1단계 것 하나로 남았다.** 3.5.2에는 `OnSecureWrap`이 따로
  있었는데, 1단계의 `OnForeignWrap`이 같은 전역에 같은 헤더 검사로 서 있으므로 거기에
  `TakeNamedFrame` 한 줄을 얹었다. 훅 둘이 같은 조건을 두 번 쓰는 꼴을 만들지 않았다.
- **`applies`에 옵션은 아직 안 들어갔다.** 옵션이 4단계에 생기므로 지금은 EUI가 로드됐는지만
  본다. 4단계에서 그 줄을 더한다.
- `UNIT_FRAMETYPES` 위 주석과 `RegisterFrame`의 `told` 위 주석은 9월 5일에 헤더 문을 근거에서
  뺐던 것이라 다시 넣었고, 9월 6일에 들어간 `IsGroupHeaderChild`와 어느 쪽이 이기는지를
  `_headerChildren` 주석에 적었다. 들은 것이 읽은 것을 이긴다.
- 되살린 아홉 케이스가 문을 다시 끊었을 때 빨갛게 나오는 것을 봤다. 열 번째인 "a frame the list
  does not name is left alone"은 없음을 재는 케이스라 어느 쪽에서도 초록이다.

### 3. 홀더에 물러나지 않는다

`DebindCliqueFake/DebindCliqueFake.lua`.

- `AskHolder(frame)`: `holder[frame]`이 참이어도 옵션이 켜져 있으면 등록한다. 꺼져 있으면 지금처럼
  `deferred`에 적고 물러난다. `Hook`, `AttachClickCastFrames`, `AskHolderAgain`, `OnHolderWrap`은
  그대로다. 프록시 뒤에서 쓰기를 듣는 것은 여전히 필요하다.
- 옵션은 `DebindCliqueFake`가 Debind보다 먼저 로드되므로 직접 읽을 수 없다. `Public.lua`가 이미
  둘 사이의 문이니 거기에 읽기 함수를 하나 둔다. 로그인 전에 들어온 프레임은 어차피 큐에 있다.
- 헤드리스 `tests/holder_spec.lua`: "홀더가 잡은 프레임엔 행이 안 생긴다"가 옵션 켬에서는
  뒤집힌다. 옵션 양쪽으로 케이스를 나눈다.
- `/debtest`: "the holder keeps the name and we take what it drops"를 옵션 켬 기준으로 다시 쓴다.
  "HoverCast on leaves the name with the pack"은 이름이 그쪽에 남는 것은 여전히 맞고 프레임은
  우리에게도 오니 그렇게 고친다.

### 4. 옵션

- `db.global`에 필드 하나. 이름은 코드 쪽 것이라 자유다(예: `takeUnregisteredFrames`). 없으면
  참이다. 끄는 것은 지우는 것이 아니라서 다른 값을 남길 일은 없다.
- 자리는 `DropDownMenus.lua`의 블리자드 개체창 항목 옆. 같은 `REQUIRES_RELOAD` 툴팁을 단다.
- 문자열은 `writing-user-facing-text.md`대로. 코드 낱말(wrap, hook, register)은 쓰지 않는다.
  사용자가 아는 것은 "내 개체창 애드온이 자체 hover cast를 켜 둔 상태에서도 Debind 키가 그 위에서
  듣는가"다.
- 헤드리스: 옵션이 없는 프로필이 참으로 읽히는 것(`migration_spec` 또는 `frames_spec`).

### 5. 팝업과 문서

- `UNIT_FRAME_NOTICE`(`DebindUI.lua` `DEBIND_UNIT_FRAME_NOTICE`, `Events.lua` `PLAYER_LOGIN`,
  `Profile.lua` `InitDB`의 `unitFrameNoticeSeen`, `migration_spec`의 두 케이스)는 **뺀다.** 그
  팝업은 3.5 사용자가 프레임을 잃는다는 안내였고, 기본값이 켬이면 잃는 것이 없다. 9월 7일
  일기의 "새 설치에도 표시해"는 그 안내가 있을 때의 말이라 함께 사라진다. 필드 `unitFrameNoticeSeen`은
  이미 쓰인 프로필에 남아 있어도 읽는 곳이 없으면 그만이다. 지우지 않는다.
- `CHANGELOG.md` `# 3.6`의 처음 세 문단(존중한다, 조용해진 키, 되찾지 않는다)과 다섯째(3.5.2가
  사라졌다)를 다시 쓴다. 3.5.2 문단은 나간 버전의 기록이라 그대로. 새 문단이 말할 것: 다른
  애드온의 hover cast가 켜진 프레임에서도 Debind 키가 듣고 그쪽 기능도 그대로 동작한다, 겹치는
  키는 Debind가 받는다, 끄는 옵션이 있다.
- `README.md`: 9월 5일 문서 6단계가 고친 세 줄(26, 121, 163행 근처)을 다시 본다.
- `0-ROADMAP.md`의 "다음 릴리스" 줄을 이 문서로 바꾼다. `legacy/leaving-unregistered-frames-alone.md`
  상태 줄에 뒤집혔다고 적고 이 문서를 가리킨다. `.zzz/unit-frame-discovery.md` 상태 줄의 뒤집힘
  표시를 다시 뒤집는다.
- 끝나면 이 문서를 `devdocs/legacy/`로 옮긴다.

## 커버리지

헤드리스가 드는 것: 재조립 규칙 전부(위 첫 것만 붙는 leave, 전부 붙는 enter, `false`와
`message` 전달, 남의 unwrap 뒤 복귀, 재진입에서 물러남), 문 셋의 옛 케이스 아홉, 홀더 규칙의
옵션 양쪽, 옵션 기본값.

`/debtest`가 드는 것: 가짜 헤더 F가 감싼 버튼에서 그쪽 키가 걸리고 풀리는 것과 우리 hover가
채워지고 비워지는 것, 전투 중 같은 것, F의 unwrap 뒤 우리가 맨 위인 것, 되받아치는 F에서
셋 안에 멈추는 것, post 본문의 `message`. EUI 케이스 셋과 홀더 케이스 둘.

닿지 못하는 것: 실제 EUI의 HoverCast를 세션 중에 껐다 켜는 전환. 킷은 EUI 설정을 바꾸지 않는다.
F가 같은 호출 순서(`WrapScript` 둘, `UnwrapScript` 둘)를 내니 그 길은 F로 본다. 커서가 실제로
프레임을 오가는 것은 킷이 못 하므로 hover 슬롯 확인은 `OnEnter`/`OnLeave`를 직접 부르는 것으로
한다. 그건 지금 `hover_spec`과 킷이 이미 하는 방식이다.
