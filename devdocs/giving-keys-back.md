# 키 돌려주기 (2026-09-18 시작)

> 상태: **착수했다.** 2026-09-18 대화에서 소유자가 낸 안이고, 아래는 그 안을 코드 자리에 앉혀
> 본 것이다.
>
> 이 문서가 기대는 측정은 전부 `legacy/dropping-the-game-fallback.md`의 것이다. 새로 잰 것은
> 없다.

## 1. 무엇

**Debind가 들고 있는 키를 어떤 동안만 게임에 돌려주는** 전역 옵션. 돌려주는 자리가 셋이고
줄도 셋이다.

| 줄 | 언제 | 무엇을 |
|---|---|---|
| 바뀐 액션 바 | 탈것, 오버라이드, 빙의, 임시 변신 바 | 그 바의 행동 단축키에 걸린 키 |
| 애완동물 대전 | 대전 동안 | 행동 단축키 1부터 5의 키 |
| 집 편집기 | 편집기가 연 바인딩 컨텍스트 동안 | 그 컨텍스트가 가져가는 명령의 키 |

집 편집기 줄은 **이미 도는 동작에 스위치를 다는 것뿐**이다(`BindingContexts.lua`의
`YieldedKeys`). 앞의 둘이 새로 만드는 것이고, 그중 대전은 아직 배포된 적 없다.

하위 체크박스 둘.

- **그 칸에 실제로 액션이 있을 때만** (바뀐 액션 바 줄 아래)
- **첫 번째 키만 돌려주기** (셋 모두에 걸린다). 한 명령에 키가 둘 걸려 있으면 앞칸의 것만
  내주고 뒷칸은 Debind가 계속 쓴다.

바뀐 바가 무엇인지는 `specialbar` 조건(**특수 단축바**)이 이미 묶어 둔 셋이다
(`Constants.lua:983`). 보너스 바는 안 들어간다. 버튼이 `ActionButtonN` 그대로고 페이지 번호만
바뀌니 사용자에게는 바가 바뀐 것이 아니라 페이지가 넘어간 것이다.

## 2. 상태마다 몇 개

`ACTIONBUTTONn` 바인딩은 `ActionButtonDown(n)`이고, 대전이 아니면 `GetActionButtonForID(n)`으로
버튼을 골라 그 버튼의 칸을 쏜다(`ActionButton.lua:97-148`). 그래서 **살아 있는 버튼의 개수가
상태마다 갈린다.**

| 상태 | 돌려줄 버튼 | 근거 |
|---|---|---|
| 스킨 있는 탈것, 스킨 있는 오버라이드 | 1부터 6 | `NUM_OVERRIDE_BUTTONS = 6`, 7부터 12는 `GetActionButtonForID`가 nil을 돌려준다 |
| 스킨 없는 탈것, 스킨 없는 오버라이드, 빙의, 임시 변신 바 | 1부터 12 | `ActionButtonN`이 그대로 산다 |
| 애완동물 대전 | 1부터 5 | `NUM_BATTLE_PET_HOTKEYS = 5`. 1부터 3은 기술, 4는 교체, 5는 포획 |

**죽은 자리는 돌려주지 않는다.** 스킨 있는 바에서 7부터 12를 내주면 그 키들이 그냥 먹통이 되고,
안 내주면 원래 걸어 둔 Debind 액션이 계속 돈다. 대전의 6부터 12도 같다.

## 3. 재료는 전부 제한 환경에 있다

전투 중에 발동해야 하는 기능이라 비보안 쪽 리빌드로는 못 한다(`CanBuildBindings`의
`InCombatLockdown()`, `UpdateBindings.lua:482`). 제한 환경 안에서 끝나야 한다.

| 필요한 것 | 제한 환경 |
|---|---|
| 바가 바뀌었나 | `HasVehicleActionBar`, `HasOverrideActionBar`, `HasTempShapeshiftActionBar` |
| 대전인가 | `SecureCmdOptionParse("[petbattle]")`. `C_PetBattles.IsInBattle`은 **없다** |
| 스킨이 있나 | 함수는 없다. `OverrideActionBar`를 참조로 넘겨 `IsShown()`으로 읽는다 |
| 그 명령의 키가 무엇인가 | `GetBindingKey` (`RestrictedEnvironment.lua:141`) |
| 칸에 액션이 있나 | `HasAction` (`RequiresValidActionSlot = true`) |
| 키를 풀고 걸기 | 핸들의 `ClearBinding`, `SetBindingClick` (`RestrictedFrames.lua:541-561`) |

