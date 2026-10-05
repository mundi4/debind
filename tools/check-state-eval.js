// **The press measures a state through the API exactly where `Constants.MEASURED_BY` says the
// state is a call**, and parses every other one in the record's `expr`. The loop measures each kind
// the way that table says, so a press that measured one another way would read the world one way
// while the loop reads it another, and nothing in a run of the game says so. The loop's bodies are
// generated, and `judgment_spec.lua` sweeps the keys they bind.
//
// So this checks the baked `EVAL_SNIPPET` holds the `STATE_EVAL_EXPRESSIONS` form of every state
// called and of no other. Until Q2d of `implementing-the-cuts-inside-the-beat-handler.md` it held
// the press to none of them.
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
const METHODS = "MEASURED_BY";

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

const methods = constantStringTable(METHODS);
const unknown = states.filter((state) => !methods[state]);
if (unknown.length > 0) {
    fail(`Constants.${METHODS}에 줄이 없는 상태: ${unknown.join(", ")}`);
}

const baked = bakeShipped(entry.body);
const wrong = states.filter((state) => baked.includes(expressions[state]) !== (methods[state] === "call"));

if (wrong.length === 0) {
    const calls = states.filter((state) => methods[state] === "call");
    console.log(`${LOCAL}이 상태 ${states.length}개 가운데 ${calls.length}개(${calls.join(", ")})만 API로 잰다.`);
    process.exit(0);
}

console.log(`${LOCAL}이 Constants.${METHODS}와 다르게 잰다:`);
for (const state of wrong) {
    console.log(`  ${state} (${methods[state]}): ${expressions[state]}`);
}
console.log("");
console.log("누름과 루프는 한 종류를 같은 방법으로 잰다. 다른 길로 재면 루프가 건 키가 누름의 답과 갈린다.");
process.exit(1);
