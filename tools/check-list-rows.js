// Does every row a list builds stand on `DebindListRowTemplate`?
//   npm run check:list-rows
//
// The rows of the main window's lists used to declare their own background, hover light and
// picked mark, each copied off the one before, and the copies drifted: one lost the yellow of its
// light, one had none, one lit from its own texture at its own height. The base template is the one
// place those are drawn now, and a new list whose row is written without it is how that comes back.
//
// Rows are found where a list names them: `factory("X"` and `SetElementInitializer("X"`. What a list
// builds that is not a row is named in NOT_ROWS with the reason, and a name there that no list builds
// any more is an error too, so the list cannot outlive what it excuses.

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..", "Debind");
const BASE = "DebindListRowTemplate";

const NOT_ROWS = {
    // The gap between two groups: an element with a height and nothing drawn.
    Frame: "spacer",
    // Group headings wear the client's own list header bar, which draws its own light.
    DebindKeyHeaderTemplate: "heading",
    DebindStoragePreviewLayerTemplate: "heading",
    DebindSwitchGroupHeaderTemplate: "heading",
    // The switch's settings: a block of controls standing in the list, not a row.
    DebindSwitchSettingsTemplate: "settings block",
    // The spell picker is a grid, and its cells are sized from the template itself.
    DebindSpellPickerHeaderTemplate: "spell picker",
    DebindSpellPickerSpacerTemplate: "spell picker",
    DebindSpellPickerRowTemplate: "spell picker",
    DebindSpellPickerAddRowTemplate: "spell picker",
    DebindSpellPickerUserRowTemplate: "spell picker",
};

function walk(dir, out, ext) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(full, out, ext);
        else if (entry.name.endsWith(ext)) out.push(full);
    }
    return out;
}

const inheritsOf = {};
for (const file of walk(root, [], ".xml")) {
    const text = fs.readFileSync(file, "utf8").replace(/<!--[\s\S]*?-->/g, "");
    for (const m of text.matchAll(/<[A-Za-z]+\s((?:[^>"']|"[^"]*")*?)\/?>/g)) {
        const name = m[1].match(/\bname="([^"]*)"/);
        if (!name) continue;
        const inherits = m[1].match(/\binherits="([^"]*)"/);
        inheritsOf[name[1]] = inherits ? inherits[1].split(",").map((s) => s.trim()) : [];
    }
}

function reachesBase(name, seen) {
    if (name === BASE) return true;
    if (seen.has(name)) return false;
    seen.add(name);
    return (inheritsOf[name] || []).some((parent) => reachesBase(parent, seen));
}

const built = new Map();
for (const file of walk(root, [], ".lua")) {
    const rel = path.relative(path.join(root, ".."), file).replace(/\\/g, "/");
    const lines = fs.readFileSync(file, "utf8").split("\n");
    lines.forEach((line, i) => {
        for (const m of line.matchAll(/\b(?:factory|SetElementInitializer)\(\s*"([^"]+)"/g)) {
            if (!built.has(m[1])) built.set(m[1], `${rel}:${i + 1}`);
        }
    });
}

const problems = [];
let rows = 0;
for (const [name, where] of built) {
    if (NOT_ROWS[name]) continue;
    rows++;
    if (!(name in inheritsOf)) {
        problems.push(`${where}: a list builds ${name}, and no XML declares it.`);
    } else if (!reachesBase(name, new Set())) {
        problems.push(`${where}: ${name} is a list row and does not inherit ${BASE}.`);
    }
}
for (const name of Object.keys(NOT_ROWS)) {
    if (!built.has(name)) {
        problems.push(`tools/check-list-rows.js: NOT_ROWS excuses ${name}, which no list builds any more.`);
    }
}

if (problems.length > 0) {
    for (const problem of problems) process.stderr.write(`  ${problem}\n`);
    process.stderr.write(`\nList rows off the base template (${problems.length}).\n`);
    process.exit(1);
}
process.stdout.write(`All ${rows} list rows inherit ${BASE}.\n`);
