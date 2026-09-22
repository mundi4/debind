// Updates the Blizzard interface code under `reference/wow-ui-source`.
//   npm run ui-source              # move every client to its newest build
//   npm run ui-source -- forever   # move just that one
//   npm run ui-source -- 12.0.7    # pin mainline to one specific build
//
// Why a git mirror and not our own export: the in-game `exportInterfaceFiles code` command
// writes files but never deletes them, so a folder exported into more than once keeps every
// file the client has since dropped. The extract this replaced held 678 of them, the oldest
// last written in August 2024 - about one in seven of everything under it, and nothing in a
// grep result tells you which is which. A checkout of a tag is that build and nothing else.
//
// Gethe/wow-ui-source carries no file the client's own export does not; that was compared whole,
// in both directions, at 12.1.0. It does not carry GlobalStrings, which lives in the client
// binary rather than in the interface code - see fetch-globalstrings.js for that half.
//
// The checkouts live outside the project and each folder under `reference/wow-ui-source` is a
// junction to one. Every worktree can point at the one copy, and `git clean -xfd` here cannot
// reach it.

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const REPO = "https://github.com/Gethe/wow-ui-source.git";
const NO_PUSH = "read-only-mirror-do-not-push";

// Folders are named after the client rather than after the branch, because the mirror's name for
// retail is `live` and no client is called that.
const CHECKOUTS = [
    { name: "mainline", branch: "live" },
    { name: "forever", branch: "forever" },
];
const MAINLINE = CHECKOUTS[0];

const root = path.join(__dirname, "..", "reference", "wow-ui-source");

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
    for (const c of CHECKOUTS.slice(1)) {
        lines.push(`  git -C ..\\wow-ui-source fetch --depth 1 origin ${c.branch}:${c.branch}`,
            `  git -C ..\\wow-ui-source worktree add ..\\wow-ui-source-${c.name} ${c.branch}`);
    }
    lines.push(`  mkdir reference\\wow-ui-source`,
        `  cmd /c mklink /J reference\\wow-ui-source\\${MAINLINE.name} ..\\wow-ui-source`);
    for (const c of CHECKOUTS.slice(1)) {
        lines.push(`  cmd /c mklink /J reference\\wow-ui-source\\${c.name} ..\\wow-ui-source-${c.name}`);
    }
    return lines.join("\n");
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
