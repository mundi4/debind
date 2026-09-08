# 전역 설정을 게임 설정창의 애드온 탭으로 (2026-09-08 설계)

> 상태 (2026-09-08): **닫혔다. §5의 1번부터 7번까지 다 들어갔다.** 항목은 대응표 그대로 하나도
> 빼거나 더하지 않았고, 더한 것은 §1의 버튼 줄 하나다. 코드는 `Debind/Options.lua`, 헤드리스는
> `tests/options_spec.lua`, 게임 안은 `/debtest`의 `Settings:` 넷.
>
> 배정된 버전은 없다. 정해지면 `0-ROADMAP.md`가 든다.
>
> **설계가 코드와 어긋난 자리 여섯을 §6에 적었다.** 고친 것은 문서 쪽이고, 왜 틀렸는지가 거기
> 있다.
>
> **§3의 "안전하다"가 한 군데 틀렸고, 2026-09-08 BugGrabber가 그것을 보였다.** 전투 중 휠 스크롤에
> `Frame:SetHeight()`가 막혔다. 원인과 고친 것은 §8, 이번에는 코드 쪽을 고쳤다.

---

## 0. 무엇을, 왜

**우리 창 제목줄의 톱니바퀴 메뉴(`SetupOptionsDropdownMenu`)에 든 것을 전부 게임 설정창(ESC, 옵션)의
AddOns 탭으로 옮긴다.** 그 안의 항목은 하나도 빼지 않고 하나도 더하지 않는다. 더하는 것은 §1의 버튼
하나뿐이다.

옮기는 이유는 셋이고 셋 다 저 메뉴에 든 것이 **계정 단위 설정**이라는 데서 나온다.

- **메뉴가 못하는 것 둘이 그 안에 있다.** 다시 불러야 먹는 체크박스(블리자드 유닛 프레임 7개, 팩,
  미등록 프레임 가져오기)는 지금 툴팁에 `REQUIRES_RELOAD`를 붙인 것이 전부다. 상태 드라이버 슬라이더는
  드롭다운 안에 템플릿을 끼워 넣은 것이라 자연스럽지 않다. 설정창에는 둘 다 원래 자리가 있다.
- **설정창이 그냥 주는 것.** 검색에 잡히고, 오른쪽 위 Defaults 버튼이 따라온다. 지금 메뉴에는 "전부
  되돌리기"가 없다.
- **자리.** 키 편집기의 톱니바퀴는 그 창의 일에 대한 것으로 읽히는데, 이 항목들은 어느 창에 대한
  것도 아니다.

**형태는 캡처 그대로 세로 목록이다.** `Settings.RegisterVerticalLayoutCategory` 하나, 캔버스 아니다.
BugSack이 저 탭에서 보이는 꼴(체크박스 줄, 좌우 화살표 드롭다운 줄, 버튼 줄)이 우리가 쓸 것 전부다.

## 1. 두 창의 관계

**우리 창은 닫지 않는다 (소유자).** 내가 "블리자드의 편집 모드 버튼처럼 서로 닫고 바꿔 타자"고 냈고
소유자가 거절했다. 우리 창은 끌어 옮길 수 있으니 옆으로 치워 두면 되고, 실제로 해 보니 클릭한 창이
위로 올라와서 가리는 문제가 크지 않다.

그래서:

- **톱니바퀴**는 `Settings.OpenToCategory(category:GetID())`로 우리 탭을 연다. 우리 창은 그대로.
  메뉴는 없어지므로 `DebindUI.xml`의 `MenuFunc` KeyValue와 `SetupMenu` 호출이 빠지고 `OnClick` 하나가
  들어간다. 아이콘 버튼의 생김새는 `UIPanelIconDropdownButtonTemplate`의 것을 그대로 쓴다. 지금 전투
  중에 회색이 되는 것(`UpdateButtons`)은 메뉴가 전투 중에 못 쓰는 것을 만지기 때문이었다. 설정창을
  여는 것은 전투 중에도 되니 그 회색은 풀린다. 전투 중에 값을 바꾸면 어떻게 되는지는 §3이 든다.
- **설정창에는 우리 창을 여는 버튼 줄 하나**(`CreateSettingsButtonInitializer`)를 둔다. 목록 맨 위.
  `DebindPublic`의 토글을 그대로 부른다. 그 토글이 이미 전투 중과 게임 메뉴 위와 프로필이 더 새로울
  때를 거절하고 말까지 하니 여기서 따로 볼 것이 없다.

**ESC.** 우리 창은 가운데 패널이 떠 있으면 ESC를 블리자드에 넘긴다(`BlizzardOwnsEscape`). 설정창은
가운데 패널이므로 둘이 같이 떠 있을 때 ESC는 설정창부터 닫는다. 손댈 것 없다.

