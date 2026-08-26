// Bakes a snippet body into the form the game receives.
//
// Three tools need this. `check-snippet-golden.js` locks the bytes a shipped build gets;
// `check-snippets.js` parses those same bytes; `check-state-eval.js` reads a baked body back to
// see that the press path measures each state the way the poll path does. They have to bake
// identically or one of them is guarding a body that never exists.
//
// Every stage comes out of `Snippets.lua` itself, run by `bake.lua`. Rewriting the rules in
// JavaScript would be a second copy that can drift, and a drifted copy silently guards something
// other than what gets baked.
const path = require("path");
const { runLuaDriver } = require("./lua51");

const driver = path.join(__dirname, "bake.lua");

/**
 * 주석 제거 → 프로브 치환. **`CONSTANTS.*` 치환은 안 한다** - 그 값은 `Constants`가 실제로
 * 실려 있어야 나오고, 부르는 쪽 둘 다 상수 값에는 관심이 없다. 검사는 그 자리를 문법상 올 수
 * 있는 것으로 메우고, 골든은 토큰 그대로 박제한다.
 *
 * 배포 갈래에서 값이 `false`인 프로브는 **호출이 통째로 사라진다.** 원문에서 멀쩡하던
 * `local x = PROBE.Winner(i)`가 `local x = `가 되는 자리라, 여기를 통과한 본문만 게임에서
 * 컴파일된다고 말할 수 있다.
 */
function bakeLive(body) {
    return runLuaDriver(driver, "live", body);
}

/** What the game actually receives: `BakeSnippet` itself, `CONSTANTS.*` turned into values. */
function bakeShipped(body) {
    return runLuaDriver(driver, "shipped", body);
}

/**
 * Reads one of `Constants`' string tables out as it stands.
 *
 * Folded onto tab and newline and fetched in one go. What is read here is single-line expressions,
 * so there is no fold to land inside a value.
 */
function constantStringTable(name) {
    const dump = runLuaDriver(driver, "constants", name);

    const out = {};
    if (dump.length === 0) return out;
    for (const row of dump.split("\n")) {
        const at = row.indexOf("\t");
        out[row.slice(0, at)] = row.slice(at + 1);
    }
    return out;
}

module.exports = { bakeLive, bakeShipped, constantStringTable };
