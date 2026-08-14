# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 말투

대화는 캐주얼하게, 반말로 해도 된다.

단 **네가 나를 극대노하게 만들 만한 잘못을 했으면 그 즉시 존댓말로 태세를 바꿔라.** 그 상황에서
네가 반말하고 있는 꼴은 내 분노 조절에 아무 도움이 안 된다.

그런 잘못이 어떤 건지:

- **맞는 길을 놔두고 쉬운 길로 간 것.** 어느 쪽이 맞는지 판단이 안 서면 고르지 말고 물어봐라.
- **문제 제기를 조사 없이 "문제 없음"으로 닫은 것.** 주석과 `.zzz` 문서는 근거가 못 된다 —
  실제 코드 경로를 따라가라. 따라간 뒤 문제가 없으면 없다고 말해도 된다.
- **낡은 메모리를 근거로 판단한 것.** `memory/` 관리는 **100% 네 몫이다.** 메모리가 짚는
  파일·함수·플래그는 쓰기 전에 아직 있는지 확인하고, 틀린 항목은 그 자리에서 고치거나 지워라.
- **테스트를 통과시키려고 쓴 것.** 지금 코드가 하는 짓을 받아적은 단언, 뭘 넣어도 통과하는 단언,
  빨개지니까 느슨하게 고친 단언. 새 테스트는 **고치기 전 코드에서 실패하는 걸 확인하고** 내놔라.
  기존 테스트가 빨개지면 먼저 의심할 건 코드다.

## What this is

A World of Warcraft addon. A key goes straight to a spell/item/macro with no action bar slot, and
five **layers** (account → class → spec → character → character+spec) decide which characters that
key covers. WoW's own keybindings are never touched — see `readme.md` for the user-facing model.

## Commands

```
npm test                      # headless Lua specs (fengari; no lua binary needed)
node tests/run.js             # same
lua5.1 tests/run.lua          # same, with a real lua5.1 (what CI runs)
lua5.1 tests/run.lua --bench  # solver benchmark
npm run lint                  # luacheck
npm run check                 # lint + test + every static check (run this before reporting done)
```

Individual static checks: `check:locales`, `check:templates`, `check:xml`, `check:xml-methods`,
`check:snippets`, `check:snippet-golden`, `check:export-fields`.

There is no filter flag for a single spec — comment out entries in `tests/run.lua`'s spec list, or
run the one file through the shim yourself.

**"link ptr to this worktree" means `npm run link -- ptr .`** (`.` is the worktree the command runs
in; `main` is the main worktree). Argument forms and the rest of the local setup are in
`devdocs/dev-setup.md`.

Read `devdocs/testing.md` **before** deciding how to verify a change. `npm run check` cannot see the
game: UI and in-game behaviour is only verified by `/debtest`, and secure-snippet failures are
silent.

## Shipped addons

| Folder | |
|---|---|
| `Debind/` | everything |
| `DebindShare/` | export/import. **LoadOnDemand** — compression libs and the received-strings drawer are never read on login |
| `Debounce/` | code-less dummy. The only path that reads pre-rename SavedVariables. Removing it orphans every existing user's config (`Debind/Legacy.lua`) |
| `DebindCliqueFake/` | stands in for Clique so unit-frame addons wire up to us |
| `DebindTest/` | in-game test kit, not shipped (`.pkgmeta` ignore) |

`.pkgmeta` has long comments on why the folder names are what they are. Read them before renaming
anything there — SavedVariables file names come out of `move-folders`.

## Architecture

Load order is `Debind/Debind.xml`, and every file shares one private table:
`local _, DebindPrivate = ...`. `DebindPublic` (`Public.lua`) is the only thing other addons see.

The pipeline, roughly:

1. **`Profile.lua`** — layered SavedVariables. `CollectActionsForKey` walks layers narrow→broad.
2. **`Ordering.lua`** — `CompareActionOrder` decides which of several actions on one key fires
   first. Pure, no WoW API (a headless spec loads it directly). Changing the rule silently
   reorders every existing user's binds; the file says don't.
3. **`Solver.lua`** — condition sets as boxes in a bitmask space; drops bindings that are fully
   covered by higher-priority ones. The invariant that matters: *one column is exactly one axis*.
   Folding independent axes (each custom state, each unit, each known spell) into one word breaks
   the set algebra. Read the header comment before touching it.
