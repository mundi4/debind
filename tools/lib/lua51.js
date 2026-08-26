// Runs one of the tools' Lua drivers under the lua5.1 binary.
//
// The tools that look at snippet bodies have to answer as the game does, and the game is 5.1: a
// parser that accepts 5.2 syntax passes a body that never compiles in the restricted environment,
// and a `tostring` that renders `2 ^ 2` as "4.0" bakes bytes no user receives. So they call into
// real 5.1 rather than an interpreter written in JavaScript.
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

let seq = 0;

/**
 * Runs `driver` with one string and gives back the string it wrote.
 *
 * Both go through files rather than stdio: a pipe on Windows translates newlines, and what these
 * drivers carry is snippet bodies that a golden locks byte for byte.
 */
function runLuaDriver(driver, mode, input) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "debind-lua-"));
    const requestPath = path.join(dir, `in-${seq++}`);
    const responsePath = path.join(dir, `out-${seq++}`);
    try {
        fs.writeFileSync(requestPath, input);
        const run = spawnSync("lua5.1", [driver, mode, requestPath, responsePath], {
            encoding: "utf8",
        });
        if (run.error && run.error.code === "ENOENT") {
            throw new Error(
                "lua5.1을 PATH에서 못 찾았습니다. 이 검사는 게임과 같은 5.1로 돌아야 합니다.\n"
                + "설치는 devdocs/dev-setup.md에 있습니다."
            );
        }
        if (run.error) throw run.error;
        if (run.status !== 0) {
            throw new Error(`${path.basename(driver)} ${mode} 실패:\n${(run.stderr || "").trim()}`);
        }
        return fs.readFileSync(responsePath, "utf8");
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
}

module.exports = { runLuaDriver };
