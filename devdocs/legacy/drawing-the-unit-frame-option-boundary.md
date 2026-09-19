# 유닛 프레임 옵션의 경계 (2026-09-08 설계)

> 상태: 전부 구현했다. §8이 무엇이 어떻게 바뀌었는지고, §9가 무엇이 그것을 지키는지다.
> **구현이 §3에서 그린 모양과 다르게 나왔다.** 관문을 헤더 문에 한 벌 더 두는 대신 헤더 문이
> 등록을 그만두게 했다. 왜 갈렸는지는 §8 머리에 있고, §3의 고른 근거는 그대로 선다.

이 문서가 정하는 것은 **유닛 프레임 세 옵션이 각각 무엇을 묻는가**와 **그 물음이 참이 되려면
코드에서 무엇이 바뀌어야 하는가**다. 앞선 세션의 조사 위에 섰고, 그 조사가 틀린 자리 둘은 §6에
적었다.

## 0. 어디서 나온 자리이고, 무엇을 봤나

**바로 앞 작업이 이 옵션들을 게임 설정창의 애드온 탭으로 옮겼다**
(`moving-global-options-to-the-settings-panel.md`). 옮기는 일 자체는 자리와 위젯을
바꾸는 일이라, **각 옵션이 무엇을 묻는 상자인지는 옛 메뉴에 있던 그대로 따라왔다.** 세 종류가 한
구역에 평평하게 서고 나서야 그 물음들이 서로 어긋나 있는 것이 보였고, 이 문서는 그 경계를 다시
긋는 자리다.

### 무엇을 조사했나

1. 유닛 프레임이 우리에게 들어오는 **모든 경로**와, 경로마다 어느 옵션이 실제로 걸리는 자리.
   `FrameRegistry.lua`(`RegisterFrame`, `TakeNamedFrame`, `CollectHeaderChildren`,
   `CollectOUFFrames`, `UpdateBlizzardFrames`), `SecureBindings.lua`의 `clickcast_register`와
   `OnClickCastRegister`, `DebindCliqueFake` 전체, `Profile.lua`의 `TakesUnregisteredFrames`와
   `TakesPackFrames`.
2. **설치된 팩 넷이 실제로 어느 문을 쓰는지.** Grid2, VuhDo, EllesmereUIUnitFrames,
   EllesmereUIRaidFrames의 소스를 직접 읽었다. 팩 체크박스가 사용자에게 무엇으로 보일지가 여기
   달려 있어서다.
3. 지금 화면(`Options.lua`)이 그 셋을 어떤 모양으로 세우고 있는지, 그리고 클라이언트가 이 깊이에
   무엇을 쓰는지(섹션 헤더, 들여쓰기 한 단계, 카테고리 나무).

### 어떤 성질의 문서인가

- **전부 읽어서 낸 것이고, 게임 안에서 돌려본 것은 하나도 없다.**
- **주석을 근거로 삼지 않았다.** 실제로 `RegisterFrame`의 관문 주석이 틀린 것이 나왔고(§2), 앞선
  세션의 조사 쪽이 틀린 자리도 둘 나왔다(§6).
- **"등록 방식 둘을 하나의 문으로 본다"는 축은 소유자 판단이다**(2026-09-08). 이 문서의 §3은 그
  축 위에 서 있고, 축이 움직이면 §3도 같이 움직인다.
- 테인트는 여기서 안 다뤘다. 별개 건이다.

## 1. 문은 하나, 문이 아닌 것이 둘

- **문 (Clique API)** — 애드온이 자기 의사로 건넨다. 안에 등록 방식이 둘 있다.
  `ClickCastFrames[frame] = true`(테이블)와 `ClickCastHeader` + `clickcast_register`(헤더
  프로토콜). **둘을 가르지 않는다.** 갈리는 기준은 그 프레임이 보안 그룹 헤더 안에서 만들어졌느냐
  뿐이고, 헤더가 자식을 만드는 순간은 제한 환경이라 테이블에 쓸 비보안 시점이 아예 없다
  (`Clique/core/core.lua:216`). 애드온의 성의 차이가 아니다.
