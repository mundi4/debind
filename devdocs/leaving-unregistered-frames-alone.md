# 등록되지 않은 개체창은 건드리지 않는다

> 상태: 계획 확정, 착수 전 (2026-09-05). 다른 세션이 이어받아도 되게 썼다. 근거는 `0-DIARY.md`
> 2026-09-05에 있고 여기엔
> 결론과 순서만 둔다.

## 무엇을 하는가

프레임에 손을 대는 것은 **주인이 넘겨준 프레임에만** 한다. 넘겨주는 문은 둘뿐이다.

- **블리자드 기본 개체창.** `UpdateBlizzardFrames`의 고정 목록과 `CompactUnitFrame_SetUpFrame` 훅.
  주인이 블리자드라 우리 옵션 토글이 곧 그쪽 말이다.
- **Clique 모양의 등록.** `ClickCastFrames[frame] = …`, `Clique:RegisterUnitFrame`, 헤더의
  `clickcast_register`. Clique는 API의 모양만 정한 것이고, Clique 애드온 자체는 꺼져 있어야 한다.

그 밖의 문, 즉 **누가 주지 않아도 우리가 찾아내서 집던 문 셋**을 없앤다. 8월 24일 커밋 `5ab917c`
("Go and find the unit frames other addons never hand over")와 그 뒤의 `ff3db73`, `2d2098a`가 넣은
것들이다.

외부에서 들어오는 **해제는 그대로 받는다.** 주인이 돌려달라는 프레임에서 클릭을 가로챌 자격은 없다.
없애는 해제는 우리 내부에서 우리가 부르던 것뿐이다.

래퍼는 **어느 경우에도 떼지 않는다.** `SecureHandlerUnwrapScript`는 맨 위 것을 떼므로 남이 우리 뒤에
감쌌으면 남의 것이 떨어진다. 켜고 끄는 것은 지금처럼 `ccframes` 행의 유무가 한다. 유일한 예외는
테스트 킷의 재베이크가 쓰는 `RewrapUnitFrames`이고, 그건 실제 플레이 경로에 없다.

## 잃는 것과 메우는 것

등록되지 않은 개체창(HoverCast를 켠 EllesmereUI, Clique를 지원하지 않는 팩)에서 잃는 것:

- 개체창에 마우스 올림 조건, 그 개체창 위의 마우스 버튼 단축키.
- **전투 중** custom target 지정. 클릭으로 잡으려면 `OnClick`을 감싸야 하고 키로 잡으려면 hover
  추적이 있어야 하는데, 둘 다 그 프레임을 감싸는 일이다. 등록 없이 되는 길은 없다.

메우는 것: **비전투에서는** `UnitWatch`가 `hover`를 못 채우면 `mouseover`로 떨어진다. 개체창 위에
커서가 있으면 게임이 `mouseover`를 세우고 비보안 쪽 `ResolveUnitToken`이 그것을 `raid12` 같은
토큰으로 푼다. 전투 중엔 그 풀이가 안 되니(보호된 프레임에 속성을 못 쓴다) 실패 메시지가 나간다.

## 하지 않는 것

- `ReclaimClickCastFrames`. **이름을 쥔 쪽이 답하고, 답하지 않은 등록만 우리가 받는다.** 남이
  `ClickCastFrames`를 자기 프록시로 갈아 끼웠으면 되찾지 않는다. 대신 그 프록시의 `__newindex`를
  감싸서, 원래 것을 먼저 부른 뒤 `ClickCastFrames[frame]`을 되묻는다. `true`면 그쪽이 잡은 것이라
  물러나고, `nil`이면 적어만 두고 버린 것이라 우리가 등록한다. `nil` 쓰기는 우리 해제로 흘린다.
  EUI 9.1.6은 `allFrames`가 꺼져 있으면 남의 등록을 담기만 하고 아무 엔진에도 안 붙이며, 헤더
  프로토콜은 어느 설정에서도 안 받는다. 이 규칙이면 EUI 설정도 프레임 이름도 안 읽고 그 둘이
  갈린다. `__metatable`로 잠근 프록시엔 아무것도 안 한다. 로드 때 한 번 `Claim()`으로 먼저 있던
  평범한 표(메타테이블 없는 것)를 넘겨받는 것은 되찾기가 아니라 남기고, 메타테이블이 걸린 표는 로드
  때 만나도 위와 같이 다룬다.