**게임 메뉴로 열었을 때의 되돌아가기.** 설정창은 게임 메뉴에서 열렸으면 닫힐 때 게임 메뉴로 돌아간다
(`TransitionBackOpeningPanel`). 그 순간 게임 메뉴가 뜨고, 우리 창은 게임 메뉴가 뜨면 물러나는 규칙
(`GameMenuFrame.Shown` 콜백)대로 숨는다. 즉 ESC, 옵션, 우리 버튼, 설정창 닫기 순서로 가면 우리 창도
같이 사라진다. **이건 고치지 않는다.** 게임 메뉴 위에 우리 창이 안 서는 것은 이미 정해진 규칙이고,
설정창을 우리 톱니바퀴로 열었으면 돌아갈 곳이 없어 이 일이 없다.

## 2. 대응표

카테고리는 하나, 이름은 `Debind`. 묶음 사이는 `CreateSettingsListSectionHeaderInitializer`로 가른다.
저장 위치의 `Options`는 `DebindPrivate.Options`(`db.options`)이고, `global`은
`DebindPrivate.db.global`이다.

**값에 `nil`이 하나의 답으로 들어 있는 항목은 전부 `Settings.RegisterProxySetting`이다.**
`RegisterAddOnSetting`은 테이블과 키를 받아 그 칸을 직접 읽고 쓰는데, 우리 저장은 "없음"이 기본값인
칸이 많고(팩, Smart Cast, 제외) 클릭 엣지는 `nil`이 셋 중 하나다. 프록시의 `setValue`가 지금 메뉴의
setter를 그대로 하고, 기본값으로 돌아오면 칸을 지운다(없음이 기본인 칸은 없음으로).

| 지금 메뉴 | 저장 | 설정창 | 값을 쓴 뒤 |
|---|---|---|---|
| **유닛 프레임** 절 | | 섹션 헤더 `UNITFRAME_OPTIONS` | |
| 클릭 엣지 3택 (라디오) | `Options.unitframeUseMouseDown` = `nil` / `true` / `false` | 드롭다운. 드롭다운 값에 `nil`을 못 쓰니 프록시 안에서 세 값을 문자열 셋으로 접고 되편다. 순서는 지금 그대로: 게임대로, 누를 때, 뗄 때 | `ApplyOptions("unitframeUseMouseDown")` |
| 블리자드 유닛 프레임 7 (player, pet, target, party, raid, boss, arena) | `Options.blizzframes[type] ~= false` | 체크박스 7. 툴팁에 `REQUIRES_RELOAD` | `UpdateBlizzardFrames()` |
| 팩 (설치된 것만) | `global.packFrames[addon]`: 꺼짐 `false`, 켜짐 없음 | 체크박스, `LoadedKnownPacks()`가 준 것만. 툴팁에 `REQUIRES_RELOAD` | 없음 |
| 미등록 프레임 가져오기 | `global.takeUnregisteredFrames ~= false` | 체크박스. 툴팁 `TAKE_UNREGISTERED_UNIT_FRAMES_DESC` + `REQUIRES_RELOAD` | 없음 |
| **Smart Cast** 절 | | 섹션 헤더 `SMART_CAST_DEFAULTS`, 툴팁 `SMART_CAST_DESC` | |
| 켬 | `Options.smartCast.enabled` (`SmartCastEnabled()`) | 체크박스 | `QueueUpdateBindings()` |
| 넷 (rez, battleRez, dispel, buff), 순서 `SMART_CAST_BRANCHES` | `Options.smartCast[branch]` (`SmartCastDefault(branch)`) | 체크박스 4. `SetParentInitializer(켬)`으로 켬이 꺼지면 회색, `Indent()` | `QueueUpdateBindings()` |
| 전투 부활과 함께 | `Options.smartCast.rezWithBattleRez` | 체크박스. 부모는 rez 상자이고 술어는 켬과 rez 둘 다 참일 때 | `QueueUpdateBindings()` |
| **특수 유닛** 절 | | 섹션 헤더 `SPECIAL_UNITS` | |
| 자기 제외 4 (tank, healer, maintank, mainassist) | `Options.excludePlayer[unit]` | 체크박스 4, 이름은 `UNIT_INFO[unit].name`. 툴팁 `EXCLUDE_PLAYER_DESC` | `GetUnitWatchHeader(unit)`가 있으면 `showPlayer` 속성 |
| **상태 드라이버** | `Options.stateDriverUpdateThrottle`, 기본 `0.2` | 슬라이더 `Settings.CreateSlider`, `CreateSliderOptions(0, 0.2, 0.01)`, 값 표시는 지금처럼 소수 둘까지. 툴팁은 `STATE_DRIVER_UPDATE_THROTTLE_DESC`에 경고 `STATE_DRIVER_UPDATE_THROTTLE_WARNING`을 빨간 줄로 | `ApplyOptions("stateDriverUpdateThrottle")` |
| 없음 | | 맨 위에 버튼 줄: 우리 창 열기 (§1) | |

