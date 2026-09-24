# Development setup

Windows, since the game is.

```
npm run stamp:install      # installs the post-checkout hook (see below)
npm run link               # lists WoW clients and worktrees
npm run link -- ptr .      # points _ptr_'s AddOns at this worktree
```

There is no `npm install` step: nothing here has a dependency outside node's own library.

## `lua5.1` on PATH

**The specs and the snippet checks need it, and it has to be 5.1.** The client is 5.1, CI installs
5.1, and what a newer interpreter answers differently lands where nothing else would catch it: a
bare `%f` printed to six places or to one, `2 ^ 2` rendered as `4.0` into bytes `snippet-golden.txt`
locks. `tests/run.lua` refuses anything newer rather than letting that pass quietly. LuaJIT reports
5.1 and is accepted.

Windows has no installer for it. Take the `Tools Executables` zip for 5.1.5 from
[LuaBinaries](https://sourceforge.net/projects/luabinaries/files/5.1.5/), unpack it somewhere under
`%LOCALAPPDATA%\Programs`, and put that folder on the user PATH. The executable is named `lua5.1.exe`
already, which is the name everything here calls. A `lua` 5.4 next to it is harmless.

## `reference/` — the client's own code and strings

Gitignored, read-only, and none of it ours. Two things live there, both fetched by a script.

```
npm run ui-source             # move every client to its newest build
npm run ui-source -- forever  # move just that one
npm run ui-source -- 12.0.7   # pin mainline to one build
npm run globalstrings         # refresh the client strings
```

`reference/wow-ui-source/` is Blizzard's interface code, one folder per client: `mainline/` and
`forever/`. Each is a junction to a folder kept outside the project, so every worktree shares one
copy. The mirror calls retail `live`, and these folders are named after the client instead, because
no client is called that.

- **`mainline/` is a shallow clone of `Gethe/wow-ui-source`**, with its push URL deliberately
  broken. Every tag in the mirror is a retail build, so a build number pins it.
- **`forever/` is copied out of the beta client's own export** (`_classic_beta_\BlizzardInterfaceCode`),
  into `..\wow-ui-source-forever-export`. The mirror's `forever` branch trailed the client: it sat at
  69913 while 70009 was the build that fixed what blocked us. Run `/exportInterfaceFiles code` in that
  client after a patch, then `npm run ui-source -- forever`. `version.txt` is the build the client
  had installed at copy time, and `SOURCE.txt` says when the export was written.

`reference/globalstrings/` is the client's own strings, one file per locale. `writing-user-facing-
text.md` is what they are for: the game's word for a thing beats one the addon invents.

**Which build you are reading varies, and retail is not always behind PTR.** `version.txt` and
`SOURCE.txt` say which one is currently there. Read them before calling anything in there live, or
unreleased.

**Do not read the in-game export folder directly.** It writes files without ever deleting them, so
an export folder accumulates files the client dropped years ago — the one `mainline/` replaced held
678 of them, and a grep cannot tell them from live code. The `forever/` copy leaves those out: one
export writes every file in one pass, so a file more than an hour older than the newest is an earlier
export's.

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

**`reference/` needs a junction, and it is three rather than one.** It is gitignored, so a new
worktree has nothing there: `reference/globalstrings` (what `npm run globalstrings` fetched) and
`reference/wow-ui-source/mainline` and `reference/wow-ui-source/forever` (each itself a junction to
a folder kept outside the project) all have to be pointed at the same places the main worktree
points at. `reference/wow-ui-source` itself is a real folder, not a junction, so it has to be
created before the two inside it. `npm run check` passes without any of them, which is exactly why
this is easy to miss — what breaks is
reading Blizzard's own code and strings, and that failure looks like "the file is not there" rather
than like a setup step nobody did.

**Before removing a worktree, break those junctions first.** `git worktree remove`, and anything
else that deletes the directory recursively, walks through a junction and takes what it points at
with it. That is the clone of Blizzard's interface code and the `forever` copy, both shared by
every worktree here.
