// Does the export leave any action field behind?
//   npm run check:export-fields
//
// `KEYS_TO_SAVE` in `Profile.lua` is the one list of "fields that get saved", and `ACTION_FIELDS`
// in `DebindShare/Export.lua` is the list of "fields that go out on the wire". They must differ by
// exactly one (`imported`), which is the only field that describes **this drawer** rather than the
// action (the comment in `Export.lua` has the detail).
//
// Why this exists: adding a field to only one of them raises **nothing anywhere**. The action saves
// fine and the export quietly drops it, so it arrives on the far side as an action with one
// condition missing - and a missing condition usually means "fires more often", which is the worst
// direction for a keybinding addon to fail in. Neither the game nor the headless specs catch it:
// a spec only looks at the fields it already knows about.
//
// `Export.lua` not reading `KEYS_TO_SAVE` directly is deliberate. That one is a local, and the
// export lives in a separate addon that does not reach into `Profile.lua`. Keeping two copies of
// the list is what this check pays for.

const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");

// Fields it is *correct* for the two lists to disagree on. Adding one means leaving a line saying why.
const EXPECTED_ONLY_IN_PROFILE = {
    // It says where the action sits *here*. Sending it would tell the far side that something they
    // just received had already been received, and quarantine it against a batch number that means
    // nothing on their machine.
    imported: "which batch it arrived on - meaningless in someone else's drawer",
};

// This list used to hold `key` and `seq` as well, under a format that carried the key on a group
// layer above the action and renamed the ranking to `order` to keep it from colliding. Both are on
// the wire under their own names now (`devdocs/building-export-import.md`), which is also what let
// the receiving side read the same whitelist instead of a blacklist of its own.
//
// **`macro` and `setstate` are on the wire and this check cannot see them.** Neither is a profile
// field: they are what a local reference is rewritten into for the trip, and they are read and
// dropped on arrival. Said here so the gap is a known one - a wire field that stopped being written
// would go unnoticed here, and `tests/import_spec.lua` is what covers those two instead.

/** Collects the keys inside the braces of `local NAME = { ... };`. */
function readFieldTable(file, tableName) {
    const source = fs.readFileSync(path.join(repoRoot, file), "utf8");
    const start = source.indexOf(`${tableName}`);
    if (start < 0) {
        throw new Error(`${file}에 ${tableName}이 없다`);
    }

    const open = source.indexOf("{", start);
    if (open < 0) {
        throw new Error(`${file}의 ${tableName} 뒤에 여는 중괄호가 없다`);
    }

    let depth = 0;
    let end = -1;
    for (let i = open; i < source.length; i++) {
        if (source[i] === "{") depth++;
        else if (source[i] === "}") {
            depth--;
            if (depth === 0) {
                end = i;
                break;
            }
        }
    }
    if (end < 0) {
        throw new Error(`${file}의 ${tableName}이 안 닫힌다`);
    }

    const body = source.slice(open + 1, end);
    const fields = new Set();

    // Two shapes: `name = true` and `["$state1"] = true`. Comment lines are skipped.
    for (const line of body.split("\n")) {
        const code = line.replace(/--.*$/, "");
        let m = code.match(/^\s*\[\s*"([^"]+)"\s*\]\s*=/);
        if (!m) m = code.match(/^\s*([A-Za-z_]\w*)\s*=/);
        if (m) fields.add(m[1]);
    }

    if (fields.size === 0) {
        throw new Error(`${file}의 ${tableName}에서 필드를 하나도 못 읽었다`);
    }
    return fields;
}

const saved = readFieldTable("Debind/Profile.lua", "KEYS_TO_SAVE");
const exported = readFieldTable("DebindShare/Export.lua", "ACTION_FIELDS");

const problems = [];

for (const field of saved) {
    if (exported.has(field)) continue;
    if (EXPECTED_ONLY_IN_PROFILE[field]) continue;
    problems.push(
        `저장은 되는데 익스포트가 안 한다: ${field}\n` +
        `    Export.lua의 ACTION_FIELDS에 넣거나, 안 보내는 게 맞으면\n` +
        `    tools/check-export-fields.js의 EXPECTED_ONLY_IN_PROFILE에 이유와 함께 적을 것.`
    );
}

for (const field of exported) {
    if (!saved.has(field)) {
        problems.push(
            `익스포트는 하는데 저장이 안 된다: ${field}\n` +
            `    Profile.lua의 KEYS_TO_SAVE에 없는 필드는 CleanUpDB가 걷어내므로 늘 nil이다.`
        );
    }
}

for (const field of Object.keys(EXPECTED_ONLY_IN_PROFILE)) {
    if (!saved.has(field)) {
        problems.push(
            `예외 명단에 있는데 KEYS_TO_SAVE에는 없다: ${field}\n` +
            `    필드가 사라졌으면 EXPECTED_ONLY_IN_PROFILE에서도 지울 것.`
        );
    }
    if (exported.has(field)) {
        problems.push(
            `예외 명단에 있는데 ACTION_FIELDS에도 있다: ${field}\n` +
            `    둘 중 하나가 틀렸다.`
        );
    }
}

if (problems.length > 0) {
    for (const problem of problems) {
        process.stderr.write(`  ${problem}\n`);
    }
    process.stderr.write(`\n익스포트 필드 명단이 어긋난다 (${problems.length}건).\n`);
    process.exit(1);
}

process.stdout.write(
    `익스포트 필드 ${exported.size}개가 KEYS_TO_SAVE와 맞는다 ` +
    `(안 보내는 것 ${Object.keys(EXPECTED_ONLY_IN_PROFILE).length}개 제외).\n`
);