**Clique가 있을 때.** 지금은 유닛 프레임 항목이 통째로 회색이고 `BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE`가
툴팁에 선다. 설정창에서는 유닛 프레임 절의 줄마다 `AddModifyPredicate(not CliqueDetected)`를 걸고 같은
문장을 툴팁에 둔다. 이 판단을 뒤집는 안은 `0-IDEAS.md`의 "Clique와 병행 동작"이고 여기와 무관하다.

**"현재 값"에 대한 두 가지 주의.**

- 설정창은 열릴 때 값을 한 번 읽고 자기 컨트롤에 들고 있다. 우리 값이 설정창 바깥에서 바뀌는 자리는
  없으니(메뉴가 없어지면) 문제가 없다. 단 `ApplyOptions`가 로그인 때 CVar에서 읽는 클릭 엣지는 저장값이
  `nil`인 채로 있고 프록시도 `nil`을 "게임대로"로 되돌리니 어긋나지 않는다.
- **Defaults 버튼은 프록시 setter를 기본값으로 부른다.** 그러니 setter는 값이 기본값과 같을 때 칸을
  지우는 쪽으로 써야 저장 파일에 기본값이 박히지 않는다. 지금 메뉴 코드가 팩에 대해 하고 있는
  것(`stored[addon] = nil`)을 전 항목에 같이 한다. `turning-an-option-off-keeps-its-value`와 어긋나지
  않는다. 그 규칙은 기능을 끌 때 값을 지우지 말라는 것이고, 이것은 사용자가 되돌리기를 누른 것이다.

## 3. 테인트

**설정창을 우리 코드에서 여는 것은 안전하다.** `Settings.OpenToCategory`는 `C_SettingsUtil.OpenSettingsPanel`
하나를 부르고, 그 C 함수가 `SettingsPanel:OpenToCategory`를 다시 부른다. C를 한 번 지나므로
`ShowUIPanel(SettingsPanel)`은 보안 스택에서 돈다. 블리자드 자기 애드온들도 같은 함수로 연다
(`ChannelFrame`, `CommunitiesTabs`, `CooldownViewerSettings`). 우리 창이 `RegisterGameMenuEscHandler`에서
피한 것(우리가 넣은 줄을 블리자드가 보안 경계 밖에서 읽는 것)이 여기는 없다.

**우리가 등록한 설정과 카테고리는 우리 테이블이라 더러워져 있다.** 설정창은 그것을 전제로 짜여 있다.
커밋, 되돌리기, Defaults가 설정 객체의 메서드를 전부 `securecallfunction`으로 감싸 부른다
(`Blizzard_SettingsPanel.lua`의 `ExitWithCommit`, `ExitWithoutCommit`, `SetAllSettingsToDefaults`).
애드온이 설정을 등록하는 것 자체가 그 시스템의 문서화된 용도다(`Blizzard_ImplementationReadme.lua`).

**남는 것은 우리 setter가 하는 일이다.** 설정창은 전투 중에도 열리고 눌리므로, setter가 전투 중에 못
하는 일을 하면 그 자리에서 터진다. 지금 메뉴는 톱니바퀴 자체가 전투 중 회색이어서 이 물음이 없었다.
지금 setter 넷 중 셋이 보안 프레임을 직접 만진다. `UpdateBlizzardFrames()`, `showPlayer` 속성 쓰기,
그리고 `ApplyOptions("stateDriverUpdateThrottle")`인데 마지막 것은 전투 중이면 **아무 말 없이
건너뛰고 미루지도 않는다** (`SecureStateDriverManager`가 보호 프레임이라서). 저장값은 이미 바뀌어 있어
다음 재구성까지 슬라이더와 실제 값이 갈린다.

**setter는 값을 쓰고 `QueueUpdateBindings()`를 부르는 것으로 끝난다 (소유자).** 보안 프레임에 닿는 일은
전부 재구성이 한다. `UpdateBindings`는 전투 중이면 빚만 적고 `PLAYER_REGEN_ENABLED`가 갚으니, 전투 중
미루기는 이미 있는 그 큐 하나가 한다. 회색으로 막는 안은 접었다. 회색은 "왜 안 되지"를 낳고, 미루기는
그냥 된다.

