// Updates the Blizzard interface code under `reference/wow-ui-source`.
//   npm run ui-source              # move every client to its newest build
//   npm run ui-source -- forever   # move just that one
//   npm run ui-source -- 12.0.7    # pin mainline to one specific build
//
// Why a git mirror for mainline and not our own export: the in-game `exportInterfaceFiles code`
// command writes files but never deletes them, so a folder exported into more than once keeps
// every file the client has since dropped. The extract this replaced held 678 of them, the oldest
// last written in August 2024 - about one in seven of everything under it, and nothing in a
// grep result tells you which is which. A checkout of a tag is that build and nothing else.
//
// Gethe/wow-ui-source carries no file the client's own export does not; that was compared whole,
// in both directions, at 12.1.0. It does not carry GlobalStrings, which lives in the client
// binary rather than in the interface code - see fetch-globalstrings.js for that half.
//
// **forever is copied out of the beta client's own export instead.** The mirror's `forever` branch
// sat at 69913 while the client ran 70009, and 70009 was the build that fixed the restricted
// environment's load order - an answer the mirror could not give. The dropped files are what the
// copy leaves out: one export writes every file in one pass, so a file older than the newest by
// more than `EXPORT_PASS_MS` was written by an earlier export and is not this build's.
//
// Each folder under `reference/wow-ui-source` is a junction to a place outside the project. Every
// worktree can point at the one copy, and `git clean -xfd` here cannot reach it.

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const REPO = "https://github.com/Gethe/wow-ui-source.git";
const NO_PUSH = "read-only-mirror-do-not-push";

// Folders are named after the client rather than after the branch, because the mirror's name for
// retail is `live` and no client is called that.
const CHECKOUTS = [
    { name: "mainline", branch: "live" },
    { name: "forever", client: "_classic_beta_", product: "wow_classic_beta" },
];
const MAINLINE = CHECKOUTS[0];
const GIT_CHECKOUTS = CHECKOUTS.filter((c) => c.branch);

const root = path.join(__dirname, "..", "reference", "wow-ui-source");
const WOW_ROOT = process.env.WOW_ROOT || "C:\\Games\\World of Warcraft";
const EXPORT_PASS_MS = 60 * 60 * 1000;
// What marks a folder as one this script filled, and so one it may empty.
const EXPORT_MARKER = "SOURCE.txt";

function git(cwd, ...args) {
    return execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

function die(msg) {
    console.error(msg);
    process.exit(1);
}

function version(dir) {
    const f = path.join(dir, "version.txt");
    return fs.existsSync(f) ? fs.readFileSync(f, "utf8").trim() : "unknown";
}

function setupHelp() {
    const lines = [`  git clone --depth 1 --branch ${MAINLINE.branch} ${REPO} ..\\wow-ui-source`];
    for (const c of GIT_CHECKOUTS.slice(1)) {
        lines.push(`  git -C ..\\wow-ui-source fetch --depth 1 origin ${c.branch}:${c.branch}`,
            `  git -C ..\\wow-ui-source worktree add ..\\wow-ui-source-${c.name} ${c.branch}`);
    }
    for (const c of CHECKOUTS.filter((c) => c.client)) {
        lines.push(`  mkdir ..\\wow-ui-source-${c.name}-export`);
    }
    lines.push(`  mkdir reference\\wow-ui-source`,
        `  cmd /c mklink /J reference\\wow-ui-source\\${MAINLINE.name} ..\\wow-ui-source`);
    for (const c of CHECKOUTS.slice(1)) {
        const dir = c.client ? `${c.name}-export` : c.name;
        lines.push(`  cmd /c mklink /J reference\\wow-ui-source\\${c.name} ..\\wow-ui-source-${dir}`);
    }
    return lines.join("\n");
}

// The build the client has installed, which is the one its export came out of as long as the
// export was taken after the last patch.
function installedVersion(product) {
    const f = path.join(WOW_ROOT, ".build.info");
    if (!fs.existsSync(f)) {
        return "unknown";
    }
    const [header, ...rows] = fs.readFileSync(f, "utf8").split(/\r?\n/).filter(Boolean);
    const columns = header.split("|").map((h) => h.split("!")[0]);
    for (const row of rows) {
        const cells = row.split("|");
        if (cells[columns.indexOf("Product")] === product) {
            return cells[columns.indexOf("Version")];
        }
    }
    return "unknown";
}

function walk(dir, out = []) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            walk(p, out);
        } else if (entry.isFile()) {
            out.push(p);
        }
    }
    return out;
}