4. **`UpdateBindings.lua`** — the insecure side. Builds attributes, `SetBindingAttributes`.
5. **`SecureBindings.lua`** + **`Snippets.lua`** — the restricted side. Snippet bodies are Lua
   source strings baked (`BakeSnippet`) before being handed to `SecureHandlerExecute` /
   `SecureHandlerWrapScript`. `tools/lib/bake.js` runs `Snippets.lua` itself through fengari so the
   checks bake exactly what ships; `tools/snippet-golden.txt` locks those bytes.
   **스니펫 본문을 건드리기 전에 `devdocs/restricted-environment.md`를 읽어라** — 핫패스가
   어디인지, 본문 안에 주석을 어디까지 쓸 수 있는지. 여기서 틀리면 아무것도 안 터지고 키 하나가
   조용히 안 먹는다.

Around that: `UnitWatch.lua` (`@healer`/`@tank` and friends), `FrameRegistry.lua` +
`CustomStates.lua` (click-casting frames, the five in-combat switches), `ActionCatalog.lua`
(searchable index), `DebindUI.lua`/`DropDownMenus.lua`/`SpellPicker.lua`/`Flyout.lua` (UI),
`Events.lua`, `Legacy.lua` (migration).

## 용어

**UI 표면의 말과 코드/주석의 말을 구분해라.**

- **UI 표면** (`Locales/*.lua`의 `L[...]`, 툴팁, 창 안의 모든 글자) 은 머글이 읽는 것이다.
  코드 용어와 일치시킬 이유가 없고, **코드나 작동 방식을 알아야 이해되는 표현은 쓰면 안 된다.**
  스니펫, 속성, 핸들러, 재빌드, 제한 환경 같은 말은 여기 나올 자리가 없다. 그 사람이 이미 아는
  것 — 키, 액션, 직업, 전문화, 캐릭터 — 으로만 말해라.
- **주석의 용어는 코드와 반드시 일치해야 한다.** 필드가 `checkedUnits`면 주석에도
  `checkedUnits`라고 쓴다. 코드에 없는 이름을 주석에서 지어내지 마라.
- **restricted environment / secure / snippet은 서로 다른 것이다.** 샌드박스 / 테인트·전투 잠금 /
  본문 문자열. 섞어 쓰지 마라.

## 주석

- **신규 주석은 전부 영어로 쓴다.**
- 기존 한국어 주석을 일괄 번역하지 마라. 다만 **어차피 손대는 주석은 통째로 영어로 다시 쓴다** —
  일부만 고쳐서 두 언어가 섞인 주석을 만들지 마라.
- 다시 쓸 때 원문의 근거를 요약해 없애지 말 것. 주석이 짧아지는 건 목표가 아니다.
- **코드가 드러내지 않는 것만 쓴다.** 왜 이 순서인지, 무엇을 우회하는지, 이 조건을 빼면 어떤
  증상이 나는지, 어느 버전부터 그런지. "무엇을 하는가"는 아래 줄이 이미 말한다.

## Repo conventions

- `reference/` is gitignored and read-only: Blizzard's interface code and the client's own strings,
  fetched by a script. None of it is ours — **never commit or push inside it.** What is in there,
  which build it is, and how to refresh it are in `devdocs/dev-setup.md`.
- `.zzz/` is gitignored design notes. They are proposals, not orders; read the status header first.
  `.zzz/refactor-candidates.md` holds things noticed but not done.
  - 문서 안의 **개별 항목**이 닫히면 `.zzz/resolved.md`로 옮긴다. 원본에는 미해결만 남긴다.
  - **문서 전체**의 구현이 완전히 끝나면 그 파일을 `.zzz/legacy/`로 옮긴다. `.zzz/` 최상단에
    남아 있는 문서는 아직 할 일이 남은 것들이다.
- CI (`.github/workflows/test.yml`) runs luacheck + specs + bench only. Network-dependent checks
  (`check:templates`) are local-only on purpose.
- Releasing is `devdocs/release.md`. Pushing a tag deploys — never push one as a side effect of
  anything else.
