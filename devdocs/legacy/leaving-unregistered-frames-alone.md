# 등록되지 않은 개체창은 건드리지 않는다

> 상태: 전부 구현됨 (2026-09-05). 근거는 `0-DIARY.md` 2026-09-05에 있고 여기엔 결론과 순서,
> 그리고 각 단계에서 계획과 갈린 것만 둔다.

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
- 헤드리스: `frames_spec.lua`가 아니라 `tests/hover_spec.lua`에 넣었다. 떨어지는 자리가 스니펫
  본문이고 `frames_spec`엔 제한 환경 인터프리터가 없어서, 인터프리터와 호버 슬롯을 이미 들고 있는
  쪽에 붙는다. 두 케이스: 호버 슬롯이 비었을 때 `mouseover`가 서 있는 토큰으로 지정되는 것(고치기
  전에 빨갛다), `mouseover`도 없을 때 아무것도 지정되지 않는 것(폴백이 무조건 걸리는 것을 막는 쪽).
  그러려면 `tests/restricted.lua`가 `UnitWatch` 본문도 재생해야 해서, 프레임마다 환경을 따로 두고
  드라이버와 `UnitWatch` 둘만 재생하도록 넓혔다. `Interp:setCustomTarget`이 그 문이다.
- `/debtest`: 세우지 않았다. `mouseover`는 실제 커서가 개체창 위에 있을 때만 게임이 세우고 킷은
  커서를 못 옮기니, 어느 갈래가 나올지가 킷 밖 상태에 달린다. 그런 케이스는 무엇을 먹여도 통과한다.
  `UnitExists("mouseover")`가 제한 환경에서 되는지는 `GetHoveredUnit`이 이미 같은 호출을 하고 있어
  따로 물을 것이 없다.

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
  `tests/wow_shim.lua`의 `SecureGroupHeader_*` 넷과 `tests/wow_frames.lua`의
  `SecureUnitButton_OnLoad`, `UnitFrame_Initialize` 심을 뺐다. `RegisterUnitWatch`,
  `GetAddOnMetadata`는 다른 곳이 쓰고 있어 남겼다.
- `/debtest`: `DebindDev/DebindTest.lua`의 EllesmereUI 케이스 셋("the single unit frames are wired,
  and read for what they are", "the standalone party and raid frames are wired as group frames",
  "the header's own children are wired as group frames")은 이름 목록과 헤더 쓸어담기를 전제하니
  지웠다. 대신 단일 개체창 하나만 세웠다("the single unit frames arrive through the Clique door",
  `applies`는 EUI가 로드됐고 `_G._ERF_IsHoverCastEnabled()`가 거짓일 때). 공격대 프레임은
  `AddFrameToClickCast`로 넘어오는 것까지는 확인했지만 프레임 이름을 모르고, 이름 없이 걷으면
  무엇을 먹여도 통과하는 케이스가 되어 안 넣었다. 이름을 확인하면 같은 자리에 붙는다.
- 계획에 없던 것 둘. `tests/unitwatch_spec.lua`의 "our own headers are not collected as click-cast
  frames"와 "a foreign group header still yields its children"도 헤더 쓸어담기를 전제하니 같이
  지웠다. `Debind/FrameRegistry.lua`의 `UNIT_FRAMETYPES` 위 주석 중 "헤더 문이 이 읽기를
  이긴다"고 하던 문단과 `RegisterFrame`의 `told` 위 문단은 헤더 문을 근거로 삼고 있었으니 다시
  썼다.
- `0-DIARY.md`의 2026-09-05 치는 이 문서와 함께 착수 전 문서 커밋에 이미 들어가 있다. 여기서 더 쓸 것은 없다.

### 3. `hoverLeaveTaken` 장치를 걷어낸다

`07867c6`과 `680fc91`이 넣은 것 전부. `git show 07867c6 680fc91 --stat`으로 대조한다.

- `Debind/FrameRegistry.lua`: `_hoverLeaveTaken`, `WriteHoverLeaveTaken`,
  `DebindPrivate.RestoreHoverLeaveTaken`, `MarkWrappedOver`, `OURS_WRAPPED`,
  `_warnedWrappedOver`, `WarnWrappedOver`, `RegisterFrame` 끝의
  `RestoreHoverLeaveTaken` 호출과 그 주석. `OnSecureWrap`과 그 훅도 같이 뺐다. 계획은 4단계의
  트리거로 남기라고 했지만 4단계의 트리거는 `DebindCliqueFake`에 서는 것이라, 여기 남기면
  아무것도 안 하는 훅이 한 단계 동안 서 있게 된다.
- `Debind/SecureBindings.lua`: `GetHoveredUnit`(Clique 아닌 쪽)의 `hoverLeaveTaken` 분기와
  `mouseover` 폴백, 그 위 주석. `EvalClickCastFrame`과 클릭 pre 본문의
  `evalFrame.hoverLeaveTaken` 분기 둘. 남는 본문이 `States.unitframe.unit`만 돌려주는 꼴이 된다.