function copyExport(checkout, target) {
    const exportRoot = path.join(WOW_ROOT, checkout.client, "BlizzardInterfaceCode");
    const source = path.join(exportRoot, "Interface");
    if (!fs.existsSync(source)) {
        die(`Nothing at ${source}. Run /exportInterfaceFiles code in the ${checkout.client} client first.`);
    }
    if (fs.existsSync(path.join(target, ".git"))) {
        die(`reference/wow-ui-source/${checkout.name} resolves to ${target}, a git checkout.\n`
            + `${checkout.name} is copied from the client's export now; repoint it:\n\n${setupHelp()}\n`);
    }
    const existing = fs.readdirSync(target);
    if (existing.length > 0 && !existing.includes(EXPORT_MARKER)) {
        die(`${target} holds files this script did not put there; it empties only its own copies.`);
    }

    const files = walk(source).map((p) => ({ p, mtime: fs.statSync(p).mtimeMs }));
    const newest = Math.max(...files.map((f) => f.mtime));
    const kept = files.filter((f) => newest - f.mtime <= EXPORT_PASS_MS);

    const before = version(target);
    for (const name of existing) {
        fs.rmSync(path.join(target, name), { recursive: true, force: true });
    }
    for (const { p } of kept) {
        const to = path.join(target, "Interface", path.relative(source, p));
        fs.mkdirSync(path.dirname(to), { recursive: true });
        fs.copyFileSync(p, to);
    }
    const after = installedVersion(checkout.product);
    fs.writeFileSync(path.join(target, "version.txt"), after + "\n");
    fs.writeFileSync(path.join(target, EXPORT_MARKER),
        `Copied from ${exportRoot}\nExport written ${new Date(newest).toISOString()}\n`
        + `Build installed at copy time ${after}\n`
        + `${kept.length} files; ${files.length - kept.length} left behind by earlier exports skipped\n`);

    console.log(`${target}\n  ${before === after ? after : `${before} -> ${after}`}`
        + `  (${kept.length} files, ${files.length - kept.length} stale skipped)`);
}

const arg = process.argv[2];
const picked = CHECKOUTS.find((c) => c.name === arg);
// Every tag in this mirror is a retail build, so an argument that is not a client name is one of
// those and belongs to mainline.
const wanted = arg && !picked ? arg : null;
const targets = picked ? [picked] : wanted ? [MAINLINE] : CHECKOUTS;

for (const checkout of targets) {
    const link = path.join(root, checkout.name);

    let target;
    try {
        target = fs.realpathSync(link);
    } catch {
        die(`Nothing at reference/wow-ui-source/${checkout.name}. One clone outside the project holds`
            + ` every client, each as its own checkout:\n\n${setupHelp()}\n`);
    }

    if (checkout.client) {
        copyExport(checkout, target);
        continue;
    }

    // A linked worktree has `.git` as a file rather than a directory.
    if (!fs.existsSync(path.join(target, ".git"))) {
        die(`reference/wow-ui-source/${checkout.name} resolves to ${target}, which is not a git checkout.\n`
            + `Repoint it at a checkout of ${REPO} - see the header of this file for why.`);
    }

    // This checkout is somebody else's repository that we only ever read. Breaking its push URL
    // makes that structural instead of a thing everyone has to remember: `git push` from inside it
    // fails on the URL before it can reach GitHub. Re-applied every run, since a fresh clone will
    // not have it.
    if (git(target, "config", "--local", "--default", "", "--get", "remote.origin.pushurl") !== NO_PUSH) {
        git(target, "config", "--local", "remote.origin.pushurl", NO_PUSH);
        console.log("push disabled on this checkout");
    }

    const before = version(target);

    if (wanted) {
        // A tag is on no branch here, so fetch it by name and sit detached on it. Getting back to
        // the newest build is this same command with no argument.
        console.log(`fetching ${wanted}...`);
        git(target, "fetch", "--depth", "1", "origin", "tag", wanted, "--no-tags");
        git(target, "checkout", "--force", wanted);
    } else {
        console.log(`fetching ${checkout.branch}...`);
        // The clone is single-branch, so its configured refspec covers `live` and nothing else.
        // Naming the remote ref in full is what gives every other branch an `origin/` to check out
        // rather than a FETCH_HEAD.
        git(target, "fetch", "--depth", "1", "origin",
            `+refs/heads/${checkout.branch}:refs/remotes/origin/${checkout.branch}`);
        git(target, "checkout", "--force", "-B", checkout.branch, `origin/${checkout.branch}`);
    }

    const after = version(target);
    console.log(`${target}\n  ${before === after ? after : `${before} -> ${after}`}`);
}
