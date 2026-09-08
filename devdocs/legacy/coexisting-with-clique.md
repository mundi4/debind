# Clique가 서 있을 때도 유닛 프레임을 잡는다 (2026-09-08 설계, 같은 날 구현)

> 상태: 구현까지 끝났다. 아래 §1은 구현 전의 상태를 적은 것이고, §8이 실제로 선 모양이다.

## 0. 어디서 나온 자리인가

유닛 프레임 옵션의 경계를 다시 긋는 자리에서 소유자가 낸 안이다
(`legacy/drawing-the-unit-frame-option-boundary.md`). 그 문서는 Clique가 없는 판을 다뤘고,
여기는 Clique가 있는 판이다. **위 구현과 같이 하지 않는다.** 저것은 결함 하나를 닫는 일이었고
이것은 새 기능이다.

읽어서 낸 것이고 게임 안에서 돌려본 것은 하나도 없다.

## 1. 지금 상태

`CliqueDetected`는 로드 때 한 번 서고(`Debind.lua`) **유닛 프레임을 통째로 내려놓는다.**
후크 열둘이 안 걸리고, `RegisterFrame`, `UnregisterFrame`, `UpdateRegisteredClicks`,
`CollectOUFFrames`, `UpdateBlizzardFrames`가 전부 맨 앞에서 돌아간다. `ccframes`도 `hccframes`도
제한 쪽 `ccframes`도 영영 빈 채로 있다.

**그래서 조용히 죽는 것이 둘 있다.** 화면에는 안 나오고 아무도 안 알려준다.

- `States.unitframe`이 안 채워지므로 `frameTypes`를 든 레코드는 **매치가 통째로 실패한다**
  (`SecureBindings.lua`의 상태 루프와 `EVAL_SNIPPET` 양쪽). 무시되는 게 아니라 거짓이 된다.
- `GetHoveredUnit`이 Clique 헤더의 `danglingButton`에서 **유닛 토큰 하나만** 읽는다.
  `frameType`도 `reaction`도 `role`도 없다. 소비자는 `UnitWatch.lua`의 커스텀 타겟 해석 하나뿐이다.

그리고 **블리자드 개체창 일곱까지 같이 내려놓는다.** 이건 Clique가 요구한 적 없는 양보다.

## 2. 잡는 법 셋, 전부 이미 있는 것

1. **테이블 문.** Clique의 `_G.ClickCastFrames`는 `__newindex`만 있는 프록시고
   `__metatable`로 안 잠겨 있다. `DebindCliqueFake.lua`의 홀더 기계
   (`AttachClickCastFrames`, `Hook`, `HolderAnswer`, `WrapIndex`, `WrapNewIndex`, `AskHolder`,
   `AskHolderAgain`)가 **정확히 이 모양을 위해 쓰였고 이미 돈다.** 자물쇠도
   `pcall(setmetatable, ...)`로 떠본다. 안 도는 이유는 하나, `Public.lua`가 Clique가 있으면 그
   애드온을 아예 안 불러서다.

   → 홀더 기계를 `Debind/`로 옮긴다. 그건 가짜 Clique 노릇과 아무 상관이 없다.
   `DebindCliqueFake`에는 `_G.Clique`와 `_G.ClickCastHeader`를 흉내 내는 부분만 남는다.

2. **헤더 문. 스니펫이 아예 필요 없다.** Clique는 헤더 등록을 자기 헤더의 `export_register`
   속성에 써 놓고 자기가 `OnAttributeChanged`로 받는다(`Clique/Clique.lua`). 우리도 같은 프레임에
   `HookScript`을 걸어 같은 값을 읽으면 된다. 이름으로 오고, 제한 환경을 안 건드린다.
   `Clique.hccframes`도 이름에서 프레임으로 가는 평범한 읽을 수 있는 표다.

3. **문이 아닌 셋.** `TakeNamedFrame`, `CollectHeaderChildren`, `CollectOUFFrames`의 후크를 그냥
   걸면 된다. 각자 `미등록 프레임 가져오기` 뒤에 그대로 선다.

## 3. 켜면 얻는 것

우리가 직접 등록하므로 `Reassemble(OnEnter/OnLeave)`가 붙고 `States.unitframe`이 다시 찬다.
그러면 §1의 조용히 죽던 둘이 살아난다. `frameTypes` 조건이 다시 맞고, `@hover`가 막힌 것으로
표시되지 않는다. Clique 전용 `GetHoveredUnit` 갈래도 필요 없어진다.

