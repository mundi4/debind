# Misc.lua와 Profile.lua 쪼개기 (2026-09-24, 인계용)

> 상태: **다 들어갔다** (2026-09-24). `preparing-the-code-for-camelot.md` 7절의 4단계를 모은 문서다.
> 무엇을 왜 쪼개는지의 결정은 그 문서 5절이 들고, 여기는 작업 방법과 들어간 자리를 든다.

## 1. 지킬 것

- **순수한 이동이다.** 동작이 안 바뀐다. 단계마다 `npm run check`가 초록이다.
- **골든.** `Misc.lua`와 `Profile.lua`에는 스니펫이 없어서(`tools/snippet-golden.txt`의 키에 두 파일이
  없다) 스니펫 골든은 안 움직인다. emit 골든(`tests/emit-golden.txt`, `emit-shipped-golden.txt`)도 바이트
  그대로여야 한다. 움직이면 이동이 아니라 동작이 바뀐 것이다.
- **파일 이름은 `Debind/` 안에서 겹치지 않는다.** 이 저장소는 파일을 이름으로 인용한다(`Client/Spells.lua`를
  `Spells.lua`와 겹치게 만들었다가 `Client/SpellBook.lua`로 고쳤다).
- **지금 자리는 근거가 아니다.** "기존 코드가 거기 있으니까"로 나눌 자리를 정하지 않는다. 같은 일을 하는
  것끼리 모은다.

## 2. 작업 환경

- **워크트리 `C:\Users\mundi4\source\repos\debind-camelot`, 브랜치 `camelot`.** `reference/` junction
  셋이 걸려 있고 거기서 `npm run check`가 돈다. 카멜롯 클라이언트(`_classic_beta_`)는 이 워크트리에
  링크되어 있다.
- **커밋은 판단대로 한다.** 이 작업에 한해 소유자가 커밋, amend, squash를 맡겼다(2026-09-24). main에
  합친 커밋은 amend하지 않는다.
- **단계마다 main에 합친다.** main 워크트리(`C:\Users\mundi4\source\repos\debind`)에서 `git status`가
  깨끗한 것을 보고 `git merge --ff-only camelot`. 지금까지 모든 단계를 이렇게 합쳤다.
- **쪼개기는 메인라인이 두 파일을 안 고치는 때에 짧게.** 통째로 옮기는 동안 main에서 같은 파일을
  고치면 충돌이 크다. 시작 전에 main의 최근 커밋과 작업 트리에서 두 파일이 움직이는지 본다.
- **파일은 Edit와 Write로만 고친다.** `sed -i` 같은 셸 치환은 안 쓴다(CLAUDE.md). `git mv`는 써도 된다.
- **`git add`에 이미 옮긴 파일의 옛 경로를 넣으면 add 전체가 실패한다.** 한 번 그래서 커밋에 이름
  변경만 들어갔다.

## 3. 옮길 때 같이 움직이는 것

- **`tests/run.lua`의 `DEBIND_FILES`와 `Debind/Debind.xml`.** 둘을 같이 고친다. `CheckLoadList`가
  `Debind.xml`의 파일이 목록에 없거나, 게임이 싣지 않는 경로가 있거나, 같은 XML에서 온 파일의 순서가
  뒤집히면 스펙이 돌기 전에 멈춘다.
- **로드 순서.** 각 파일은 읽히는 순간 `DebindPrivate.X`를 지역 변수로 잡는다. 새 파일은 그것이 부르는
  것보다 뒤에, 그것을 부르는 것보다 앞에 둔다. 호출 시점에만 `DebindPrivate`를 거쳐 닿는 것은 순서와
  상관없다.
- **경로를 든 도구.**
  - `tools/check-reload-options.js`: `Profile.lua`의 `RELOAD_REQUIRED_OPTIONS`와 `Misc.lua`의
    `ApplyOptions` 본문을 경로로 읽는다. `ApplyOptions`는 맨 위 수준 함수이고 `end`가 0열이어야 한다.
    둘 다 제자리에 두거나 도구를 같이 고친다.
  - `tools/check-dbver.js`: `Migration.lua`만 읽고 `if (dbver <= N)` 단계를 가장 가까운 `function`
    머리로 묶는다.
  - `tools/check-export-fields.js`: `Profile.lua`의 `KEYS_TO_SAVE`를 읽는다. 그 표는 `Profile.lua`에 둔다.
