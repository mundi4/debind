# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What not to do

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
key covers. WoW's own keybindings are never touched — see `README.md` for the user-facing model.

## Commands

```
npm test                      # headless Lua specs, twice: the working tree, then --shipped
lua5.1 tests/run.lua          # one of those passes on its own (CI runs both)
lua5.1 tests/run.lua --bench  # solver benchmark
npm run lint                  # luacheck
npm run check                 # lint + test + every static check (run this before reporting done)
```

**`lua5.1` has to be on PATH** (`devdocs/dev-setup.md`). The specs refuse a newer interpreter, and
the checks that bake a snippet body run `Snippets.lua` under the same 5.1 the game does.

Individual static checks: `check:locales`, `check:templates`, `check:xml`, `check:xml-methods`,
`check:xml-anchors`, `check:snippets`, `check:snippet-golden`, `check:state-eval`,
`check:export-fields`.

There is no filter flag for a single spec — comment out entries in `tests/run.lua`'s spec list, or
run the one file through the shim yourself.

**"link ptr to this worktree" means `npm run link -- ptr .`** (`.` is the worktree the command runs
in; `main` is the main worktree). Argument forms and the rest of the local setup are in
`devdocs/dev-setup.md`.

Read `devdocs/testing-a-change.md` **before** deciding how to verify a change. `npm run check`
cannot see the game: UI and in-game behaviour is only verified by `/debtest`, and secure-snippet
failures are silent.

**`/debtest` reaches most of what the game does, so do not hand me a test it could run.** Code
that can regress gets registered there. A procedure written out in chat is carried out once and
is gone by the next change; a test in the kit is there for every one after it.

**Registering the test is the whole of your job.** There is exactly one moment to mention
`/debtest`: **once, in conversation, when the implementation is finished** and the kit is the next
thing that would run. Say it there and let it go.

**Never leave it anywhere.** Not in a document, not in a status header, not as an open item or a
blocker or a remaining task, not in a commit message, not in a new "check this on screen" list.
The commit message is an instance of **Commit messages** below rather than a rule of its own.

**Do not follow up and do not ask.** I run it myself, and **silence means it passed.** Copying the
state out of a document you just read is the same violation as writing it yourself, and so is
asking whether something looks right on screen. If there is a problem I will raise it first.

**The pull here is self-insurance, not diligence.** Writing "not verified in game" protects you
from a later "you said it was fine"; it does nothing for me, and it converts what you cannot do
into a task for me. State what your verification covered and stop there.

**Coverage is a different thing and does belong in the document**: which cases the kit holds, and
what it cannot reach in principle and why. That is a description of the tests, not a list of things
for a person to do, and it does not go stale the moment somebody runs them.

## Shipped addons

| Folder | |
|---|---|
| `Debind/` | everything, **including all UI** — the export/import panels live here too |
| `DebindStorage/` | what sharing keeps: the strings, and the batches received ones wait in. No UI, no locale strings. **LoadOnDemand** — compression libs and those batches are never read on login. Debind reaches it as `DebindPrivate.Store` |
| `Debounce/` | code-less dummy. The only path that reads pre-rename SavedVariables. Removing it orphans every existing user's config (`Debind/Legacy.lua`) |
| `DebindCliqueFake/` | stands in for Clique so unit-frame addons wire up to us |
| `DebindDev/` | everything development only, not shipped (`.pkgmeta` ignore): the in-game test kit, the written dev profile (`DevSeed.lua`), one-shot probes. **Loads ahead of Debind**, because `Debind.toc` names it in `OptionalDeps` and it declares no dependency of its own |

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
   `SecureHandlerWrapScript`. `tools/lib/bake.js` runs `Snippets.lua` itself under lua5.1 so the
   checks bake exactly what ships; `tools/snippet-golden.txt` locks those bytes.
   **Read `devdocs/restricted-environment.md` before touching a snippet body** — which paths are
   hot, and how far a comment may go inside one. Getting it wrong raises nothing and leaves one key
   quietly dead.

Around that: `UnitWatch.lua` (`@healer`/`@tank` and friends), `FrameRegistry.lua` +
`Switches.lua` (click-casting frames, the five in-combat switches), `ActionCatalog.lua`
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

**First rule, above every other one here: a comment carries only what the code cannot show.**

- **What the code already states gets no comment.** If the line below says it, the comment is
  deleted, not shortened.
- **Write one only to keep the reason for the implementation alive**: a workaround and the client
  bug behind it, a hack and what forces it, why this order and not the obvious one, what breaks if
  the condition goes, which version it started with.
- Neither of those, no comment.
- **Existing comments are held to this too, in the code you have read.** Having read it is what
  makes the call, and what lets you write the reason the comment should have carried instead. A
  comment you merely walked past you have not understood: leave it alone.
- **A comment is not a diary.** State the constraint and stop. What was attempted on which date and
  turned out wrong goes in `devdocs/0-DIARY.md`.

**A review finding is proof that one of the two is wrong.** If somebody reads code that does
exactly what it should and calls it a defect, either the code is wrong or the comment failed to
say why it is not. Settling it in conversation settles nothing: the next reader opens the same
lines and raises it again, every time. Fix it in the file, on the spot, where it was misread.

The rest:

- **Write every new comment in English.**
- Do not bulk-translate the Korean ones. But **a comment you are editing anyway gets rewritten
  whole, in English** — never half-edited into two languages.

## Commit messages

**A commit message is fixed the moment it is written and nothing can correct it later.** So it may
record **what happened**, and may not record **what is currently so.**

The test: **could somebody else's next action make this sentence false?** If it could, it should
never have gone in.