- `FinishBindingUpdate`가 지금 `ApplyOptions("stateDriverUpdateThrottle")` 하나를 부른다. 이것을
  `ApplyOptions()`로 넓히고, `ApplyOptions`에 블리자드 프레임 등록(`UpdateBlizzardFrames`)과
  `showPlayer` 갈래를 더한다. 클릭 엣지는 이미 그 안에 있고, 전투 중이면 빚만 적는 꼴도 이미 거기
  있다(`clickEdgeSuspended`). 값은 들고 다니지 않고 전투 끝에 저장값을 다시 읽는다. 두 번 바꿨으면
  마지막 것이 서야 한다.
- Smart Cast 넷과 켬은 지금도 `QueueUpdateBindings()`라 그대로.
- 팩과 미등록 프레임은 다음 로그인에 먹는 것이라 부를 것이 없다. 그대로.

**전투 중에는 목록 아래에 빨간 문구 한 줄이 선다 (소유자).** "전투가 끝난 뒤에 적용됩니다." 회색 대신
이것이다. 섹션 헤더 하나를 빨간 글자로 두고 `AddShownPredicate(InCombatLockdown)`를 건다. 설정창은
줄의 보임을 자기가 다시 그릴 때만 다시 묻으므로, `PLAYER_REGEN_DISABLED`와 `PLAYER_REGEN_ENABLED`에서
우리 카테고리가 떠 있으면 목록을 다시 그리게 해야 한다. 어떻게 하는지는 구현하는 쪽이
`Blizzard_SettingsList.lua`에서 찾는다. 문구는 클라이언트가 이미 가진 말이 있는지 먼저 본다
(`writing-user-facing-text.md`).

**위 문단이 틀린 자리다 (2026-09-08).** `AddShownPredicate`가 하는 일은 우리 함수를 초기화기의 칸에
쓰는 것이고, 우리가 쓴 칸은 오염된 칸이다. 설정창은 그 칸을 `Display`와 `RepairDisplay`에서 감싸지
않고 읽고, 같은 실행 안에서 목록을 다시 짓는다. 그래서 그 뒤에 스크롤 박스가 쓴 수는 전부 오염된 채
세션 끝까지 남고, 다음 휠 스크롤이 전투 중이면 `SetHeight`가 막힌다. 위에서 "안전하다"고 한 근거 둘,
곧 `OpenToCategory`가 C를 지난다는 것과 설정 객체의 메서드를 `securecallfunction`으로 감싼다는 것은
둘 다 맞았다. 틀린 것은 **초기화기에 함수를 얹는 것이 그 감싸기 밖에 있다는 것**을 못 본 것이다.
경로 전체와 고친 것은 §8.

## 4. 빠지는 것

- `SetupOptionsDropdownMenu` 통째.
- `DebindStateDriverUpdateThrottleSliderTemplate`과 그 믹스인. 쓰는 곳이 그 메뉴 하나다.
- 톱니바퀴의 `MenuFunc`. `TooltipTitle`은 남는다.
- `SMART_CAST_DEFAULTS_DESC`의 첫 문장이 "This menu holds the account setting"이다. 메뉴가 아니게
  되므로 고쳐 쓴다. 다른 문자열은 그대로 옮겨 간다. 새 문자열은 §3의 빨간 문구 한 줄과 설정창 버튼의
  글자 정도다. `writing-user-facing-text.md`대로 클라이언트가 이미 가진 말을 먼저 찾는다.

## 5. 순서

1. `Options.lua` 하나를 새로 두고 `Debind.xml`에 넣는다. 등록은 `ADDON_LOADED` 뒤, 프로필이 선
   뒤여야 한다(`DebindPrivate.Options`가 `Profile.lua`에서 대입된다). 카테고리 ID는 톱니바퀴가 쓰니
   `DebindPrivate`에 둔다.
2. `ApplyOptions`를 §3대로 넓히고 `FinishBindingUpdate`가 그것을 통째로 부르게 한다. 메뉴가 아직 있는
   채로 이 단계만 먼저 하고 `npm run check`를 지난다. 지금 메뉴의 setter 셋이 하던 직접 호출이 이
   시점에 빠진다.
3. 대응표 순서대로 등록. setter는 값을 쓰고 `QueueUpdateBindings()`, 기본값이면 칸을 지운다. 전투 중
   문구 줄을 넣는다.
4. 톱니바퀴를 바꾸고, 설정창의 버튼 줄을 넣는다.
5. §4를 지운다. 안 쓰게 된 문자열은 grep으로 찾는다. `check:locales`는 다른 로케일을 enUS에 맞춰 보는
   검사라 enUS에서 고아가 된 키는 안 잡는다.
