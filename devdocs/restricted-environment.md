# Writing code for the restricted environment

Read this before touching a snippet body — the string handed to `SecureHandlerExecute`,
`SecureHandlerWrapScript`, or a `SetAttribute` that a snippet later runs.

## Three words, kept apart

| | |
|---|---|
| **restricted environment** | the sandbox a snippet body actually runs in, behind an API whitelist |
| **secure** | the taint and combat-lockdown side: secure frame, secure handler, `InCombatLockdown` |
| **snippet** | the body string itself |

## Hot paths

Where a line costs something every time:

- **the state watch loop** — the update pass that runs whenever a watched state changes
- **click-time eval** — `EVAL_SNIPPET` and the wrappers spliced from it (`SecureBindings.lua`)
- **hover enter/leave** — `clickcast_onenter` / `clickcast_onleave` → `setup_onenter` /
  `setup_onleave`

Push work to build time here; a value carried into the restricted environment is paid for on every
run. What is not in this list — the setup snippets that run once at login — does not need the same
squeeze.

Habits that are free elsewhere and are not free here: building a table per run, walking everything
to find one thing, composing strings, and a layer of indirection added for readability.

## Comments in a body

**Only whole-line comments, and only in a body that goes through `BakeSnippet`.**

`StripSnippetComments` blanks a line only when the whole line is a comment (`^[ \t]*%-%-`).
Everything else is carried through verbatim, which makes three things true:

- **Never put a comment at the end of a line of code.** `local a = 1 -- note` survives, and if the
  next chunk is concatenated onto that same line it lands inside the comment and is gone. Silently:
  `check-snippets` still sees a body that parses.
- Opening a line with `--[[` is refused by an `assert`.
- A body that never reaches `BakeSnippet` — a string passed straight to `SecureHandlerExecute` —
  keeps every comment, whole-line ones included. Put none there at all.

Explanations belong in the Lua comment above the body, not inside it.

## Why the failures are quiet

A body the restricted environment cannot compile does not raise anything. The snippet never
attaches and the symptom is "that one key stopped working". If something behaves as though the
addon is loaded and doing nothing, suspect a snippet that did not attach before suspecting logic.
