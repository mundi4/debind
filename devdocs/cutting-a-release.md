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

**`DB_VERSION`을 올리기 전에 마지막 태그의 값부터 본다.** `git show v<태그>:Debind/Constants.lua`
가 답한다. 그 값보다 위는 **아무도 저장한 적 없는 번호**다 - 그 판을 들고 있는 것은 이 저장소를
직접 도는 우리뿐이고, 사용자는 마지막으로 나간 판에서 다음 릴리스로 한 번에 올라온다.

그래서 **미출시 구간은 계단이 아니라 한 칸이다.** 저장 모양을 바꾸는 변경이 그 사이에 셋 붙으면
셋 다 그 한 칸 안에 들어간다. 서로 무관한 일이 한 단계에 같이 있는 것은 어긋난 것이 아니다 -
단계가 뜻하는 것은 "이 판에서 저 판으로"이지 "이 변경 하나"가 아니다.

**변경마다 하나씩 올리면 아무도 안 지나는 단계가 영원히 남는다.** 2026-09-09에 6 위로 7·8·9가
그렇게 쌓였다가 7 하나로 접혔다. 사다리 끝을 보고 하나 더 붙이는 것은 판단이 아니고, 그때 물어야
하는 것은 "마지막 계단이 몇이냐"가 아니라 **"나간 판이 몇이냐"**다.

접을 때 같이 움직이는 것들: `Constants.DB_VERSION`, 각 사다리의 `dbver <= N`, 그 번호를 본문에
적어둔 주석과 문서, `tests/migration_spec.lua`의 진입 판과 제목, `DebindDev/DevSeed.lua`의
`SEEDS[N]`. **현재 판의 씨앗은 결과를 든다** - `/deb seed`를 인자 없이 치면 그것이 서므로, 그
판이 저장하는 모양 그대로여야 한다. 그 아래 판의 씨앗이 입력이다.

**`CHANGELOG.md` is written, not generated.** `.pkgmeta` sets `manual-changelog`, so whatever is in
that file becomes the release notes on CurseForge. Without it the packager scrapes commit subjects.

**The workflow has no `workflow_dispatch`, on purpose.** Running it without a tag makes the packager
publish an alpha to CurseForge and Wago — a "just checking the config" click leaves something to
delete on both. Re-run a failed run from the Actions page instead.

## Hotfixing an older release

Only when `main` holds work that cannot ship yet. Otherwise release from `main`.

**Branching from the tag is the right default, and the reason is verification.** What ships is then
exactly the fix, so the only thing to check is the fix. Branching from a later commit drags in
whatever was finished since, and all of that has to be verified too, at the worst possible moment.

**Before you cut, read `0-ROADMAP.md` once and ask whether anything waiting has a closing window.**
Most waiting work loses nothing by waiting one more release. A few things do: a guard that only
counts if it reaches users *before* the thing it guards against is worthless the moment that thing
ships, and a hotfix may be the only release leaving before then. This is a look, not a burden. If
there is such a thing, decide then whether it is small enough to carry; if there is not, cut from
the tag and move on. 3.2.1 and 3.2.2 both went out from the tag without that look, and the
downgrade guard lost its window (`legacy/guarding-against-a-downgrade.md`).

```
git switch -c hotfix-3.1.7 v3.1.6
# fix, commit, write the note
git tag v3.1.7
git push origin v3.1.7          # the tag deploys; the branch need not be pushed
git switch main && git merge hotfix-3.1.7
```

**Merge it back.** The branch exists to reach an older state, not to become a second line — leaving
it unmerged is what turns `main` and the releases into histories that can no longer be reconciled.

Two things do not work on a worktree checked out at an old tag: `DebindDev` needs the matching
`Debind` internals, so in-game verification is unavailable there (use `npm run check` plus a manual
smoke test), and SavedVariables written by newer local code will not downgrade — move them aside
first.

## What ends up in the zip

The `ignore` list in `.pkgmeta` decides, and **anything at the repo root that is not on it ships
inside the addon folder** — that is how `README.md` and `CHANGELOG.md` get there. Dotfiles and
dotfolders never ship; the packager's copy prunes `.*` before the ignore list is consulted.

So: adding a development file or folder at the repo root means adding it to `ignore` in the same
change, unless its name starts with a dot.