두 엔진이 한 프레임에 서는 것은 이미 답이 나와 있다. 맨 위를 잡고 위에 있던 것을 다시 돌려준다
(`FrameRegistry.Reassemble`, `legacy/standing-on-top-of-foreign-wrappers.md`). Clique를 깬 적이
없어야 한다는 조건은 그 기계가 이미 지고 있다.

## 4. 옵션

전역 하나, `REQUIRES_RELOAD`. 켜면 §2의 셋을 다 건다.

**기본값은 꺼짐.** Clique를 쓰는 모든 사람의 판을 안 묻고 바꾸지 않는다.

`CliqueDetected` 하나로 서 있던 스물몇 자리가 갈린다. 어떤 것은 "양립이 꺼져 있다"가 되고, 어떤
것은 아예 없어진다. 화면 쪽(`Options.lua`의 회색, `DropDownMenus.lua`의 잠금,
`ActionDisplay.lua`의 빨간 경고, 로그인 줄)이 전부 그 갈림을 따라간다.

## 5. 꺼져 있을 때 무엇이 남나

**옵션이 끄는 것은 문 하나다.** 애드온이 자기 의사로 Clique에 건넨 프레임. 그건 그 애드온이
Clique를 골라서 걸어 들어간 것이고, 양립을 껐다는 것은 거기 끼어들지 않겠다는 말이다. 문이 아닌
셋도 같이 내려간다. 아무도 안 건넨 프레임을 Clique가 이미 쥐고 있는 판이라 뚫고 들어갈 자리가
아니다.

**블리자드 개체창 일곱은 그 문 밖이다.** 블리자드는 아무 데도 안 건넸다. Clique가 집어간
것이고(`Clique/modules/Blizzard_utils.lua`의 `RegisterBlizzardFrame`) 우리도 집어간다
(`UpdateBlizzardFrames`). 같은 `ClickCastFrames` 테이블을 지나는 것은 Clique의 구현 사정이지 그
프레임이 그 문으로 왔다는 뜻이 아니다. **그러니 양립이 꺼져 있어도 블리자드 프레임은 우리가
잡는다.** `UpdateBlizzardFrames`가 맨 앞에서 돌아가는 것을 걷어낸다.

겹치는 프레임은 사용자가 정한다. Clique도 프레임별 상자를 갖고 있고
(`addon.settings.blizzframes.PlayerFrame` 식) 우리도 갖고 있다(`Options.blizzframes`). 그리고 둘
다 서더라도 맨 위를 잡고 위에 있던 것을 다시 돌려주므로 양쪽이 다 돈다.

이 한 가지만으로도 지금보다 낫다. 오늘은 Clique가 깔려 있으면 블리자드 개체창까지 통째로
내려놓는다.

## 6. 무엇이 무엇을 지킬 수 있나

설계 때 이 절이 세운 것은 §9가 실제로 선 모양으로 답한다. 여기 두면 답이 둘이 된다.

## 7. 안 정한 것 (구현 때 정해진 것)

- 순서. 어느 릴리스에 넣을지는 여전히 안 정했다(`0-ROADMAP.md`에 아직 없다). 배포 전에 붙인다.
- 옵션 문구. `Use Alongside Clique`로 정했다. `양립`도 `호환`도 안 쓴다. 둘 다 무엇이 달라지는지를
  안 말하는 코드 쪽 말이다. 설명문이 무엇을 약속하지 않는지는 `Locales/enUS.lua`의 그 키 위에
  적어 뒀다.
- 홀더 기계를 옮길 때 `DebindCliqueFake`가 어디까지 남는지. **템플릿 때문에 선이 저절로 그어졌다.**
  `ClickCastUnitTemplate`은 가상 템플릿이라 XML로만 서고, Clique가 깔려 있으면 그쪽 XML이 이미 같은
  이름을 세워 놔서 우리 XML이 같이 로드되면 그 자리에서 에러가 난다. 그래서 그 애드온은 지금처럼
  Clique가 있으면 안 열리는 채로 남고, 거기 남는 것은 Clique 이름으로 서는 셋뿐이다. 템플릿,
  `_G.Clique`, `_G.ClickCastHeader`.

## 8. 실제로 선 모양