6. `/debtest`에 등록: 카테고리가 등록되어 있다, 대응표의 항목마다 설정 변수가 풀린다, 프록시 setter가
   저장을 표대로 쓰고 재구성을 예약한다(기본값은 칸이 없다), 켬이 꺼지면 넷이 회색이다,
   `ApplyOptions()`가 전투 밖에서 블리자드 프레임과 `showPlayer`를 저장값대로 쓴다. 헤드리스가 못 보는
   것은 설정창의 그리기 전부와 전투 중 문구 줄이 뜨고 지는 시점이고, 그 둘은 원리상 게임 안에서만
   보인다.
7. `npm run check`.

## 6. 설계가 코드와 어긋난 자리

구현하면서 코드를 따라가 보니 위의 설계가 여섯 군데 틀렸다. **고친 것은 코드가 아니라 이 문서이고,**
아래가 각각 무엇을 잘못 봤는지다. 위 본문은 원래 쓴 대로 두었다 — 지운 뒤에 읽는 사람은 왜 이렇게
됐는지를 알 수 없다.

**1. 톱니바퀴는 전투 중에 회색이었던 적이 없다 (§1).** `UpdateButtons`가 이 버튼에 거는 것은
`IsEditingAction()`, 곧 **아이콘 선택기가 떠 있는 동안**이다. 전투와는 상관이 없다. 문서가 그렇게 읽은
것은 `DebindUI.xml`의 그 버튼 주석이 "`UpdateButtons` greys this out in combat"이라고 **잘못 적혀
있었기** 때문이다. 주석을 근거로 삼은 것이 잘못이고, 그 주석은 이번에 고쳤다. 그러니 "풀릴 회색"이
애초에 없었고, 아이콘 선택기 쪽 회색은 그대로 남는다.

**2. 들어간 것은 `OnClick`이 아니라 `OnMouseUp`이다 (§1).** `DropdownButton`은
`RegisterForMouse("LeftButtonDown", "LeftButtonUp")`로 서므로 `OnClick`이 서지 않는다. 그리고
`UIPanelIconDropdownButtonTemplate`이 이미 `<OnMouseUp method="OnMouseUp"/>`를 걸어 자기 믹스인의
그 이름을 부르는데, 파생 프레임의 믹스인에 같은 이름을 두면 **그 자리가 우리 것으로 바뀐다** — 눌린
아이콘이 도로 안 올라온다. 그래서 이름을 `OpenSettings`로 다르게 두고 `inherit="append"`로 붙였다.
메뉴 생성기가 없으니 `OnMouseDown_Intrinsic`은 열 것을 못 찾고 그냥 돌아온다.

**3. `SetParentInitializer`만으로는 회색이 되지 않는다 (§2, Smart Cast 넷).** 부모가 사 주는 것은
들여쓰기와 "부모 값이 움직이면 다시 그린다" 둘뿐이다. 회색을 정하는 것은
`SettingsControlMixin:IsEnabled`이고 그것이 읽는 것은 **modify 술어뿐**이다
(`Blizzard_SettingControls.lua`). 그래서 술어를 `SetParentInitializer`의 둘째 인자로 같이 넘긴다.

**4. 등록은 `ADDON_LOADED`가 아니라 `PLAYER_LOGIN`이다 (§5-1).** 줄 하나 때문이다. 팩 체크박스는
`LoadedKnownPacks()`가 준 것만 세우는데, 그 함수가 `C_AddOns.IsAddOnLoaded`를 묻는다. 우리
`ADDON_LOADED` 시점에는 우리보다 늦게 로드되는 애드온이 아직 "예"라고 답하지 않으므로, 그 애드온을
쓰는 사람의 화면에서 상자가 통째로 빠진다. 나머지 항목은 더 일러도 상관없었다. 자리는 바인딩이 다
선 뒤다 — 로그인부터 키가 걸릴 때까지 사이에 아무것도 끼우지 않는다는 규칙이 `Events.lua`에 있다.

**5. 섹션 헤더는 대응표의 셋뿐이라 문자열 둘이 고아가 됐다 (§2).** `BLIZZARD_UNIT_FRAMES`와
`ADDON_UNIT_FRAMES`는 메뉴에서 하위 메뉴의 이름이었고, 대응표는 그 자리에 헤더를 두지 않았다.
§5-5대로 지웠다(enUS, koKR, ruRU). 블리자드 상자는 "Player Frame" 식으로, 팩 상자는 그 애드온의 Title로
각자 이름을 대므로 묶음 이름 없이도 읽힌다.

**6. 슬라이더가 쓰던 반올림이 틀려 있었다 (§2, 상태 드라이버).** 옛 믹스인은
`floor(value * 1000 + 1) / 1000`으로 저장했는데, 이것은 정확한 값에 1000분의 1을 더한다 — 0을 0.001로,
0.07을 0.071로 저장한다. 0은 "매 프레임 돈다"를 뜻하는 정상 설정이라(`ApplyOptions`의 `PollEveryFrame`)
이 어긋남이 그냥 넘어갈 것이 아니었다. 옮기면서 단계에 맞춰 반올림하는 것으로 바꿨고
(`floor(value * 100 + 0.5) / 100`), 그래야 저장된 수와 화면의 `%.2f`가 같은 수다.

