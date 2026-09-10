// Does every XML attribute we write exist?
//   npm run check:xml-attrs
//
// **The game does not stop for an attribute it does not know.** It writes one line and carries on:
//
//     Unrecognized XML attribute: propagateMouseClicks
//
// The frame loads, the attribute does nothing, and what it was supposed to do is missing with
// nothing on screen saying so. That is how `propagateMouseClicks` -- a name guessed off the Lua
// `SetPropagateMouseClicks` -- shipped past `check:xml`, which reads tags and never looks inside
// one (2026-09-10).
//
// The list of real names is not written here. It is **read off Blizzard's own XML** in
// `reference/`, so a name the client added is a name this check already knows.
//
// **Local only**, like `check:templates`: `reference/` is fetched, not committed, and CI has none.
// With it missing the check says so and passes -- a check that cannot run must not read as one
// that ran.

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const reference = path.join(root, "reference", "wow-ui-source");

// `<Tag a="1" b='2'/>`의 속성 이름만. 값 안의 `=`는 따옴표가 막는다.
const ATTR = /([A-Za-z][\w.]*)\s*=\s*("[^"]*"|'[^']*')/g;
const TAG = /<([A-Za-z][\w.]*)((?:[^>"']|"[^"]*"|'[^']*')*?)\/?>/g;
const COMMENT = /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>/g;

function xmlFiles(dir, out) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.name.startsWith(".") || entry.name === "node_modules") continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) xmlFiles(full, out);
        else if (entry.name.endsWith(".xml")) out.push(full);
    }
    return out;
}

function attrsIn(text, each) {
    // Comments go, their newlines stay -- otherwise every line number printed below points further
    // up the file than the attribute it is about.
    const body = text.replace(COMMENT, (m) => m.replace(/[^\n]/g, " "));
    let tag;
    TAG.lastIndex = 0;
    while ((tag = TAG.exec(body))) {
        let attr;
        ATTR.lastIndex = 0;
        while ((attr = ATTR.exec(tag[2]))) {
            each(attr[1], () => body.slice(0, tag.index + attr.index).split("\n").length);
        }
    }
}

if (!fs.existsSync(reference)) {
    console.log("reference/wow-ui-source가 없어 XML 속성 이름을 대조하지 못했다 (npm run ui-source).");
    process.exit(0);
}

const known = new Set();
for (const file of xmlFiles(reference, [])) {
    attrsIn(fs.readFileSync(file, "utf8"), (name) => known.add(name));
}

const ours = [];
for (const dir of ["Debind", "DebindStorage", "DebindDev", "DebindCliqueFake", "Debounce"]) {
    const full = path.join(root, dir);
    if (fs.existsSync(full)) xmlFiles(full, ours);
}

let failed = 0;
let counted = 0;
for (const file of ours) {
    const rel = path.relative(root, file);
    attrsIn(fs.readFileSync(file, "utf8"), (name, lineOf) => {
        counted += 1;
        if (!known.has(name)) {
            console.error(`${rel}:${lineOf()}: 클라이언트가 모르는 XML 속성 ${name}`);
            failed += 1;
        }
    });
}

if (failed) {
    process.exit(1);
}
console.log(`XML 속성 ${counted}개가 전부 클라이언트가 아는 이름이다.`);