**키를 구워 넣지 않는다.** `GetBindingKey`가 제한 환경에 있으니 바가 바뀌는 그 순간 직접 읽으면
되고, 그러면 낡은 값이 낄 자리가 없다. 사용자가 전투 중에 게임 설정에서 `ACTIONBUTTON1`을
다시 걸어도 따라간다.

`ClearBinding`은 `SetOverrideBinding(드라이버, true, key, nil)`이다. 우리가 그 키에 올려 둔
오버라이드만 걷히고, 그 아래 있던 게임 자신의 바인딩이 드러난다. 그게 이 기능의 전부다.

## 4. 언제 도나

`RegisterAttributeDriver`로 `BindingDriver`에 상태 하나를 더 건다. 매니저는 자기 이벤트를 받으면
`timer`를 0으로 놓고 다음 프레임에 등록된 드라이버를 전부 다시 푼다. 값이 바뀔 때만 속성을 쓰고,
그 쓰기가 `_onattributechanged`를 깨운다(`SecureStateDriver.lua:119-143`).

- **주기 폴링이 필요 없다.** `RegisterUnitWatch`(`WantsStatePoll`)와 무관하게 돈다.
- **전투 중에도 돈다.** 매니저 쪽은 비보안이지만 우리 본문은 제한 환경 안이다.
- 필요한 이벤트는 매니저 기본값에 없다. `UPDATE_OVERRIDE_ACTIONBAR`, `UPDATE_VEHICLE_ACTIONBAR`,
  `PET_BATTLE_OPENING_START`, `PET_BATTLE_CLOSE`는 우리가 등록한다
  (`UpdateBindings.lua:671-696`). **옵션이 켜져 있으면 `specialbar`를 쓰는 바인딩이 하나도 없어도
  등록해야 한다.**

드라이버 식은 상태마다 다른 값을 내야 한다. 값이 같으면 매니저가 속성을 안 쓰고, 그러면 우리가
안 깨어난다.

```
[petbattle] b; [vehicleui] v; [possessbar] p; [overridebar] o; [shapeshift] s; 0
```

`[vehicleui]`가 `[possessbar]`보다 앞이다. **빙의는 `[possessbar]`가 참이고 `[vehicleui]`는
거짓이다**(§4-5에서 잼). 이 식은 깨우는 데만 쓰고, 몇 개를 돌려줄지는 본문이 §3의 함수로 다시
판정한다.

**리빌드가 지나가면 다시 돌아야 한다.** `UpdateBindingsMap`이 모든 키에 `SetBindingClick`을 다시
걸므로(`UpdateBindings.lua:2253`), 돌려준 상태에서 리빌드가 지나가면 키가 도로 우리 것이 된다.
리빌드를 닫는 블록이 `state-unitexists`를 1로 쓰니(`ApplyBindingPlan`), 본문을 거기서도 한 번
부르면 자기 치유가 된다.

## 5. 본문이 하는 일

**모양은 첫 커밋의 `UpdateBindings`가 이미 쓴 것이다**(`ed170bd:Debounce/SecureBindings.lua:207-250`).
거기서는 키마다 `bindings.bound`에 **지금 이 키에 무엇이 걸려 있는지**를 들고 있다가, 이번에 이긴
것이 그것과 다를 때만 `ClearBinding`이나 `SetBindingClick`을 불렀다. 집합을 만들어 차집합을 내는
것보다 가볍고, 무엇보다 검증된 모양이다.

```
돌려줄 개수 N을 정한다 (상태가 없으면 0, 아니면 6 / 12 / 5)
i = 1..12:
  이번에 돌려줄 키인가:
    i > N 이면 아니다
    액션 있는 것만 돌려주는 옵션이면 HasAction(칸)이 거짓일 때 아니다
    GetBindingKey(명령)의 키 (하위 옵션이면 첫 번째만)
  그 키의 bindings를 찾는다. 우리가 건 키가 아니면 건너뛴다
  bindings.givenBack와 같으면 아무것도 안 한다
  참으로 바뀌면 ClearBinding, 거짓으로 바뀌면 SetBindingClick
  bindings.givenBack를 새 값으로 둔다
```

