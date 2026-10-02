# BindPad 설정 가져오기 (2026-09-27 조사)

> 상태: **설계안을 썼다** (2026-10-02, §5부터). §9의 물음 가운데 1은 정해졌고 2~5가 남았다. 구현은
> 시작하지 않았다.
>
> 쓴 세션: §1~§4는 `debind-b4`(세션 ID `f364bb3c-2947-41ea-8e2a-09346690d99a`), §5부터는 `debind-57`(세션 ID
> `ed0d0503-e213-4652-a740-c4c5f270a73d`).

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
- **화면의 프로필 탭은 넷이다.** 저장 상한은 5(`BINDPAD_MAXPROFILETAB`)인데 `BindPadProfileTab5`는 템플릿의
  `hidden="true"`를 그대로 받고 아무도 `Show`하지 않는다. 그래서 5번 프로필은 정식 서비스에서 초기 전문화(번호 5)인
  캐릭터가 기록 없이 자기 번호를 쓸 때만 생긴다. 탭을 누르면 지금 전문화의 기록이 그 프로필로 바뀐다
  (`SwitchProfile`). 그래서 어느 전문화도 가리키지 않는 프로필도 남아 있을 수 있다.

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

## 5. 읽는 판 (2026-10-02)

우리가 서는 두 클라이언트에 맞는 BindPad는 둘이고, 저장 모양이 같다.

- **정식 서비스: BindPad 3.1**(CurseForge 3383, 파일 7637420, 12.0.1). 2.1.22와 다른 곳은 `UIPanelWindows`를
  `pcall`로 감싼 것과 함수 하나가 `""`를 돌려주는 것뿐이다. §1~§4가 그대로 맞는다.
- **카멜롯: BindPad Forever 1.0.1**(leehmanQQ의 포크, TOC 16001, CurseForge 1709144). 2.1.22 정식 서비스판을
  카멜롯 API로 옮긴 것이다. 폴더 이름(`BindPad`), `BindPadVars`, 칸과 액션 문자열은 그대로다. 다른 점은
  하나다. **`profileForTalentGroup`의 키가 전문화 번호가 아니라 이중 전문화 그룹(1, 2)이다**
  (`C_SpecializationInfo.GetActiveSpecGroup`). 그룹은 우리 쪽에서 레이어도 조건도 아니다
  (`preparing-the-code-for-camelot.md` 3-3). 그 밖에 캐릭터 키는 `UnitName`의 이름 하나라서, 카멜롯에서
  이름이 같고 성이 다른 두 캐릭터는 BindPad 안에서 한 키를 같이 쓴다. 우리는 있는 그대로 읽는다.

아이콘은 두 판이 다르다(`BindPadIcon`과 `Icon`). Clique처럼 `GetAddOnMetadata("BindPad", "IconTexture")`로 묻는다.

## 6. 설계안: Clique 가져오기와 같은 길

**새로 짜는 것은 변환기와 메뉴 하나다.** 보관함 항목, 미리보기, 추가 팝업(`DebindAddFrame`), `PlanArrival`의
층 선택은 Clique가 이미 깔아 둔 것을 탄다(`importing-clique-profiles.md` §2, §3).

### 6-1. 입구

- [+]의 드롭다운에 **From BindPad**가 From Clique 아래에 선다. BindPad가 로드되어 있지 않거나 `BindPadVars`가
  없으면 꺼진 채 보인다. Clique와 같은 이유로 언제나 보인다.
- 하위 메뉴는 **캐릭터 → 프로필** 두 단이다(소유자, 2026-10-02). 한 단으로 "이름 - 서버 - 프로필 n"을 늘어놓으면
  줄이 캐릭터 수 × 프로필 수가 된다. 캐릭터는 `PROFILE_<서버>_<이름>` 키에서 "이름 - 서버"로 보이고,
  그 아래 프로필 1~5 중 `[n]`이 있는 것만 선다. 툴팁에 그 프로필을 쓰는 전문화(정식 서비스) 또는
  그룹(카멜롯)과 가져올 바인딩 수가 선다.
