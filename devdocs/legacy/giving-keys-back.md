# 키 돌려주기 (2026-09-18 시작)

> 상태: **들어갔다** (2026-09-18). 설정 줄 다섯, 액션의 `keepInBindingContext` 제거,
> `UpdateGivenBackKeys`와 그것을 깨우는 속성 드라이버까지.
>
> 2026-09-19에 셋이 더 들어갔다. 집 편집기 줄이 보안 쪽으로 옮겨졌고(6절), 본문이 상태를 다시
> 묻는 대신 드라이버 글자를 읽게 되었으며(2절, 4절), 오버뷰 왼쪽 열 머리글 색이 **"이 키를 누르면
> Debind가 무언가 하느냐"**를 말하게 되었다(`IsKeyHandled`).
>
> 2026-09-24에 legacy로 옮겼다(소유자). 8절은 게임에서 그 상태를 밟아야 닫히는 물음이라 열린
> 채로 남는다.
>
> 그 색은 키를 어떻게 걸었는지를 안 묻는다. 개체창 위 마우스 버튼은 키를 물지 않고 프레임으로
> 들어오는데 멀쩡히 돌고, 에러만 있는 그룹은 키를 물고 있으니 흰색이다(안 나간다는 것은 마크가
> 말한다). 회색은 키가 게임으로 넘어가는 셋뿐이다 - 꺼둔 것만, 다른 전문화 레이어에만, 게임 메뉴 키.
>
> 2026-09-19에 `/abp`로 잰 값이 2절의 표다. 그 밖에는 `legacy/dropping-the-game-fallback.md`의
> 측정에 기댄다.

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

하위 체크박스 하나: **그 칸에 실제로 액션이 있을 때만** (바뀐 액션 바 줄 아래).

**한 명령이 가진 키는 전부 넘어간다.** "첫 번째 키만 돌려주기"를 두려다 뺐다. 9절을 볼 것.

바뀐 바가 무엇인지는 `specialbar` 조건(**특수 단축바**)이 이미 묶어 둔 셋이다
(`Constants.lua:983`). 보너스 바는 안 들어간다. 버튼이 `ActionButtonN` 그대로고 페이지 번호만
바뀌니 사용자에게는 바가 바뀐 것이 아니라 페이지가 넘어간 것이다.

## 2. 상태마다 몇 개

`ACTIONBUTTONn` 바인딩은 `ActionButtonDown(n)`이고, 대전이 아니면 `GetActionButtonForID(n)`으로
버튼을 골라 그 버튼의 칸을 쏜다(`ActionButton.lua:97-148`). 그래서 **살아 있는 버튼의 개수가
상태마다 갈린다.**

**개수와 페이지는 드라이버 글자가 정한다.** 본문은 깨어난 뒤 상태를 다시 묻지 않는다
(2026-09-19). 글자마다 개수 하나와 페이지 함수 하나가 붙고, 페이지 함수는 상태가 아니라 바
인덱스를 답하므로 빌드 내내 같은 값이다.

| 글자 | 상태 | 돌려줄 버튼 | 페이지 |
|---|---|---|---|
| `b` | 애완동물 대전 | 1부터 5 | 없다 |
| `v` | 탈것 UI | 1부터 6 | `GetVehicleBarIndex()` |
| `o` | 오버라이드 바 | 1부터 6 | `GetOverrideBarIndex()` |
| `p` | 빙의 | 1부터 12 | `GetVehicleBarIndex()` |
| `s` | 임시 변신 | 1부터 12 | `GetTempShapeshiftBarIndex()` |

근거는 셋이다. 6은 `NUM_OVERRIDE_BUTTONS`고 7부터 12는 `GetActionButtonForID`가 nil을 돌려준다.
12는 `ActionButtonN`이 그대로 사는 자리다. 5는 `NUM_BATTLE_PET_HOTKEYS`고 1부터 3은 기술, 4는
교체, 5는 포획이다.

**죽은 자리는 돌려주지 않는다.** 스킨 있는 바에서 7부터 12를 내주면 그 키들이 그냥 먹통이 되고,
안 내주면 원래 걸어 둔 Debind 액션이 계속 돈다. 대전의 6부터 12도 같다.