- `hoverLeaveTaken` 장치(3.5.2). Clique 자체가 `OnEnter`/`OnLeave` 래퍼로 hover를 추적하므로, Clique에
  프레임을 넘기고 그 위에 leave를 또 감싸는 애드온은 Clique에서도 hover가 끊긴다. 그 애드온이 Clique
  지원을 깨뜨리는 것이고 우리가 메울 일이 아니다.
- `DB_VERSION` 범프. 팝업의 "봤다" 표시는 평범한 필드 하나로 한다(2026-08-27 결정).
- 우클릭 메뉴의 custom target 항목 복원. `5ab917c`가 지운 것이고 왜 지웠는지 기록이 없다. 이 트랙과
  별개다.

## 순서

커밋 하나마다 `npm run check`가 통과해야 한다. 스니펫 본문이 바뀌는 단계는 골든을 다시 뜨고
diff를 읽는다(`node tools/check-snippet-golden.js --update`, `lua5.1 tests/run.lua --update-golden`).
`/debtest` 케이스는 각 단계에서 등록만 하고 언급하지 않는다.

### 1. custom target의 `mouseover` 폴백

문을 닫기 **전에** 메울 것을 먼저 넣는다.

- `Debind/UnitWatch.lua`, `UnitWatch:SetAttribute("_onattributechanged", …)` 본문. `unit == "hover"`
  분기에서 `GetHoveredUnit`이 `nil`을 주면 `UnitExists("mouseover")`일 때 `unit = "mouseover"`로 둔다.
  그 뒤는 이미 깔린 길이다. 비전투면 `ResolveUnitToken`이 토큰으로 풀고, 전투 중이면 값이
  `mouseover`인 채로 `UnitExists(unit)` 분기에 떨어져 `OnSetCustomTargetFailed`가 불린다.
- `OnSetCustomTargetFailed`(같은 파일, 비보안). 전투 중 `mouseover`를 받으면 `DoResolveUnitToken`이
  `UnitInRaid`·`UnitIsUnit`을 `mouseover`에 부른다. 12.1 secret 값이 나올 수 있으니 그 경로의 유닛
  API 호출이 가드를 거치는지 확인하고, 아니면 `SameUnit`처럼 가드된 헬퍼로 바꾼다
  (`secret-reads-must-stay-guarded`). `CUSTOM_TARGET_HELP_MESSAGE_*`는 "개체창에 마우스를 올린 채로
  해 보십시오"인데, 이 경우는 이미 개체창 위에서 나온 것이라 말이 안 맞는다.
  `originalValue == "hover"`이고 값이 `mouseover`인 경우엔 도움말을 붙이지 않는다.
- 헤드리스: `tests/frames_spec.lua`의 "a unit that exists resolves to the token it is standing in"과
  "nothing is resolved in combat" 옆에, `hover`가 비었을 때 `mouseover`로 떨어지는 경우와 `mouseover`도
  없을 때 아무것도 안 하는 경우를 더한다. **고치기 전에 빨간 것을 본다.**
- `/debtest`: 등록하지 않은 `SecureUnitButtonTemplate` 프레임(`CreateTestUnitFrame`을 등록 없이 쓰는
  변형) 위에서 `SETCUSTOM` 키를 눌러 비전투에 지정되는 것, 전투 중엔 실패 메시지가 나가는 것.

### 2. 찾아내서 집는 문 셋을 없앤다

전부 `Debind/FrameRegistry.lua`다. 함수 이름으로 찾는다.

- **oUF 목록.** `DebindPrivate.CollectOUFFrames`, `_oufLibraries`, 그 위 주석. 호출부는
  `Debind/Events.lua`의 `Events.PLAYER_ENTERING_WORLD`. 그 핸들러가 비면 등록도 뺀다.