- **공유 문자열은 없다.** BindPad에는 내보내기가 없다.
- `Debind.toc`의 `OptionalDeps`에는 넣지 않는다. 메뉴를 여는 때는 로그인 뒤라 BindPad의 SavedVariables가
  이미 읽혀 있고, 순서가 필요한 곳이 없다.

### 6-2. Payload 하나는 (캐릭터, 프로필) 하나다

BindPad에서 한 캐릭터가 한 순간에 실제로 쓰는 것이 이 묶음이다. 키를 누르면 서는 것은
`AllKeyBindings`의 `CLICK BindPad` 줄 가운데 **그 이름의 칸이 일반 탭이나 그 프로필의 탭 1~3에 있는 것**뿐이다
(§2의 "버튼 속성은 칸이 있을 때만 걸린다"). 변환기는 정확히 그것만 옮긴다.

- 줄 하나가 액션 하나다. 한 칸에 키가 둘 걸려 있으면 액션도 둘이다. 우리 액션은 키를 하나만 든다.
- 칸이 없는 줄은 버린다. BindPad에서도 아무 일을 안 한다.
- `CLICK BindPad`로 시작하지 않는 줄(게임 바인딩의 사본)은 읽지 않는다. 우리는 게임 키바인딩을 건드리지
  않는다.
- 키는 Clique 변환기의 `TranslateKey`를 같이 쓴다. 둘째 벌을 짜지 않고 `Clique.lua`에서 공용 자리로 옮긴다.
- `payload.class`는 비운다. BindPad는 직업을 저장하지 않는다(§1).
- 이름은 "이름 - 서버 (프로필 n)"이다. 문구는 `writing-user-facing-text.md`대로 따로 다듬는다.

### 6-3. 칸과 액션의 대응

| BindPad 칸 | Debind | 이유 |
|---|---|---|
| `SPELL` | `SPELL`, 값은 `name` | BindPad 버튼이 이름으로 시전한다. 등급이 있는 클라이언트에서는 최고 등급이 나가고, 이름 값의 우리 액션도 같다(`importing-clique-profiles.md` §4). `spellid`는 쓰지 않는다 |
| `ITEM` | 이름 값의 `ITEM` | `*item-`에 이름이 들어간다 |
| `MACRO` | `MACRO`, 값은 `name` | 이름으로 찾는다 |
| `CLICK`(BindPad 매크로) | `MACROTEXT`, 본문은 `macrotext`, 아이콘은 `texture` | 탈것, 전투 애완동물, 장비 구성, 소환수 명령, "매크로로 바꾸기"가 모두 이 모양으로 저장되어 있다 |

**Hover Cast는 켜지 않는다.** BindPad는 키바인딩이지 클릭 캐스팅이 아니다. 조건 없는 평범한 키로 들어간다.

**`checkselfcast`와 `checkfocuscast`(§2)는 옮길 것이 없다. `casting`을 비워 두면 같은 동작이 난다.**
우리 버튼이 그 두 속성을 끄는 것은(`Debind.lua`의 `DefaultClickFrame`) 같은 일을 우리가 직접 하기 때문이다.
자기 시전 키와 주시 대상 시전 키는 설정 탭의 `selfCast`, `focusCast`가 켜고 끄고, 액션마다
`casting.selfCastKey`, `casting.focusCastKey`가 정한다. 값이 없으면 `"cast"`라서(`CastKeyChoiceOf`) 그 키를
누르면 자기 자신이나 주시 대상에게 나간다. BindPad의 SPELL, ITEM 칸이 하던 일과 같다.

### 6-4. 층과 전문화는 추가할 때 정한다

Clique와 같다. 전부 `GENERAL[0]`에 두고 `source = "bindpad"`를 적는다. 추가 팝업이 층(General, 지금 직업,
지금 캐릭터)을 묻는다. 다른 점은 둘이다.