- `Debind/UpdateBindings.lua`: 폴링 스니펫의 `unitframe.hoverLeaveTaken and not UnitExists("mouseover")`
  분기와 그 위 주석 블록. `DebindPrivate.hoverIsRead`는 `WarnWrappedOver`만 읽으니 같이 뺀다.
- `Debind/Locales/enUS.lua`, `koKR.lua`: `WARNING_MESSAGE_HOVER_ANSWERED_ELSEWHERE`. ruRU에는
  없었다.
- `DebindDev/Probe_HoverLeaveTaken.lua` 파일 삭제(TOC엔 이미 없다).
- 골든 셋 다시 떴다. `tools/snippet-golden.txt`의 여섯 군데만 사라졌고, `tests/emit-golden.txt`와
  `tests/emit-shipped-golden.txt`는 그 분기가 빠지면서 남은 몸이 한 단 왼쪽으로 온 것뿐이다.
  shipped 쪽은 `lua5.1 tests/run.lua --shipped --update-golden`으로 따로 떠야 한다.
- `CHANGELOG.md`의 3.5.2 문단은 이미 나간 버전의 기록이라 손대지 않는다. 새 노트(6단계)에서
  되돌렸다고 쓴다.

### 4. 되찾기를 "홀더의 프록시에 훅"으로 바꾼다

거의 전부 `DebindCliqueFake/DebindCliqueFake.lua`다.

- **`Claim()`이 `AttachClickCastFrames`가 됐다.** 전역이 없거나 메타테이블이 없는 표면 지금처럼
  우리 프록시를 세우고 `Adopt`한다. 메타테이블이 있으면 `Hook(previous)`로 가고 전역은 그대로 둔다.
  `__metatable`로 잠긴 표는 `getmetatable`이 표를 안 주므로 아무것도 안 하고 돌아간다.
- **`Hook(proxy)`.** 이미 감싼 메타테이블이면(약한 표 `hooked`) 돌아간다. 아니면 `__newindex`를
  우리 함수로 바꾼다. 우리 함수는 원래 것을 먼저 부르고(함수면 호출, 표면 그 표에 쓰기, 없으면
  `rawset`), `nil`/`false`면 우리 해제로 흘리고, 아니면 `offered[frame]`에 적고 `AskHolder`로 간다.
  `__index`는 안 건드린다.
- **`AskHolder(frame)`.** `holder[frame]`이 참이면 그쪽이 잡은 것이라 `deferred`에 적고 물러난다.
  `nil`이면 적어만 두고 버린 것이라 `offered[frame]`으로 등록한다.
- **계획과 갈린 것 하나.** 계획은 `__newindex`가 없는 프록시를 "평범한 표처럼 `Adopt`"하라고 했다.
  대신 `Hook`이 그런 표도 받아서 `__newindex`를 새로 얹고(원래 자리는 `rawset`), 표 안에 이미 있던
  행은 `pairs`로 돌며 `AskHolder`에 넣는다. 규칙이 하나로 서고, 새 키 쓰기를 우리가 듣게 된다.
  `Adopt`를 그대로 쓰면 홀더가 잡은 프레임까지 우리가 가져간다.
- **되묻기 `AskHolderAgain`.** `deferred`의 프레임과 `ccframes`의 `hd` 아닌 행을 전부 `AskHolder`에
  다시 넣는다. 전투 중이면 통째로 물러난다.
- **트리거 `OnHolderWrap`.** 전역 `SecureHandlerWrapScript`와 `SecureHandlerUnwrapScript`에
  `hooksecurefunc`. 우리가 아는 프레임(`offered`·`deferred`·`ccframes`)이고 헤더가 우리 것이
  아닐 때만 `C_Timer.After(0)`으로 그 프레임 하나를 되묻는다. 되묻기 앞에서
  `AttachClickCastFrames`를 먼저 불러 세션 중에 전역이 바뀐 경우를 잡는다. 전투 중엔 안 건다.
  참고: `SecureHandlerUnwrapScript`는 인자가 둘이라 헤더가 `nil`로 온다. 우리 헤더 판정은 wrap
  쪽에서만 걸린다.
- `Debind/Events.lua`: 세 자리의 호출을 새 이름으로. `PLAYER_ENTERING_WORLD`와
  `PLAYER_REGEN_ENABLED`에는 `AskHolderAgain()`을 붙였다. `PLAYER_LOGIN` 쪽은 아직 아무도 프레임을
  안 준 시점이라 붙이지 않았다.
