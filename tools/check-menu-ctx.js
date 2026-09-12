// Does every menu value handler get the ctx it reads?
//
// `MenuKit.MakeHandlers` builds the four callbacks the game's menu calls back with one argument:
// the `data` table the row was created with. The action they edit rides in `data.ctx`, and
// `ActionValues.Get`/`Set` index `ctx.action` with no guard, so a data table written without a
// `ctx` raises the moment the row is drawn.
//
// Why this exists: nothing else can see it. luacheck sees a well-formed table, the headless specs
// never build a menu, and the raise happens in an initializer inside the game's menu system - one
// group opens empty and everything around it looks fine. Five of these were written at once when
// `DropDownMenus.lua` was split and the file-scope `_action` the callbacks used to read went away
// (`devdocs/legacy/putting-the-menus-on-a-kit.md`).
//
// **What counts as a data table**: a brace group carrying both `key` and `value` and no `label`.
// A node declaration carries `label` and is the thing this must not flag; an item list entry
// carries `text` and `value` but no `key`.

const fs = require("fs");
const path = require("path");

const FILES = [
    "Debind/MenuKit.lua",
    "Debind/ActionMenuModel.lua",
    "Debind/ActionMenuNodes.lua",
    "Debind/ActionMenuProbe.lua",
    "Debind/ActionMenuItems.lua",
    "Debind/DropDownMenus.lua",
];

const root = path.resolve(__dirname, "..");

/** Whole-line Lua comments only. A `--` inside a string would take the rest of a real line with it. */
function stripComments(source) {
    return source.split("\n").map((line) => (/^\s*--/.test(line) ? "" : line)).join("\n");
}

const offenders = [];
let checked = 0;

for (const rel of FILES) {
    const full = path.join(root, rel);
    if (!fs.existsSync(full)) {
        process.stderr.write(`${rel}이 없다. 목록이 낡았다.\n`);
        process.exit(1);
    }
    const source = fs.readFileSync(full, "utf8");
    const text = stripComments(source);

    // Innermost brace groups: a data table holds no table of its own.
    const re = /\{[^{}]*\}/g;
    let m;
    while ((m = re.exec(text)) !== null) {
        const body = m[0];
        if (!/\bkey\s*=/.test(body) || !/\bvalue\s*=/.test(body)) continue;
        if (/\blabel\s*=/.test(body)) continue;
        checked += 1;
        if (/\bctx\s*=/.test(body)) continue;
        const line = text.slice(0, m.index).split("\n").length;
        offenders.push(`${rel}:${line}: ${body.replace(/\s+/g, " ").trim()}`);
    }
}

if (offenders.length > 0) {
    process.stderr.write("ctx 없이 세운 메뉴 data 표가 있다. 그 행은 열리는 순간 터진다.\n");
    for (const line of offenders) {
        process.stderr.write(`  ${line}\n`);
    }
    process.exit(1);
}

process.stdout.write(`메뉴 data 표 ${checked}개가 전부 ctx를 든다.\n`);