**그리고 하나는 코드를 문서 쪽이 아니라 §1의 규칙 쪽에 맞췄다.** §1은 설정창의 버튼이
"`DebindPublic`의 토글을 그대로 부른다"고 했는데, 그 토글은 **떠 있는 창을 닫는다**. 소유자의 규칙은
"설정창의 버튼은 우리 창을 열 뿐"이고 버튼 글자도 "Open Debind"라, 눌러서 닫히면 글자가 거짓말이 된다.
그래서 떠 있으면 `Raise()`로 앞에 세우고, 안 떠 있을 때만 토글을 부른다 — 토글이 전투 중과 게임 메뉴
위와 새 프로필을 거절하는 자리는 그 하나뿐이라 §1이 기댄 것은 그대로 남는다.

## 7. 무엇이 무엇을 지키는가

- **`tests/options_spec.lua`** — 값에 대한 물음 전부. 카테고리가 이름대로 서는지, 대응표의 스물한 개
  설정 변수가 다 풀리는지, setter가 표대로 쓰고 기본값에서 칸을 지우는지(클릭 엣지 셋, 블리자드 상자,
  제외, 브랜치의 기본값이 `true`인 것과 `false`인 것, 켬, 스로틀), setter가 보안 쪽에 아무것도 안
  보내고 재구성만 예약하는지, Smart Cast 넷과 전투 부활 상자가 언제 회색인지, Clique가 유닛 프레임 줄
  전부를 가져가고 그 밖은 안 건드리는지, **어느 줄도 shown 술어를 들고 있지 않은지 (§8)**, 전투 문구
  줄의 프레임이 두 regen 이벤트를 듣고 전투 중에만 제목을 보이는지. 그리고 setter가 내려놓은 일을
  `ApplyOptions()`가 받았는지 — `showPlayer`를 저장값대로 쓰고, 전투 중에는 안 쓰고, 전투가 끝나면
  쓰고, 블리자드 프레임 등록에 닿는지.
- **`/debtest`의 `Settings:` 넷** — 클라이언트만 답할 수 있는 것. 카테고리가 설정창에 실제로 서고 줄이
  그려지는지, 톱니바퀴가 그 카테고리를 열면서 우리 창을 안 닫는지, 목록의 버튼이 우리 창을 열고 두 번
  눌러도 안 닫는지, **우리 카테고리를 열어도 목록의 스크롤 상태 세 칸이 `issecurevariable`로 깨끗한지
  (§8)**. 그 마지막 것이 `ScrollTarget`의 `IsProtected`와 `IsAnchoringRestricted`를 결과 줄에 같이
  적는다. §8의 열린 물음 하나가 그 값이다.
- **원리상 어느 쪽도 못 보는 것 하나**: 전투 문구 줄이 화면에서 뜨고 지는 순간. `InCombatLockdown`은
  클라이언트의 것이라 게임 안에서 억지로 참으로 만들 수 없고, 줄 하나 보자고 싸움을 시작하는 시험은
  값어치가 없다. 술어(헤드리스)와 그것이 타고 다니는 다시 그리기(게임 안)를 각각 잡아 양쪽 끝만
  묶어 두었다.

## 8. 전투 중 휠 스크롤에 `SetHeight`가 막힌 것 (2026-09-08)

```
1x [ADDON_ACTION_BLOCKED] AddOn 'Debind' tried to call the protected function 'Frame:SetHeight()'.
[C]: in function 'SetHeight'
ScrollController.lua:15 SetFrameExtent <- ScrollBox.lua:205 Layout <- :781 Update
<- :317 SetScrollPercentageInternal <- ... <- ScrollController.lua:96 OnMouseWheel
<- Blizzard_SettingsPanel.lua:89
```

`Debind/Options.lua`를 넣은 뒤, 전투 중에 설정창을 휠로 스크롤했을 때. 12.1 레퍼런스로 경로를 다시
따라갔다.

### 한 줄

**우리가 `AddShownPredicate`로 초기화기에 쓴 함수를, 블리자드의 `SettingsListMixin:Display`와
`RepairDisplay`가 `ShouldShow()` 안에서 감싸지 않고 읽는다.** 그 읽기가 그 실행을 오염시키고, 같은 실행이
이어서 `SetDataProvider` 또는 `Insert`/`RemoveIndex`로 스크롤 박스를 통째로 다시 짓는다. 그때 쓰인
값(데이터 프로바이더, 보이는 범위, 팬 비율, 프레임 목록)이 전부 오염된 칸이 되고, 뒤의 어느 `Update`도
그 칸을 먼저 읽으니 세션 끝까지 오염이 남는다. 그중 하나가 전투 중이면 `Layout`의 `SetHeight`에서 막힌다.