- **남긴 것.** 로드 때 `AttachClickCastFrames()`, `Adopt`, `ccframesMeta`, `registered`.
- 헤드리스: 새 파일 `tests/holder_spec.lua`. `tests/run.lua`가 이 스펙에만 `Public.lua`와
  `DebindCliqueFake`를 얹는다(`cliqueFake = true`). 둘을 매 스펙에 얹으면 `SecureHandlerWrapScript`
  훅이 상관없는 스펙 앞에 서게 된다. `tests/wow_shim.lua`에 `SlashCmdList`를 심었다. `Public.lua`가
  로드 때 거기에 쓴다. 열두 케이스이고, 그중 여덟이 옛 규칙(전역을 무조건 갈아 끼우기)에서
  빨갛게 나오는 것을 확인했다.
- `/debtest`: "Click-cast table: the name comes back, and twice is not twice"를 "the holder keeps
  the name and we take what it drops"로 갈아 썼다. 이름을 안 되찾는 것, 홀더가 잡은 프레임엔 행이
  안 생기는 것, 버린 프레임엔 생기는 것, `nil` 쓰기가 행을 지우는 것. 그리고 EUI용으로 "HoverCast
  on leaves the name with the pack"을 세웠다.

### 5. 내부 해제 호출 정리와 큐 하나로 합치기

- `Debind/FrameRegistry.lua` `RegisterFrame`: `if (DebindPrivate.ccframes[button]) then
  UnregisterFrame(button) end`를 뺐다. 행은 그 아래에서 어차피 새로 쓴다.
- `registerBlizzardFrame`: `else DebindPrivate.UnregisterFrame(frame)` 분기를 뺐다. 체크를 끄면 다음
  로그인부터 등록하지 않는다.
- `Debind/DropDownMenus.lua`: 블리자드 개체창 항목에 `SetInstructionTooltip`으로 클라이언트 문자열
  `REQUIRES_RELOAD`를 달았다. 체크박스 일곱 개마다가 아니라 그 일곱을 담은 항목 하나에 단다.
  드롭다운 체크박스는 툴팁 자리를 안 받고, 일곱 번 같은 말을 다는 것도 아니다.
- **큐를 하나로.** `RegisterQueue`와 `UnregisterQueue`가 `FrameQueue` 하나가 됐다. 항목은
  `{ op, button, type }`이고 들어온 차례대로 처리한다. `RegisterClickQueue`는 별개라 그대로.
- **계획이 못 본 것.** 순서만 합쳐서는 안 됐다. 전투 중에는 행(`ccframes`)이 의도를 안 담는다.
  해제는 행을 남긴 채 큐에만 들어가므로 뒤이은 등록이 "행이 이미 있다"며 조용히 돌아갔고, 등록은
  행을 안 만드니 뒤이은 해제가 "행이 없다"며 아무것도 안 했다. 그래서 프레임마다 마지막으로 큐에
  들어간 말을 `_queued`(약한 키)에 들고, 그 두 관문이 행보다 이것을 먼저 읽는다. 큐를 비울 때
  같이 비운다. 두 케이스 다 이 장치 없이는 빨갛게 나오는 것을 봤다.
- 헤드리스 `tests/frames_spec.lua`: "a frame offered in combat is queued rather than written off"를
  `FrameQueue`로 고치고, 전투 중 "해제 뒤 등록"과 "등록 뒤 해제"를 더했다. `throughCombat` 헬퍼가
  `PLAYER_LOGIN`을 먼저 쏜다. `PLAYER_REGEN_ENABLED` 등록이 로그인 핸들러 안에 있어서, 안 쏘면
  큐가 안 비워지고 두 케이스가 아무것도 안 재고 초록으로 나온다. 그래서 헬퍼가 끝에 큐가 비었는지도
  본다.
- `/debtest`: "Blizzard frames: unticking a box leaves the frame wired until the next login". 껐을 때
  행이 남는 것과 다시 켰을 때 행이 있는 것. 전투 중 두 순서는 락다운을 흉내 낼 수 없어 헤드리스에
  맡긴다.

### 6. 팝업과 릴리스 노트

- `Debind/DebindUI.lua`에 `DEBIND_UNIT_FRAME_NOTICE`. `button1 = OKAY`,
  `button2 = CONFIRM_POPUP_DONT_SHOW_AGAIN`(둘 다 클라이언트 문자열), `wide = 1`.
  [확인]은 닫기만 하고 다음 로그인에 다시 뜬다. 필드를 쓰는 것은 두 번째 버튼뿐이다.
- 본문은 `Locales/enUS.lua`에만. `UNIT_FRAME_NOTICE_TITLE`과 `UNIT_FRAME_NOTICE` 둘로 나눠 넣고
  팝업이 `|n|n`으로 잇는다. §팝업 문안의 글머리표 두 개는 문단 둘로 폈다. 게임에는 목록이 없고,
  줄 앞의 `-`는 대시다.