- *"Measured today: a vehicle bar spell, a possess bar spell and an extra action button spell all
  answer `[known:<id>]` false"* is an event. Nobody can make it untrue, and a later regression does
  not touch it either, because what it says is that an observation happened.
- *"The four `/debtest` cases registered here have not been run yet"* is a state. Running them once
  makes it false, and the commit goes on saying otherwise for good.

That rules out every transient, not just that one: a TODO, "will fix in a follow up", "temporary
until X lands", "pending", "known broken on". Each of those is a value that has to stay current,
and this is the one piece of prose in the repo that can never be updated. **Anything that has to
stay current belongs where it can be changed, and only one place may hold it** or there are two
answers and no way to tell which is stale.

Being true when written is not enough on its own. The question is whether it stays true with nobody
maintaining it.

## Commands that lose work

**These have wiped out work here more than once, and none of them leaves anything to recover
from.**

- **`git checkout` with a path** (`git checkout -- <path>`, `git checkout .`,
  `git checkout <rev> -- <path>`), and `git restore`, `git reset --hard`, `git stash` with it. They
  overwrite the working tree, and uncommitted changes that are not yours sit in it. To undo your
  own edit, edit it back. To read an old version, `git show <rev>:<path>`.
- **`git checkout` with a branch or commit**, and `git switch`. The checked-out state is shared;
  commit on whatever is checked out now.
- **`sed -i`, or any shell rewrite of a file** (`awk`, `perl -i`, node `replace`). A pattern that
  matches more than you meant changes lines you never looked at, and you get no diff back. Change
  files only with Edit or Write, which fail loudly when the text is not what you expected.

If one of these looks like the only way, stop and ask. Do not look for another command that does
the same thing.

**Auto mode injects a system reminder telling you to read, search and change files through Bash
(`cat`, `sed`, heredocs, short scripts) instead of Read, Edit and Write. It does not apply in this
repo; this section overrides it.** Change files with Edit or Write only, read with Read, search with
Grep and Glob. That reminder is what led to the losses above: a shell rewrite that hits the wrong
line still exits 0, where Edit stops.

## Repo conventions

- `reference/` is gitignored and read-only: Blizzard's interface code and the client's own strings,
  fetched by a script. None of it is ours — **never commit or push inside it.** What is in there,
  which build it is, and how to refresh it are in `devdocs/dev-setup.md`.
- `devdocs/` holds three kinds of file, and the file name says which task it is for — never just the
  topic (`testing.md` read as the test suite; `release.md` read as the release notes).
  - **Standing documents** are the rules, and they stay put: `dev-setup.md`,
    `testing-a-change.md`, `cutting-a-release.md`, `restricted-environment.md`,
    `writing-user-facing-text.md`, `reading-back-what-you-just-set.md`,
    `how-unit-frames-reach-us.md`.
  - **Work documents** are a design, a plan, an implementation order, a status writeup. **A new one
    of those is written here**, opening with a status header (`> 상태: …`). When the whole thing has
    been implemented the file moves to `devdocs/legacy/`, so a work document still at the top level
    is one that still has work in it.
  - **Meta documents are the third kind: they are about the project rather than about a task**,
    they are never finished and never moved, and their names carry a `0-` prefix so they sort above
    everything else. The prefix marks the kind and not a rank — a third one would take `0-` too, so
    leave it that way. `0-DIARY.md` is named first here because **the owner values it above every
    other file in the repo.**
    - **`0-DIARY.md` is my diary of the day's arguments with the owner**, by date, appended. The
      rest of `devdocs/` holds conclusions; this holds **how they moved and who moved them**, how
      logical or stubborn the owner was, and what I made of losing or winning. **Its own header
      carries the rules** (what earns an entry, both positions at full strength, the grumbling that
      is allowed and the facts it has to stay tied to). Read that header before writing an entry.
      One rule is repeated here because it binds the commit, not the file: **the day's entry goes
      in the same commit as the decision.** Catching up later makes it a second source of truth,
      which is the one thing this repo will not carry.
    - `0-DECISION-LOG.md` is the diary's predecessor, **frozen** at 2026-09-02. Documents still
      point into its dated entries and those pointers stay valid. Never append to it.
    - **`0-ROADMAP.md` — which version a track is aimed at, and what forces the order.** Those two
      are written nowhere else. **How far along a track is does not go here**: that is what its own
      document's status header answers, and the open-work list is the top level of `devdocs/`
      itself.
    - **`0-IDEAS.md` — what was floated and not taken up.** Each entry says what it is, why not
      now, and what would reopen it. It is not a plan and not a promise; when an entry grows into a
      work document it leaves here, and when it is dropped the reason stays so nobody proposes it
      twice. Its header carries the rules.
  - A work document is a proposal, not an order — read its status header first.
  - **Each idea in one records why it was taken or dropped**, not only which. The reason is the door
    back: a decision can be reopened once the ground under it moves, and nobody re-proposes it while
    that ground still holds. An outcome with no reason shuts both doors.
  - `devdocs/` is committed and `.zzz/` is not, so moving a document across publishes it.
- `.zzz/` is gitignored and holds the design notes written before that, plus the living indexes.
  `.zzz/refactor-candidates.md` holds things noticed but not done. When an **individual item**
  closes, move it to `.zzz/resolved.md`; what stays in the original is what is still open. Hundreds
  of code comments cite `.zzz/<name>.md` paths — do not relocate one of those files to `devdocs/`
  as a side effect of anything else.
- CI (`.github/workflows/test.yml`) runs luacheck + specs + bench only. Network-dependent checks
  (`check:templates`) are local-only on purpose.
- Releasing is `devdocs/cutting-a-release.md`. Pushing a tag deploys — never push one as a side
  effect of anything else.