- **뚫고 들어가는 것** — 이름 후크(`TakeNamedFrame`), 헤더 자식 훑기(`CollectHeaderChildren`),
  oUF 훑기(`CollectOUFFrames`). 셋 다 `TakesUnregisteredFrames()`가 켜고 끈다.
- **남이 Clique 이름을 점유했을 때** — `DebindCliqueFake`의 `AskHolder`. 홀더가 놓은 프레임은
  옵션과 무관하게 받고, 홀더가 쥔 프레임은 `TakesUnregisteredFrames()`가 켜져 있을 때만 같이
  받는다.

## 2. 지금 코드의 결함: 팩 스위치가 문 안에서 반쪽만 걸린다

코드로 확인했다.

- 테이블 등록은 `DebindPrivate.RegisterFrame`을 지나고, 그 함수 맨 앞
  (`FrameRegistry.lua:675`)에서 `TakesPackFrames`를 묻는다.
- 헤더 프로토콜은 제한 환경의 `clickcast_register` 스니펫이 `ccframes`를 직접 채우고
  (`SecureBindings.lua:1134~`), 마지막에 `CallMethod("OnClickCastRegister", button:GetName())`으로
  비보안 쪽 `DebindPrivate.ccframes[button]`을 **직접** 쓴다(`SecureBindings.lua:1171`).
  **`RegisterFrame`을 아예 안 지난다.** 그러니 팩 스위치가 안 걸린다.

`RegisterFrame`의 관문 위 주석은 "every door comes through here"라고 단언하는데 그 단언이 틀렸다.

**사용자가 보는 결과.** `Grid2` 체크박스가 무엇을 끄는지를 그 사람의 레이아웃 선택이 정한다.
Grid2는 보통 파티와 공대에 블리자드 보안 헤더를 써서 헤더 프로토콜로 오고(`GridLayout.lua:41`의
`SECURE_INIT`), 커스텀 레이아웃과 `SPECIAL_HEADERS`와 `nameList`에 필터를 얹은 조합에서는 자기
구현 헤더를 써서 테이블로 온다(`GridGroupHeaders.lua:332`). 앞쪽은 안 꺼지고 뒤쪽만 꺼진다. 읽을
수 있는 규칙이 아니다.

(`template(dbx, insecure)`의 `insecure` 인자는 `Grid2.debugging` 스위치와 레이아웃 미리보기
뿐이라 릴리스에서 항상 거짓이다. 위의 갈림은 그 인자와 무관하게 `dbx`만으로 갈린다.)

## 3. 결정 1: 팩 스위치는 문에도 건다. (다) 뜻을 승격한다

§2의 반쪽을 그대로 두는 안은 없다. 놓인 안은 셋이었다.

- **(가) 문 전체에 건다.** 지금 테이블 쪽에만 걸린 관문을 헤더 프로토콜에도 건다. 팩 상자의 뜻은
  그대로 "그 애드온이 건넨 것을 우리가 거부한다"이고, 달라지는 것은 그 거부가 경로를 안 가리게
  되는 것뿐이다.