- **기존 사용자에게만.** `Debind/Profile.lua` `InitDB`에서 `_G.DebindVars`가 없어 새로 만드는
  경우에만 `db.unitFrameNoticeSeen = true`. 필드가 없는 프로필이 이 판 이전의 프로필이다.
  `Events.lua`의 `PLAYER_LOGIN`이 `profileIsNewer` 검사 뒤에서 읽는다. 읽는 자리는
  `DebindPrivate.db.global`이다. `DebindPrivate.db`는 `{ global, char }` 두 칸이라 계정 파일
  최상단 필드는 `db.global` 밑에 있다.
- 헤드리스 `tests/migration_spec.lua`에 둘: 없던 프로필을 새로 만들면 표시가 붙는 것(고치기 전에
  빨갛다), 이미 있던 프로필은 안 붙는 것. `tests/wow_shim.lua`에 `StaticPopup_Show` 심을 넣었다.
  띄운 것을 `world.popups`에 적기만 한다. `DebindUI.lua`가 헤드리스에 없어서 대화상자 자체는
  못 본다.
- `README.md`: 26행에 Clique 자체는 꺼야 한다는 말을 붙였다. 121행의 우클릭 메뉴 문장은 지우고
  비전투/전투 차이로 갈아 썼다. 163행에는 팩이 자체 hover cast를 켜면 프레임을 가져간다는 문장을
  더했다.
- `CHANGELOG.md` 맨 위에 새 문단. **버전 번호는 소유자가 낼 때 정한다**(`cutting-a-release.md`).
  지금 머리말은 `# 3.6`으로 적어 뒀고, 소유자가 다른 번호를 고르면 그 한 줄만 고치면 된다.
- `.zzz/unit-frame-discovery.md` 상태 줄에 뒤집힘 표시를 붙였다. 본문은 그대로.
- 이 문서를 `devdocs/legacy/`로 옮겼다.

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

헤드리스가 드는 것: 종류 읽기(Clique 문의 `unknown` 행), 전투 중 큐 순서와 마지막 말이 서는 것,
`mouseover` 폴백의 두 갈래, 홀더의 프록시를 다루는 열두 가지(`holder_spec`), 팝업 표시가 기존
프로필에만 없는 것, 래퍼를 안 떼는 것(`hover_spec` "등록을 풀어도 OnEnter/OnLeave 래퍼는 안
뗀다"), 스니펫 골든.

`/debtest`가 드는 것: HoverCast가 꺼진 EUI 프레임이 Clique 문으로 오는 것, HoverCast를 켠 EUI가
이름을 쥐고 있는 것, 남의 프록시 뒤에 서서 버린 프레임만 받는 것, 블리자드 토글을 껐다 켰을 때
행이 남고 다시 서는 것.

닿지 못하는 것: 세션 중에 EUI의 HoverCast나 `allFrames`를 껐다 켜는 전환. 킷은 EUI 설정을 바꾸지
않으니, 그 전환을 듣는 훅과 되묻기는 헤드리스에서 `SecureHandlerWrapScript`를 직접 불러 잡는
것까지다. 팝업이 화면에 그려지는 것도 킷 밖이다. `DebindUI.lua`가 헤드리스에 없어 헤드리스는
띄우기로 한 결정까지만 보고, 킷에는 대화상자를 띄웠다 닫는 케이스를 안 세웠다. 전투 중 큐의 두
순서도 락다운을 흉내 낼 수 없어 헤드리스에 남는다.
`mouseover` 폴백이 실제 커서 아래에서 도는 것도 킷 밖이다. 킷은 커서를 못 옮기고, 게임이 세워 준
`mouseover` 없이는 어느 갈래가 나올지가 킷 밖 상태에 달린다.

## EllesmereUI 9.1.6에서 확인한 것 (2026-09-05)

- HoverCast가 꺼져 있으면 공격대 프레임(`AddFrameToClickCast`)과 단일 개체창(`SetupUnitMenu`)을
  `ClickCastFrames[frame] = true`로 넘긴다. 이름 목록 없이도 Clique 문으로 온다.
- HoverCast를 켜면 자기 프레임을 먼저 `nil`로 되돌린 뒤 `ClickCastFrames`를 프록시로 바꿔 끼고, 그
  세션 안에서는 다시 내리지 않는다(`ccHookInstalled`가 다시 거짓이 되는 곳이 없다). 껐다고 우리에게
  돌아오지 않고 리로드가 있어야 한다. EUI 쪽 사정이라 우리가 할 일은 없다.
- HoverCast에 있고 우리에게 없는 바인딩 기능은 없다. 전역 `[@mouseover]` 버튼은 우리가 조건과
  순서로 더 잘게 가르고, 프리셋과 Smart Rez는 죽음·전투 조건과 순서 있는 두 행동으로 된다.
