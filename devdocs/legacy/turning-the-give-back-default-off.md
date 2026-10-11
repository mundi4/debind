# When no action runs의 기본값을 끔으로 (2026-10-11 계획)

> 상태: 다 했다(2026-10-11). G5(도움말)는 `fc5c138`, G1~G4는 `045ab49`이고, G6은 이 문서를 legacy로 옮긴 커밋에
> 함께 들어갔다.
>
> 쓴 세션: `debind-04` (세션 ID `c195d036-99e0-4d57-8c7f-d9e7b8854a90`).

## 0. 정한 것

**`giveBackWhenNoActionRuns`의 기본값을 끔(Press Does Nothing)으로 바꾼다** (소유자, 2026-10-11). 2026-10-07에
켬으로 들어갔고(`giving-keys-back-when-no-action-runs.md` 1절), v4.1.2에는 없던 옵션이라 아직 나간 적이 없다.

까닭은 넷이다. 그날 논의는 일기 2026-10-11 절에 있다.

- 옵션을 모르는 사용자에게는 아무 일도 안 일어나는 쪽이 낫다. 켬이 틀리면 다른 것(액션바 칸, WoW 기본 단축키)이 나가고,
  그 원인은 Debind 창 밖에 있다.
- 켬에서 키를 놓을지는 누를 때가 아니라 beat가 정한다. 주기 기본이 0.2로 남아(2026-10-10), 이벤트로 못 듣는 상태
  변경 뒤에는 그만큼 판정이 낡는다. 끔은 키를 쥐고 누를 때 판정하므로 이 창이 없다.
- 누르고 떼는 함정(이동이 안 멈춤, 핑 휠이 안 닫힘)은 고치지 않았다. 기본이 켬이면 모든 사용자가 그 함정을 진다.
- 4.0부터 4.1.2까지는 키를 쥐었다. 그동안 가려져 있던 WoW 기본 단축키가 켬에서는 다시 나간다. 끔은 4.x의 동작
  그대로다.

**기존 사용자도 마이그레이션 없이 끔을 받는다.** 4.x에서 키가 하던 일과 같아서 바뀌는 키가 없다.

**What's New는 이미 끔을 기준으로 고쳐졌다** (`72a428a`, 다른 세션). 이 문서의 범위가 아니다.

## 1. 확인한 것

- 읽는 곳은 `ActionBindings.lua`의 `GiveBackWhenNoActionRuns` 하나다. 부르는 곳은 `UpdateBindings.lua`의 리빌드와
  `SettingsTab.lua`의 드롭다운이다. 키트가 격리하는 동안 이 함수를 바꿔 끼운다.
- 지금 저장은 켬이 `nil`, 끔이 `false`다(`SettingsTab.lua`의 드롭다운). `ResetToDefaults`는 `nil`을 쓴다.
- v4.1.2 태그 전체에 `giveBackWhenNoActionRuns`가 없다(`git grep`). 실사용자에게 저장된 값이 없다.
- `CHANGELOG_VERSION`은 v4.1.2와 `25b210e` 둘 다 2다.
- UI 문자열(`Locales/enUS.lua`)과 코드 주석 가운데 이 기본값에 기대는 것은 `ActionBindings.lua`의 함수 주석 하나다.
  `DebindUI.lua`, `Issues.lua`, `Locales/enUS.lua`의 주석은 "켜져 있으면"으로 적혀 있어 그대로 맞다.
- 다른 로케일과 README에는 이 옵션을 다루는 글이 없다.

**기본값만 뒤집어 돌린 결과** (`25b210e`에서, 다른 세션이 커밋하지 않은 변경은 빠진 트리).

- `--all`에서 18개, `--all --shipped`에서 10개가 실패한다.
- emit 골든을 새로 쓰면 두 파일에서 약 2,900줄이 빠진다. `t.tail="giveback"`과 `JudgeStaged`, 곧 판정 루프 전체다.

**2절 G1의 고정을 넣고 돌린 결과** (같은 트리).

