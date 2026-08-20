# 3.2가 내보낸 것 중 아무도 안 읽은 절반 (2026-08-20)

> 상태: **1·2·3·4번을 읽었다(2026-08-20).** 5·6·7번이 남았다.
>
> 이건 릴리스 전 실사가 아니라 **사후**다. 3.2는 나갔고 사용자 손에 있다. 그러니 여기서 나오는
> 것은 "내보내도 되나"가 아니라 "무엇이 나갔나"에 답한다.
>
> 다 읽으면 이 문서는 `legacy/`로 간다. 읽다 나온 결함은 `.zzz/refactor-candidates.md`나
> 자기 문서로 가고, 여기 쌓지 않는다.

## 왜 이런 목록이 생겼나

3.2는 `v3.1.6..HEAD`로 커밋 217개, 파일 112개였다. 릴리스 검토를 **범위를 줄이고 깊이를 지키는**
쪽으로 돌렸고, 그래서 절반이 남았다. 판단 자체는 그대로 유효하다. 얕게 전부 훑었으면 무엇도
확인 못 한 채 전부 봤다고 적었을 것이다.

**다만 한 번 잘못 걸렀다.** 클릭 시점 평가(`CLICK_TIME_EVAL`)가 처음 이 목록에 있었다. 그건
이 릴리스에서 모든 사용자의 모든 키가 지나는 경로라 안 읽고 넘길 자리가 아니었다. 배포 직전에
따라갔고 결과는 `SecureBindings.lua`의 래퍼와 `Solver.lua`의 `IsKeyAlwaysOurs`에 적혀 있다.
**고를 때의 기준은 코드량이 아니라 "이게 틀리면 무엇이 죽나"다.**

## 무엇이 남았나

크기 순이 아니라 **틀렸을 때 비싼 순**으로 다시 세웠다.

1. ~~**`Misc.lua` +803.** `UnitConditionForBinding`, `HoverConditionFromLegacy` 같은 유닛 조건
   접기.~~ **읽었다(2026-08-20).** 마이그레이션 규칙은 정의역 전부에서 맞다(디스크에 잘못
   변환된 데이터는 없다). 나온 것 셋은 43·44·45번으로 `.zzz/refactor-candidates.md`에 갔고,
   `savedvars_spec`은 지웠다. 그 자리는 `migration_spec`이 리터럴 기대값으로 다시 잡는다.
2. ~~**`UpdateBindings.lua` +748.** 비보안 쪽 어트리뷰트 조립.~~ **읽었다(2026-08-20).**
   솔버가 기대는 순서 체인은 성립한다. 다만 그룹 쪽 체인은 이 파일이 아니라
   `Constants.STATE_EVAL_EXPRESSIONS`와 `EVAL_SNIPPET`에 있어서, `Solver.lua` 머리말의
   포인터를 고치고 raid가 먼저인 이유를 그 두 자리에 적었다. `known` 극성이 런타임에서
   뒤집히던 것은 소유자가 조건의 뜻으로 끊어서 닫았다(`0-DECISION-LOG.md`, `.zzz/resolved.md`의
   46번). 클릭캐스팅 전용 키가 폴링을 끌던 것(47번)과 그 원인인 `click`의 세 가지 뜻(48번)도
   같은 날 닫았다. 47번의 인게임 확인은 `/debtest`의 "Click-cast only"가 든다.
3. ~~**`Snippets.lua` +264와 `SecureBindings.lua`의 나머지 스니펫.**~~ **읽었다(2026-08-20).**
   줄 끝 주석은 46개 본문 어디에도 없었고, 이제 `check:snippets`가 그것을 거절한다. 그전에는
   어느 검사도 못 봤다 - 파싱은 되고, 골든은 안 굽는 본문까지 깎아서 찍는다. `StripSnippetComments`가
   끝 개행을 잃던 것(46개 중 28개)과 `BakeSnippet`의 문서 주석이 다른 표 위에 갇혀 있던 것,
   `UpdateMacroTexts`의 죽은 `if (true or ...)`를 고쳤다.
4. ~~**`Solver.lua` +377.** 헤더가 지키라는 축 불변식을 다시 따라가는 일.~~ **읽었다(2026-08-20).**
   상자 대수는 맞다. `region \ O` 조각들이 서로소이고, 깊이별 작업 공간이 겹치지 않고, 예산은
   "못 지우는 쪽"으로만 틀린다. 축 폭은 넷 중 셋만 잡히고 있었다. groups·forms는 2-c가,
   frameTypes는 2-b가 일곱 값을 다 열거하는데 **`bonusbars`는 이 스펙 어디에도 없었고**, 하필
   `Constants` 쪽만 파생값이라(`MAX_BONUSBAR_OFFSET`) 그 상수를 올리면 조용히 갈린다.
   `solver_spec` 2-d가 양방향으로 잡는다.
5. **UI 전체.** `DebindUI.lua` +3273, `DropDownMenus.lua` +1055, 새 파일 `ExportUI`/`ImportUI`/
   `KeyCapture` 약 2600줄. 분량은 여기가 제일 크다. 순위가 아래인 것은 **틀렸을 때 키가 안
   죽기 때문**이다.
6. **`enUS.lua` +828.** 새 문자열을 `writing-user-facing-text.md` 기준으로 훑는 일.
7. `FrameRegistry.lua` +237, `Events.lua`, `ActionCatalog.lua`, `Constants.lua`.

## 읽기 전에 알고 갈 것

- **`npm run check`가 초록인 것은 이 목록에 대해 아무 말도 안 한다.** 어느 층이 무엇을 보는지는
  `testing-a-change.md`에 있다.
- 이 경로들을 실제로 보는 층은 `/debtest` 하나다. 코드를 읽어서 나오는 것은 "이렇게 짜여 있다"
  까지고, "이렇게 동작한다"는 거기서만 나온다.
- 결함을 찾으면 **여기 쌓지 말 것.** 고칠 수 있으면 고치고, 아니면
  `.zzz/refactor-candidates.md`로 보낸다. 이 문서는 읽었는지 여부만 든다.