### 2026-09-19에 `/abp`로 잰 것

| 상황 | 토큰 | 페이지 | 칸 | 스킨 |
|---|---|---|---|---|
| 스킨 있는 오버라이드 바 (표본 둘) | `[overridebar]` | 18 | 205~210, 6개 | 628126 / 534041 |
| 빙의 | `[possessbar]` | 16 | 181~192, 12개 | 없다 |
| 스킨 있는 탈것 (울두아르) | `[vehicleui]` | 16 | 181~186, 6개 | 534041 |
| 보너스 바 (드루이드 형상) | `[bonusbar:5]` | 11 | 121~132 | 없다 |
| 탈것 조수석 | 없다 | 1 | 안 바뀐다 | 없다 |

빙의에서 `hasVehicle`이 참인데 `[vehicleui]`는 거짓이었다. **토큰과 `Has...`의 답은 일대일이
아니다.** `.zzz/macro-conditionals.md:213`이 `[vehicleui]`를 `HasVehicleActionBar()`로 적는데,
이 표본이 그것을 반증한다.

`v`와 `o`가 6인 근거가 이 표본 셋이고, 그것이 8절이 아직 열려 있는 이유다.

### 드라이버가 깨운 순간 바가 아직 안 올라와 있다

본문이 `HasVehicleActionBar()` 계열로 페이지를 잡던 동안의 구멍이다. 그 순간 전부 거짓이라
페이지가 nil, 개수가 0이 되어 **키를 하나도 안 돌려주고 끝났고**, 다음 전이까지 그대로
남았다. 2026-09-19에 `Probe_ActionBars.lua`로 쟀다. 울두아르 탈것은 드라이버가 깨울 때
`state:vehicleui page:1:1`이고 1초 뒤에야 `vehicle:16:181`이었다. 보너스 바도 같다.

2026-09-14 측정이 이걸 못 잡은 것은 그때 드라이버가 불린 상태가 `overridebar`, `possessbar`,
`extrabar`, `none` 넷뿐이었기 때문이다(`legacy/dropping-the-game-fallback.md:315`).

글자로 갈래를 고르면 이 자리에 안 걸린다.

## 3. 재료는 전부 제한 환경에 있다

전투 중에 발동해야 하는 기능이라 비보안 쪽 리빌드로는 못 한다(`CanBuildBindings`의
`InCombatLockdown()`, `UpdateBindings.lua:482`). 제한 환경 안에서 끝나야 한다.

| 필요한 것 | 제한 환경 |
|---|---|
| 어느 바인가 | 드라이버가 쓴 글자. `self:GetAttribute("state-giveback")` |
| 그 바의 페이지 | `GetVehicleBarIndex`, `GetOverrideBarIndex`, `GetTempShapeshiftBarIndex` |
| 그 명령의 키가 무엇인가 | `GetBindingKey` (`RestrictedEnvironment.lua:141`) |
| 칸에 액션이 있나 | `GetActionInfo`의 둘째 반환값. **`HasAction`이 아니다** (아래) |
| 키를 풀고 걸기 | 핸들의 `ClearBinding`, `SetBindingClick` (`RestrictedFrames.lua:541-561`) |

**`HasVehicleActionBar` 계열과 `SecureCmdOptionParse("[petbattle]")`, `OverrideActionBar:IsShown()`은
본문에서 빠졌다** (2026-09-19). 글자가 답을 들고 오므로 다섯 호출이 전이마다 사라졌고, 바가 아직
안 올라온 순간에 물어서 빈손으로 끝나던 구멍도 같이 닫혔다(2절).

**키를 구워 넣지 않는다.** `GetBindingKey`가 제한 환경에 있으니 바가 바뀌는 그 순간 직접 읽으면
되고, 그러면 낡은 값이 낄 자리가 없다. 사용자가 전투 중에 게임 설정에서 `ACTIONBUTTON1`을
다시 걸어도 따라간다.

`ClearBinding`은 `SetOverrideBinding(드라이버, true, key, nil)`이다. 우리가 그 키에 올려 둔
오버라이드만 걷히고, 그 아래 있던 게임 자신의 바인딩이 드러난다. 그게 이 기능의 전부다.

## 4. 언제 도나

