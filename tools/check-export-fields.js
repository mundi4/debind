// Does an account backup leave any option behind?
//   npm run check:export-fields
//
// The options an account backup carries (`OPTION_FIELDS` in `DebindStorage/Export.lua`) against
// every option the settings tab's Defaults resets. The addon keeps no list of its options anywhere
// else, and Defaults has to touch every one of them, so it is the list. An option missing from
// `OPTION_FIELDS` is left out of every backup with nothing said.
//
// **Action fields are not compared here any more: there is one list.** The wire's `ACTION_FIELDS`
// is read off `KEYS_TO_SAVE`, and conditions and `casting` read Debind's own tables, so a field
// cannot be saved and left out of the export, or the other way round.
//
// **`macro` and `setstate` are on the wire and no list names them.** Neither is a profile field:
// they are what a local reference is rewritten into for the trip, and they are read and dropped on
// arrival. `tests/import_spec.lua` covers those two.

const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const NL = String.fromCharCode(10);

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

function readResetOptions() {
    const file = "Debind/SettingsTab.lua";
    const source = fs.readFileSync(path.join(repoRoot, file), "utf8");
    const start = source.indexOf("local function ResetToDefaults");
    if (start < 0) {
        throw new Error(`${file}에 ResetToDefaults가 없다`);
    }
    const end = source.indexOf(NL + "end", start);
    const names = new Set();
    for (const m of source.slice(start, end).matchAll(/\boptions\.(\w+)/g)) {
        names.add(m[1]);
    }
    if (names.size === 0) {
        throw new Error(`${file}의 ResetToDefaults에서 옵션을 하나도 못 읽었다`);
    }
    return names;
}

const resetOptions = readResetOptions();
const optionFields = readFieldTable("DebindStorage/Export.lua", "OPTION_FIELDS");

const problems = [];

for (const field of resetOptions) {
    if (optionFields.has(field)) continue;
    problems.push(
        `설정 탭의 기본값이 되돌리는 옵션인데 계정 백업에 안 실린다: ${field}` + NL +
        `    Export.lua의 OPTION_FIELDS에 타입과 함께 넣을 것.`
    );
}

for (const field of optionFields) {
    if (resetOptions.has(field)) continue;
    problems.push(
        `계정 백업은 싣는데 설정 탭의 기본값이 안 되돌린다: ${field}` + NL +
        `    옵션이 사라졌으면 OPTION_FIELDS에서 지우고, 아니면 ResetToDefaults가 빠뜨린 것이다.`
    );
}

if (problems.length > 0) {
    for (const problem of problems) {
        process.stderr.write(`  ${problem}\n`);
    }
    process.stderr.write(`\n계정 백업의 옵션 명단이 어긋난다 (${problems.length}건).\n`);
    process.exit(1);
}

process.stdout.write(`옵션 ${optionFields.size}개가 설정 탭의 기본값과 맞는다.\n`);
