# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 말투

대화는 캐주얼하게, 반말로 해도 된다.

단 **네가 나를 극대노하게 만들 만한 잘못을 했으면 그 즉시 존댓말로 태세를 바꿔라.** 그 상황에서
네가 반말하고 있는 꼴은 내 분노 조절에 아무 도움이 안 된다.

What earns it:

- **Taking the easy road with the right one in plain sight.** If you cannot tell which is which,
  do not pick — ask.
- **Closing something I raised as "no problem" without investigating it.** Comments and `.zzz`
  documents are not evidence; follow the actual code path. Having followed it, saying there is no
  problem is fine.
- **Reasoning from a stale memory.** `memory/` is **entirely yours to keep.** Before acting on what
  one says, check that the file, function or flag it names still exists, and fix or delete the
  entry on the spot when it does not.
- **Writing a test to make it pass.** An assertion transcribing what the code happens to do now,
  one that passes whatever you feed it, one loosened because it went red. A new test is handed over
  only after **you have seen it fail against the unfixed code**. When an existing test goes red,
  the code is the first suspect.

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
   **Read `devdocs/restricted-environment.md` before touching a snippet body** — which paths are
   hot, and how far a comment may go inside one. Getting it wrong raises nothing and leaves one key
   quietly dead.

Around that: `UnitWatch.lua` (`@healer`/`@tank` and friends), `FrameRegistry.lua` +
`CustomStates.lua` (click-casting frames, the five in-combat switches), `ActionCatalog.lua`
(searchable index), `DebindUI.lua`/`DropDownMenus.lua`/`SpellPicker.lua`/`Flyout.lua` (UI),
`Events.lua`, `Legacy.lua` (migration).

## Terminology

**What reaches a user and what stays in the code are two vocabularies. Keep them apart.**

- **The user-facing surface** — `L[...]` in `Locales/*.lua`, tooltips, every word inside the window
  — is read by someone who has never seen the code. It has no reason to match the code's words, and
  **must not use anything that has to be understood through the code or through how it works.**
  Read `devdocs/writing-user-facing-text.md` before adding or rewording a string: a word the client
  already has beats one we invent.
- **A comment must use the code's names.** If the field is `checkedUnits`, the comment says
  `checkedUnits`. Do not invent a name in a comment that the code does not use.
- **restricted environment, secure and snippet are three different things** — the sandbox, the
  taint and combat-lockdown side, and the body string. Do not use one for another.

## Comments

- **Write every new comment in English.**
- Do not bulk-translate the Korean ones. But **a comment you are editing anyway gets rewritten
  whole, in English** — never half-edited into two languages.
- Rewriting it must not summarise away the reasoning it held. A shorter comment is not the goal.
- **Write only what the code does not already show.** Why this order, what it works around, what
  breaks if the condition goes, which version it started with. The line below already says what it
  does.

## Repo conventions

- `reference/` is gitignored and read-only: Blizzard's interface code and the client's own strings,
  fetched by a script. None of it is ours — **never commit or push inside it.** What is in there,
  which build it is, and how to refresh it are in `devdocs/dev-setup.md`.
- `.zzz/` is gitignored design notes. They are proposals, not orders; read the status header first.
  `.zzz/refactor-candidates.md` holds things noticed but not done.
  - When an **individual item** closes, move it to `.zzz/resolved.md`. What stays in the original
    is what is still open.
  - When a **whole document** has been implemented, move the file to `.zzz/legacy/`. Whatever is
    left at the top level of `.zzz/` is what still has work in it.
- CI (`.github/workflows/test.yml`) runs luacheck + specs + bench only. Network-dependent checks
  (`check:templates`) are local-only on purpose.
- Releasing is `devdocs/release.md`. Pushing a tag deploys — never push one as a side effect of
  anything else.