- **"모든 캐릭터" 키**(`GeneralKeyBindings`에 같은 액션으로 있는 줄). BindPad가 계정 공용이라고 저장한 유일한
  정보다. §9-3의 물음이다.
- **전문화.** 정식 서비스에서는 그 프로필을 쓰는 전문화 번호를 `untranslated`에 둔다. 번호 묶음은
  `profileForTalentGroup`에서 그 프로필로 가는 번호, 그리고 기록이 없으면서 프로필 번호와 같은 번호다
  (`GetProfileForSpec`). Clique의 `spec1`~`spec5`처럼 직업이 없는 번호이고, 추가 팝업의 전문화 축(각 전문화
  레이어에 추가, 조건으로 설정, 지우기)이 그대로 받는다. 지금 직업의 전문화를 모두 덮으면 제한이 없는
  것으로 본다는 규칙도 같다. `CliqueSpecMask`가 `untranslated`의 모양을 출처마다 읽도록 넓힌다.
  **카멜롯에서는 아무것도 두지 않는다.** 그룹 번호는 전문화가 아니다. 어느 그룹의 프로필을 가져올지는
  사용자가 메뉴에서 고른 것으로 끝난다.

### 6-5. BindPad 쪽 키는 그대로 남고, 치우는 법을 반드시 알린다

가져와도 BindPad가 걸어 둔 게임 키바인딩(`CLICK BindPadKey:...`)은 지우지 않는다. 그것은 게임 키바인딩이고,
우리는 그것을 건드리지 않는다. 받아들인 뒤에는 우리 것이 오버라이드 바인딩이라(`ClearOverrideBindings(BindingDriver)`가
쓰는 그 자리) 같은 키에서 이긴다. 받아들이기 전에는 도착 표시가 키를 막으므로 BindPad 것이 그대로 나간다.

**남은 줄은 나중에 터진다.**

- 우리 액션을 끄거나 지우면 키가 게임 키바인딩으로 돌아가고, 거기 걸린 BindPad 것이 다시 나간다.
- BindPad를 지워도 줄은 게임의 키바인딩 저장에 그대로 남는다. 우리 액션이 없는 순간 그 키는 아무 일도 안
  하고, BindPad가 걸 때 밀려난 원래 게임 기능도 돌아오지 않는다.
- **BindPad를 지운 뒤에는 치울 길이 사실상 없다**(소유자, 2026-10-02). 키바인딩 창은 `GetBinding`의 명령
  목록을 그리고, `CLICK` 줄은 그 목록에 없는 것으로 보인다(BindPad의 `DoSaveAllKeys`가 그 목록을 돈 뒤 칸들의
  액션을 따로 적는다). 어느 키인지 모르니 남는 것은 단축키 설정 초기화와 WTF 파일 직접 수정 둘이다.

그래서 **치울 수 있는 때는 BindPad가 아직 깔려 있는 동안뿐이고, 그 안에서 칸마다 키를 풀어야 한다.**

**우리가 치우지 않는다**(소유자, 2026-10-02: "우리가 안하는게 맞아. 고장낼 가능성이 있으니 더더욱").
`SetBinding`과 `SaveBindings`는 전투 밖이면 우리도 부를 수 있으니 막힌 것은 아니다. 안 하는 이유는 넷이다.

- 게임 키바인딩은 건드리지 않는다는 원칙이 있다(`CLAUDE.md`의 "What this is").
- BindPad가 켜져 있으면 로그인과 프로필 전환 때 `DoRestoreAllKeys`가 다시 건다. 막으려면 BindPad의
  SavedVariables를 고쳐야 한다.