**옵션.** `db.workAlongsideClique`, `REQUIRES_RELOAD`, 기본값 꺼짐. `InitDB`가 한 번 읽는다.
설정창에는 **Clique가 깔려 있을 때만** 행이 선다. 안 깔렸으면 아무것도 안 답하는 상자라서 회색으로
두는 것이 아니라 아예 없다. 그 절의 다른 행을 전부 회색으로 만드는 술어(`NotClique`)가 이 행 하나만
비껴간다. 회색으로 만들면 읽는 사람이 이유만 보고 답할 자리가 없어진다.

**하나의 술어.** `Profile.StandsAsideForClique()`. `CliqueDetected`를 직접 묻던 자리 전부가 이걸
묻는다. 플래그는 "그 애드온이 깔려 있나"를 말하고, 그 자리들이 묻던 것은 더 좁은 물음이었다.
`CliqueDetected`를 지금도 그대로 묻는 곳은 둘뿐이다. `Public.lua`의 `DebindCliqueFake` 적재
(템플릿 충돌)와 설정 행을 세울지 말지.

**게이트가 `RegisterFrame`에서 문으로 내려갔다.** 예전에는 그 함수 첫 줄이라 게임 안 모든 프레임을
거절하는 것이었다. 지금은 각 문이 각자 묻는다. 테이블 문(`ClickCastTable.AttachClickCastFrames`,
`OnHolderWrap`), 이름 문(`TakeNamedFrame`), 헤더 자식(`CollectHeaderChildren`),
oUF(`CollectOUFFrames`). §5대로 블리자드 개체창은 그 밖이라 `UpdateBlizzardFrames`와
`CompactUnitFrame_SetUpFrame` 후크는 아무것도 안 묻는다.

**후크는 무조건 걸린다.** 옵션은 `InitDB`부터 읽히는데 후크는 파일 스코프에서 걸리므로, 로드 때
가를 수가 없다. 그래서 열둘을 다 걸고 함수 안에서 묻는다. 술어는 `InitDB` 전에 "물러선다"로
답하고, 그게 이 사용자가 옵션 전에 갖고 있던 쪽이다.

**제한 쪽은 `InitDB`에서 갈린다.** `SecureBindings`가 파일 스코프에서 일반 갈래를 써 놓고,
물러서는 판이면 `ApplyStandAsideForClique()`가 덮는다. `Clique.header`가 없으면 그냥 돌아선다.
예전에는 그 자리에서 터졌고, 파일 스코프에서 터지면 애드온이 통째로 죽었다.

**헤더 문.** `ClickCastTable.AttachCliqueHeader()`가 Clique 헤더의 `OnAttributeChanged`에
`HookScript`을 걸고 `export_register` / `export_unregister`를 읽는다. 붙이는 순간 이미
`Clique.hccframes`에 들어 있던 것도 같이 데려온다. 그때까지는 우리가 안 듣고 있던 창이다.

## 9. 무엇이 무엇을 지키고 있나

**헤드리스 (`tests/frames_spec.lua`, "Standing aside for Clique, and not standing aside")** — 여섯.
물러선 판에서 이름 문이 닫히는 것, 나란히 서는 판에서 열리는 것, 등록이 행에 frameType을 채우는 것
(§3이 말하던 것이 여기서 답해진다), 물러서 있어도 블리자드 개체창은 잡는 것, Clique 헤더가 내보낸
프레임이 우리에게 닿는 것, 후크 전에 이미 들어와 있던 것을 데려오는 것. 여섯 다 고치기 전 코드에서
빨간 것을 보고 넘겼다.

**게임 안에서만** — 진짜 Clique가 깔린 판. 홀더 기계가 Clique의 프록시에 실제로 붙는지,
`export_register` 후크가 실제로 불리는지, 두 엔진이 한 프레임에서 다 도는지. 개발자 판에 Clique를
깔았다 뺐다 해야 하는 일이라 자동으로 돌 수 있는 것이 아니다.

**원리상 어느 쪽도 못 보는 것** — Clique가 다음 판올림에서 `export_register`나 프록시 모양을 바꾸는
것. 둘 다 그쪽 내부 구현이고 우리에게 약속된 적이 없다. 바뀌면 이 문은 아무 소리 없이 조용해지고,
그때 남는 것은 옵션이 꺼져 있는 것과 같은 판이다.

**설계가 보장하지 않는 것.** 두 엔진이 한 프레임에 서는 것은 의도이지 보장이 아니다. 서로 계속
뺏는 프레임에서는 `FrameRegistry.StandDown`이 우리를 물러나게 하고 한 번 알린다. 툴팁이 `should
still`이라고 헐겁게 말하는 근거가 이것이다.