- **이름 목록.** `NAMED_UNIT_FRAMES`, `NameOf`, `TakeNamedFrame`, 그 위의 긴 주석 블록. 훅:
  `RegisterStateDriver`, `RegisterAttributeDriver`, `SecureUnitButton_OnLoad`, `RegisterUnitWatch`,
  `UnitFrame_Initialize`, `SecureHandlerSetFrameRef`(`OnSecureFrameRef`). `SecureHandlerWrapScript`
  훅(`OnSecureWrap`)은 3단계에서 표시 용도가 나가고 4단계에서 되묻기 트리거로 다시 쓰이니, 여기서는
  `TakeNamedFrame` 호출만 뺀다.
- **헤더 자식.** `CollectHeaderChildren`과 `SecureGroupHeader_OnLoad`/`_Update`,
  `SecureGroupPetHeader_OnLoad`/`_Update` 훅 넷. `_headerChildren`과 `RegisterFrame` 안의
  `told = _headerChildren[button] and … or UNITFRAME_TYPES[type]`에서 헤더 분기.
  `Debind/UnitWatch.lua`의 `DebindPrivate.OwnGroupHeaders`는 쓰는 곳이 이것뿐이니 같이 뺀다.
- **남기는 것.** `ReadFrameType`, `DeriveFrameType`, `UNIT_FRAMETYPES`, `GROUP_NAME_WORDS`. Clique 문으로
  온 프레임은 종류를 안 들고 오므로 여전히 유닛에서 읽어야 한다. `RegisterFrame`의 "unknown은 답이
  아니라서 두 번째 등록을 받는다" 논리도 그대로다. `CompactUnitFrame_SetUpFrame` 훅도 그대로다
  (블리자드 문). `MarkWrappedOver`는 3단계까지 그대로 둔다.
- `.luacheckrc`: `5ab917c`, `ff3db73`가 넣은 전역(`SecureGroupHeader_OnLoad` 등)을 뺀다. 안 쓰는
  전역이 남아도 lint는 통과하니, `git show 5ab917c ff3db73 -- .luacheckrc`로 대조해서 뺀다.
- 헤드리스 `tests/frames_spec.lua`에서 지우는 케이스: "a library's frames are fetched, and the ones
  appended after them", "a pack's own frames are taken by name as it wires them up", "the other doors
  take the same frames", "a frame the list does not name is left alone", "our own wrapping does not
  come back through the door", "a header hands over its children when it is loaded", "children made
  after the load are taken on the next update", "a pet header's children are group frames too", "the
  walk stops at the first missing child". 그 위의 `CollectOUFFrames` 헬퍼와 `ForeignFrame`도
  쓰는 곳이 없어지면 뺀다. **남기는 케이스:** "a frame nobody described is read off its own unit",
  "a party frame holding the player is still a party frame", "a frame named for the player is the
  player frame", "an addon named for a group frame does not make all its frames group frames",
  "a frame that could not be read is asked again". 이건 Clique 문에도 필요한 종류 읽기다.
  `tests/wow_shim.lua`, `tests/wow_frames.lua`의 `SecureGroupHeader_*`, `SecureUnitButton_OnLoad`,
  `UnitFrame_Initialize`, `RegisterUnitWatch`, `GetAddOnMetadata` 심은 다른 스펙이 안 쓰면 뺀다.
- `/debtest`: `DebindDev/DebindTest.lua`의 EllesmereUI 케이스 셋("the single unit frames are wired,
  and read for what they are", "the standalone party and raid frames are wired as group frames",
  "the header's own children are wired as group frames")은 이름 목록과 헤더 쓸어담기를 전제하니
  지운다. 대신 하나를 세운다. **HoverCast가 꺼진 EUI**는 단일 개체창과 공격대 프레임을
  `ClickCastFrames[frame] = true`로 넘기므로(`EUI_RaidFrames_ClickCast.lua`의 `AddFrameToClickCast`,
  `EllesmereUIUnitFrames.lua`의 `SetupUnitMenu`), 그 문으로 온 행이 있고 종류가 유닛에서 읽혀
  있는지 본다. `applies`는 EUI가 로드됐고 `_G._ERF_IsHoverCastEnabled()`가 거짓일 때.