### 앞선 판단 여섯을 코드로 다시 본 것

1. **델리게이트가 경계다** — 맞다. `AttributeDelegate`는 `SetForbidden()`을 받고, 인자는
   `securecallfunction(unpack, ...)`으로 꺼낸다.
2. **함수 인자를 거부한다, 예외는 프록시의 getter/setter와 튜토리얼** — 맞다. `ErrorIfFunctionArgs`,
   `UnpackArgs`, `SecureWrapFunctionArgs`. 프록시의 둘은 `ProxySettingMixin`이 `securecallfunction`으로
   부른다.
3. **그래서 setter/getter는 깨끗하다** — 맞다. 문제가 다른 데 있다는 것도 맞다.
4. **`data` 테이블의 `name` 읽기가 줄을 그릴 때마다 `Update` 한복판을 오염시켜서 구조적으로 피할 수
   없다** — **틀렸다.** 줄 하나가 그려지는 길은 전부 감싸져 있다. `SettingsListMixin:OnLoad`가 뷰의
   `Factory`, `Resetter`, `ExtentCalculator`를 `securecallfunction`으로 감싸고, 그 안에서 `InitFrame`이
   `frame:Init`을 부른다. 초기화기 호출 자체도 `ScrollBoxListViewMixin:InvokeInitializers`가
   `secureexecuterange`로 돈다. `data.name`을 읽는 `SettingsListElementMixin:Init`은 그 안이다. 그래서
   **줄을 등록하기만 한 애드온은 이 오류를 내지 않는다.** BugSack, Grid2가 같은 탭에 있고 조용한 이유가
   이것이다.
5. **초기화기에 직접 얹은 것들은 델리게이트를 안 지난다** — 맞다. 그런데 그중 **읽히는 자리가 감싸기
   밖인 것은 하나뿐이다.** `AddModifyPredicate`와 `SetParentInitializer`의 술어는 `IsEnabled`가 읽고,
   그것을 부르는 것은 `Init`(감싸짐)과 값이 바뀔 때의 콜백 `EvaluateState`(보호 호출 없음)다.
   `SetLabelFormatter`와 함수 툴팁, 버튼의 `buttonClick`, 덮어쓴 `GetIndent`는 전부 `data` 안이거나
   `Init` 안에서 읽힌다. `isSettingElement`는 접근성 낭독 문자열에서만 읽힌다. **`AddShownPredicate`가
   유일하게 `Display`(줄 135)와 `RepairDisplay`(110, 119)에서 맨 채로 읽힌다.**
6. **`PLAYER_REGEN_DISABLED`의 `RepairDisplay`가 막힌 호출을 낸다** — 경로는 맞고 동기다.
   `dataProvider:Insert` → `OnSizeChanged` → `ScrollBoxListMixin:OnViewDataChanged` →
   `FullUpdate(UpdateImmediately)` → `Update` → `Layout` → `SetHeight`. 정렬 비교자가 없을 때
   `pendingSort`가 거짓이어서 미뤄지지 않는다. 단 **관찰된 것은 휠 스택 하나**고, 이 경로가 막힌 스택은
   없었다. 두 경로가 같은 원인의 두 증상이라 따로 고칠 것이 없다. §3의 술어를 빼면 `RepairDisplay`를
   부를 이유도 같이 사라진다.

### 두 가지 확인

**테인트 모델.** 블리자드 자기 코드가 전제하는 모델이 그대로다. `Blizzard_Setting.lua:425`의 주석:
*"any table access will taint execution and must be done through secure call wrappers."*
`SettingsList.lua:145`는 `rawget`까지 `securecallfunction`으로 감싼 뒤 돌려받은 문자열을 맨 채로 비교한다.
곧 **칸을 읽는 것이 오염시키고, 감싼 호출이 돌려준 값은 그 뒤 실행을 오염시키지 않는다.** 그래서
감싸기 안에서 읽은 것은 안전하고, 감싸기 밖에서 읽은 것은 그 실행 전체를 물들인다. 이 모델에서
`SettingsPanelMixin:RepairDisplay`가 `securecallfunction(settingsList.RepairDisplay, ...)`로 감싸는 것은
**그 뒤의 실행**만 지킬 뿐 **그 안에서 도는 `SetHeight`**는 지키지 못한다. 안에서 오염되면 안에서 막힌다.