`RegisterAttributeDriver`로 `BindingDriver`에 상태 하나를 더 건다. 매니저는 자기 이벤트를 받으면
`timer`를 0으로 놓고 다음 프레임에 등록된 드라이버를 전부 다시 푼다. 값이 바뀔 때만 속성을 쓰고,
그 쓰기가 `_onattributechanged`를 깨운다(`SecureStateDriver.lua:119-143`).

- **주기 폴링이 필요 없다.** 매니저가 이벤트를 받고 값이 움직일 때만 돈다.
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
거짓이다**(§4-5에서 잼).

**식은 설정에 따라 줄인다** (2026-09-19). 대전만 켜져 있으면 `[petbattle] b; 0`, 바뀐 바만이면
나머지 넷이다. 안 쓰는 갈래를 매니저가 매 beat마다 푸는 것을 막는다. 둘 다 꺼져 있으면 드라이버
자체를 내린다.

**식이 내는 글자가 답 전체다.** 몇 개를 돌려줄지도 어느 페이지인지도 글자가 정하고, 본문은 다시
묻지 않는다(2절).

**리빌드가 지나가면 다시 돌아야 한다.** `UpdateBindingsMap`이 모든 키에 `SetBindingClick`을 다시
걸므로(`UpdateBindings.lua:2253`), 돌려준 상태에서 리빌드가 지나가면 키가 도로 우리 것이 된다.
`ApplyGiveBack`이 마지막에 `UpdateGivenBackKeys`를 직접 한 번 부르는 것이 그 자리다.

## 5. 본문이 하는 일

**모양은 첫 커밋의 `UpdateBindings`가 이미 쓴 것이다**(`ed170bd:Debounce/SecureBindings.lua:207-250`).
거기서는 키마다 `bindings.bound`에 **지금 이 키에 무엇이 걸려 있는지**를 들고 있다가, 이번에 이긴
것이 그것과 다를 때만 `ClearBinding`이나 `SetBindingClick`을 불렀다. 집합을 만들어 차집합을 내는
것보다 가볍고, 무엇보다 검증된 모양이다.