- `0-DIARY.md`의 2026-09-05 치는 이 문서와 함께 착수 전 문서 커밋에 이미 들어가 있다. 여기서 더 쓸 것은 없다.

### 3. `hoverLeaveTaken` 장치를 걷어낸다

`07867c6`과 `680fc91`이 넣은 것 전부. `git show 07867c6 680fc91 --stat`으로 대조한다.

- `Debind/FrameRegistry.lua`: `_hoverLeaveTaken`, `WriteHoverLeaveTaken`,
  `DebindPrivate.RestoreHoverLeaveTaken`, `MarkWrappedOver`(`OnSecureWrap`은 4단계의 트리거로 남기고 그 안의 `MarkWrappedOver` 호출만 뺀다), `OURS_WRAPPED`,
  `_warnedWrappedOver`, `WarnWrappedOver`, `RegisterFrame` 끝의
  `RestoreHoverLeaveTaken` 호출과 그 주석, `_hoverWrapped` 위 주석 중 이 장치를 가리키는 부분.
- `Debind/SecureBindings.lua`: `GetHoveredUnit`(Clique 아닌 쪽)의 `hoverLeaveTaken` 분기와
  `mouseover` 폴백, 그 위 주석. `EvalClickCastFrame`과 클릭 pre 본문의
  `evalFrame.hoverLeaveTaken` 분기 둘. 남는 본문이 `States.unitframe.unit`만 돌려주는 꼴이 된다.
- `Debind/UpdateBindings.lua`: 폴링 스니펫의 `unitframe.hoverLeaveTaken and not UnitExists("mouseover")`
  분기와 그 위 주석 블록. `DebindPrivate.hoverIsRead`는 `WarnWrappedOver`만 읽으니 같이 뺀다.
- `Debind/Locales/enUS.lua`, `koKR.lua`: `WARNING_MESSAGE_HOVER_ANSWERED_ELSEWHERE`.
- `DebindDev/Probe_HoverLeaveTaken.lua` 파일 삭제(TOC엔 이미 없다).
- 골든 둘 다시 뜨기. `tools/snippet-golden.txt`에 `hoverLeaveTaken`이 여섯 군데 있으니 diff에서
  그것만 사라졌는지 본다.
- `CHANGELOG.md`의 3.5.2 문단은 이미 나간 버전의 기록이라 손대지 않는다. 새 노트(6단계)에서
  되돌렸다고 쓴다.

### 4. 되찾기를 "홀더의 프록시에 훅"으로 바꾼다

전부 `DebindCliqueFake/DebindCliqueFake.lua`다.

- **`Claim()`을 둘로 가른다.** 전역이 없거나 메타테이블이 없는 표면 지금처럼 우리 프록시를 세우고
  `Adopt`한다. 메타테이블이 있고 우리 것이 아니면 `Hook(previous)`로 간다. 로드 때와
  `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_ENABLED`에서 같은 함수를 부르되, 이름은
  `ReclaimClickCastFrames`에서 `AttachClickCastFrames` 같은 것으로 바꾼다. 되찾는 일이 없어졌으니
  이름이 거짓말을 하면 안 된다.
- **`Hook(proxy)`.** `getmetatable(proxy)`가 `nil`이면(`__metatable`로 잠김) 아무것도 안 하고 돌아간다.
  이미 감싼 메타테이블이면(약한 표에 표시) 돌아간다. 아니면 `mt.__newindex`를 우리 함수로 바꾼다.
  우리 함수는 원래 `__newindex(t, frame, value)`를 먼저 부르고, `value`가 `nil`/`false`면
  `DebindPublic:UnregisterFrame(frame)`, 아니면 `proxy[frame]`(원래 `__index`)을 읽어 `true`면
  `deferred[frame] = true`로 적고 물러나고, `nil`이면 `DebindPublic:RegisterFrame(frame, value)`.
  `__index`는 건드리지 않는다. 원래 `__newindex`가 없는 프록시(순수 `__index`만 있는 것)는 쓰기가
  rawset으로 떨어지니 감쌀 것이 없고, 그 표는 평범한 표처럼 `Adopt`한다.