`bindings.givenBack`가 첫 커밋의 `bindings.bound`에 해당하는 한 칸이다. 이미 있는 테이블에 붙으니
표를 새로 만들지 않는다.

미리 굽는 것도 그만큼 준다.

**초기화 때 한 번.** 프로필을 안 따르는 고정값이라 리빌드가 다시 만들 이유가 없다
(`SecureBindings.lua`에서 `ActionSlots`나 `MouseButtonNumbers`를 세우는 자리).

- **명령 이름 12개.** 본문에서 `"ACTIONBUTTON" .. i`를 만들면 전이마다 문자열이 생긴다.

**리빌드 때.** 프로필이 정하는 값이다.

- **키에서 그 키의 `bindings`로 가는 표.** 지금 `ClickTimeKeys`는 클릭 버튼 이름에서 가는
  방향뿐이다. `UpdateBindingsMap`의 `SetBindingClick` 줄 옆에서 같이 굽는다
  (`UpdateBindings.lua:2251-2255`).
- **도로 걸 때 쓸 클릭 버튼 이름.** 지금은 `SetBindingClick` 인자로만 지나가고 아무 데도 안
  남는다. 같은 `bindings` 테이블에 한 칸으로 붙인다.

칸 계산은 `ACTION_SLOT_SNIPPET`이 이미 하는 것과 같은 식이다
(`SecureBindings.lua:421-435`). `HasAction`을 쓴다면 그 식을 나눠 쓴다.

## 6. 대전 양보와의 관계

지금 대전 중 1부터 5를 놓는 일은 `BindingContexts.lua`의 `PetBattleKeys`가 한다. 비보안 쪽에서
`GetBindingKey`를 읽어 리빌드로 넘기는 길이고, 대전 중에는 전투 잠금이 아니라서 통한다(§5-1).

**같은 일을 두 곳이 들면 안 된다.** 이 옵션이 대전을 포함하는 이상 `PetBattleKeys`는
없어지고 본문의 한 갈래가 된다. `CollectPetBattleKeys`, `IsKeyYieldedToPetBattle`,
`NUM_PET_BATTLE_BUTTONS`, `inPetBattle`과 그 두 이벤트가 같이 나간다.

**`YieldedKeys`는 자리에 그대로 남는다.** 집 편집기는 전투 중에 열리지 않으니 비보안 쪽
리빌드로 충분하고, 이미 그렇게 돌고 있다. 이 옵션이 더하는 것은 `RefreshYieldedKeys`가 세기
전에 보는 스위치 하나와 "첫 번째 키만"이다.

## 7. 설정 줄

키를 돌려주는 자리가 셋이고, 전역에 들어갈 옵션이니 셋이 다 여기 선다(2026-09-18, 소유자).

```
## 키 돌려주기
 [ ] 바뀐 액션 바
    [ ] 그 칸에 실제로 액션이 있을 때만
 [x] 애완동물 대전 (1부터 5)
 [x] 집 편집기
 ---
 [ ] 첫 번째 키만 돌려주기
```

값은 `db.options`에 평평하게 둔다(`selfCast`, `switchMessages`와 같은 자리). **없는 것이
기본값이고, 기본과 다를 때만 쓴다.**

| 필드 | 기본 | 저장되는 값 |
|---|---|---|
| `giveBackOnReplacedBar` | 끔 | 켤 때 `true` |
| `giveBackWhenActionExists` | 끔 | 켤 때 `true` |
| `giveBackInPetBattle` | **켬** | 끌 때 `false` |
| `giveBackInBindingContext` | **켬** | 끌 때 `false` |
| `giveBackFirstKeyOnly` | 끔 | 켤 때 `true` |

**기본이 갈리는 곳은 그 상황이 전투 중이냐다** (2026-09-18, 소유자). 대전과 집 편집기는 둘 다
전투 중에 일어나지 않는다. 그 동안 키를 내줘도 사용자가 크게 욕볼 일이 없으니 기본이 켬이다.
바뀐 바는 대부분 전투 중이고, 그때 걸어 둔 키가 다른 것을 하면 그것이 곧 손해다.