```
돌려줄 개수 N과 페이지를 글자에서 읽는다 (글자가 없으면 0)
ContextKeys에 든 키를 이번에 돌려줄 집합에 얹는다
i = 1..12:
  이번에 돌려줄 키인가:
    i > N 이면 아니다
    액션 있는 것만 돌려주는 옵션이면 GetActionInfo(칸)의 id가 없을 때 아니다
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
(`SecureBindings.lua:421-435`).

**`HasAction`은 이 자리에서 못 쓴다** (2026-09-18, 소유자가 게임에서 잼). 스킨 있는 오버라이드
바에서 206번 칸은 `HasAction`이 참인데 `GetActionInfo`가 nil이었고, 그 바 자신의 버튼도 숨겨져
있었다. 블리자드도 `HasAction`을 안 본다. `OverrideActionBar`의 `Setup`이 버튼을 보이고 숨기는
기준은 `GetActionInfo(button.action)`의 둘째 반환값이 0보다 큰지다. 우리도 같은 것을 읽는다.

## 6. 대전 양보와의 관계

지금 대전 중 1부터 5를 놓는 일은 `BindingContexts.lua`의 `PetBattleKeys`가 한다. 비보안 쪽에서
`GetBindingKey`를 읽어 리빌드로 넘기는 길이고, 대전 중에는 전투 잠금이 아니라서 통한다(§5-1).

**같은 일을 두 곳이 들면 안 된다.** 이 옵션이 대전을 포함하는 이상 `PetBattleKeys`는
없어지고 본문의 한 갈래가 된다. `CollectPetBattleKeys`, `IsKeyYieldedToPetBattle`,
`NUM_PET_BATTLE_BUTTONS`, `inPetBattle`과 그 두 이벤트가 같이 나간다.

**집 편집기 줄도 보안 쪽으로 옮겼다** (2026-09-19). 2026-09-18에 여기 "집 편집기는 전투 중에
열리지 않으니 비보안 쪽 리빌드로 충분하다"고 적었던 근거는 **그 비용을 안 잰 것**이다.

잰 값: 벤치(`lua5.1 tests/run.lua --bench`)로 액션 20개 / 바인딩 60개 / 조건 밀도 0.2 프로필이
솔버만 평균 22.06ms, 최대 38ms이고 리빌드는 그 위에 굽기가 얹힌다. 솔버 결과는 캐시되지 않는다
(`UnreachableBindingCache`는 결과 캐시가 아니라 이번 풀이에서 떨어진 바인딩의 표식이고
`BuildKeyMap` 첫 줄에서 비워진다). 편집기는 모드마다 컨텍스트가 갈리니 한 번 열고 닫는 동안
여러 번 돈다.

**비보안 쪽은 "컨텍스트가 점유하는 키"라는 사실만 넘긴다.** `BakeContextKeys`가 제한 환경의
`ContextKeys`에 대입문으로 굽고, 잡을지 놓을지는 `UpdateGivenBackKeys`가 네 갈래를 합쳐 한 번에
정한다. 그래야 `bindings.givenBack`이 유일한 답으로 남는다.

- 리빌드는 `yielded`를 안 본다. 편집기가 가져간 키도 평소처럼 굽고, 넘겨주는 일은 보안 쪽이
  한다. 그래서 `IsKeyOurs`가 양보 중에도 참이고, 오버뷰 머리글이 흰색으로 선다.
- 굽는 자리는 둘이다. 컨텍스트 전이, 그리고 **리빌드 끝(`ApplyGiveBack`)**. 리빌드가 오버라이드를
  전부 걷고 다시 걸므로, 편집기가 열린 채 리빌드가 돌면 넘겨준 키가 돌아온다.
- 전투 중이면 `PLAYER_REGEN_ENABLED`까지 미룬다(`FlushContextKeys`). 지금 리빌드가 미뤄지는
  것과 같은 제약이다.

**안 간 길 둘.** `[house:editor]` 매크로 조건으로 드라이버를 만들기 - 모드마다 다른 컨텍스트가
켜지는데 조건은 하나짜리 참·거짓이라 모드 전환을 못 따라간다. 비보안 쪽에서 그 키만
`SetOverrideBinding`으로 여닫기 - 한 키의 양보를 두 곳이 들게 된다. 보안 쪽 `bindings.givenBack`이
비보안 쪽이 벗긴 것을 모르므로, 차량바가 끝날 때 편집기가 연 채로 키가 우리에게 돌아오고,
반대로 편집기를 닫으며 씌우면 차량바가 서 있는 내내(전투 중) 키가 우리 것으로 남는다.

**안 푸는 것.** 편집기가 열린 채 전투가 시작되고 그 안에서 단축키가 바뀌는 경우. 전투 중에는
보안 쪽에 아무것도 못 보낸다. 그런 자리가 실제로 있는지도 안 재봤다.

## 7. 설정 줄

키를 돌려주는 자리가 셋이고, 전역에 들어갈 옵션이니 셋이 다 여기 선다(2026-09-18, 소유자).

```
## 키 돌려주기
 [ ] 바뀐 액션 바
    [ ] 그 칸에 실제로 액션이 있을 때만
 [x] 애완동물 대전 (1부터 5)
 [x] 집 편집기
