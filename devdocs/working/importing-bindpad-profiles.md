# BindPad 설정 가져오기 (2026-09-27 조사)

> 상태: **조사만 했다** (2026-09-27). 설계와 구현은 아직 시작하지 않았다. 보관함 탭을 먼저 손본 뒤에
> 시작한다(소유자).
>
> 쓴 세션: `debind-b4`, 세션 ID `f364bb3c-2947-41ea-8e2a-09346690d99a`.

보관함 탭에서 Clique 프로필로 payload를 만들듯이(`importing-clique-profiles.md`) BindPad 설정으로도
payload를 만들려는 일이다. 여기에는 BindPad 2.1.22의 코드(`BindPad.lua`)와 xptr 계정의 실제 저장
파일에서 읽은 것만 담는다.

## 1. 저장 모양

전역 `BindPadVars` 하나에 모두 들어 있다. SavedVariables라서 BindPad가 로드되어 있을 때만 읽을 수 있다.
`Debind.toc`의 `OptionalDeps`에는 BindPad가 없다.

**계정 단위로 저장되는 것**

- `BindPadVars[1..numSlot]`: 일반 탭(탭 1)의 칸이다. 모든 캐릭터가 같이 본다.
- `BindPadVars.GeneralKeyBindings`: 키에서 액션 문자열로 가는 표다. 칸의 "모든 캐릭터"
  체크(`isForAllCharacters`)가 켜진 키만 든다. 로그인할 때 이 표가 그 캐릭터의 모든 프로필에 덮어써진다
  (`DoRestoreAllKeys`, `CarryOverKeybinding`).
- `tab`, `numSlot`, `version`, `saveAllKeysFlag`, `showHotkey`: 화면과 옵션 값이다.

**캐릭터 단위로 저장되는 것**: `BindPadVars["PROFILE_<서버>_<이름>"]`

- `[1..5]`: 프로필이다. 프로필마다 다음을 가진다.
  - `AllKeyBindings`: 게임 키바인딩 **전체**의 사본이다(`DoSaveAllKeys`가 `GetBinding`을 모두 돈다).
    BindPad 것은 값이 `CLICK BindPad`로 시작하는 줄뿐이고, 나머지는 게임 기본 바인딩이다.
  - `CharacterSpecificTab1..3`: 캐릭터 전용 탭 2~4의 칸이다.
  - `version`: 252 이상인 프로필만 `CarryOverKeybinding`이 건드린다.
- `profileForTalentGroup[전문화 번호] = 프로필 번호`: 기록이 없는 전문화는 자기 번호와 같은 프로필을
  쓴다(`GetProfileForSpec`). 전문화를 바꿔 본 적이 없는 번호는 기록이 없다.

**직업은 어디에도 저장되지 않는다.** BindPad 코드는 `UnitClass`를 부르지 않는다. 캐릭터는 서버와
이름으로만 구분되고, 전문화 번호는 `GetSpecialization()`의 값 그대로다. 그래서 전문화 번호에는 직업이
없고, 이 점은 Clique의 `spec1`~`spec5`와 같다. 드루이드의 1번 프로필을 마법사가 받으면 비전의 것으로
읽힌다. 번호가 뜻을 갖는 순간은 추가할 때 지금 직업을 알게 될 때뿐이다.

## 2. 칸과 액션 문자열

칸 하나가 액션 하나이고, 키는 칸이 아니라 그 칸의 액션 문자열에 걸린다(`CreateBindPadMacroAction`).

| 칸의 `type` | 액션 문자열 | 버튼이 하는 일(`UpdateMacroText`) | 칸에 있는 값 |
|---|---|---|---|
| `SPELL` | `CLICK BindPadKey:SPELL <이름>` | `*spell-`에 이름 | `name`, `spellid`, `bookType`, `texture` |
| `ITEM` | `CLICK BindPadKey:ITEM <이름>` | `*item-`에 이름 | `name`, `linktext`, `texture` |
| `MACRO` | `CLICK BindPadKey:MACRO <이름>` | `*macro-`에 이름 | `name`, `texture` |
| `CLICK` | `CLICK BindPadMacro:<이름>` | `*macrotext-`에 본문 | `name`, `macrotext`, `texture` |

- `CLICK` 칸은 BindPad 자체 매크로다. 탈것, 전투 애완동물, 장비 구성, 소환수 명령(`BindPadPetAction`),
  그리고 사용자가 SPELL, ITEM, MACRO 칸을 "매크로로 바꾸기"한 것이 모두 여기로 온다
  (`PlaceIntoSlot`, `ConvertToBindPadMacro`). 이름은 일반 탭과 지금 프로필의 탭들 사이에서 대소문자를
  무시하고 겹치지 않게 붙는다(`NewBindPadMacroName`). 다른 프로필끼리는 겹칠 수 있다.
- **버튼 속성은 칸이 있을 때만 걸린다.** `UpdateMacroText`는 일반 탭과 지금 프로필의 탭 1~3을 돌며
  칸마다 속성을 건다(`AllSlotInfoIter`). 그래서 `AllKeyBindings`에 줄이 남아 있어도 그 이름의 칸이
  없으면 키를 눌러도 아무 일도 없다.
- **`BindPadKey`는 `checkselfcast`와 `checkfocuscast`를 켠다**(`InitProfile`). SPELL과 ITEM 칸은 자기
  시전 수정자나 주시 대상 시전 수정자를 누르면 그 대상에게 나간다. 우리 버튼은 둘 다 끈다
  (`Debind.lua`의 `DefaultClickFrame`).
- 키 문자열은 게임 키바인딩의 것 그대로다(`ALT-CTRL-SHIFT-` 순서). `BUTTON3`, `BUTTON4`,
  `MOUSEWHEELUP` 같은 마우스 키도 평범한 키바인딩으로 들어온다.

## 3. 겹쳐 저장되는 것

- `GeneralKeyBindings`의 줄은 그 캐릭터의 모든 프로필 `AllKeyBindings`에도 같은 줄로 들어 있다. 캐릭터마다
  읽으면 계정 공용 키가 캐릭터 수만큼 나온다.
- 일반 탭 칸의 키는 "모든 캐릭터"가 꺼져 있어도, 일반 탭에서 걸었다면 그 캐릭터의 모든 프로필
  `AllKeyBindings`에 들어간다(`ManuallySetBinding`, `CarryOverKeybinding`).
- 여러 전문화가 한 프로필을 같이 쓸 수 있다. 전문화 수는 저장되지 않으므로, 어떤 줄이 그 캐릭터의
  모든 전문화에 걸린 것인지는 데이터만으로 가를 수 없다.

## 4. xptr의 실제 데이터 (2026-09-27)

`WTF\Account\10179303#4\SavedVariables\BindPad.lua`의 내용이다. 캐릭터는 `PROFILE_Fyrakk_Adelia` 하나
(드루이드)이고, 프로필은 1~4다. `profileForTalentGroup`에는 `[4] = 4` 하나만 있다. 일반 탭에는 SPELL
칸 둘(30번 Regrowth 8936, 31번 Rejuvenation 774)이 있고, 캐릭터 전용 탭은 비어 있다.
`GeneralKeyBindings`도 비어 있다. BindPad 줄은 프로필 1~3의 `1 = CLICK BindPadKey:SPELL Regrowth`
하나씩이다. 프로필 4의 `1`에는 게임 기본 바인딩이 들어 있다. Rejuvenation 칸은 키가 없다.
