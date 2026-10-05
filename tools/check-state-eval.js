// **The press asks the state axes by parsing the record's `expr`, and measures none of them through
// the API** (`implementing-the-trimmed-tail-key-beat.md` P2). `Constants.STATE_EVAL_EXPRESSIONS` is
// what the beat still measures with, so a press that took one of those forms back up would read the
// world one way while the beat reads it another, and nothing in a run of the game says so.
//
// So this checks the baked `EVAL_SNIPPET` holds **none** of the table's forms. It used to check
// the opposite -- that the press measured every one of them -- for as long as the press did.
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
const measured = states.filter((state) => baked.includes(expressions[state]));

if (measured.length === 0) {
    console.log(`${LOCAL}이 상태 ${states.length}개를 API로 재지 않는다 (t.expr 파싱으로 묻는다).`);
    process.exit(0);
}

console.log(`${LOCAL}이 상태를 API로 다시 잰다. ${measured.length}개:`);
for (const state of measured) {
    console.log(`  ${state}: ${expressions[state]}`);
}
console.log("");
console.log("누름은 레코드의 t.expr을 파싱해 상태를 묻는다(UpdateBindings.lua의 StateExpression).");
console.log("API로 재면 박자와 누름이 다른 길로 세상을 읽는다.");
process.exit(1);