- **인용.** 옮긴 이름을 "`X.lua`의 Y"로 든 인용은 옮긴 파일을 가리키게 고친다. 파일 이름만 든 인용은
  남은 쪽을 가리키면 그대로 둔다. `legacy/`, `0-DIARY.md`, `0-DECISION-LOG.md`는 그때의 자리를 적은
  기록이라 안 고친다.
- **폴더로 옮기는 것은 인용을 안 깬다.** 경로를 든 도구만 고치면 된다. `forEachSnippet`는 하위 폴더까지
  읽는다(1단계에서 고쳤다).

## 4. 들어간 자리 (2026-09-24)

**`Profile.lua`.** 마이그레이션 사다리 셋(`MigrateLayer`, `MigrateSwitches`, `MigrateDB`)과 그 도움
함수, `MigrateOptions`가 `Migration.lua`로 갔다. `Profile.lua` 바로 뒤에 실린다. `ForEachStoredAction`은
스위치 이름 바꾸기와 쓰임 모으기도 쓰므로 `Profile.lua`에 남았다. `Legacy.lua`는 따로 있는 파일(개명 전
SavedVariables)이라 합치지 않았다.

**`Misc.lua`.** 조건은 `Debind/Conditions/`에 모은다(소유자). 앞으로 조건마다 파일이 하나씩 늘 자리이고,
드는 것은 조건의 모델과 판정까지다. 솔버의 컬럼, 메뉴, 툴팁은 제자리에 둔다. 솔버 컬럼까지 조건이 답하게
할지는 따로 논의한다(`.zzz/conditions-own-their-solver-columns.md`, main 워크트리).

| 파일 | 든 것 |
|---|---|
| `Conditions/Units.lua` | 유닛 조건 모델, `ResolvedUnitOf`, `BuildUnitStates`, 역할 측정, `CannotStand` |
| `Conditions/Specs.lua` | 직업과 전문화 카탈로그, 전문화 집합, `DescribeSpecCondition`, `SpecConditionHolds` |
| `Conditions/Known.lua` | `KnownSpellAsked`, `KnownConditionCanHold` |
| `Conditions/Talents.lua` | 옛 `Talents.lua` 통째로 |
| `ActionBindings.lua` | `CastUnitOf`, 액션에서 바인딩으로(`FillBinding`, 시전 선택, 쌍둥이), `MakeOrderRecord`, `IsConditionalBinding`, `IsBareWorldClick`, `ActionUnitFrameIsOn` |
| `Issues.lua` | 키 유효성, 정의 안 된 스위치, 없는 매크로, 이슈 등급과 판정 |
| `MacroText.lua` | 탈것 본문, 매크로 변환, `ParseMacroText`, 본문 속 유닛과 스위치 |
| `Misc.lua`에 남은 것 | 주문 이름과 아이콘, 장비 칸, 플라이아웃, 펫 명령과 `ActionTakesUnit`, 키 표시, 실행 중 도움, `ApplyOptions` |

**`ActionTakesUnit`은 `Misc.lua`에 남았다.** 조건이 아니라 액션이 겨누는 대상에 대한 물음이고, 펫
명령 표를 읽는다. `ActionBindings.lua`, `Issues.lua`, `MacroText.lua`는 파이프라인 파일이라 폴더에 넣지
않고 맨 위에 둔다(`preparing-the-code-for-camelot.md` 5절).

**로드 순서는 `Misc.lua`, `Conditions/`의 셋, `ActionBindings.lua`, `Issues.lua`, `MacroText.lua`다.**
나중 파일이 앞 파일의 이름을 읽는 순간 `DebindPrivate`에서 잡는다. 옛 `Misc.lua` 안의 파일 지역 변수였던
것(`UnitConditionToState`, `RoleMeasuredUnder`, `CannotStand`, `UNIT_SOURCE_ROW`, `UNIT_SOURCE_AT`)은
그래서 `DebindPrivate`에 올라갔다.

## 5. 폴더

`Debind/Menus/`에 액션 메뉴 넷과 `MenuKit.lua`, `Debind/Help/`에 도움말 넷(`HelpPlate`, `HelpTip`,
`HelpText`, `HelpTopics`)과 그 XML 둘이 갔다. 경로를 든 것은 `DebindUI.xml`, TOC, `tests/run.lua`,
`check-menu-ctx`, `build-help`였다. `build-help`는 TOC에서 `HelpTopics.lua`를 파일 이름이 아니라
`Debind/` 아래 경로로 찾는다.
