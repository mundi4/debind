# `which-action-a-key-runs.md`를 구현하기 (2026-09-16 시작)

> 상태: **여섯 단계가 다 들어갔다.** `implementing-focus-and-self-cast.md` §3-13이 들어가면 이 문서와 그
> 문서가 `legacy/`로 간다.
>
> 규칙은 `which-action-a-key-runs.md`가 들고, 여기는 순서와 각 단계가 건드리는 자리만 든다. 둘이 갈리면 스펙이
> 맞다. 결정의 근거 중 문서에 없는 것은 `.zzz/hover-twin-wrong-2026-09-15.md`("그 당시의 근거")와 `0-DIARY.md`의
> 2026-09-15, 2026-09-16 항목에 있다.

## 0. 단계를 이렇게 자른 이유

**이름 바꾸기가 먼저다.** 뒤의 모든 단계가 `hover`와 `unitframe`이 겹치는 자리를 건드린다. 이름을 나중에 바꾸면
방금 쓴 코드와 테스트를 한 번 더 건드리고, 동작을 바꾼 뒤에 이름을 바꾸면 헤드리스가 깨졌을 때 어느 쪽 때문인지
못 가른다. 이름 바꾸기는 동작을 안 바꾸는 커밋이라 헤드리스가 그대로 통과하는 것이 검증이다.

**저장 모양을 바꾸는 단계는 마이그레이션과 한 커밋이다.** 옛 이름을 읽는 코드가 사라지는 커밋에 `dbver`가 같이
없으면 그 사이의 빌드가 사용자 프로필을 못 읽는다.

**메뉴는 맨 뒤다.** 값의 뜻이 코드에서 먼저 서야 메뉴가 그것을 보여 준다. 메뉴 배선에는 킷 테스트를 안 단다.

## 1. 이름 합치기 (동작 없음)

스펙 §0. 유닛 이름과 유닛 조건 키는 `unitframe`, 기능은 `hoverCast`, `hover`는 액션의 모드가 고른 유닛.

- 보안 쪽: `UnitAliasMap["hover"]`, `SetUnit("hover")`, `hoverUnit`, `hoverFrameType`, `RESOLVE_UNIT_SNIPPET`과
  `COMPOSE_MACROTEXT_SNIPPET`의 `"hover"` 비교, `HandoffHoverUnit`, `GetHoveredUnit`이 `unitframe` 쪽으로.
  `States.unitframe`, `DirtyFlags.unitframe`, 상태 이름 `"unitframe"`은 그대로.
- 비보안 쪽: 조건 키 `units.hover`, 바인딩 필드 `hover`, `DeriveHoverFields`, `HoverReactionMask`,
  `HoverConditionFromLegacy`, `hoverConditionIsOn`, `hoverIsOn`, `ActionHoverIsOn`, `BuildHoverMenu`,
  `HoverFrameTypeChecked`, `hoverRole`, `HoverMarkTooltip`, `GetHoveredLine`이 `unitframe` 쪽으로.
- 기능 이름은 남는다: `hoverTwin`, `HoverTwins`, `HoverCastMode`, `RefreshHoverCast`, `hoverCastChoices`.
- 저장값: `conditions.units.hover` → `conditions.units.unitframe`, `unit = "hover"` → `"unitframe"`.
  나가지 않은 `dbver <= 6` 단계에 얹었다 - 안 나간 단계가 나갈 때까지 저장 변경을 다 받는다는 규칙
  그대로라, `DB_VERSION`은 7에 그대로다.
- **매크로 본문도 옮긴다.** 손으로 친 `@hover`와 `/click DebindCustom<n> hover`가 유닛을 **이름으로**
  읽는 자리다. 이름이 `Constants.SPECIAL_UNITS`에서 빠지는 순간 파서가 그 토큰을 못 알아보고 게임에
  글자 그대로 넘기는데, 아무것도 안 터진다. 안 옮기면 3단계에서 같은 철자가 다른 뜻으로 돌아오므로
  깨지는 것보다 나쁘다. 스위치 계산식(`expr`)도 같은 본문이라 스위치 사다리와 페이로드 manifest에
  같은 단계를 세웠다. 단계가 옛 이름을 직접 들고, `ParseMacroText`를 안 탄다 - 그쪽은 이제 그 토큰을
  못 본다.