- **되묻기.** `deferred`는 약한 키 표. `PLAYER_ENTERING_WORLD`와 `PLAYER_REGEN_ENABLED`에서 프록시가
  우리 것이 아니면, `deferred`의 프레임과 `ccframes`에 행이 있으면서 `hd`가 아닌 프레임에 대해
  `proxy[frame]`을 다시 읽는다. `deferred`에 있는데 `nil`이 됐으면 등록하고 `deferred`에서 뺀다.
  행이 있는데 `true`가 됐으면 해제하고 `deferred`에 넣는다. 전투 중엔 어차피 이 자리에 안 온다.
- **트리거.** 홀더가 프레임을 잡고 놓는 순간을 블리자드 함수로 듣는다. 전역
  `SecureHandlerWrapScript`와 `SecureHandlerUnwrapScript`에 `hooksecurefunc`를 건다(메서드 꼴
  `header:WrapScript`도 `SecureHandlers.lua`의 `SecureHandlerMethod_WrapScript`가 호출 시점에 전역
  이름으로 부르니 같이 잡힌다). 훅에서는 프레임이 우리가 아는 것(`ccframes` 행 또는 `deferred`)이고
  헤더가 `BindingDriver`가 아닐 때만, `C_Timer.After(0)`으로 그 프레임 하나의 되묻기를 건다. 그
  되묻기 앞에서 전역의 메타테이블이 바뀌었으면 `Hook`을 먼저 붙인다. 이 훅은 3단계에서 나가는
  `OnSecureWrap`과 자리가 같지만 하는 일이 다르다(표시가 아니라 되묻기). 전투 중이면 걸지 않고
  `PLAYER_REGEN_ENABLED`의 되묻기에 맡긴다. 애드온 이름도 프레임 이름도 안 본다.
- **홀더가 놓을 때 `UnwrapScript`를 부르는 것이 "잡힌 등록은 물러난다"를 필수로 만든다.** EUI의
  `DoUnregisterFrame`은 `header:UnwrapScript(frame, "OnEnter"/"OnLeave")`를 부르고, 그건 맨 위
  래퍼를 뗀다. 우리가 그 위에 감싸 있었다면 우리 래퍼가 떨어지고 `_hoverWrapped`는 여전히 감싼
  줄 안다. 홀더가 잡은 프레임에 우리가 올라가지 않는 것이 그 사고를 막는 유일한 길이다.
- `Debind/Events.lua`: 두 이벤트의 호출을 새 이름으로. 주석은 "이름을 되찾는다"가 아니라 "홀더가
  버린 등록을 받는다"로 다시 쓴다.
- **남기는 것.** 로드 때 `Claim()`, `Adopt`, `ccframesMeta`, `registered`.
- 헤드리스 `tests/`: `ReclaimClickCastFrames`를 부르는 스펙을 새 이름으로 바꾸고, 다음을 더한다.
  메타테이블이 걸린 표를 만나면 갈아 끼우지 않는 것, 그 프록시에 `true`를 쓰면 홀더의 `__index`가
  `true`를 줄 때는 행이 안 생기고 `nil`을 줄 때는 생기는 것, `nil` 쓰기가 행을 지우는 것,
  `__metatable`이 잠긴 표엔 손대지 않는 것, 되묻기가 `true`에서 `nil`로 바뀐 프레임을 등록하는 것.
  그리고 `SecureHandlerWrapScript`/`UnwrapScript`를 남의 헤더로 직접 불렀을 때 다음 틱에 그 프레임이
  되물어지는 것. 첫 셋은 지금 코드에서 **빨갛게 나와야 한다**(지금은 갈아 끼운다).