- 원래 무엇이 있었는지는 어디에도 없다. 키 하나의 기본값을 묻는 API도 없다. 있는 것은 기본 세트 전체를
  불러오는 `LoadBindings(Enum.BindingSet.Default)`뿐이다. 그래서 기본값으로 돌리려면 세트를 통째로 갈아
  끼웠다가 되돌려야 하고, 그때마다 `UPDATE_BINDINGS`가 난다. 저장 안 된 변경이 날아가고, 기본 명령을
  사용자가 다른 키로 옮겨 둔 경우에는 그 배치가 흔들린다.
- 바인딩 세트가 캐릭터별이면 지금 캐릭터 것만 닿는다.

이 결정을 다시 열 수 있는 때는 하나다. 키 하나의 기본값을 읽는 API가 생기고, 사용자가 BindPad를 끈 뒤에만
도는 길이 설 때다. 그래도 원칙의 예외라서 소유자가 정한다.

**정해졌다: 이것을 반드시 알린다**(소유자, 2026-10-02). 알리는 자리는 둘이다.

- **From BindPad 메뉴의 툴팁.** 가져오기 전에 읽힌다.
- **BindPad 출처 payload의 추가 팝업.** 실제로 넣는 순간이고, Clique 출처와 갈리는 문장이 하나 붙는다.

**알릴 내용은 소유자가 정했다**(2026-10-02). BindPad를 지우는 것만으로 BindPad의 설정은 사라지지 않는다.
BindPad는 와우의 단축키 설정에 덮어쓰기 때문에, 풀려면 BindPad 안에서 모든 단축키를 해제하고 와야 한다.
그러지 않으면 애드온을 모두 꺼도 BindPad의 바인딩이 그대로 남는다.

**코드와 저장 파일로 따라가 본 것**(2026-10-02, BindPad 3.1).

- **키는 게임이 저장한다.** 키를 걸 때 `BindKey` → `ManuallySetBinding` → `InnerSetBinding`이 `SetBinding(key,
  "CLICK BindPadKey:...")`를 부르고, `SaveBindings(GetCurrentBindingSet())`로 저장한다. xptr 계정의
  `bindings-cache.wtf`(2026-09-26)에 `bind 1 CLICK BindPadKey:SPELL Regrowth`가 실제로 있다. 이 파일은
  애드온과 상관없이 게임이 읽는다.
- **키를 푸는 길은 칸의 Unbind 하나다**(`BindPadBindFrame_Unbind` → `UnbindSlot`). **칸에서 아이콘을 빼내는
  것으로는 안 풀린다.** `PickupSlot`은 칸을 `table.wipe`할 뿐 `SetBinding`을 부르지 않는다. 그 키는 칸이
  없는 줄을 가리킨 채 남는다.
- **프로필을 바꾸면 그 프로필의 키를 다시 건다**(`SwitchProfile` → `DoRestoreAllKeys`가 `AllKeyBindings`의
  `CLICK BindPad` 줄을 `SetBinding`하고 저장한다). 그래서 한 프로필에서 다 풀어도 다른 프로필로 가면 그
  프로필의 키가 돌아온다. 게임 파일에 남는 것은 BindPad를 마지막으로 끈 순간의 프로필 키다.
- **바인딩 세트가 캐릭터별인 사람은 캐릭터마다 따로다.** 저장 대상이 `GetCurrentBindingSet()`이다.
- "Save All Keys"가 켜져 있으면 `DoRestoreAllKeys`가 그 프로필에 없는 게임 키바인딩까지 푼다. 가져오기와는
  관계없지만, BindPad 사용자의 게임 키바인딩이 이미 프로필마다 바뀌어 있을 수 있다는 뜻이다.

"남는다"가 뜻하는 것은 키가 BindPad 것에 묶여 있다는 것이다. BindPad가 없으면 눌러도 아무 일도 안 하고, 그
키의 원래 게임 기능도 돌아오지 않는다. 문장은 `writing-user-facing-text.md`대로 다듬되, 코드의 말(`CLICK`,
오버라이드)은 쓰지 않는다. 이 애드온이 생긴 이유가 이것이다
(Debounce 시절, 소유자가 BindPad를 쓰다가 만들었다).