- 옛 코드에서 2286개(`--all`)와 1919개(`--all --shipped`) 모두 통과한다. 골든은 안 움직인다.
- 기본값을 뒤집은 코드에서도 같다.
- `--bench-beat` 출력은 고정 전 HEAD와 고정 뒤 뒤집은 코드에서 셈 값이 같고, 시간 값만 다르다.

## 2. 고칠 것

### G1. 테스트를 켬으로 고정한다 (코드보다 먼저)

옵션을 비워 둔 채 켬을 기대하던 호출에 `{ giveBackWhenNoActionRuns = true }`를 넘긴다. 같은 파일에 `HOLD_UNMATCHED`가
있으면 그 옆에 `GIVE_BACK_UNMATCHED`를 둔다.

뒤집으면 빨개지는 것.

- `specspells_spec.lua` "a known with no spell is left out of the build"
- `talents_spec.lua` "the key goes where a false condition sends it"
- `keymap_spec.lua` "an action that cannot fire answers its key as one that never runs"
- `plan_spec.lua` "a measured condition on a key the loop does not judge asks for no event"
- `eval_spec.lua` S5 #42
- `judgment_spec.lua` "a key ours in every state keeps no item, and holds at every point" (`--all`에서만 돈다)
- `judgmentloop_spec.lua` N1, N4, N5, N6
- `loopoff_spec.lua` "a key with a gap stays ours…", "a key whose one action the specialization condition leaves out",
  "a hover action on a mouse button beside a left-out action", "a key whose one action has no way to fire",
  "a key whose only binding the builder refuses"
- emit: `emit_fixture.lua`의 `M.profile()`에 옵션을 넣는다. 골든을 새로 쓰지 않는다.

**뒤집어도 통과하지만 켬을 보던 것.** 끔에서는 키를 늘 쥐므로 아무것도 안 보고 통과한다.

- `judgmentloop_spec.lua` N3
- `plan_spec.lua` "a key whose conditional actions cover every state asks for no loop". `judges = false`인 줄들이
  끔에서 그냥 맞는다.
- `loopoff_spec.lua` "a left-out frame action alone leaves its mouse button unhandled", "a frame action alone whose
  binding the builder refuses". 메시지가 "with the option on"이라고 적은 쪽 호출이다.

**`beatbench.lua`의 `bind`는 `options`가 없으면 켬을 넘긴다.** 그러지 않으면 벤치가 소리 없이 끔을 잰다. 끔을 재는 두
줄은 이미 `false`를 넘긴다.

**고정하지 않는 것.** `loopoff_spec.lua` "a hover action alone leaves its mouse button to the frame"는 켬과 끔을
견주지 않는다. 개체창 위에서만 도는 액션뿐인 마우스 버튼은 옵션과 상관없이 키를 안 잡는다
(`which-action-a-key-runs.md`의 "막지는 않는다" 문단).

### G2. 기본값을 뒤집는다

- `GiveBackWhenNoActionRuns`는 저장값이 `true`일 때만 켬이다.
- 그 위 주석("On with the value absent"와 그 이유)은 0절의 까닭으로 다시 쓴다.
- 드롭다운은 켬이면 `true`, 끔이면 `nil`을 쓴다. `ResetToDefaults`의 `nil`은 그대로 맞다. 개발 프로필에 남은 `false`도
  끔으로 읽힌다.
- `Export.lua`의 `OPTION_FIELDS`는 그대로다.
- 개발 클라이언트 프로필도 값이 `nil`이면 끔으로 바뀐다.

### G3. 키트

격리는 **켬 고정을 그대로 둔다.** 기본값을 바꿔도 키트가 보는 값은 안 바뀐다. 끔으로 옮기려면 켬을 전제로 짠
사례를 하나씩 다시 봐야 하는데, 그렇게 해서 얻는 것이 없다. 끔 경로는 `HoldUnmatchedKeys`를 부르는 5개 사례와
헤드리스 `loopoff_spec.lua`가 본다.

"기본값"이라고 적은 곳은 "키트가 고정한 켬"으로 고친다.

- `SetIsolated`의 "The default, whatever the tester runs with"
- 6675의 "With `giveBackWhenNoActionRuns` on, the default"
- 6754의 주석과 6757의 실패 메시지("held by default")