- `/debtest`: EUI가 로드됐고 HoverCast가 켜져 있을 때(`_G._ERF_IsHoverCastEnabled()`), 전역의
  메타테이블이 우리 것이 아닌 채로 남아 있는 것과, 테스트 프레임을 `ClickCastFrames[f] = true`로
  넣었을 때 EUI가 안 잡으면 우리 행이 생기고 잡으면 안 생기는 것.

### 5. 내부 해제 호출 정리와 큐 하나로 합치기

- `Debind/FrameRegistry.lua` `RegisterFrame`: `if (DebindPrivate.ccframes[button]) then
  UnregisterFrame(button) end`를 뺀다. 행은 그 아래에서 어차피 새로 쓴다. 보안 쪽 `InitFrame`은
  `ccframes[button] = ccframes[button] or newtable()`이라 기존 행을 재사용하고 `frameType`을
  덮어쓴다. `hd` 행에는 이 자리까지 오지 않는다(`seen.hd`면 위에서 돌아간다).
- `registerBlizzardFrame`: `else DebindPrivate.UnregisterFrame(frame)` 분기를 뺀다. 체크를 끄면 다음
  로그인부터 등록하지 않는다.
- `Debind/DropDownMenus.lua` 블리자드 개체창 체크박스 일곱 개: `SetInstructionTooltip`으로 클라이언트
  문자열 `REQUIRES_RELOAD`("다시 불러오기 필요")를 단다. 우리 문자열을 새로 만들지 않는다.
  체크박스 콜백의 `UpdateBlizzardFrames()` 호출은 켤 때 즉시 등록되게 그대로 둔다.
- **큐를 하나로.** `Debind/Events.lua` `PLAYER_REGEN_ENABLED`가 `RegisterQueue`를 다 비우고 나서
  `UnregisterQueue`를 비우므로, 전투 중에 해제 뒤 재등록이 오면 등록이 먼저 처리되고(행이 있어
  그대로 통과) 해제가 나중에 처리되어 결국 행이 사라진다. `FrameRegistry.lua`의 두 큐를
  `{ op, button, type }` 항목 하나의 큐로 합치고 들어온 차례대로 처리한다. `RegisterClickQueue`는
  별개라 그대로.
- 헤드리스: "a frame offered in combat is queued rather than written off" 옆에, 전투 중 "해제 뒤
  등록"과 "등록 뒤 해제"가 각각 마지막 말대로 끝나는지 두 케이스. 첫 것은 지금 코드에서
  **빨갛게 나와야 한다.**
- `/debtest`: 같은 두 순서를 실제 락다운 없이 `InCombatLockdown`을 흉내 낼 수 없으니 헤드리스에
  맡기고, 킷에는 블리자드 토글을 껐다 켰을 때 행이 생기는 것만 둔다.

### 6. 팝업과 릴리스 노트

- `Debind/DebindUI.lua`의 `StaticPopupDialogs["DEBIND_APPROVE_ALL_OCCUPIED"]` 모양을 따라
  `DEBIND_UNIT_FRAME_NOTICE`를 만든다. `button1 = OKAY`(클라이언트 문자열), `button2`는 "다시 보지
  않기"인데 클라이언트에 그 말이 있으면 그것을 쓴다(`reference/globalstrings/`에서 `NEVER_SHOW`,
  `DONT_SHOW` 계열을 먼저 찾는다). `wide = 1`.
- 본문은 `Locales/enUS.lua`에만 넣는다(`check:locales`는 빠진 키를 enUS로 채우니 실패하지 않는다).
  문안은 아래 §팝업 문안 그대로.
- **기존 사용자에게만.** `Debind/Profile.lua` `InitDB`에서 `_G.DebindVars`가 없어 새로 만드는 경우
  `db.unitFrameNoticeSeen = true`를 같이 쓴다. 그 밖에는 필드가 없으니 `PLAYER_LOGIN`(`Events.lua`,
  `profileIsNewer` 검사 뒤)에서 `not db.unitFrameNoticeSeen`이면 띄운다. "다시 보지 않기"만 그
  필드를 `true`로 쓰고, 확인은 닫기만 한다.