각 줄에 그 위로 하나씩 더 있다.

- 대전 기술은 행동 칸이 아니라 어떤 액션 타입으로도 못 닿는다(§5). 끄면 그 키로 대전할 길이
  아예 없다.
- 편집기가 가져가는 키는 애초에 우리 것이 아니라서 물러나는 것이지 사용자 편의로 내주는 것이
  아니다(`BindingContexts.lua` 머리말). 끄면 편집기 안에서 우리가 하우징 조작 키를 가로챈다. 이
  양보는 v3.5.2로 이미 나갔다(`27348de`).
- 바뀐 바의 칸은 행동 단축키 액션이 닿는다. 원하는 사람은 그 액션을 선언하면 된다.

**액션의 `keepInBindingContext`는 없어진다** (2026-09-18, 소유자). 액션마다 붙은 잡다한 설정이
너무 많다는 것이 이유다. 이 줄이 전역에 서면 같은 물음의 답이 두 곳에 있게 되고, 둘 중 전역
하나만 남긴다. 지금 합치는 자리는 `IsKeyYielded(key) and not action.keepInBindingContext`다
(`Debind.lua:295`).

같이 나가는 것: `Profile.lua`의 액션 필드 목록 한 줄, `ActionMenuItems.lua`의 메뉴 항목, 그 문구,
그리고 저장된 값을 걷어내는 마이그레이션 한 단계. v3.5.2에서 이 값을 켜 둔 사용자는 전역 줄
하나로 옮겨 가는 것이 아니라 값을 잃는다. 잃는 쪽을 골랐다.

**"첫 번째 키만"은 세 줄 모두에 걸린다.** 다만 세는 것이 줄마다 다르다. 위 두 줄은
`ACTIONBUTTON1`부터 `12`의 첫 키이고, 집 편집기 줄은 게임이 그 컨텍스트에서 가져가는 명령
전부(`CollectClaimedKeys`가 `GetNumBindings`를 훑는다)의 첫 키다. 어느 쪽이든 그 명령은 첫 키로
닿으므로 못 쓰게 되는 조작은 없다.

**하위 체크박스 값은 상위를 꺼도 남긴다.** 끄는 것과 지우는 것은 다르고, 무시하는 것은 코드가
한다. `giveBackWhenActionExists`는 `giveBackOnReplacedBar`가 꺼져 있으면 읽히지 않을 뿐이다.

다섯 다 리로드가 필요 없으니 `RELOAD_REQUIRED_OPTIONS`에 안 들어간다. 바뀌면 굽는 표와 드라이버
등록이 달라지므로 `QueueUpdateBindings`로 리빌드를 건다.

`SettingsTab.lua`에서 하위 체크박스는 `Checkbox(..., INDENT)`로 이미 있는 모양이다(`Whitelist`가
그렇게 쓴다).

라벨은 소유자가 부른 **키 돌려주기**를 쓴다. 문구는 `writing-user-facing-text.md`를 따라 쓰고
`Locales/`에 올린다.

## 8. 열린 물음

**스킨 있는 오버라이드 바에서 스킨 없는 오버라이드 바로 바로 넘어가면 개수를 못 고친다.**
드라이버 값이 둘 다 `o`라 매니저가 속성을 안 쓰고, 우리가 안 깨어난다. 그동안 6개만 돌려준
상태로 남는다. 그런 직접 전이가 실제로 있는지는 안 재봤다. 없으면 이 항목은 닫힌다.

## 9. 무엇이 재지고 무엇이 안 재지나

- **헤드리스가 보는 것**: 상태와 옵션 값에서 "어느 명령을 돌려주는가"를 내는 순수 함수. 상태
  일곱 가지와 하위 옵션 두 값의 곱.
- **정적 검사가 보는 것**: 본문이 lua5.1로 컴파일되는지(`AssertSnippetCompiles`), 문구가 모든
  로케일에 있는지(`check:locales`).
- **원리상 안 재지는 것**: `ClearBinding` 뒤에 그 키를 눌렀을 때 게임 바인딩이 실제로 드러나는가,
  스킨 있는 바에서 개수가 6으로 서는가, 전이 순간의 타이밍. 제한 환경 안에서 일어나는 일이고
  `npm run check`는 게임을 못 본다. 설정 줄 배선도 같다.
