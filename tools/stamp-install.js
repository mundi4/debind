// Installs the `post-checkout` hook that keeps `Debind/DevStamp.lua` current, and writes the stamp
// once for the checkout it is run from.
//
// Hooks live outside the working tree, so git cannot ship them -- this is what stands in for that.
// Run it once per clone. Worktrees need nothing: they share the common `.git`, and therefore the
// hook.

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

function git(...args) {
    return execFileSync("git", args, { cwd: process.cwd(), encoding: "utf8" }).trim();
}

const hookPath = path.join(git("rev-parse", "--git-common-dir"), "hooks", "post-checkout");
const source = path.join(__dirname, "post-checkout.sample");

if (fs.existsSync(hookPath) && !fs.readFileSync(hookPath, "utf8").includes("stamp-dev.js")) {
    process.stderr.write(`${hookPath} already exists and is not ours - merge it by hand.\n`);
    process.exit(1);
}

fs.copyFileSync(source, hookPath);
fs.chmodSync(hookPath, 0o755);
process.stdout.write(`installed ${hookPath}\n`);

require("./stamp-dev.js");
