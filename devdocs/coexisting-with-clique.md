# Clique가 서 있을 때도 유닛 프레임을 잡는다 (2026-09-08 설계)

> 상태: 설계만 섰다. 구현은 하나도 안 했다. 순서도 안 정했다.

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

- **헤드리스** — `CliqueDetected`가 참일 때 각 문이 옵션에 따라 열리고 닫히는지. 지금 스펙들은
  Clique가 없는 판만 세우므로, 그 플래그를 세운 판을 하나 만들어야 한다. 그리고 §3이 말하는 것
  하나가 여기서 답해진다. 프레임을 등록하면 `frameTypes` 조건이 다시 맞는지.
- **게임 안에서만** — 진짜 Clique가 깔린 판. 홀더 기계가 Clique의 프록시에 실제로 붙는지,
  `export_register` 후크가 실제로 불리는지, 두 엔진이 한 프레임에서 다 도는지. **개발자 판에
  Clique를 깔았다 뺐다 해야 하는 일이라 자동으로 돌 수 있는 것이 아니다.**
- **원리상 어느 쪽도 못 보는 것** — Clique가 다음 판올림에서 `export_register`나 프록시 모양을
  바꾸는 것. 둘 다 그쪽 내부 구현이고 우리에게 약속된 적이 없다.

## 7. 안 정한 것

- 순서. 어느 릴리스에 넣을지 정하지 않았다(`0-ROADMAP.md`에 아직 없다).
- 옵션 문구. `양립`은 코드 쪽 말이고 사용자에게 그대로 쓸 말이 아니다.
  `writing-user-facing-text.md`를 보고 다시 지어야 한다.
- 홀더 기계를 `Debind/`로 옮길 때 `DebindCliqueFake`가 어디까지 남는지.
