# Misc.lua와 Profile.lua 쪼개기 (2026-09-24, 인계용)

> 상태: **`Profile.lua`의 마이그레이션이 `Migration.lua`로 나갔다** (2026-09-24). `Misc.lua`는 남았고,
> 나눌 자리는 6절에 정했다. `preparing-the-code-for-camelot.md` 7절의 4단계를 모은 문서다. 무엇을 왜
> 쪼개는지의 결정은 그 문서 5절이 들고, 여기는 지금 코드를 잰 값과 작업 방법을 든다. 4단계가 끝나면
> 이 문서는 `legacy/`로 간다.

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
- **인용.** `Misc.lua`나 `Profile.lua`를 이름으로 든 곳이 코드에 168곳, 문서(`devdocs/`, `docs/`,
  `CLAUDE.md`)에 153곳이다(2026-09-24). 옮긴 이름을 "`Misc.lua`의 X"로 든 인용만 고친다. 파일 이름만
  든 인용은 남은 쪽을 가리키면 그대로 둔다.
- **폴더로 옮기는 것은 인용을 안 깬다.** 경로를 든 도구만 고치면 된다. `forEachSnippet`는 하위 폴더까지
  읽는다(1단계에서 고쳤다).

## 4. Misc.lua 지도 (4464줄, 2026-09-24)

맨 위 수준 정의의 줄 번호다. 구역 경계는 이것으로 잡고, 자르기 전에 다시 잰다.

| 줄 | 무엇 |
|---|---|
| 16-275 | 주문 이름과 아이콘, 빈 펫 부르기 칸, 장비 칸, 플라이아웃 아이콘(자기 이벤트 프레임 161), `GetFlyoutNameAndIcon`, `GetFlyoutCastableSlots`, `GetSpellTabNameAndIcon` |
| 277-418 | 펫 명령 표와 매크로, `ActionTakesUnit`, `GetMacroSlotLimits` |
| 420-837 | 유닛 조건 모델: `UnitConditionForBinding`, 옛 조건 변환, `UnitConditionToState`, 그룹 칸, `ResolvedUnitOf`, `CastUnitOf`, `SOURCE_*`, `BuildUnitStates` |
| 839-927 | 역할 측정, `CannotStand` |
| 929-1942 | `do` 블록 하나: 액션에서 바인딩으로. `FillBinding`, `GetBindingInfoForAction`, 옵션 읽기, 시전 선택, 쌍둥이 |
| 1943-2021 | `IsConditionalAction`, `MakeOrderRecord` |
| 2023-2397 | 직업과 전문화 카탈로그, 전문화 집합 마스크, `DescribeSpecCondition`, `SpecIDForIndex`, `SpecConditionHolds` |
| 2399-2782 | 알려진 주문 조건, 키 표시와 유효성, 정의 안 된 스위치, 없는 매크로 |
| 2784-3398 | 이슈 등급과 판정: `ACTION_CHECKS` 2977, `EvaluateIssues` 3168, `GetBindingIssue(s)`, `GetNotRunningReason` |
| 3400-3828 | 탈것 매크로, `CANCEL_FORM_LINE`, `CanConvertToMacroText`, `ConvertToMacroText` |
| 3829-4064 | `do`: `ParseMacroText`, 매크로 문자열 캐시, 유닛 이름 바꾸기 |
| 4065-4253 | `do`: 매크로 문자열 속 스위치 |
| 4254-4464 | 실행 중 도움: 이름, 특수 유닛과 스위치 알림, `GetVersionLabel`, `DisplayMessage`, `ApplyOptions` 4397 |

**구역을 넘나드는 파일 지역 변수** (정의 줄, 쓰는 줄. 주석 속 이름도 섞여 있으니 자를 때 다시 본다):

| 이름 | 정의 | 쓰는 줄 |
|---|---|---|
| `BuildUnitStates` | 709 | 1039 1049 1166 1205 1290 1362 2884 3485 3537 3583 |
| `UnitConditionForBinding` | 455 | 1163 2505 2872 2893 3139 3140 |
| `UnitFrameConditionFromLegacy` | 508 | 1181 2477 3490 |
| `UnitConditionToState` | 569 | 808 936 2904 |
| `RoleMeasuredUnder` | 840 | 2889 2902 |
| `CannotStand` | 878 | 1363 3304 |
| `SOURCE_ROW`, `SOURCE_AT` | 692-693 | 3309-3336 |
| `IntersectStoredUnitConditions` | 3499 | 3583 3816 (481 947 997은 확인할 것) |
| `SWITCH_CLICK_TARGET` | 3441 | 3805 4144 4177 4193 4234 |
| `GetBindingInfoForAction` | 1943 | 그 뒤 전역(2325 2392 2437 2471 3446 3572 3588 3683 3693) |

