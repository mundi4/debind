// `wow-reference` sits next to the main worktree, outside the repo. Found through git's common
// directory rather than as `..` from here: a worktree under `.claude/worktrees/<name>` is three
// levels below the main worktree, and every worktree shares the one `.git` that lives in it.
const { execFileSync } = require("child_process");
const path = require("path");

const commonDir = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], {
    cwd: __dirname,
    encoding: "utf8",
}).trim();

module.exports = path.join(path.dirname(path.dirname(commonDir)), "wow-reference");