**`Display`의 `SetDataProvider`만 감싸고 `RepairDisplay`의 `Insert`는 안 감싼 것이 의도인지 구멍인지.**
둘 다 같은 답이다. 감싸기는 `ShouldShow`가 이미 오염시킨 실행을 되돌리지 못하므로 어느 쪽 감싸기도
이 오류에는 소용이 없다. 블리자드 자기 술어는 보안 코드가 쓴 칸이라 `ShouldShow`가 오염을 안 내고,
그래서 저쪽 코드에서는 구멍이 드러나지 않는다. 애드온이 `AddShownPredicate`를 쓰는 경우를 저쪽이
감싸지 않은 것은 구멍이지만 우리가 메울 수 있는 것이 아니다.

### 우리가 줄일 수 있는 것: **있다, 그리고 전부다**

`AddShownPredicate`를 안 쓰면 오염이 들어가는 자리가 없다. 나머지는 위 5번대로 감싸기 안에서만 읽힌다.

그래서 이렇게 고쳤다:

- **전투 문구 줄은 항상 목록에 있고, 자기 프레임이 보임을 정한다.** `DebindSettingsCombatNoticeTemplate`
  (`DebindUI.xml`)은 `SettingsListSectionHeaderTemplate`을 물려받고, 믹스인 `DebindSettingsCombatNoticeMixin`
  (`Options.lua`)이 두 regen 이벤트를 프레임에 걸어 `Title`만 켜고 끈다. `Init`은 패널의 감싸기 안에서
  돌고, 이벤트는 우리 프레임으로 직접 오니 어느 길도 패널에 쓰지 않는다. 전투 밖에서는 목록 끝에 빈
  헤더 한 줄이 남는다.
- **`RefreshOptionsPanel`, `SettingsInbound.RepairDisplay` 호출, `PLAYER_REGEN_DISABLED` 등록이 빠졌다.**
  부를 이유가 같이 사라졌다.
- 화면의 글자와 색은 그대로다 (빨강, 전투 중에만). 항상 보이는 한 줄로 바꾸는 것(**나** 안)은 `Init`과
  `OnEvent`의 `SetShown` 한 줄을 빼고 색을 정하는 일이고, 그것은 소유자가 정한다.

**원래 후보 둘은 둘 다 답이 아니었다.** (가) `PLAYER_REGEN_DISABLED`만 빼기는 `Display`와
`PLAYER_REGEN_ENABLED`의 `RepairDisplay`가 여전히 술어를 읽으므로 오염이 그대로 남는다. (나) 술어를
없애고 항상 서 있는 줄은 오염을 없애지만, 술어 없이도 전투 중에만 보이는 길이 있으니 그 값어치를
치를 이유가 없다.

### 다른 애드온도 같은 오류를 내는가

위 4번대로 **줄을 등록하기만 한 애드온은 아니다.** `AddShownPredicate`를 쓴 애드온은 같은 오류를 낸다.
가리는 법은 `issecurevariable(view, "dataIndexBegin")` 같은 읽기다. 우리 카테고리를 열기 전과 뒤에
그 답이 갈리면 우리가 원인이고, 어느 카테고리를 열어도 거짓이면 다른 누가 이미 물들였다. 등록한
`/debtest`가 우리 쪽 답을 낸다.

### 열린 물음: 어느 프레임이 protected인가

**못 찾았다.** `Blizzard_SettingsPanel.xml`, `Blizzard_SettingsList.xml`, `ScrollBox.xml` 어디에도
`protected="true"`가 없고, 12.1 레퍼런스 전체에서 그 속성은 `SecureTemplatesBase.xml`과
`QuickKeybind.xml` 둘에만 있다. 패널 안쪽에 앵커를 거는 protected 프레임도 XML과 Lua에서 못 찾았다.

관찰이 좁혀 주는 것은 있다. 같은 `Update` 안에서 `AcquireInternal`이 새 줄 프레임에 `SetHeight`
(`ResizeFrame`)와 `Show`를 먹이고 `Layout`이 `SetPoint`를 먹였는데 그것들은 막히지 않았고, 부모인
`ScrollTarget`의 `SetHeight`만 막혔다. 자식이 아니라 부모만 막힌 것이니 protected 상속은 아니고,
**`ScrollTarget`에 앵커 제한(`IsAnchoringRestricted`)이 걸려 있다**는 쪽이 맞아 보인다. 어떤 protected
프레임이 거기 앵커되어 있는지는 클라이언트만 답할 수 있어서, 등록한 `/debtest`가 `IsProtected`와
`IsAnchoringRestricted`를 결과 줄에 적는다.

**이 물음이 4번의 결론을 흔들지는 않는다.** 4번은 "무엇이 오염시키나"이고 이것은 "오염된 실행이 어디서
막히나"다. 오염이 없으면 어느 프레임이 protected여도 막힐 것이 없다.
