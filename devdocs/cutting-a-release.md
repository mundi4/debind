# Cutting a release

Pushing a tag is the deploy. There is no other button.

```
# on main, with the work already merged
#   1. add the new version's section to CHANGELOG.md
git commit -am "Write the 3.1.7 note"
git tag v3.1.7
git push origin main
git push origin v3.1.7          # this push is the deploy
```

**The tag is pushed by name, on its own line.** It used to say `git push origin main
--follow-tags`, which pushes **annotated** tags and nothing else. Every tag this project has ever
cut is lightweight (`git cat-file -t v3.1.6` answers `commit`), so that command pushed main,
printed nothing about a tag, and deployed nothing — the one failure this file exists to prevent,
in the shape that looks like success. Caught while cutting 3.2.

`.github/workflows/build.yml` fires on `push: tags` and hands the checkout to
[BigWigsMods/packager](https://github.com/BigWigsMods/packager), which builds the zip and uploads
to CurseForge, Wago and GitHub Releases.

## Rules

**Tag names are `v<major>.<minor>.<patch>`.** Some older tags (`3.1.4`, `3.1.5`) were cut without
the `v` — do not copy them.

**Never bump a version by hand.** The TOCs carry `## Version: @project-version@` and the packager
substitutes it from the tag. A number typed into a TOC is a number that will disagree with the tag.

**`CHANGELOG.md` is written, not generated.** `.pkgmeta` sets `manual-changelog`, so whatever is in
that file becomes the release notes on CurseForge. Without it the packager scrapes commit subjects.

**The workflow has no `workflow_dispatch`, on purpose.** Running it without a tag makes the packager
publish an alpha to CurseForge and Wago — a "just checking the config" click leaves something to
delete on both. Re-run a failed run from the Actions page instead.

## Hotfixing an older release

Only when `main` holds work that cannot ship yet. Otherwise release from `main`.

```
git switch -c hotfix-3.1.7 v3.1.6
# fix, commit, write the note
git tag v3.1.7
git push origin v3.1.7          # the tag deploys; the branch need not be pushed
git switch main && git merge hotfix-3.1.7
```

**Merge it back.** The branch exists to reach an older state, not to become a second line — leaving
it unmerged is what turns `main` and the releases into histories that can no longer be reconciled.

Two things do not work on a worktree checked out at an old tag: `DebindTest` needs the matching
`Debind` internals, so in-game verification is unavailable there (use `npm run check` plus a manual
smoke test), and SavedVariables written by newer local code will not downgrade — move them aside
first.

## What ends up in the zip

The `ignore` list in `.pkgmeta` decides, and **anything at the repo root that is not on it ships
inside the addon folder** — that is how `README.md` and `CHANGELOG.md` get there. Dotfiles and
dotfolders never ship; the packager's copy prunes `.*` before the ignore list is consulted.

So: adding a development file or folder at the repo root means adding it to `ignore` in the same
change, unless its name starts with a dot.
