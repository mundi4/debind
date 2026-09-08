# 전역 설정을 게임 설정창의 애드온 탭으로

> 상태: **설계만 (2026-09-08). 코드 없다.** 소유자와 대화 한 번으로 세웠고, 구현은 다른 모델이 이어
> 받는다. 그래서 §2의 대응표는 구현하는 쪽이 코드를 다시 읽지 않고도 옮길 수 있게 저장 위치와 적용
> 함수까지 적었다. 다툰 자리는 `0-DIARY.md` 2026-09-08에 있다.
>
> 배정된 버전은 없다. 정해지면 `0-ROADMAP.md`가 든다.

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
