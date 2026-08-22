# Writing code for the restricted environment

Read this before touching a snippet body — the string handed to `SecureHandlerExecute`,
`SecureHandlerWrapScript`, or a `SetAttribute` that a snippet later runs.

## Three words, kept apart

| | |
|---|---|
| **restricted environment** | the sandbox a snippet body actually runs in, behind an API whitelist |
| **secure** | the taint and combat-lockdown side: secure frame, secure handler, `InCombatLockdown` |
| **snippet** | the body string itself |

## Names carry more here than anywhere else

**A name inside a body is often the only thread back to where the value came from.** Three things
take the usual ways of finding out away:

- **Every body shares one environment.** A global written by one snippet is read by another with
  nothing between them to follow. `States`, `DirtyFlags`, `UnitAliasMap` are all reached that way.
- **Bodies are spliced textually.** `EVAL_SNIPPET` is concatenated into each wrapper, so locals it
  declares (`winner`, `hoverUnit`, `unitframe`) are live in code that never declared them, and the
  declaration is in another string in another part of the file.
- **Half the values are baked in from outside.** `t.combat` was written by `appendKeyValue` in
  `UpdateBindings.lua`. Inside the body there is no definition to jump to at all.

So a body cannot be read the way ordinary Lua is read, by following a name to where it was set.
The name has to be right on its own, and a name that says the wrong thing is not a blemish here —
it is the only evidence a reader has, pointing the wrong way.

`isNonClick` was that for a long time. It was baked as a record key and read back as `t[subset]`,
and it named records that are bound with `SetBindingClick` and click a button on
`DefaultClickFrame`. Two separate edits reached for the wrong flag because of it. It is `holdsKey`
now, and `isClick` is `isClickCast`.

**Renaming a key that crosses into a body moves `tools/snippet-golden.txt`.** That is expected;
update it and read the diff, which should hold nothing but the identifier.

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

**`RunAttribute` costs more than a function call, and it is not a compile.** Blizzard keys a closure
cache on the body string, so `loadstring` runs once for a given body and every call after it is a
hit (`RestrictedExecution.lua`, `CreateClosureFactory` and `CallRestrictedClosure`). What a call
still costs is an attribute read, two hash lookups, an environment swap, a `pcall`, and a scrub of
`self` and of every argument. That is enough to keep out of a hot path and not enough to treat as a
compile, so weigh it against what the body actually does rather than reaching for a rule.

Two things follow from the cache being keyed by text. A body whose text changes on every rebuild
takes a fresh entry each time, and the cache is shared across every addon and rotates at a thousand
entries. Generated snippets are worth keeping textually stable for that reason as well as for
reading the golden.

What splits a body is **text concatenation at build time**: `EVAL_SNIPPET` is spliced into each
wrapper that carries it. Splicing also keeps the locals it declares (`winner`, `hoverUnit`) visible
to the code after it, which a call could not do without turning each one into a shared global.

The click wrappers hold **no `RunAttribute` and no `RunFor` at all**, and that is kept deliberately
(decided 2026-08-11). The ones that remain sit in setup, in hover enter/leave, and in the state
paths.

## Comments in a body

**Whole-line comments only. Never one at the end of a line of code.**

`StripSnippetComments` blanks a line only when the whole line is a comment (`^[ \t]*%-%-`).
Everything else is carried through verbatim, which makes three things true:

- **Never put a comment at the end of a line of code.** `local a = 1 -- note` survives, and if the
  next chunk is concatenated onto that same line it lands inside the comment and is gone. This is
  the one that has to hold everywhere, baked or not, and `check:snippets` refuses it — nothing else
  could, since the body still parses and the golden shows it stripped.
- Opening a line with `--[[` is refused by an `assert`, in a body that is baked. In one that is
  not, it is an ordinary long comment and nothing objects.
- **A body that never reaches `BakeSnippet` ships every comment it has.** Most bodies here are
  that — a string handed straight to `SecureHandlerExecute` or `SetAttribute`, with only
  `InstallSnippet` and the two explicit `BakeSnippet(...)` calls going through the strip. Whole-line
  comments are fine there and plenty of them are deliberate; they cost bytes and a one-time parse
  and nothing per run. What is not fine there is the same thing that is not fine anywhere: a
  comment sharing a line with code.

Explanations belong in the Lua comment above the body when the reasoning is long. Inside the body,
keep to what a reader of that line needs.

## Why the failures are quiet

A body the restricted environment cannot compile does not raise anything. The snippet never
attaches and the symptom is "that one key stopped working". If something behaves as though the
addon is loaded and doing nothing, suspect a snippet that did not attach before suspecting logic.
