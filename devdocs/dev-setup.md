# Development setup

Windows, since the game is.

```
npm install
npm run stamp:install      # installs the post-checkout hook (see below)
npm run link               # lists WoW clients and worktrees
npm run link -- ptr .      # points _ptr_'s AddOns at this worktree
```

## `reference/` — the client's own code and strings

Gitignored, read-only, and none of it ours. Two things live there, both fetched by a script.

```
npm run ui-source            # move to the newest retail build
npm run ui-source -- 12.0.7  # pin one build
npm run globalstrings        # refresh the client strings
```

`reference/wow-ui-source/` is Blizzard's interface code — a junction to a shallow clone of
`Gethe/wow-ui-source` kept outside the project, so every worktree shares one copy. Its push URL is
deliberately broken.

`reference/globalstrings/` is the client's own strings, one file per locale. `writing-user-facing-
text.md` is what they are for: the game's word for a thing beats one the addon invents.

**Which build you are reading varies, and retail is not always behind PTR.** `version.txt` and
`SOURCE.txt` say which one is currently there. Read them before calling anything in there live, or
unreleased.

**Do not go back to the in-game `exportInterfaceFiles` export.** It writes files without ever
deleting them, so an export folder accumulates files the client dropped years ago — the one this
replaced held 678 of them, and a grep cannot tell them from live code.

## Pointing a client at a checkout

`npm run link` swaps the junctions under one client's `Interface\AddOns` so they point into one
worktree. One client and one worktree per run, both named — the other clients keep what they had.

| argument | |
|---|---|
| client | `retail`, `ptr`, `xptr` (with or without underscores), or a full path |
| worktree | `.` for the one you are in, `main` for the main worktree, otherwise the folder name |

The addon list comes from the target worktree — every top-level folder holding a `.toc` of its own
name — so an addon that exists only in that worktree gets linked too. `WOW_ROOT` overrides the
default `C:\Games\World of Warcraft`.

**It removes only junctions that point into a worktree.** A real folder under `AddOns` is reported
and skipped, and a link left over from a worktree that had an addon this one does not is reported
but not removed. Nothing here ever removes a directory recursively: on a junction that would delete
the files it points at rather than the link.

`/reload` picks up a swap — the client re-reads the TOC. No restart.

**Which client you are linked to is part of any in-game result.** `_ptr_` and `_retail_` differ in
runtime behaviour, not only in API surface, and neither is reliably the newer one — see the PTR rule
in [testing-a-change.md](testing-a-change.md) before reading an in-game failure as a bug.

## The dev stamp

A released build shows its version in the window title and the login line, read from the TOC, which
the packager stamps from the tag. A working copy has no version there, so it shows the checkout's
name instead — that is `Debind/DevStamp.lua`, which the `post-checkout` hook writes.

Hooks live outside the working tree and git cannot ship them, which is what `npm run stamp:install`
is for. Run it once per clone; worktrees need nothing, since they share the common `.git` and
therefore the hook. `npm run stamp` refreshes the file by hand.

The file is gitignored and its TOC line sits inside a `#@debug@` block, so it reaches neither the
package nor a user. Without the hook there is no file and the label reads `dev`.

## Worktrees

`node_modules` is not created in a new worktree and is not linked automatically. Make the junction
by hand after `git worktree add`, or none of the tooling runs there.

**Before removing a worktree, break that junction first.** `git worktree remove` — and anything
else that deletes the directory recursively — walks through the junction and takes the main repo's
`node_modules` with it.