유닛 조건 모델(420-837)은 바인딩 파생, 이슈 판정, 매크로 변환이 다 쓴다. 쪼개면 그 이름들을
`DebindPrivate`에 올리고 나머지 파일이 읽는 순간 잡게 하거나, 유닛 조건 파일을 그것들보다 앞에 싣는다.

## 5. Profile.lua

**끝났다.** 마이그레이션 사다리 셋(`MigrateLayer`, `MigrateSwitches`, `MigrateDB`)과 그 도움 함수,
`MigrateOptions`가 `Migration.lua`로 갔고, 그 파일은 `Profile.lua` 바로 뒤에 실린다.
`ForEachStoredAction`은 스위치 이름 바꾸기와 쓰임 모으기도 쓰므로 `Profile.lua`에 남았고,
`Migration.lua`가 읽는 순간 `DebindPrivate`에서 잡는다. `InitDB`는 `DebindPrivate.MigrateDB`를 부른다.
`Legacy.lua`는 따로 있는 파일(개명 전 SavedVariables)이라 합치지 않았다.

## 6. Misc.lua를 나눌 자리 (소유자, 2026-09-24)

조건은 `Debind/Conditions/` 폴더에 모은다. 앞으로 조건마다 파일이 하나씩 늘 자리다. 폴더에 드는 것은
조건의 모델과 판정까지이고, 솔버의 컬럼, 메뉴, 툴팁은 지금 자리에 둔다.

| 파일 | 4절 지도의 줄 |
|---|---|
| `Conditions/Units.lua` | 420-927 (유닛 조건, 역할), 277-418의 `ActionTakesUnit` 묶음 |
| `Conditions/Specs.lua` | 2023-2397 (카탈로그, 전문화 집합, `DescribeSpecCondition`, `SpecConditionHolds`) |
| `Conditions/Known.lua` | 2399-2442 (`KnownSpellAsked`, `KnownConditionCanHold`) |
| `Conditions/Talents.lua` | 지금의 `Talents.lua` 통째로 |
| `ActionBindings.lua` | 929-2021 |
| `Issues.lua` | 2443-3398 (키 유효성, 정의 안 된 스위치, 없는 매크로, 이슈 판정) |
| `MacroText.lua` | 3400-4253 |
| `Misc.lua`에 남는 것 | 16-275, 펫 명령, 4254-4464 (`ApplyOptions`) |

맨 위의 새 파일 셋은 파이프라인 파일이라 폴더에 넣지 않는다(`preparing-the-code-for-camelot.md` 5절).
`ActionBindings.lua`가 읽는 순간 `BuildUnitStates` 같은 이름을 잡으므로 `Conditions/`의 파일이
그보다 먼저 실린다.

## 7. 4단계 밖에서 열려 있는 것

- **아틀라스 `common-icon-minus` 대체.** 카멜롯에 없다. 후보 여섯을 프로브의 `minus candidates` 구역이
  재는데, 기록은 `/reload` 두 번 뒤에 파일로 나온다(한 번은 재고, 한 번은 쓴다). 들어오면
  `StorageUI.lua`의 `CHECK_SOME`을 "있으면 `common-icon-minus`, 없으면 잰 후보"로 층에서 고른다.
- **로케일**(`preparing-the-code-for-camelot.md` 6절), **배포 줄**(`shipping-on-the-camelot-client.md`
  9절), **`SpecSpells` 카멜롯 키**(그 문서 6절, 드루이드 말고 다른 직업의 측정이 필요하다).
- **이중 전문화**(계획 3-3)는 캐릭터가 진행해야 잴 수 있다. 기록이 생기기 전에는 보고에서 꺼내지 않는다.
- **전문 기술 주문을 주문 목록에 넣을지**는 정하지 않았다(계획 3-4).

## 8. 프로브 기록 읽기

카멜롯 SavedVariables:
`C:\Games\World of Warcraft\_classic_beta_\WTF\Account\10179303#1\SavedVariables\DebindCamelotProbe.lua`

```
lua5.1 -e 'dofile("DebindCamelotProbe.lua"); for b,r in pairs(DebindCamelotProbeDB.builds) do for k,v in pairs(r) do print(v) end end'
```

캐릭터 기록은 `DebindCamelotProbeDB.characters["<빌드> <이름-서버>"][<레벨>][<구역>]`, 이벤트는
`.events`다. 프로브를 고칠 때는 구역을 더하기만 한다(`shipping-on-the-camelot-client.md` 12절). 새로
알게 된 사실은 그 자리에서 해당 작업 문서에 적는다.