- `Options.hoverCastMode`의 `"hover"`는 안 옮긴다. 읽는 쪽이 `"mouseover"`가 아니면 `"unitframe"`을
  내므로 옛 값이 그대로 새 기본값으로 읽힌다.
- 가져오기는 손댈 것이 없었다. 페이로드는 `MigrateLayer`를 그대로 타고, `ACTION_FIELDS`와
  `CONDITION_TYPES` 어느 쪽도 유닛 이름을 나열하지 않는다.
- 스니펫 본문이 바뀌니 `tools/snippet-golden.txt` 갱신.
- 테스트: 기존 헤드리스 전부가 이름만 바뀐 채 통과. `normalize_spec`에 옛 이름 옮기기 한 줄.

## 2. Unit Frame 조건 축 없애기

스펙 §0, §2, §8. `unitframe`, `mouseover`, `hover`가 보통 유닛이 되고, 역할과 프레임 종류가 유닛 조건 값의 항목이
된다.

- `UnitConditionForBinding`의 값 표에 `role`, `frameTypes`. `BuildUnitStates`가 역할을 `units.unitframe`(과
  `"@"`가 `unitframe`으로 풀릴 때)에서 읽고, 프레임 종류도 같은 자리에서 `binding.unitFrameTypes`로 접는다.
  잴 수 없는 유닛에 실린 역할과 프레임 종류는 참.
- 없어진 것: 액션 루트(또는 `conditions`)의 `frameTypes`, 바인딩의 `unitframe` 필드와 `DeriveUnitFrameFields`,
  `CompareActionOrder`의 개체창 단계와 `GetDecidingOrderAxis`의 `"UNITFRAME"`, 이슈 검사의 `"hover"`·
  `"reactions"`·`"frameTypes"` 갈래(`"units"` 갈래가 본다), 목록 행의 개체창 마크.
- 파생 필드 대신 `Misc.UnitFrameConditionOf`가 그 조건을 읽는다. 남은 독자는 유닛이 아니라 **키**를 묻는
  자리들이다: 클릭 경로(`isClickCast`/`holdsKey`), 마우스 버튼 유효성, 대상이 빈 액션의 채워넣기.
- `UnitFrameConditionFromLegacy`는 남겼다. `dbver <= 4`가 3.x 이전의 `hover`/`reactions` 쌍을 접는 규칙이고,
  없어진 조건 축과 상관이 없다.
- `BuildUnitStates`의 마우스 버튼 암묵 [가리키지 않음]은 키의 규칙이라 남는다.
- `dbver <= 6`: `conditions.frameTypes`(와 액션 루트의 것) → `units.unitframe.frameTypes`. 개체창 조건이
  없는 액션은 [사용 안 함]인 줄로 들어가 마스크를 기억한다. 개체창 단계가 빠지므로 키 묶음마다 `seq`를
  **옛 비교자** 순서대로 다시 매기고, 그 비교자는 마이그레이션 안에 한 벌 있다.
- 메뉴: Unit Frame 노드가 없어지고 `unitframe`이 유닛 조건 메뉴의 보통 줄이 됐다. 역할과 프레임 종류는
  `unitframe`과 Resolved Unit에서만 보인다. `hover`는 유닛으로서 3단계에서 생기므로 그때 줄이 는다.
  "Don't use the action on the unit you are pointing at"은 Other Options의 조합키 체크박스 둘 옆으로
  옮겼다 - 4단계가 셋을 같이 없앤다.
- 테스트: `ordering_spec`(개체창 단계 없음), `solver_spec`(프레임 종류 무차별 대조가 새 저장 모양으로),
  `normalize_spec`·`hovertwin_spec`·`keymap_spec`(마스크가 조건 안에 산다), `issue_spec`·`role_spec`(갈래가
  `units`로), `display_spec`(옛 철자가 유닛 줄로 그려진다).

## 3. Casting 값과 쌍둥이 규칙

스펙 §3, §4, §5, §6, §8. `action.casting` 표와 규칙 하나.