- `README.md`: 26행 "Unit frame addons that support Clique already work with it"에 Clique 자체는
  꺼져 있어야 한다는 말을 붙인다. 121행 "there's an entry on the unit right-click menu too"는
  `5ab917c` 이후 거짓이니 뺀다. 163행 문단은 "Debind leaves unit frames to Clique"가 지금도 맞으니
  두되, 팩이 자체 hover cast를 켜면 프레임을 가져간다는 문장을 더한다.
- `CHANGELOG.md` 맨 위에 새 버전 문단. 내용은 §팝업 문안과 같은 사실을 노트 어투로. 3.5.2가 넣은
  "다른 애드온이 감싼 프레임에서 mouseover로 답한다"가 되돌아갔다는 것도 한 줄.
- `.zzz/unit-frame-discovery.md` 상태 줄에 "2026-09-05 뒤집힘, `devdocs/leaving-unregistered-frames-alone.md`"를
  붙인다. 본문은 그대로(조사 기록).
- 이 문서를 `devdocs/legacy/`로 옮긴다.

## 팝업 문안

> **Unit frames work differently now**
>
> Earlier versions went looking for unit frames that no addon had handed over, and took them. A
> frame that was never registered belongs to its addon, and taking it anyway was not our place.
> Debind no longer does that.
>
> So the hover condition and mouse button bindings on unit frames now work on the game's own unit
> frames, and on unit frame addons that register their frames through Clique support. Two things
> make that happen:
>
> - Most unit frame addons register through Clique support only while their own hover cast feature
>   (or whatever they call it) is turned off. If yours has one, turn it off. While it is on, that
>   addon keeps its frames for itself and Debind leaves them alone.
> - If Clique itself is installed, disable it. Debind answers in Clique's place, and steps aside
>   while Clique is running.
>
> Set Custom Target while hovering still works on any unit frame out of combat. In combat it works
> only on frames registered as above, and only on the player, pet, party, raid, boss and arena
> frames among them.

## 커버리지

헤드리스가 드는 것: 종류 읽기(Clique 문의 `unknown` 행), 전투 중 큐 순서, `mouseover` 폴백의 값
쪽, 래퍼를 안 떼는 것(`hover_spec` "등록을 풀어도 OnEnter/OnLeave 래퍼는 안 뗀다"), 스니펫 골든.

`/debtest`가 드는 것: HoverCast가 꺼진 EUI 프레임이 Clique 문으로 오는 것, 등록 안 된 프레임 위의
비전투 custom target 지정과 전투 중 실패 메시지, 블리자드 토글을 켰을 때의 등록.

닿지 못하는 것: 세션 중에 EUI의 HoverCast나 `allFrames`를 껐다 켜는 전환. 킷은 EUI 설정을 바꾸지
않으니, 그 전환을 듣는 훅과 되묻기는 헤드리스에서 `SecureHandlerWrapScript`를 직접 불러 잡는
것까지다. 팝업이 기존 사용자에게만 뜨는 것도 새 계정 SavedVariables가 있어야 보여서 킷 밖이다.

## EllesmereUI 9.1.6에서 확인한 것 (2026-09-05)

- HoverCast가 꺼져 있으면 공격대 프레임(`AddFrameToClickCast`)과 단일 개체창(`SetupUnitMenu`)을
  `ClickCastFrames[frame] = true`로 넘긴다. 이름 목록 없이도 Clique 문으로 온다.
- HoverCast를 켜면 자기 프레임을 먼저 `nil`로 되돌린 뒤 `ClickCastFrames`를 프록시로 바꿔 끼고, 그
  세션 안에서는 다시 내리지 않는다(`ccHookInstalled`가 다시 거짓이 되는 곳이 없다). 껐다고 우리에게
  돌아오지 않고 리로드가 있어야 한다. EUI 쪽 사정이라 우리가 할 일은 없다.
- HoverCast에 있고 우리에게 없는 바인딩 기능은 없다. 전역 `[@mouseover]` 버튼은 우리가 조건과
  순서로 더 잘게 가르고, 프리셋과 Smart Rez는 죽음·전투 조건과 순서 있는 두 행동으로 된다.