### G4. 테스트 주석

"on, the default"라고 적은 곳을 고친다.

- `judgmentloop_spec.lua` 397
- `loopoff_spec.lua` 2
- `specspells_spec.lua` 228

### G5. 도움말

`debind-ae`가 했다(`fc5c138`, 소유자 지시, 2026-10-11). `help-pages` 스킬을 따르고, 끝에 `npm run help`를
돌린다.

- `keys-given-back.md`
  - 1번 항목: "starts on *Key is given back*"을 *Press does nothing*으로 바꾼다.
  - 반대 방향 문단을 새로 둔다. 다른 키는 아무 일도 안 하게 두고 한 키만 돌려주려면, 그 키에 조건 없는
    *Give Key Back*을 *Very Low*로 둔다. 끔에서 Give Key Back이 키를 돌려주는 것은 `loopoff_spec.lua`
    "an unused action stands where it is…"가 지킨다.
  - 끝의 *Nothing* 문단("while your other keys are given back")은 켬을 고른 사람을 위한 것으로 남긴다.
  - 함정 문단 주석의 "the default give-back shows none"을 고친다.
- `ordering.md`
  - 21: "the key is given back by default, or the press does nothing"을 고친다.
  - 55의 주석은 액션바 칸 문단을 뺀 근거가 "기본으로 게임에 돌아간다"였다. 그 근거를 `keys-given-back.md`로 바꾼다.
    그 페이지가 설정과 키 하나짜리 Give Key Back을 둘 다 주므로 문단은 되살리지 않는다.
- `cast-options.md`: 61(*Self Cast Key*)과 63(*Hover Cast*)의 "the key is given back by default", 24 주석의 "the
  default it is on the next row"를 고친다. 61은 처음 계획에서 빠졌고 `debind-ae`가 찾았다.
- `targeting.md`: 22 주석의 "holds under the give-back default"를 고친다.

### G6. 문서

- `which-action-a-key-runs.md`
  - 116: "(기본)"을 끔 쪽으로 옮긴다.
  - S5 #42(191): 켬과 끔을 바꿔 적는다. eval #42가 G1에서 켬으로 고정된다.
  - 475–476, 481: "(기본)", "(기본 켬)"을 뺀다.
- `giving-keys-back-when-no-action-runs.md`(legacy) 1절의 "기본 켬"과 "기본값을 켬으로 둔 까닭" 밑에, 2026-10-11에
  끔으로 바뀌었다는 것과 이 문서 이름을 적는다.
- `handing-the-rest-of-a-key-to-the-game.md`(legacy) 30, 78, 492의 "(기본)", "(기본 켬)"을 뺀다.

### G7. 마무리

`npm run test:all`과 `npm run check`. G1과 G4가 같은 파일에 섞여 있어 G1~G4는 한 커밋으로 넣었다.

## 3. 거친 안

- **emit 골든을 새로 쓴다.** 판정 루프 전체가 골든에서 빠진다. 끔 경로는 `loopoff_spec.lua`가 따로 본다.
- **하네스가 옵션이 없으면 켬을 넘긴다.** 스펙의 `Bind(actions)`가 출하 기본값과 반대 뜻이 된다. 다음에 스펙을 쓰는
  사람이 그것을 모르고 짠다. 벤치는 측정 도구라 예외로 둔다(G1).
- **키트 격리를 끔으로 옮긴다.** G3.
- **Key Is Given Back 툴팁에 누르고 떼는 함정을 넣는다.** 켬을 고르는 화면 바로 옆에 도움말 링크가 있고
  (`b981620`), 함정은 그 페이지에 있다.
- **마이그레이션.** 저장된 값이 없다(1절).

## 4. 이 계획이 못 본 것

- 다른 세션이 커밋하지 않은 테스트 변경(`tests/run.lua`, `tests/hover_spec.lua`, `tests/customtarget_spec.lua` 등)은
  1절의 실행에 들어 있지 않다. 그 변경이 커밋된 뒤 G1을 하기 전에 기본값만 뒤집어 다시 돌려, 실패 목록이 같은지 본다.