- `action.casting = { selfCastKey = { mode, aim }, focusCastKey = { mode, aim }, hoverCast = { mode, aim },
  normalCast }`. `CleanUpDB`가 `"skip"` 옆의 `aim`과 빈 표를 지운다. Export 필드 표.
- `TwinUnitFor`를 규칙 하나로: 원본 조건 전부 + [그 액션의 `hover` 있음], 대상은 골랐으면 그 대상 아니면 `hover`.
  특례 전부 제거(`original.unit == "hover"` 분기, `ignoreHoverUnit` 분기, `TYPES_WITH_HOVER_UNIT_OPTION` 분기,
  마우스 버튼 원본에 쌍둥이를 안 만드는 마지막 `if`). 주석의 "`mouseover`로 바꾸면 명판까지 닿는다"는 틀린 이유라
  지운다. 만날 자리가 없는 조건에서 nil을 내는 것만 남는다.
- `HoverCastMode(action)`가 액션의 `casting.hoverCast.mode`와 설정 탭 모드를 합쳐 그 액션의 유닛을 답한다.
  `HoverCastEnabled`와 `Options.hoverCast`는 없어진다. 설정 탭에는 모드만 남고 기본은 `"unitframe"`.
- `SelfCastEnabled(action)`, `FocusCastEnabled(action)`이 설정 탭의 켜고 끄기와 `casting.*.mode`를 합쳐 답한다.
- `GetBindingsForAction`: `aim = "usual"`이면 쌍둥이의 대상을 비운다. `normalCast = false`면 원본을 안 넣고
  `BuildKeyMap`이 4층에서 뺀다. 넷을 다 끈 액션은 빈 목록. `Constants.CAST_KEY_IGNORE`와 `ignoreSelfCastKey`,
  `ignoreFocusCastKey`, `ignoreHoverUnit`은 없어진다.
- `UnrollIntoTiers`: 3층을 쌍둥이 레코드로 따로 정렬하던 것(`MakeOrderRecord`의 `binding` 인자, `HoverTwins`,
  `HoverTwinSortComparison`)을 없애고 원본 순서 그대로 편다. 원본과 같은 쌍둥이가 4층 원본을 덮는 것은 솔버가
  한다.