- **(나) 문 전체에서 뺀다.** 목록의 원래 용도로 돌아간다(`FrameRegistry.lua:1073` 주석: *"The hook
  only decides when, and `KNOWN_PACK_FRAMES` decides what."*). 팩 상자는 이름 후크 전용이 되고
  `미등록 프레임 가져오기`의 자식으로 앉는다.
- **(다) 뜻을 승격한다.** 팩 상자는 "이 애드온은 아예 안 건드린다"가 된다. 경로와 무관하고, 그
  애드온이 건넸는지와도 무관하다. 구현은 (가)와 같고, 다른 것은 상자가 약속하는 말이다.

**고른 것: (다).** 팩 체크박스의 뜻은 **"Debind는 이 애드온의 유닛 프레임을 아예 안 건드린다"**다.
경로와 무관하고, 그 애드온이 우리에게 건넸는지와도 무관하다.

**왜 (나), 곧 문에서 빼는 안이 아닌가.** 팩 상자가 이름 후크 전용이 되면, 프레임을 건네주는
팩에게는 그 상자가 **아무것도 안 하는 상자**가 된다. `TakeNamedFrame`은 후크가 불릴 때마다 돌지만
이미 행이 있는 프레임은 `RegisterFrame`이 검사 전에 되돌려 보내므로, 건네주는 팩의 프레임은 이름
후크가 집을 일이 애초에 없다. 그리고 **어느 팩이 건네줄지는 로그인 시점에 알 수 없다.** 같은
Grid2가 레이아웃에 따라 양쪽이다. 그러면 상자가 켜졌는지 꺼졌는지로 화면이 답을 못 하고, 지금
보드의 넷(Grid2, VuhDo, EllesmereUIUnitFrames, EllesmereUIRaidFrames)이 모두 테이블에 건네주고
있으니 넷 다 죽은 상자가 된다. 소유자가 건 조건, 곧 아무것도 안 하는 체크박스를 세우지 않는다는
것을 정면으로 깬다.

**왜 (가)가 아니라 (다)인가.** 구현은 같다. (가)는 문 전체에 스위치를 걸되 뜻은 "건넨 것을
거부한다"에 묶어 두는 안인데, 문 셋에 다 걸고 나면 남는 동작이 (다)와 한 글자도 다르지 않다.
같은 코드에 더 좁은 이름표를 붙이는 것은 이름표만 틀리게 만드는 일이라 고를 이유가 없다.

**애드온이 자기 의사로 건넨 것을 우리가 거부하는 것이 옳은가.** 옳다. Clique에 이런 스위치가 없는
것은 Clique가 **사용자가 직접 깔아서 쓰는 엔진**이기 때문이다. 깐 사람은 어디서든 쓰겠다고 이미
말했다. Debind는 사용자가 시키지 않아도 눈에 띄는 유닛 프레임을 주워 오는 자세라, 그 자세에는
빠져나갈 문이 하나 있어야 맞다. 그리고 거부해도 그 팩의 자기 클릭 처리는 그대로다. 우리가 그
프레임을 감싼 적이 없으니 뗄 것도 없다.

## 4. 결정 2: 홀더 물음은 안 가른다

"아무도 안 건넨 것을 뚫고 들어갈까"와 "남이 쥔 것을 같이 가져갈까"는 분명 다른 물음이다. 그래도
체크박스는 하나로 둔다.

- 홀더가 있는 판 자체가 드물다. 지금 보드에서 홀더를 세우는 것은 EllesmereUIRaidFrames 하나뿐이다
  (`EUI_RaidFrames_ClickCast.lua:1617`의 `SetupClickCastFramesHook`). 나머지 판에서는 둘째 상자가
  영영 아무 일도 안 한다. §3에서 (나)를 버린 이유와 같은 결함이다.
- 두 물음의 답이 갈리는 사용자를 그릴 수 없다. 안 건넨 프레임은 놔두라고 말한 사람이 남이 쥔
  프레임은 가져가라고 말할 이유가 없다.
- 지금 문구가 이미 둘을 같이 덮는다. 홀더가 쥔 프레임은 그 애드온이 자기 것으로 쥐고 있는
  프레임이므로, "addons keep to themselves"가 그대로 맞는 말이다.

## 5. 결정 3: 팩 상자는 계속 "설치돼 있나"를 묻는다

(다)를 고르고 나면 상자의 뜻이 경로에 안 달리므로, 세울지 말지를 정하는 물음도 경로에 안 달린다.
설치된 팩은 어느 문으로 오든 상자가 막는다. `LoadedKnownPacks()`는 그대로 쓴다.

"우리에게 안 건네고 있나" 같은 물음은 답이 로그인 뒤에야 생기는데, 카테고리는 `PLAYER_LOGIN`에 한
번 서고 다시 안 선다. 예측으로 세우는 목록이 되고, 그 예측이 틀리는 것이 지금의 결함이다.

설치돼 있는데 그 팩의 유닛 프레임을 안 쓰는 사람에게는 상자가 헛돈다. 그건 블리자드 개체창 상자
일곱이 이미 지고 있는 성질이고(숨겨 둔 프레임의 상자), 우리가 알 수 있는 것도 아니다.

### 이 상자로 못 지목하는 것

**목록에 없는 애드온은 뺄 수 없다.** 지목하는 어휘가 `KNOWN_PACK_FRAMES`뿐이라서다. 두 상자를
프레임 하나에 겹쳐 보면 이렇게 갈린다.

| | 문을 연다 (Clique 문) | 문을 안 연다 |
|---|---|---|
| **목록에 있는 팩** | 팩 상자가 정한다 | 팩 상자와 미등록 상자가 둘 다 켜져야 받는다 |
| **목록에 없는 애드온** | **무조건 받는다** | 미등록 상자가 정한다 |

**축이 둘로 보이지만 팩 상자 쪽만 구멍이 있다.** 구현이 헤더 문까지 `RegisterFrame`으로
접었으므로(§8) 위 칸의 문 구분은 팩 상자에게 아무 뜻이 없다. 목록에 있는 팩은 어느 문으로 오든
상자가 막는다. 남는 것은 아래 줄, 곧 **지목할 이름이 없는 애드온**이다.

오른쪽 아래 칸에서 실제로 닿는 것은 블리자드 보안 그룹 헤더를 쓰거나 oUF를 쓰는 애드온뿐이다.
`TakeNamedFrame`은 목록이 있어야 집으므로, 자기 헤더를 굴리면서 문도 안 여는 애드온은 우리가 볼
방법이 없다. **그래서 어느 상자로도 못 빼는 것은 오른쪽 위 한 칸뿐이다.**

**이 구멍은 (다)가 만든 것이 아니다.** 목록에 없는 애드온을 뺄 수단은 지금도 없고, 이름이 바뀌면
아무것도 안 맞아서 원래 자리로 돌아간다는 것을 `KNOWN_PACK_FRAMES` 주석이 이미 지고 있다. **그리고
화면에는 안 드러난다.** 목록에 없는 애드온은 상자도 없으니, 못 지키는 약속을 하는 자리가 없다.
(나)에서 문제가 됐던 것은 반대다. 상자가 서 있는데 아무 일도 안 한다.

메우는 일반해는 아무 애드온 이름이나 적어 넣는 칸인데, 그것은 범용 설정 레이어라 안 둔다. 좁은
해는 원래 하던 그대로, 제보가 오면 목록에 행을 더하는 것이다.

## 6. 앞선 조사가 틀린 자리

**1. 셋째 칸(종류)은 이름 후크 전용이 아니다.** `ReadFrameType`이 유닛을 읽기 **전에**
`KNOWN_PACK_FRAMES`를 훑어 `row[3]`을 쓴다(`FrameRegistry.lua:322~327`). 그래서 테이블로 들어와
`told`가 없는 프레임도 같은 값을 받는다. 같은 프레임이 경로에 따라 종류가 다르게 붙는다는 말은 이
목록의 행에 대해서는 성립하지 않는다. `KNOWN_PACK_FRAMES` 위 주석이 "a row that carries one holds
it whichever door the frame arrives through"라고 적은 그대로다. 주석이 맞고 조사가 틀렸다.

**2. `OnClickCastRegister`에서 이름으로 팩을 묻는 것은 되지만, 관문으로는 못 쓴다.** `buttonName`이
오는 것은 맞고 `PackAddonForFrameName`이 답도 한다. 그런데 그 `CallMethod`가 불릴 때는 스니펫이
이미 `info.hd`, `frameType`, `useparent-clickbutton`, `button:Run`, `clickcast_onenter`와
`clickcast_onleave`를 다 써 놓은 뒤다. 거기서 비보안 행만 안 만들면 제한 환경에는 등록이 남고
비보안에는 없는 어긋난 상태가 된다.

그래서 여기서 낸 결론은 "관문은 스니펫 안에 있어야 한다"였다. **그 결론이 안 따라온다.** 셋째
길이 있었다. 스니펫이 그 다섯 가지를 아예 안 쓰게 하는 것. 그러면 `CallMethod`가 늦는 것이 문제가
아니게 되고 관문도 한 벌로 끝난다(§8).

## 7. 그래서 화면은 이렇게 선다

**먼저 불변식 하나. 이 구역의 모든 상자는 뺄셈이다.** 켜서 무언가 늘어나는 상자가 하나도 없다.
팩 상자를 끄면 그 애드온이 빠지고, 미등록 상자를 끄면 안 건네준 프레임이 빠지고, 블리자드 상자를
끄면 그 개체창이 빠진다. 끈 상자들이 뺀 것의 합집합이 Debind가 안 건드리는 것이고, 사용자가
읽어야 할 규칙은 그 한 줄이 전부다.

**이것이 §5 표의 "둘 다 켜져야 받는다"를 설명 없이 읽히게 만드는 것이다.** 상자 둘이 다 "안 하기"를
뜻하면 그 둘의 AND는 따로 배울 것이 없다. 배워야 하는 것은 OR이거나, 부모 자식이거나, 한쪽이
다른 쪽을 뒤집을 때다. 아래에서 중첩과 부모 상자를 안 쓰는 진짜 근거가 이것이고, 새 상자를 들일
때 먼저 물어야 할 것도 이것이다.

**약한 자리는 반대 방향 하나뿐이다.** 상자를 켰는데 아무 일도 안 생기는 경우. 목록에 있으면서 문은
안 여는 팩을 켜 두고 미등록 상자를 껐을 때다. 그 답은 이미 화면에 있다.
`TAKE_UNREGISTERED_UNIT_FRAMES_DESC`의 마지막 문장이 끄면 애드온이 건넨 프레임만 쓴다고 말한다.
**여기에 새 문자열을 붙이지 않고, 팩 상자 툴팁이 저 상자를 가리키게도 하지 않는다**
(`writing-user-facing-text.md`: 다른 컨트롤의 이름을 문장 안에 적지 않는다. 그 상자 이름이 바뀌면
문장이 없는 것을 가리킨다).

소유자가 낸 그림에서 **팩 상자를 `미등록 프레임 가져오기` 밑에 들여쓰는 부분만 뺀다.** 그 중첩이
말하는 것은 부모가 꺼지면 자식은 뜻이 없다는 것인데, (다)에서 둘은 서로 독립이다. 팩 상자를 끄는
것은 경로와 무관하게 그 애드온을 안 건드리는 것이고, `미등록 프레임 가져오기`는 아무도 안 건넨
프레임에 대한 것이다.

블리자드 개체창 일곱 위에 부모 체크박스를 두는 안도 안 고른다. 그 부모는 새 저장값이어야 하고
(`turning-an-option-off-keeps-its-value` 때문에 일곱을 지울 수 없으므로), 새 저장값과 새
마이그레이션을 들여서 얻는 것이 한 번에 끄기 하나뿐이다. 묶어 읽히게 하는 일은 **섹션 헤더**가
이미 하고, 그것이 클라이언트 자신이 이 깊이에 쓰는 물건이다. 들여쓰기가 한 단계뿐이라는 제약
(`Blizzard_SettingControls.lua:225`)도 이 안에서는 아예 안 걸린다.

서브카테고리로 가르는 안도 안 고른다. 왼쪽 나무에 한 줄을 더 세워서 상자 열 개를 옮기는 것은, 한
화면에 다 들어가는 것을 두 화면으로 나누는 일이다.

```
Unit Frames                                   (섹션 헤더, UNITFRAME_LABEL)
  Clicking a Unit Frame Casts On              (드롭다운)
Blizzard Unit Frames                          (섹션 헤더)
  Player Frame
  Pet Frame
  Target and Focus
  Party Frames
  Raid Frames
  Boss Frames
  Arena Frames
Unit Frame Addons                             (섹션 헤더)
  Grid2                                       (설치된 팩마다 하나, 그 애드온의 Title)
  EllesmereUI Unit Frames
  VuhDo
  Use Unit Frames Addons Keep to Themselves
```

`미등록 프레임 가져오기` 상자를 마지막 묶음에 두는 것은, 그것이 답하는 물음도 남의 유닛 프레임
애드온에 대한 것이기 때문이다. 설치된 팩이 하나도 없어도 그 헤더와 그 상자는 선다.

### 문구 초안

- **섹션 헤더 `Unit Frames`는 클라이언트의 `UNITFRAME_LABEL`을 그대로 쓴다.** 세 로케일에 이미 다
  들어 있어서 번역할 것이 없고, 게임이 말을 바꾸면 따라간다(`ESCAPE_TO_UNBIND`와 같은 수법). 지금의
  `L["UNITFRAME_OPTIONS"] = "Unit frame options"`는 지운다.
- `Blizzard Unit Frames`와 `Unit Frame Addons` 두 헤더 키는 새로 만든다. 이 이름들은 앞선 작업에서
  한 번 지운 것인데(그 문서 §6-5), 그때는 평평한 한 묶음이라 고아였고 지금은 묶음이 셋이다.
- **타이틀 케이스는 블리자드 식으로.** 주요 낱말만 올리고 관사와 짧은 전치사는 내린다
  (`SHOW_PINGS_ON_RAID_FRAMES = "Show Pings on Raid Frames"`). 그래서 소유자 그림의
  `Clicking A Unit Frame Casts On`은 `Clicking a Unit Frame Casts On`이고,
  `Use Unit Frames Addons Keep To Themselves`는 `Use Unit Frames Addons Keep to Themselves`다.
- 팩 상자의 툴팁은 뜻이 바뀌었으니 같이 바뀐다. 지금은 `REQUIRES_RELOAD` 한 줄뿐이다. 초안:
  "Unticked, Debind leaves this addon's unit frames alone. The addon's own click handling is
  unaffected." 뒤에 `REQUIRES_RELOAD`. 애드온이 프레임을 "건넨다"는 말은 여기 안 들어간다. 그것은
  Clique API를 아는 사람의 어휘고, (다)의 뜻은 건넸는지와 무관하다는 것이라 그 말이 없어야 맞다.
- `TAKE_UNREGISTERED_UNIT_FRAMES_DESC`는 지금 문장이 홀더 경우도 덮으므로 그대로 둔다.

## 8. 코드에서 무엇이 바뀌었나

**§3에서 그린 모양과 다르게 나왔다.** 거기서 (다)를 고른 근거는 그대로다. 달라진 것은 그 뜻을
참으로 만드는 방법이고, 관문을 헤더 문에 한 벌 더 두는 대신 **헤더 문이 등록을 그만두게 했다.**

한 번은 계획대로 해 봤다. 꺼진 팩의 이름 패턴을 제한 환경에 실어 두고 `clickcast_register`가 맨
앞에서 맞춰 보는 것이다. 되기는 됐고 되돌렸다. 팩 스위치 규칙이 두 벌이 되어 누군가 둘을 맞춰야
하고, 우리 설정이 제한 환경으로 건너간다.

**되돌린 근거는 배선이 어디서 끝나느냐다.** 우리 배선은 `SecureHandlerWrapScript`로 `OnClick`을
감싸야 완성되고(`ApplyDebindRouting`), 그건 보호된 프레임에 대한 비보안 호출이라 전투가 막는다.
그러니 헤더 문으로 전투 중에 들어와도 클릭은 `RegisterClickQueue`로 밀렸다. **제한 환경만으로
배선이 끝난 적이 없다.** 그렇다면 그 문이 등록을 붙들고 있을 이유도 없다.

**감내한 것.** `clickcast_register`는 제한 환경 본문이라 전투 중에도 돌고, 전에는 그 자리에서
`clickcast_onenter`를 자식에 달아 호버 슬롯까지 세웠다. 이제는 `RegisterFrame`이 전투 중엔 큐로
가므로 그 프레임이 전투가 끝날 때까지 호버도 안 걸린다. 범위는 좁다. `clickcast_register`는
`initialConfigFunction`에서 **자식이 처음 만들어질 때만** 돌고, 헤더는 이번 세션에 깔아 본 적 없는
크기로 커질 때만 새 자식을 만든다. 잃는 것은 "전투 중에 처음 생긴 슬롯이 그 전투 동안 호버 시전이
안 된다"이고, 우리 프레임은 이미 그렇게 산다.

1. **`clickcast_register`와 `clickcast_unregister`가 두 줄이 됐다.** 버튼 이름을 `CallMethod`로
   내보내는 것이 전부다. 없어진 것은 제한 쪽 `hd`와 `frameType`, `useparent-clickbutton`,
   자식 환경에 심던 `debind_driver`, 그리고 자식에 달던 `clickcast_onenter`/`clickcast_onleave`다.
   `RegisterFrame`이 `InitFrame`과 `Reassemble(OnEnter/OnLeave)`로 같은 자리를 채운다.
2. **`OnClickCastRegister`가 한 틱 뒤에 `RegisterFrame(button, "group")`을 부른다.** 미루는 이유는
   그 콜백이 헤더가 자식을 아직 만들고 있는 한복판에서 불리고, 등록은 `SecureHandlerExecute`로
   제한 환경에 다시 들어가기 때문이다. 그 콜백이 하는 일은 표시를 세우는 것과 이 호출뿐이다.
3. **`hd`와 `hccframes`를 `RegisterFrame`이 소유한다.** `_headerOwned`라는 약한 표를
   `MarkHeaderOwned`가 세우고, `ClaimForHeader`가 행이 서는 자리마다 그 둘을 얹는다.
   **인자도 큐 항목도 안 늘렸다** — 전투 중 큐를 거쳐 드레인될 때도 표시가 프레임에 그대로 남아
   있어야 하는데, `_headerChildren`이 이미 같은 수법을 쓴다.

   **처음에는 이 둘을 `RegisterFrame` 바깥에 뒀고, 그게 결함 셋을 한꺼번에 낳았다** (코드 리뷰,
   2026-09-08). `RegisterFrame`이 일찍 돌아가거나 전투 큐로 미루는 경로에서 둘 다 안 붙었다.
   다른 문이 이미 그룹 프레임으로 등록해 둔 행은 조기 반환에 걸려 헤더의 주장을 못 받고, 전투 중
   등록은 `hccframes`에 안 들어가고, 전투 중 철회는 행이 없다고 돌아가 큐에 취소를 안 쌓아서
   드레인이 헤더가 이미 거둬간 프레임을 배선했다. **행이 서는 자리가 셋이면 표시를 얹는 자리도
   셋이어야 한다**는 것이 배운 것이고, 그래서 `ClaimForHeader` 하나가 그 셋을 다 맡는다.
4. **`RegisterFrame` 관문 위의 "every door comes through here"가 참이 됐다.** 지금까지 틀려 있던
   그 문장이 이 변경의 요지라는 것을 주석에 적었다.
5. **`clickcast_onenter`/`clickcast_onleave`는 드라이버에 남되 몸이 바뀌었다.** 헤더 문이 심던
   `debind_driver`를 읽고 있어서, 그 심기가 없어지면 남이 복사해 간 본문이 nil에서 죽는다. 부모의
   `clickcast_header`를 자기가 찾는 꼴로 바꿨다. Clique의 두 본문이 그 모양이다. 우리 것은 이제
   아무도 안 읽고, `ClickCastHeader`가 갖춰야 할 모양으로 남는다.
6. **`WrappedByUs`의 주석**에서 "헤더 문 프레임은 우리 래퍼가 없다"를 지웠다. 이제 모든 문의
   프레임이 같은 래퍼를 지고, 행과 래퍼가 갈리는 자리는 클릭 쪽 하나다.
7. **`Options.lua`의 유닛 프레임 구역이 §7의 세 묶음으로 다시 섰다.** `미등록 프레임 가져오기`가
   팩 목록 뒤로 갔다.
8. **로케일** — `UNITFRAME_OPTIONS` 삭제(세 파일 다), `BLIZZARD_UNIT_FRAMES`와
   `ADDON_UNIT_FRAMES` 추가, 팩 상자 툴팁 `PACK_FRAMES_DESC` 추가,
   `TAKE_UNREGISTERED_UNIT_FRAMES`와 `UNITFRAME_CLICK_EDGE`와 `BLIZZARD_UNIT_FRAMES_TARGET`을
   타이틀 케이스로. ruRU에는 새 키를 안 넣었다.
9. `tools/snippet-golden.txt`가 움직였다. 스니펫 둘이 줄고 `clickcast_on*` 둘이 바뀐 것뿐이다.
10. `tests/wow_shim.lua`가 `UNITFRAME_LABEL`을 답한다. 클라이언트 문자열을 그대로 쓰는 자리라
    섀도가 그것을 모르면 스펙 전체가 nil을 읽는다.
11. `restricted-environment.md`의 핫패스 목록에서 호버 줄을 고쳤다. 우리 프레임이 실제로
    도는 것은 `setup_onenter_wrap` 쪽이고, `clickcast_onenter`는 남이 복사해 갔을 때의 길이다.

**이름 없는 헤더 자식은 이 문으로 못 온다.** `CallMethod`는 인자를 문자열과 숫자와 boolean으로
깎으므로(`RestrictedFrames.lua`) 프레임 핸들을 못 넘기고, 헤더에 이름이 없으면 자식 이름도 nil이다
(`SecureGroupHeaders.lua`가 `name and (name.."UnitButton"..i)`로 만든다). Clique도 같은 자리에서
같은 답을 낸다. 그런 프레임은 `CollectHeaderChildren`이 프레임 객체로 잡으므로
`미등록 프레임 가져오기`가 켜져 있으면 그대로 배선된다. 안 메웠다.

이 문서 밖의 일로 하나 적어 둔다. **Grid2의 자기 구현 헤더가 그리는 파티 블록의 자기 슬롯은 지금
`FRAMETYPE_PLAYER`로 잡힌다.** `^grid2layoutheader%d+unitbutton%d+` 행에 셋째 칸이 없고,
`IsGroupHeaderChild`는 부모의 `OnEvent`이 블리자드 것일 때만 참인데 Grid2 자기 헤더는 아니라서
`player` 토큰이 그대로 읽힌다. 이름에 `party`도 `raid`도 없으니 `GROUP_NAME_WORDS`도 못 잡는다.
경계 논의와는 별개 건이고 여기서 안 고쳤다.

## 9. 무엇이 무엇을 지키나

- **헤드리스 (`tests/frames_spec.lua`)** — 팩 관문이 비보안 문 셋(테이블, 이름 후크, 홀더)에서
  각각 걸리는 것은 전부터 있던 케이스다. 헤더 문이 `RegisterFrame`을 지나게 되면서 **그 문의
  관문도 헤드리스로 답할 수 있게 됐다.** 새로 셋. 꺼진 팩이 헤더 문으로도 거절되고 다른 팩은 같이
  안 꺼지는 것, 헤더 소유 행을 평범한 해제가 못 가져가고 헤더 자신의 문으로만 나가는 것, 그리고
  전투 중 헤더 등록이 큐를 기다렸다가 드레인에서 `hd` 행으로 서는 것. 마지막 것이 3번의 표시가
  큐를 건너 살아남는지를 묻는다. 3번의 결함 셋을 잡느라 셋이 더 붙었다. 다른 문이 이미 세운 행에
  헤더의 주장이 닿는지, 전투 중 철회가 큐에 쌓인 등록을 취소하는지, 그리고 큐를 거친 등록이
  `hccframes`에 들어가는지.
- **헤드리스 (`tests/options_spec.lua`)** — 유닛 프레임 줄이 머리말 셋을 낀 열두 줄로, 그 차례대로
  서는 것. 그리고 그중 어느 줄도 들여쓰기를 안 지고 있는 것 — 부모 상자를 안 쓰기로 한 결정이
  화면에서 참인지를 묻는 것이 이 두 번째다. 값에 대한 물음(setter가 쓰는 칸, 기본값에서 칸을
  지우는 것, Clique가 이 줄들을 회색으로 만드는 것)은 전부터 있던 것이다.
- **정적** — `check:snippet-golden`이 두 스니펫이 신호 두 줄로 줄어든 것을 바이트로 잠근다.
  `check:snippets`가 그것을 파싱하고, `check:locales`가 지운 키가 세 파일에서 다 빠졌는지를 본다.
- **게임 안에서만 (`/debtest`)** — 신호의 왕복 그 자체. 제한 환경에서 진짜 헤더가
  `clickcast_register`를 돌려 이름이 밖으로 나오고 한 틱 뒤에 행이 서는지, 그 프레임이 클릭
  라우팅까지 받는지를 헤더 인수 케이스가 본다. 호버 래퍼가 실제로 걸리는 것도 여기서만 답한다 —
  그 문의 프레임이 `clickcast_onenter` 대신 우리 래퍼를 지는 것이 이번에 바뀐 자리다. 설정창의 세
  묶음이 실제로 그려지는 것도 클라이언트만 답한다.
- **원리상 어느 쪽도 못 보는 것** — 남의 팩이 다음 판올림에서 등록 경로를 바꾸는 것. 그건
  `KNOWN_PACK_FRAMES`의 이름 패턴이 지고 있는 위험과 같은 것이고, 바뀌면 아무것도 안 맞아서 이
  관문이 조용히 통과시킨다.
