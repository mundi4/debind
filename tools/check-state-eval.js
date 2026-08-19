// The poll path and the press path measure the same states, and they have to measure them the
// same way.
//
// `UpdateBindings.lua` builds its 0.2s state loop out of `Constants.STATE_EVAL_EXPRESSIONS`.
// `SecureBindings.lua`'s `EVAL_SNIPPET` spells the same measurements out as literals instead,
// because a body assembled from interpolated strings is one `tools/lib/snippets.js` cannot
// resolve, and an unresolvable body drops out of every other snippet check without a sound.
//
// So the agreement is checked here, against the **baked** body: `CONSTANTS.GROUP_RAID` is a number
// by then, which is the form the shared table holds.
//
// Drift here is the worst kind of quiet. The poll and the press would answer differently for the
// same state, and nothing downstream could tell which one was wrong.
//
// This lived in `SecureBindings.lua` as a load-time `assert` under `if (DebindPrivate.DEBUG)`
// until 2026-08-20, which meant the only thing that ever ran it was logging in on a development
// client. Someone who edited one of the two without opening the game heard nothing.
const fs = require("fs");
const path = require("path");
const { collectSnippetLocals } = require("./lib/snippets");
const { bakeShipped, constantStringTable } = require("./lib/bake");

const srcDir = path.join(__dirname, "..", "Debind");

// Named rather than searched for. A rename fails here by name, which is the loud half of the
// trade; a search would quietly find nothing and report green.
const FILE = "SecureBindings.lua";
const LOCAL = "EVAL_SNIPPET";
const TABLE = "STATE_EVAL_EXPRESSIONS";

function fail(message, hint) {
    console.log(message);
    if (hint) console.log(hint);
    process.exit(1);
}

const src = fs.readFileSync(path.join(srcDir, FILE), "utf8");
const entry = collectSnippetLocals(src).get(LOCAL);

if (!entry) {
    fail(`${FILE}에서 \`local ${LOCAL} = [[...]]\`를 못 찾았다.`,
        `이름을 바꿨으면 이 파일의 LOCAL도 같이 바꿀 것. 그 이름은 \`tools/lib/snippets.js\`가\n`
        + "본문을 되찾는 데도 쓰므로 다른 스니펫 검사도 같이 놓친다.");
}

const expressions = constantStringTable(TABLE);
const states = Object.keys(expressions).sort();

// An empty table would let everything below pass without measuring anything.
if (states.length === 0) {
    fail(`Constants.${TABLE}가 비어 있다. 그대로 두면 이 검사는 아무것도 안 보고 통과한다.`);
}

const baked = bakeShipped(entry.body);
const missing = states.filter((state) => !baked.includes(expressions[state]));

if (missing.length === 0) {
    console.log(`측정식 ${states.length}개를 ${LOCAL}이 같은 모양으로 잰다.`);
    process.exit(0);
}

console.log(`${LOCAL}이 Constants.${TABLE}와 다르게 잰다. ${missing.length}개:`);
for (const state of missing) {
    console.log(`  ${state}`);
    console.log(`    표: ${expressions[state]}`);
}
console.log("");
console.log(`폴은 UpdateBindings.lua가 이 식으로 걸고, 프레스는 ${FILE}의 ${LOCAL}이 잰다.`);
console.log("둘이 갈리면 같은 상태에 서로 다른 답이 나오고, 그 아래 어디에도 어느 쪽이 틀렸는지");
console.log("아는 곳이 없다. 한쪽을 일부러 고쳤으면 다른 쪽도 같이 고칠 것.");
process.exit(1);