- 이슈 검사에 `"casting"` 갈래. 넷을 다 끈 액션은 WARNING이고, 바인딩이 없어 키에 안 선다. **키는
  그대로 잡는다.** 이 단계가 `BuildKeyMap`의 `KeysToHold` 기록을 바인딩 있는 액션 안에 넣어서, 키에 그
  액션뿐이면 키가 게임으로 갔다. 2026-09-17에 밖으로 뺐다(스펙 S5 #42, #43, `eval_spec`).
- 프레임 클릭 경로는 손댈 것이 없었다. 클릭캐스팅 갈래가 이미 `noneFrom`부터 끝까지 돌고, hover 쌍둥이가
  `CASTMOD_NONE`이라 그 구간이 3층과 4층이다. 가리키지 않은 누름에서 3층을 건너뛰는 것은 성능 항목이라
  안 넣었다.
- **개체창 조건의 대상 채워넣기를 없앴다.** 대상을 안 고른 원본은 조건이 무엇이든 게임이 놓는 대상으로
  나간다(스펙 §5). 남겨두면 "Cast as usual"이 원본을 `unitframe`으로 채운 액션에서 할 일이 없어지고,
  아무것도 안 가리킨 누름이 없는 유닛에게 나갔다. 옛 액션은 쌍둥이만 있는 액션으로 옮겨져 뜻이 그대로다.
- **쌍둥이로 매크로 변환을 막던 갈래를 없앴다** (`ConditionsSurviveMacroText`). 쌍둥이는 액션이 유닛을
  받든 못 받든 서고 유닛을 받아 가는 것이 이 스펙이다(§3). 주문도 유닛을 쓰는 것과 안 쓰는 것이 있는데
  넘기는 쪽은 언제나 넘기고, 본문이 그 유닛을 읽느냐도 똑같이 그 액션의 몫이다. 읽게 하는 방법이 `@@`이고
  (`implementing-focus-and-self-cast.md` §4), **그것이 없다고 변환을 막을 이유는 없다** (2026-09-16,
  소유자). probe 거절은 남는다 - 주문서로 갈리는 두 주문을 본문 하나가 못 든다.
- Other Options의 체크박스 셋은 그대로 두고 새 값에 이었다(`casting.<줄>.aim`). 4단계가 셋을 없앤다.
  메뉴 키가 두 겹을 가리키게 `ActionMenuModel`의 `Get`/`Set`이 `casting.<줄>.<칸>` 주소를 읽는다.
- **"개체창 위에서 도는 액션"을 조건 말고 Casting으로도 읽는다.** 옛 개체창 조건 액션은 조건이 안 적힌
  채로 옮겨 오는데, 왼/오른쪽 마우스 버튼의 유효성이 그 조건만 보고 있어서 옮긴 날 클릭캐스팅 액션이
  통째로 빨개졌다. 물음 하나에 답하는 자리를 하나로 뒀다: `ActionUnitFrameIsOn`이 조건이 살아 있거나
  Casting이 개체창 전용인 것을 같이 답하고, 유효성·`KeysToHold`·쌍둥이 셋이 그것을 쓴다. 2026-09-17에
  수식키 없는 왼클릭·오른클릭이 늘 개체창 전용이 되면서(스펙 §7) 그 유효성 검사와 ERROR는 없어졌다.
- **개체창 위에서 눌리는 마우스 버튼에는 조합키 쌍둥이를 안 만든다** (2026-09-16, 소유자, 스펙 §7).
  개체창 클릭은 조합키 칸이 늘 [없음]이고 그 액션은 키를 안 잡으므로, self·focus 쌍둥이는 어느 경로로도
  안 읽힌다. 만들어 두면 그 레코드가 키를 잡아 맨 왼쪽 클릭을 세상에서 가져갔다. 키보드 키의 같은
  액션은 그대로 쌍둥이를 갖는다.
- 이슈 검사의 `"casting"` 갈래는 모드가 아니라 `TwinUnitFor`에 묻는다. [없을 때]를 건 유닛은 모드가
  서 있어도 쌍둥이가 없어서, 모드만 물으면 바인딩이 하나도 없는 액션이 아무 말 없이 지나갔다.
- `dbver`: 스펙 §8의 표 중 Casting 줄들. 옮긴 뒤 한 번 알린다 - `db.castingNotice`를 세우고 로그인 줄
  하나가 그 칸을 지우면서 말한다(`ReportCastingMigration`).
- 커버리지. 헤드리스가 드는 것: `hovertwin_spec`이 §4의 표와 §5의 표, 네 값이 바인딩을 넣고 빼는 것,
  `keymap_spec`이 네 층과 각 층 안의 원본 순서와 `normalCast = false`와 넷을 다 끈 액션,
  `migration_spec`이 §8의 Casting 줄들과 알림 한 번, `eval_spec`이 누름 종류마다 어느 바인딩이 이기고
  어느 유닛으로 나가는지. 킷이 드는 것: 실제 프레임 위의 누름에서 쌍둥이와 원본이 갈리는 것, 조합키
  값 둘이 쌍둥이를 빼거나 겨냥을 바꾸는 것. 원리상 못 재는 것은 스펙 §10이 든다.
- 나머지 스펙 파일들은 액션을 Skip this action으로 세운다(`tests/casting.lua`). 값을 안 적은 액션이
  쌍둥이를 받으므로, 안 그러면 순서와 승자를 재는 파일들이 자기 물음 대신 쌍둥이 개수를 읽는다.
- `implementing-focus-and-self-cast.md`에서 뒤집히는 문단을 이 단계에서 고친다: §3-4의 "3층 안은 … 순서
  기록으로", "hover 쌍둥이가 원본의 `unit`으로 나가는 경우는 넷", "Unit Frames 모드의 마우스 버튼에는 … 만들지
  않는다", §3-12 전체, §5의 "hover 층 안을 원래 액션 순서로 두는 안도 버렸다". `legacy/adding-hover-and-mouseover-cast.md`
  §6의 "역할 둘"은 뒤집힌 것으로 남긴다.

## 4. Casting 메뉴

스펙 §6. 액션 메뉴의 Casting 하위 메뉴. Self Cast Key, Focus Cast Key, Hover Cast 각각 하위 메뉴, Normal Cast
체크박스.

- `CreateCastingMenu`(`ActionMenuItems.lua`)가 Target 아래에 선다. Other Options의 체크박스 셋은
  없어졌다.
- 조합키 두 줄은 값 셋을 한 목록으로 낸다. 저장은 `mode`와 `aim` 두 필드인데 누름에서는 셋이 배타라,
  읽고 쓰는 자리를 하나로 뒀다(`CastKeyChoiceOf`, `SetCastKeyChoice`). **`mode = "skip"`을 쓸 때 `aim`을
  같이 지운다.** `CleanUpDB`가 로그아웃에 지우는 값이라, 남겨 두면 오늘과 내일의 메뉴가 다른 답을 낸다.
  Hover Cast의 모드 줄도 같은 이유로 `SetHoverCastMode`를 탄다.
- Normal Cast 체크박스는 킷의 것이 아니다. 켠 것이 **값 없음**이라, 킷의 체크박스(`MenuKit.TOGGLE`)로
  두면 체크할 때마다 기본값을 액션마다 적어 넣는다.
- 라벨: 조합키 둘은 클라이언트의 `AUTO_SELF_CAST_KEY_TEXT`·`FOCUS_CAST_KEY_TEXT`, 가리킨 누름은
  설정 탭과 같은 `POINTED_UNIT_CAST`. 한 물음에 창마다 다른 이름이 서지 않는다.
- 잠그기: 설정 탭에서 끈 조합키는 줄 전체가 `blocked`(하위 메뉴가 아니라 잠긴 단추 하나). 대상을 고른
  액션은 [Cast as usual]이 잠기고 첫 줄이 같은 문장을 주석으로 단다(`CAST_KEY_TARGET_PICKED` 하나가 두
  자리를 든다). Hover Cast가 Skip이면 겨눔 두 줄이 잠긴다.
- 액션 툴팁의 옛 체크박스 줄은 메뉴의 말로 바뀌었다(`POINTED_UNIT_CAST` / `CASTING_AS_USUAL`).
  `IGNORE_HOVER_UNIT`·`IGNORE_SELF_CAST_KEY`·`IGNORE_FOCUS_CAST_KEY`와 `LINE_TOOLTIP_IGNORE_HOVER_UNIT`은
  세 로케일에서 없어졌다.
- 여러 액션을 골라 한 번에 고치는 길(`editing-many-actions-at-once.md`)은 따로 세울 것이 없었다. 읽기는
  전부 `AllActions`/`AnyAction`이고, 갈린 선택의 개수는 `MixedCount`가 붙인다.
- 커버리지. 새 킷 테스트는 안 달았다. 한 번 보면 끝나는 배선이다. 이미 있던 킷 테스트 하나(조합키
  쌍둥이의 겨눔)는 체크박스를 누르던 것을 Casting 줄을 타고 내려가 [Cast as usual]을 누르도록 고쳤고,
  그것이 새 트리에서 값이 실제로 써지는 것을 든다. 메뉴가 쓰는 값이 무엇을 뜻하는지는 3단계의 spec들이
  그대로 든다. 헤드리스가 원리상 못 재는 것은 메뉴 트리(어느 줄이 어디에 서고 언제 잠기는지)이고,
  그것은 클라이언트의 메뉴가 있는 게임 안에만 있다.

## 5. 도움말과 문서

스펙 §9. `HELP_ORDERING_BODY`와 `HELP_TARGETING_BODY`를 다시 썼다.

- 순서 도움말이 **누름 넷을 물음 앞에 세운다.** 어느 액션이 목록에 서는지가 누름으로 갈리고, 중요도와
  조건과 레이어는 그 묶음 안의 순서다. 개체창 단계가 빠져 물음은 셋이 됐고, 손잡이를 짚는 문단에
  Casting이 들어갔다. 조합키 누름은 제 묶음에서 끝나고 가리킨 누름은 아래로 흘러내린다는 것도 여기 있다.
- 대상 도움말은 갈래가 하나 바뀌었다. 옛 "가리킨 개체창의 유닛에 쓴다" 갈래가 **"Unit Frame이나
  Mouseover를 대상으로 고른 경우"**가 됐다. 보통 유닛이라 안 가리키면 누름을 삼키고, 뒤 액션으로
  넘기려면 그 유닛에 [있음] 조건을 건다(스펙 §5). 옛 체크박스를 짚던 문단은 Casting의 [Cast as usual]과
  [Skip this action]으로 바뀌었고, 설정 탭 쪽 문단은 모드 하나만 남은 Hover Cast를 말한다.
- **같이 낡아 있던 문자열 둘을 여기서 고쳤다.** `IMPORTANCE_DESC`가 아직 개체창 단계를 넷 중 첫째로
  들고 있었고(2단계가 지나간 자리다. 세 로케일 전부), `POINTED_UNIT_CAST_DESC`는 "소환수 명령은 빼고
  매크로와 탈것은 안 건드린다"고 말하고 있었다. 쌍둥이는 이제 모든 액션에 선다(스펙 §3).
- ruRU는 번역하지 않았다. 없어진 단계 한 줄을 지우고 번호만 다시 매겼다.
- `@@`는 이 단계 때 없어서 문자열에 안 적었다. 2026-09-16에 들어갔고(`implementing-focus-and-self-cast.md`
  §4), 문자열은 그때도 안 건드렸다.
- 커버리지. `check:locales`는 열쇠와 자리표시자만 본다. **문장이 참말인지는 어느 검사도 못 본다.**
  킷도 못 잰다. 도움말 창에 뜨는 것은 로케일 표의 값 그대로이고, 값이 맞는 말인지는 읽어서 아는 것뿐이다.

`implementing-focus-and-self-cast.md`의 §3-13(Auto Self Cast 끄는 체크박스)은 이 문서와 별개로 아직
안 들어갔다. 다 들어가면 이 문서와 `implementing-focus-and-self-cast.md`가 `legacy/`로 간다.

## 6. Hover Cast의 Skip을 세 줄과 같은 뜻으로

스펙 §6, §7, §8 (2026-09-16 저녁). 3단계가 넣은 Hover Cast의 "Skip"은 쌍둥이만 안 만들었고, 조합키 없는
누름은 3층부터 4층까지 보므로 원본이 가리키는 동안에도 4층에서 나갔다. 같은 라벨이 줄마다 다른 일을 했고,
그 값은 사용자 눈에 Cast as usual과 안 갈렸으며, "가리키는 동안 실행하지 않기"가 이 메뉴에 없었다(다른
세션의 검토). 그 값은 옮기기 때문에 있던 것이라 없앤다.

- 저장 모양: `hoverCast = { mode = nil | "unitframe" | "mouseover", aim = nil | "usual" | "skip" }`,
  조합키 둘은 `{ aim = nil | "usual" | "skip" }`. `mode`에서 `"skip"`이 빠지고 `aim`에 `"skip"`이 든다.
  아직 안 나간 `dbver` 단계 안에서 고친다. 옛 `mode = "skip"`을 읽던 자리(`HoverCastMode`,
  `CastKeyChoiceOf`, `SetCastKeyChoice`, `SetHoverCastMode`, `tests/casting.lua`)가 따라간다.
- `TwinUnitFor`: `aim = "skip"`이면 쌍둥이를 안 만든다. **원본에 [모드의 유닛 없음]을 얹는다.** 조건 표에
  적지 않는다. 조건 표는 `IsConditionalBinding`이 읽어 순서를 정하는데, Skip은 Casting 값이지 사용자가 건
  조건이 아니라 순서를 움직이면 안 된다(옮긴 옛 마우스 버튼 액션이 전부 조건 있는 액션이 되어 옛 순서가
  깨진다). 바인딩의 별도 필드에 두고 `BuildUnitStates`(솔버)와 `MergeKeyUnitConditions`(레코드)만 읽는다.
  마우스 버튼의 암묵 [개체창 없음]이 이미 그렇게 조건 표 밖에서 처리된다. 사용자가 그 유닛에 [있음]이나
  반응을 걸어 만날 자리가 없으면 **원본만 안 세운다**(Normal Cast를 끈 것과 같은 모양). ERROR
  (`CONDITIONS_NEVER`)로 보고하면 액션이 통째로 키에서 빠져 멀쩡한 조합키 쌍둥이까지 죽는다. 넷이 다 없어졌을
  때만 `CASTING_NONE_LEFT`(WARNING)다.
- 마우스 버튼의 암묵 [개체창 없음](`BuildUnitStates`)은 그대로다. Skip이 얹는 것과 같은 조건이라 겹쳐도
  뜻이 안 바뀐다.
- 메뉴: Hover Cast 하위 메뉴가 모드 셋(설정 탭 모드, Unit Frames, Mouseover)과 답 셋(가리킨 유닛에,
  평소대로, Skip this action)이 된다. Skip이 모드 줄에서 답 줄로 옮겨 간다. 대상을 고른 액션은 [Cast as
  usual]이 잠긴다. Skip일 때 잠글 줄은 없다.
- 옮기기(§8): 옛 개체창 조건 액션은 그대로(`mode = "unitframe"`, Normal Cast 끔). 그 밖의 옛 키보드 키
  액션은 `aim = "usual"`, 옛 마우스 버튼 액션은 `{ mode = "unitframe", aim = "skip" }`. 3단계의 옮기기가
  이미 나갔다면 그 값(`mode = "skip"`)을 이 값으로 한 번 더 옮긴다. 안 나갔으면 3단계의 줄을 고친다.
  `CASTING_MIGRATED_MESSAGE`가 "하던 대로 옮겨졌다"로 남는다.
- 툴팁과 도움말: `CASTING_HOVER_SKIP_DESC`와 `CASTING_HOVER_SKIPPED`가 새 뜻으로. 2026-09-16 저녁에 넣은
  임시 문구("가리키는 유닛이 아무 영향도 안 준다. Hover Cast를 켠 액션들이 먼저")는 옛 뜻이라 지운다.
  `HELP_TARGETING_BODY`는 통째로 다시 쓴다. 소유자와 고친 초안이 `.zzz/help-targeting-draft-2026-09-16.md`에
  있다. 첫 문단은 Debind의 규칙만, 게임 설정은 그 뒤 한 줄로, 순서는 Target·쥔 키·가리킨 유닛, Normal Cast도 한
  절, 게임이 그다음에 무엇을 하는지는 안 적는다 (소유자).
- 테스트: **스펙 §S5의 줄 하나가 테스트 하나다.** 41줄을 전부 헤드리스로 세우고, 지금 코드와 갈리는 줄이
  이 단계가 고칠 자리다. 아래는 그 줄들이 들어갈 파일이다.
  `hovertwin_spec`(Skip이 원본에 [없음]을 얹는 것, [있음]과 만나면 원본만 없음, 순서 레코드는 그대로),
  `keymap_spec`, `migration_spec`(키보드와 마우스 버튼이 갈리는 것), `eval_spec`(Skip 액션이 개체창 위에서 안
  나가는 것). `tests/casting.lua`의 `skipHover`가 만들던 "쌍둥이도 조건도 없는 액션"은 이제 없는 모양이라
  그것을 쓰던 스펙 일곱 파일과 emit 골든이 움직인다. **골든은 움직인 줄마다 Skip이 원본에 [없음]을 얹은 것으로
  설명되는지 읽고 넘긴다.** 설명 안 되는 줄이 버그다. 킷: 개체창 위에서 Skip 액션이 안 나가고 다음 액션이
  받는 것.
- 이미 `dbver 7`로 옮겨진 프로필(소유자 클라이언트뿐, 안 나간 단계)의 `mode = "skip"`은 다시 안 옮긴다. 사용자에게
  없을 상태를 읽는 코드는 두지 않는다. `DevSeed.lua`로 다시 쓰거나 메뉴에서 다시 고른다.

## 7. 커버리지

스펙 §10. 헤드리스가 재는 것과 킷이 재는 것은 각 단계의 테스트 줄에 있다. 원리상 못 재는 것은 게임이 놓는
대상(Auto Self Cast)과 개체창 클릭이 개체창에 닿는 길이고, `matching-the-clients-cast-targeting.md` §4가 든다.
