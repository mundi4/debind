// Points one WoW client's AddOns folder at one worktree, by swapping the junctions.
//
//   npm run link                        list the client folders and worktrees, change nothing
//   npm run link -- ptr                 show what _ptr_ currently points at
//   npm run link -- ptr debind-3.1.6    point _ptr_ at that worktree
//   npm run link -- ptr main            point _ptr_ back at the main worktree
//
// One client and one worktree per run, both named explicitly. Nothing is swapped that was not
// asked for, so the other clients keep whatever they had.
//
// The addon list comes from the **target worktree** -- every top-level folder holding a `.toc` of
// its own name -- so an addon that exists only in that worktree gets linked too.
//
// Junctions rather than symbolic links: they need no elevation, and WoW cannot tell the difference.
// A link that was a symbolic link becomes a junction once swapped.
//
// Windows only, which is what the junction is.

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const WOW_ROOT = process.env.WOW_ROOT || "C:\\Games\\World of Warcraft";

function git(...args) {
    return execFileSync("git", args, { cwd: process.cwd(), encoding: "utf8" }).trim();
}

const C = {
    dim: (s) => `\x1b[90m${s}\x1b[0m`,
    cyan: (s) => `\x1b[36m${s}\x1b[0m`,
    green: (s) => `\x1b[32m${s}\x1b[0m`,
    yellow: (s) => `\x1b[33m${s}\x1b[0m`,
};

function die(message) {
    process.stderr.write(`${message}\n`);
    process.exit(1);
}

// ---------------------------------------------------------------- links

// `lstat` reports a junction as a symbolic link, which is the distinction that matters here: a real
// directory must never be touched, and this is what tells them apart.
function readLinkTarget(p) {
    let st;
    try {
        st = fs.lstatSync(p);
    } catch {
        return null;
    }
    if (!st.isSymbolicLink()) {
        return null;
    }
    // Junction targets come back with the `\\?\` device prefix.
    return fs.readlinkSync(p).replace(/^\\\\\?\\/, "");
}

function isRealDirectory(p) {
    try {
        const st = fs.lstatSync(p);
        return st.isDirectory() && !st.isSymbolicLink();
    } catch {
        return false;
    }
}

// **The one call in this file that can destroy someone's work, so the guard lives here rather than
// at the call site.** A caller that forgets to check cannot get past this; a caller that checks and
// then hands over the wrong path cannot either.
//
// `rmdir` on a junction takes away the reparse point alone and leaves the target untouched --
// verified, not assumed. What must never appear here is a recursive remove (`fs.rmSync` with
// `recursive`, `rm -rf`, PowerShell's `Remove-Item -Recurse`): those walk *through* the junction
// and delete the files it points at. That is how a node_modules once went.
function removeLink(p) {
    const st = fs.lstatSync(p);
    if (!st.isSymbolicLink()) {
        throw new Error(`refusing to remove ${p}: it is not a link`);
    }
    fs.rmdirSync(p);
}

const samePath = (a, b) =>
    path.resolve(a).replace(/[\\/]+$/, "").toLowerCase() ===
    path.resolve(b).replace(/[\\/]+$/, "").toLowerCase();

// ---------------------------------------------------------------- discovery

function worktrees() {
    const out = [];
    for (const line of git("worktree", "list", "--porcelain").split(/\r?\n/)) {
        if (line.startsWith("worktree ")) {
            const p = path.resolve(line.slice(9));
            // The porcelain listing puts the main worktree first.
            out.push({ path: p, name: path.basename(p), isMain: out.length === 0 });
        }
    }
    return out;
}

function clientFolders() {
    let entries;
    try {
        entries = fs.readdirSync(WOW_ROOT, { withFileTypes: true });
    } catch {
        die(`No WoW folder at ${WOW_ROOT}   (set WOW_ROOT to point elsewhere)`);
    }
    return entries
        .filter((e) => e.isDirectory())
        .map((e) => e.name)
        .filter((n) => fs.existsSync(path.join(WOW_ROOT, n, "Interface", "AddOns")));
}

function resolveAddOnsPath(spec) {
    if (/[\\/]/.test(spec)) {
        if (isRealDirectory(spec)) {
            return path.resolve(spec);
        }
        die(`No such folder: ${spec}`);
    }
    // `retail` and `_retail_` both work.
    for (const candidate of [spec, `_${spec.replace(/^_|_$/g, "")}_`]) {
        const p = path.join(WOW_ROOT, candidate, "Interface", "AddOns");
        if (isRealDirectory(p)) {
            return p;
        }
    }
    process.stderr.write(`\nNo Interface\\AddOns under "${spec}". Available:\n`);
    for (const b of clientFolders()) {
        process.stderr.write(`  ${b}\n`);
    }
    process.exit(1);
}

function resolveWorktree(spec, trees) {
    if (spec === "main") {
        return trees.find((w) => w.isMain).path;
    }
    const byName = trees.find((w) => w.name === spec);
    if (byName) {
        return byName.path;
    }
    if (isRealDirectory(spec)) {
        return path.resolve(spec);
    }
    process.stderr.write(`\nNo worktree "${spec}". Available:\n`);
    for (const w of trees) {
        process.stderr.write(`  ${w.name.padEnd(28)} ${w.path}${w.isMain ? "  (main)" : ""}\n`);
    }
    process.stderr.write(`\nTo make one:  git worktree add ..\\debind-<name> -b <branch>\n`);
    process.exit(1);
}