```

값은 `db.options`에 평평하게 둔다(`selfCast`, `switchMessages`와 같은 자리). **없는 것이
기본값이고, 기본과 다를 때만 쓴다.**

| 필드 | 기본 | 저장되는 값 |
|---|---|---|
| `giveBackOnReplacedBar` | 끔 | 켤 때 `true` |
| `giveBackWhenActionExists` | 끔 | 켤 때 `true` |
| `giveBackInPetBattle` | **켬** | 끌 때 `false` |
| `giveBackInBindingContext` | **켬** | 끌 때 `false` |

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

**하위 체크박스 값은 상위를 꺼도 남긴다.** 끄는 것과 지우는 것은 다르고, 무시하는 것은 코드가
한다. `giveBackWhenActionExists`는 `giveBackOnReplacedBar`가 꺼져 있으면 읽히지 않을 뿐이다.

다섯 다 리로드가 필요 없으니 `RELOAD_REQUIRED_OPTIONS`에 안 들어간다. 바뀌면 굽는 표와 드라이버
등록이 달라지므로 `QueueUpdateBindings`로 리빌드를 건다.

`SettingsTab.lua`에서 하위 체크박스는 `Checkbox(..., INDENT)`로 이미 있는 모양이다(`Whitelist`가
그렇게 쓴다).

라벨은 소유자가 부른 **키 돌려주기**를 쓴다. 문구는 `writing-user-facing-text.md`를 따라 쓰고
`Locales/`에 올린다.

## 8. 열린 물음

**`v`와 `o`를 6으로 둔 것은 다른 것이 나올 때까지다** (2026-09-19, 소유자). 잰 표본은 셋뿐이고
(2절) 셋 다 스킨이 있었다.

- **`[overridebar]`가 참인데 스킨이 0인 자리.** 블리자드 코드에 갈래는 있다
  (`ActionBarController.lua:157-158`). 밟히면 그 토큰의 답이 6이 아니라 12다.
- **`[vehicleui]`가 언제나 스킨 있는 바인가.** 표본이 하나다(울두아르, `vehicleSkin=534041`,
  6칸). 실제 대응은 탈것 UI 쪽으로 보이지만 C 코드라 확인할 길이 없다.

둘 중 하나라도 12로 밝혀지면 2절의 표가 틀린다. 재보려 했으나 풍운수도사 분신 주문이 삭제되어
못 밟았다(2026-09-19, 소유자).

**스킨 있는 오버라이드 바에서 스킨 없는 오버라이드 바로 바로 넘어가는 자리도 같은 물음이다.**
드라이버 값이 둘 다 `o`라 매니저가 속성을 안 쓰고, 우리가 안 깨어난다. 위의 갈래가 안 밟히는
것이면 이 항목도 같이 닫힌다.

두 바에 다른 글자를 주는 길은 없다(2026-09-24). 드라이버 값은 매크로 조건에서만 나오는데
스킨을 보는 조건이 없고, `[overridebar]`는 `HasOverrideActionBar()` 하나다. 스킨을 가르는 것은
`OverrideActionBar`가 떴느냐뿐이다(`ActionBarController.lua:148-152`). 그 `OnShow`/`OnHide`를
`WrapScript`로 잡아 깨우는 길은 소유자가 막았다.

**칸의 내용이 바뀌는 것도 같은 구멍이다.** "채워진 버튼만"은 드라이버가 깨울 때 한 번 읽는다.
토큰이 그대로인 채 칸만 채워지거나 비면 다시 안 읽는다. 위와 같은 기계이고, 여는 열쇠도 같다.
드라이버 값이 이 두 가지를 구분할 수 있게 되는 것.

### 남의 애드온은 이 물음에 답을 안 갖고 있다

2026-09-19에 둘을 읽었고, **둘 다 "칸이 몇 개냐"는 세지 않는다.** 페이지만 정한다. 다시 찾아볼
일이 없도록 적어 둔다.

- **Dominos** — 드라이버를 일곱 개 걸고 무엇이 움직이든 페이지를 다시 계산한다. 하나가 일러서
  틀리면 뒤따라오는 것이 고치는 모양이다. 키를 거는 쪽은 매크로 조건이 아니라
  `OverrideActionBarButton1`의 `OnShow`/`OnHide`를 `WrapScript`으로 잡고, 도는 루프가 1부터
  6으로 **박혀 있다.**
- **EllesmereUI** — Dominos를 베꼈는데 프레임에 붙는 부분은 일부러 뺐다. 주석이 이유를 적는다.
  `OverrideActionBar`에 자식으로 붙으면 그 보호 프레임의 자식 계통이 오염돼
  `BeginActionBarTransition`이 막힌다. 그래서 `overrideui`를 `[overridebar][vehicleui]` 매크로
  조건으로 만드는데, **그 값을 읽는 데가 없다.**

## 9. 안 둔 것: "첫 번째 키만 돌려주기"

한 명령에 키가 둘 걸려 있을 때 앞칸만 내주고 뒷칸은 Debind가 계속 쓰는 하위 체크박스. 설계도
코드도 한 번 들어갔다가 **잰 값 하나로 빠졌다** (2026-09-18, 소유자).

**게임이 두 칸의 자리를 리로드 너머로 안 지킨다.** 소유자가 `ACTIONBUTTON1`의 키를 다 지우고
첫 칸에 `1`을 걸고 리로드, 둘째 칸에 마우스 중간 버튼을 걸고 다시 리로드했더니 **첫 칸이 중간
버튼이 되어 있었다.** 설정 창은 거는 시점에는 자리를 지킨다(`Blizzard_Keybindings.lua`의
`RebindKeysInOrder`가 슬롯 순서대로 다시 건다). 뒤집히는 곳은 저장과 복원이고, 그 순서를 정하는
코드는 클라이언트 Lua에 없다.

그래서 "첫 번째 키"가 **로그인마다 다른 키를 가리킨다.** 체크박스가 약속할 수 있는 것이 없다.

**다시 열리는 조건은 하나다.** 두 칸의 자리가 저장을 건너 지켜지거나, 사용자가 화면에서 본
그 자리를 우리가 다른 방법으로 알아낼 수 있게 되는 것.

## 10. 커버리지

**헤드리스가 본문을 그대로 돈다.** `tests/giveback_spec.lua`가 제한 환경 인터프리터 위에서
`UpdateGivenBackKeys`를 부르고, `ClearBinding`과 `SetBindingClick`이 쓴 오버라이드 표를
`GetBindingAction(key, true)`로 읽는다. `boundkey_spec.lua`가 연 길이다.

| 무엇 | 어디 |
|---|---|
| 글자 다섯이 저마다 몇 개를 넘기는지 (`b`5, `v`6, `o`6, `p`12, `s`12) | `giveback_spec` |
| 바 질의가 전부 거짓인 순간에도 글자가 답을 낸다 | `giveback_spec` |
| 바뀐 바 줄이 꺼져 있으면 아무것도 안 넘어간다 | `giveback_spec` |
| 대전 줄은 값이 없으면 켜져 있고, `false`를 써야 꺼진다 | `giveback_spec` |
| 한 명령이 가진 키 둘이 다 넘어간다 | `giveback_spec` |
| 빈 칸은 건너뛰고, 그 옵션이 꺼져 있으면 안 건너뛴다 | `giveback_spec` |
| 넘긴 사이에 명령을 다시 걸어도 키가 돌아온다 | `giveback_spec` |
| 같은 상태로 한 번 더 돌면 바인딩 호출이 0이다 | `giveback_spec` |
| 컨텍스트가 점유한 키가 넘어가고 돌아오는 것, 우리가 안 건 키는 건너뛰는 것 | `giveback_spec` |
| 바가 끝나도 편집기가 열려 있으면 그 키는 안 돌아오는 것 | `giveback_spec` |
| 편집기가 열린 채 리빌드가 돌아도 그 키가 넘어간 채로 있는 것 | `giveback_spec` |
| 집 편집기 줄이 꺼져 있으면 점유 키가 안 넘어가는 것 | `giveback_spec` |
| 어느 키가 점유로 잡히는지 (헤더 행, `None` 컨텍스트, 키 둘, 집합이 움직였나) | `context_spec` |
| 점유된 키도 `KeyMap`에 서고 우리가 잡는 것 | `context_spec` |
| 본문이 lua5.1로 컴파일되는지, 문구가 로케일에 다 있는지 | `npm run check` |

**오버뷰 머리글 색에는 테스트가 없다.** 색을 고르는 것이 `IsKeyHandled(key)` 불린 하나고, 그
불린이 각 경우에 무엇인지는 `keymap_spec`이 든다. 남는 것은 그 값을 읽어 문자열에 색을 입히는 한
갈래와, 그 문자열이 템플릿에 닿는 배선이다. 둘 다 읽으면 끝나는 자리라 재지 않는다.

**원리상 안 재지는 것.**

- `ClearBinding` 뒤에 그 키를 눌렀을 때 게임 자신의 바인딩이 실제로 나가는가.
- 전이가 도착하는가. 블리자드 매니저가 드라이버를 푸는 일이고 헤드리스에는 매니저가 없다.
- 8절의 둘. 그 상태를 인게임에서 밟아야 한다.
- 컨텍스트 전이가 리빌드를 안 도는 것의 값. 도는지 안 도는지는 잴 수 있어도 프레임 시간은 못
  잰다.
- 설정 줄 배선.
