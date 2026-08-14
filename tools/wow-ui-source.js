// Updates the Blizzard interface code under `reference/wow-ui-source`.
//   npm run ui-source              # move to the newest retail build
//   npm run ui-source -- 12.0.7    # check out one specific build instead
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
// The clone itself lives outside the project and `reference/wow-ui-source` is a junction to it.
// Every worktree can point at the one copy, and `git clean -xfd` here cannot reach it.

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const REPO = "https://github.com/Gethe/wow-ui-source.git";
const BRANCH = "live";
const NO_PUSH = "read-only-mirror-do-not-push";

const link = path.join(__dirname, "..", "reference", "wow-ui-source");

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

const wanted = process.argv[2];

let target;
try {
    target = fs.realpathSync(link);
} catch {
    die(`Nothing at reference/wow-ui-source. Clone the mirror outside the project and junction to it:\n\n`
        + `  git clone --depth 1 --branch ${BRANCH} ${REPO} ..\\wow-ui-source\n`
        + `  cmd /c mklink /J reference\\wow-ui-source ..\\wow-ui-source\n`);
}

if (!fs.existsSync(path.join(target, ".git"))) {
    die(`reference/wow-ui-source resolves to ${target}, which is not a git checkout.\n`
        + `Repoint it at a clone of ${REPO} - see the header of this file for why.`);
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
    console.log(`fetching ${BRANCH}...`);
    git(target, "fetch", "--depth", "1", "origin", BRANCH);
    git(target, "checkout", "--force", "-B", BRANCH, `origin/${BRANCH}`);
}

const after = version(target);
console.log(`${target}\n  ${before === after ? after : `${before} -> ${after}`}`);