// An addon is a top-level folder holding a `.toc` named after it. Read rather than hardcoded, since
// the set of folders changes.
function addonNames(root) {
    return fs
        .readdirSync(root, { withFileTypes: true })
        .filter((e) => e.isDirectory() && !e.name.startsWith("."))
        .map((e) => e.name)
        .filter((n) => fs.existsSync(path.join(root, n, `${n}.toc`)))
        .sort();
}

// Links under AddOns that point into any worktree -- ours. Anything else in there belongs to
// someone else and is never counted, listed or removed.
function ourLinks(addOnsPath, trees) {
    const roots = trees.map((w) => w.path.replace(/[\\/]+$/, "").toLowerCase());
    const out = [];
    for (const e of fs.readdirSync(addOnsPath, { withFileTypes: true })) {
        const target = readLinkTarget(path.join(addOnsPath, e.name));
        if (!target) {
            continue;
        }
        const t = target.toLowerCase();
        if (roots.some((r) => t.startsWith(`${r}\\`) || t.startsWith(`${r}/`))) {
            out.push({ name: e.name, target });
        }
    }
    return out;
}

function wowIsRunning() {
    try {
        const out = execFileSync("tasklist", ["/fo", "csv", "/nh"], { encoding: "utf8" });
        return /"Wow(T|B|Classic)?\.exe"/i.test(out);
    } catch {
        return false;
    }
}

// ---------------------------------------------------------------- run

const [target, worktreeSpec] = process.argv.slice(2);
const trees = worktrees();

function printWorktrees() {
    for (const w of trees) {
        process.stdout.write(
            C.dim(`  ${w.name.padEnd(28)} ${w.path}${w.isMain ? "  (main)" : ""}\n`)
        );
    }
}

if (!target) {
    process.stdout.write(`\nUsage:  npm run link -- <client-folder> <worktree>\n\n`);
    process.stdout.write(C.cyan("Client folders:\n"));
    for (const b of clientFolders()) {
        process.stdout.write(C.dim(`  ${b}\n`));
    }
    process.stdout.write(C.cyan("\nWorktrees:\n"));
    printWorktrees();
    process.stdout.write(C.dim(`\n  e.g.  npm run link -- ptr main\n\n`));
    process.exit(0);
}

const addOnsPath = resolveAddOnsPath(target);

if (!worktreeSpec) {
    process.stdout.write(`\n${C.cyan(addOnsPath)}\n`);
    const links = ourLinks(addOnsPath, trees);
    if (links.length === 0) {
        process.stdout.write(C.dim("  (nothing here points at a worktree)\n"));
    }
    for (const l of links) {
        process.stdout.write(`  ${l.name.padEnd(20)} -> ${l.target}\n`);
    }
    process.stdout.write(C.cyan("\nWorktrees:\n"));
    printWorktrees();
    process.stdout.write("\n");
    process.exit(0);
}

const worktreeRoot = resolveWorktree(worktreeSpec, trees);
const addons = addonNames(worktreeRoot);

if (addons.length === 0) {
    die(`No folder under ${worktreeRoot} holds a .toc of its own name.`);
}

// A restart used to be needed. `/reload` re-reads the TOC now, so a changed file list -- which is
// what pointing the link somewhere else amounts to -- follows along.
if (wowIsRunning()) {
    process.stdout.write(
        C.yellow("\n!! WoW is running. /reload picks the new links up (it re-reads the TOC).\n")
    );
}

process.stdout.write(`\n${C.cyan(addOnsPath)}\n${C.green(`  -> ${worktreeRoot}`)}\n\n`);

let changed = 0;
let skipped = 0;

for (const name of addons) {
    const linkPath = path.join(addOnsPath, name);
    const want = path.join(worktreeRoot, name);

    if (fs.existsSync(linkPath) || readLinkTarget(linkPath)) {
        if (isRealDirectory(linkPath)) {
            process.stdout.write(C.yellow(`  ${name.padEnd(20)} skipped - a real folder, not a link\n`));
            skipped++;
            continue;
        }
        const current = readLinkTarget(linkPath);
        if (current && samePath(current, want)) {
            process.stdout.write(C.dim(`  ${name.padEnd(20)} already correct\n`));
            continue;
        }
        removeLink(linkPath);
    }

    fs.symlinkSync(want, linkPath, "junction");
    process.stdout.write(C.green(`  ${name.padEnd(20)} -> ${want}\n`));
    changed++;
}

// Left over from a worktree that had an addon this one does not. Reported, never removed -- it is
// not this run's to decide.
const stale = ourLinks(addOnsPath, trees).filter((l) => !addons.includes(l.name));
if (stale.length > 0) {
    process.stdout.write(C.yellow("\nLinks here for addons this worktree does not have (left alone):\n"));
    for (const s of stale) {
        process.stdout.write(C.yellow(`  ${s.name.padEnd(20)} -> ${s.target}\n`));
    }
    process.stdout.write(C.dim("  Disable them in the addon list, or remove them by hand.\n"));
}

process.stdout.write(C.green(`\n${changed} link(s) changed, ${skipped} skipped.\n`));
if (skipped > 0) {
    process.stdout.write(C.yellow("Skipped ones are real folders and were not touched.\n"));
}
process.stdout.write(C.dim("Other clients are unchanged. Run again against one to move it.\n\n"));
