# `which-action-a-key-runs.md`를 구현하기 (2026-09-16 시작)

> 상태: **아직 아무것도 안 들어갔다.** 단계 0부터다. 각 단계가 한 세션 크기이고, 단계마다 이 헤더를 고친다.
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
- 저장값: `conditions.units.hover` → `conditions.units.unitframe`, `unit = "hover"` → `"unitframe"`,
  `Options.hoverCastMode`의 `"hover"` → `"unitframe"`. `dbver` 하나. 가져오기(`DebindStorage/Import.lua`)는 옛
  이름을 받는다. Export 필드 표.
- 스니펫 본문이 바뀌니 `tools/snippet-golden.txt` 갱신.
- 테스트: 기존 헤드리스 전부가 이름만 바뀐 채 통과. `normalize_spec`에 옛 이름 옮기기 한 줄.

## 2. Unit Frame 조건 축 없애기

스펙 §0, §2, §8. `unitframe`, `mouseover`, `hover`가 보통 유닛이 되고, 역할과 프레임 종류가 유닛 조건 값의 항목이
된다.

- `UnitConditionForBinding`의 값 표에 `role`, `frameTypes`. `BuildUnitStates`가 역할을 `units.unitframe`(과
  `"@"`가 `unitframe`으로 풀릴 때)에서 읽는다. 잴 수 없는 유닛에 실린 역할과 프레임 종류는 참.
- 없어지는 것: 액션 루트(또는 `conditions`)의 `frameTypes`, 바인딩의 `hover` 필드와 `DeriveHoverFields`,
  `CompareActionOrder`의 hover 단계와 `GetDecidingOrderAxis`의 `"HOVER"`(`Ordering.lua` 머리의 "바꾸지 말 것"은
  이 결정으로 뒤집힌다), 이슈 검사의 `"hover"`와 `"frameTypes"` 갈래(`"units"` 갈래가 본다),
  `HoverConditionFromLegacy`.
- `BuildUnitStates`의 마우스 버튼 암묵 [가리키지 않음]은 키의 규칙이라 남는다. 이름만 `unitframe`.
- `dbver`: `units.hover`의 역할과 `conditions.frameTypes` → `units.unitframe`. 스펙 §8의 표 중 조건 줄들. hover
  단계가 빠지므로 키 묶음마다 `seq`를 **옛 비교자**(hover 단계가 든 것) 순서대로 다시 매긴다. 옛 비교자는
  마이그레이션 안에 한 벌 둔다.
- 메뉴: Unit Frame 노드(`BuildHoverMenu`)가 없어지고, 유닛 조건 메뉴가 `unitframe`, `mouseover`, `hover`를
  보통 유닛으로 그린다. 역할과 프레임 종류는 `unitframe`과 Resolved Unit에서만 보이고, 툴팁이 "Unit Frames 모드일
  때만 검사되고 그 밖에서는 무시된다"고 말한다.
- 테스트: `ordering_spec`(hover 단계 없음), `normalize_spec`(옮기기 줄마다 하나), `eval_spec`(역할과 프레임 종류가
  `unitframe` 조건으로), `display_spec`.

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
- 이슈 검사에 `"casting"` 갈래. 넷을 다 끈 액션은 WARNING.
- 프레임 클릭 경로(`SecureBindings.lua`의 클릭캐스팅 갈래)가 조합키 없는 누름과 같은 구간(`noneFrom`부터 끝)을
  돈다. 가리키지 않은 누름에서 3층을 건너뛰는 것은 성능 항목이라 재 보고 넣는다.
- `dbver`: 스펙 §8의 표 중 Casting 줄들. 옮긴 뒤 한 번 알린다.
- 테스트: `hovertwin_spec`(§4의 표 전부, §5의 표 전부), `keymap_spec`(네 층과 원본 순서, `normalCast = false`,
  넷을 다 끈 액션), `normalize_spec`(옮기기), `eval_spec`(누름 종류마다 승자와 유닛), 킷 테스트(가리킨 누름,
  조합키 누름, 개체창 클릭에서 누가 이기고 어디로 나가는지).
- `implementing-focus-and-self-cast.md`에서 뒤집히는 문단을 이 단계에서 고친다: §3-4의 "3층 안은 … 순서
  기록으로", "hover 쌍둥이가 원본의 `unit`으로 나가는 경우는 넷", "Unit Frames 모드의 마우스 버튼에는 … 만들지
  않는다", §3-12 전체, §5의 "hover 층 안을 원래 액션 순서로 두는 안도 버렸다". `legacy/adding-hover-and-mouseover-cast.md`
  §6의 "역할 둘"은 뒤집힌 것으로 남긴다.

## 4. Casting 메뉴

스펙 §6. 액션 메뉴의 Casting 하위 메뉴. Self Cast Key, Focus Cast Key, Hover Cast 각각 하위 메뉴, Normal Cast
체크박스.

- 라벨은 `writing-user-facing-text.md`를 따라 정한다. 스펙의 문구는 제안이다.
- Other Options 맨 위의 체크박스 둘과 옛 Unit Frame 노드의 "Don't use the action on the unit you are pointing at"이
  없어진다.
- 대상을 고른 액션에서 `aim` 줄이 잠기고, 설정 탭에서 끈 조합키의 하위 메뉴가 잠긴다.
- 여러 액션을 골라 한 번에 고치는 길(`editing-many-actions-at-once.md`)이 이 값들에도 선다.
- 킷 테스트는 안 단다. 한 번 보면 끝나는 배선이다.

## 5. 도움말과 문서

스펙 §9. `HELP_ORDERING_BODY`와 `HELP_TARGETING_BODY`를 다시 쓴다. `implementing-focus-and-self-cast.md`의
§3-13(Auto Self Cast 끄는 체크박스)은 이 문서와 별개로 아직 안 들어갔다. 다 들어가면 이 문서와
`implementing-focus-and-self-cast.md`가 `legacy/`로 간다.

## 6. 커버리지

스펙 §10. 헤드리스가 재는 것과 킷이 재는 것은 각 단계의 테스트 줄에 있다. 원리상 못 재는 것은 게임이 놓는
대상(Auto Self Cast)과 개체창 클릭이 개체창에 닿는 길이고, `matching-the-clients-cast-targeting.md` §4가 든다.