## 7. 손볼 곳

- `DebindStorage/BindPad.lua`(새 파일): 순수 변환기. `BindPadVars`, 캐릭터 키, 프로필 번호, `gameType`을 받아
  payload와 액션 수를 낸다. 캐릭터와 프로필 목록을 내는 함수도 같이 든다(`CliqueProfiles`에 해당).
  `DebindStorage.toc`에 싣는다.
- `DebindStorage/Clique.lua`: `TranslateKey`를 공용 자리로 옮긴다.
- `DebindStorage/Import.lua`: `PlanArrival`의 `fromClique`를 "층을 묻는 출처"로 넓히고, `untranslated`를 출처마다
  읽는다.
- `Debind/StorageUI.lua`: 메뉴 항목과 그 툴팁의 알림(§6-5), 행 아이콘과 툴팁의 출처 줄, `OnAddClicked`의 출처
  판정.
- `DebindAddFrame`: BindPad 출처일 때 서는 알림 문장(§6-5).
- `Debind/Locales/*.lua`: 메뉴, 꺼진 이유, 출처 줄, 항목 이름, 알림 문장.

## 8. 검사

- **헤드리스**: `bindpad_spec.lua`. 변환기가 순수 함수이므로 §6-3의 표, 칸 없는 줄, 키 둘, 게임 바인딩 줄,
  `GeneralKeyBindings`, 정식 서비스의 전문화 묶음과 카멜롯의 무시를 한 줄씩 잡는다. 입력의 하나는 §4의 xptr
  실제 파일이다. `PlanArrival`이 `bindpad` 출처를 Clique처럼 다루는지는 `import_spec.lua`에 붙인다.
- **킷**: `BindPadVars`를 실제로 읽는 입구와 메뉴는 헤드리스가 닿지 않는다. BindPad가 로드된 클라이언트에서
  목록이 저장 파일과 맞는지를 `/debtest`에 넣는다.

## 9. 소유자가 정할 것

1. **payload 단위. 정해졌다: (캐릭터, 프로필) 하나다**(소유자, 2026-10-02: "그 프로필을 따로 가져와야
   한다", §6-2). 캐릭터 하나에 프로필 전부를 넣으면 같은 키에 서로 다른 프로필의 액션이 겹치고, 그것을 가를
   축이 정식 서비스에서는 전문화뿐이고 카멜롯에는 없다.
2. **키가 없는 칸.** 버리기를 제안한다. 가져오는 것은 바인딩이고, 키 없는 칸은 BindPad에서도 아무것도
   하지 않는다. 우리 액션은 키 없이도 설 수 있으니, 칸에 모아 둔 것까지 옮기자면 그것도 된다.
3. **"모든 캐릭터" 키.** 둘 중 하나다.
   - (가) 팝업이 고른 층과 상관없이 언제나 General로 간다. BindPad가 저장한 뜻을 그대로 옮긴다.
   - (나) 구분하지 않고 전부 고른 층으로 간다. Clique와 똑같이 단순하다.

   (가)를 제안한다. 층을 가를 정보가 데이터에 있는 유일한 경우라서, 버리면 사용자가 받은 뒤에 손으로
   다시 나눠야 한다.
4. **카멜롯의 그룹.** 그룹은 레이어가 아니라서 두 그룹의 프로필을 둘 다 가져오면 같은 키에 액션이 둘씩
   선다. 막지 않고 미리보기와 받아들이기의 키 충돌 물음에 맡기기를 제안한다.
5. **남은 키를 짚어 주기.** §6-5의 알림에 더해, 가져온 액션의 키 가운데 게임 키바인딩이 아직 `CLICK BindPad`인
   것을 `GetBindingAction`으로 읽어 보여 줄지. 읽기만 하므로 게임 상태는 건드리지 않는다. BindPad를 이미 지운
   사람도 키를 알면 키바인딩 창에서 하나씩 덮어쓸 수 있어 초기화까지 가지 않는다.
