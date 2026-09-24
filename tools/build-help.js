// Help pages: docs/ingamehelp/<locale>/<page>.md in, Debind/Locales/Help/<locale>.lua out, and
// docs/ingamehelp/index.md in, Debind/Help/HelpTopics.lua out.
//   npm run help           write the Lua
//   npm run check:help     fail when the Lua on disk is not what the sources make
//
// writing-a-help-page.md is the format, rebuilding-in-game-help.md the
// reasons.
//
// **The output ships and nothing rebuilds it at package time**, so the check is the only thing
// standing between an edited page and a release carrying the old text.

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const sourceDir = path.join(root, "docs", "ingamehelp");
const HELP_DIR = "Debind/Locales/Help";
const REGISTRY_FILE = "Debind/Help/HelpTopics.lua";
const outDir = path.join(root, HELP_DIR);
const localesXml = path.join(root, "Debind", "locales.xml");
const BASE = "enUS";
const CHECK = process.argv.includes("--check");

// `*menu name*`, `**lead**` and `[text](page.md)`. **A menu name is the blue `MenuKit` gives a row
// that holds a value**, so a word in it reads as a row the reader can find. **A link is green, not
// `LINK_FONT_COLOR`**: that one and the blue could not be told apart in game, and green is what the
// help row in a menu and the (i) tooltip's "click for more info" already wear, so everything that
// opens a help page looks the same (2026-09-17, owner).
const MENU_COLOR = "BLUE_FONT_COLOR";
const LEAD_COLOR = "HIGHLIGHT_FONT_COLOR";
const LINK_COLOR = "GREEN_FONT_COLOR";

const errors = [];

function fail(where, message) {
    errors.push(`${where}: ${message}`);
}

// **The same cut as `ParseHelpText` in `HelpText.lua`, and the two must agree.** The tags are
// converted per block rather than per line because a paragraph folded in the source puts a tag's
// two ends on different lines, and each block goes out on one line so the game's parse of the
// output lands on exactly these blocks.
function parseBlocks(text) {
    const blocks = [];
    let current = null;

    for (const line of text.split("\n")) {
        const [, indent, rest] = line.match(/^( *)(.*?)\s*$/);
        const heading = rest.match(/^#\s+(.*)$/);
        const note = rest.match(/^>\s+(.*)$/);
        const item = rest.match(/^(\d+\.)\s+(.*)$/) || rest.match(/^(-)\s+(.*)$/);

        if (rest === "") {
            current = null;
        } else if (heading) {
            blocks.push({ kind: "heading", text: heading[1] });
            current = null;
        } else if (note) {
            current = { kind: "note", text: note[1] };
            blocks.push(current);
        } else if (item) {
            current = { kind: "item", marker: item[1], indent: indent.length - (indent.length % 2), text: item[2] };
            blocks.push(current);
        } else if (current) {
            current.text += " " + rest;
        } else {
            current = { kind: "paragraph", text: rest };
            blocks.push(current);
        }
    }

    return blocks;
}

// `\*` stands for a literal asterisk. It is swapped for a character no page can contain before the
// tags are read, so an escaped star is never taken for half of one. Built rather than typed: a raw
// NUL in this file makes git treat it as binary.
const STAR = String.fromCharCode(0);

// `titleOf(page)` is the title the page shows in this locale, or undefined for a page that does not
// exist.
function convertInline(text, where, titleOf) {
    if (text.includes("|")) {
        // A raw escape would get past the tags and put back the hand-typed colour codes this tool
        // exists to replace.
        fail(where, `"|" is not allowed; colours come from the tags only: ${text}`);
        return text;
    }

    let out = text.split("\\*").join(STAR);

    // **A link is `[title]`, the way every link in the game is**, and the title is the target
    // page's, filled in here (2026-09-17, owner). Text written in the source would be a second copy
    // of the title that goes stale the day the page is renamed, so it is refused rather than used.
    out = out.replace(/\[([^\]]*)\]\(([^)]+)\)/g, (_, label, target) => {
        const m = target.match(/^([a-z0-9-]+)\.md$/);
        const title = m && titleOf(m[1]);
        if (title === undefined || title === null) {
            fail(where, `link to a page that does not exist in ${BASE}: ${target}`);
            return label;
        }
        if (label !== "") {
            fail(where, `leave the link text empty, [](${target}); the page's title goes in: ${label}`);
        }
        // Without a colour of its own a link reads as plain text and nobody knows to click it.
        return `|cn${LINK_COLOR}:|Hdebind:help:${m[1]}|h[${title}]|h|r`;
    });

    out = out.replace(/\*\*([^*]+?)\*\*/g, (_, inner) => `|cn${LEAD_COLOR}:${inner}|r`);
    out = out.replace(/\*([^*]+?)\*/g, (_, inner) => `|cn${MENU_COLOR}:${inner}|r`);

    if (out.includes("*")) {
        fail(where, `unbalanced "*": ${text}`);
    }

    return out.split(STAR).join("*");
}

// The title and the blocks, before any inline is converted: a link needs every page's title first.
function readPage(file, where) {
    let src = fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");

    src = src.replace(/<!--[\s\S]*?-->/g, "");
    if (src.includes("<!--")) {
        fail(where, "a comment is not closed");
        return null;
    }
    if (src.includes("-->")) {
        fail(where, "\"-->\" with no comment open");
        return null;
    }

    const lines = src.split("\n");
    const titleAt = lines.findIndex((l) => l.trim() !== "");
    const title = titleAt >= 0 && lines[titleAt].match(/^#\s+(.*?)\s*$/);
    if (!title) {
        fail(where, "the first line that is not a comment has to be the title, \"# ...\"");
        return null;
    }
    if (/[*[\]|]/.test(title[1])) {
        // The title goes to a menu row, a tooltip and a dropdown as well as the window, and a colour
        // on it would be read in every one of them.
        fail(where, `no tags or links in the title: ${title[1]}`);
    }

    const blocks = parseBlocks(lines.slice(titleAt + 1).join("\n"));
    if (blocks.length === 0) {
        fail(where, "the page has no body");
    }

    return { title: title[1], blocks };
}

function renderBody(blocks, where, titleOf) {
    const out = [];
    let previous = null;
    for (const block of blocks) {
        // A paragraph right after another block would be joined onto it by the game's parse, so it
        // needs the blank line. Headings and items start a block on their own; the blank line
        // between them is only kept where the source reads better with it.
        if (previous && !(previous.kind === "item" && block.kind === "item")) {
            out.push("");
        }
        const text = convertInline(block.text, where, titleOf);
        if (block.kind === "heading") {
            out.push(`# ${text}`);
        } else if (block.kind === "note") {
            out.push(`> ${text}`);
        } else if (block.kind === "item") {
            out.push(`${" ".repeat(block.indent)}${block.marker} ${text}`);
        } else {
            out.push(text);
        }
        previous = block;
    }

    const body = out.join("\n");
    if (body.includes("]==]")) {
        fail(where, "the body contains \"]==]\", which ends the Lua string");
    }

    return body;
}

function keyFor(page) {
    return `HELP_${page.toUpperCase().replace(/-/g, "_")}`;
}

function luaString(text) {
    return `"${text.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
}

function build() {
    const locales = fs.readdirSync(sourceDir, { withFileTypes: true })
        .filter((e) => e.isDirectory())
        .map((e) => e.name)
        .sort();

    if (!locales.includes(BASE)) {
        fail(sourceDir, `no ${BASE} folder; every other locale falls back to it`);
        return new Map();
    }

    const pageNames = (locale) => fs.readdirSync(path.join(sourceDir, locale))
        .filter((f) => f.endsWith(".md"))
        .map((f) => f.slice(0, -3))
        .sort();

    const basePages = new Set(pageNames(BASE));
    const outputs = new Map();

    const registry = buildRegistry(basePages);
    if (registry) {
        outputs.set(REGISTRY_FILE, registry);
    }

    const pages = new Map();
    for (const locale of locales) {
        const read = new Map();
        for (const page of pageNames(locale)) {
            const where = `docs/ingamehelp/${locale}/${page}.md`;
            if (!/^[a-z0-9-]+$/.test(page)) {
                fail(where, "a page name is lower-case letters, digits and \"-\"; it becomes a link and a locale key");
                continue;
            }
            if (!basePages.has(page)) {
                // The key would exist in this locale alone, which check-locales reports as a
                // leftover of a deleted string.
                fail(where, `no page of that name in ${BASE}`);
                continue;
            }
            const parsed = readPage(path.join(sourceDir, locale, `${page}.md`), where);
            if (parsed) {
                read.set(page, parsed);
            }
        }
        pages.set(locale, read);
    }

    for (const locale of locales) {
        // A page missing in this locale falls back to enUS in game, so a link to it shows that title.
        const titleOf = (page) => (pages.get(locale).get(page) || pages.get(BASE).get(page) || {}).title;
        const lines = [
            `-- Generated by tools/build-help.js from docs/ingamehelp/${locale}/. Edit those and run`,
            "-- `npm run help`; `npm run check:help` fails when this file and they disagree.",
            "local _, addon = ...;",
            "local L = addon.L;",
        ];
        if (locale !== BASE) {
            lines.push(`if (GetLocale() ~= "${locale}") then return end`);
        }

        for (const [page, parsed] of pages.get(locale)) {
            const body = renderBody(parsed.blocks, `docs/ingamehelp/${locale}/${page}.md`, titleOf);
            lines.push("");
            lines.push(`L["${keyFor(page)}_TITLE"] = ${luaString(parsed.title)}`);
            lines.push(`L["${keyFor(page)}_BODY"] = [==[`);
            lines.push(body);
            lines.push("]==]");
        }

        outputs.set(`${HELP_DIR}/${locale}.lua`, lines.join("\n") + "\n");
    }

    return outputs;
}

// index.md: `# KEY` opens a section whose name is that locale key, `---` opens one with no name at
// all, and `- page` puts a page in it. A nameless section is a line across the picker: what is
// under it belongs apart, and naming the group would be a heading to word and translate for a
// split the line already makes.
function buildRegistry(basePages) {
    const where = "docs/ingamehelp/index.md";
    const file = path.join(sourceDir, "index.md");
    if (!fs.existsSync(file)) {
        fail(where, "missing; it is what puts a page in the help window");
        return null;
    }

    // The section name is looked up at run time, out of reach of check-locales, and a key that is
    // not there shows its own name as the heading.
    const enUS = fs.readFileSync(path.join(root, "Debind", "Locales", `${BASE}.lua`), "utf8");

    const sections = [];
    const listed = new Set();
    for (const [i, raw] of fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n").split("\n").entries()) {
        const line = raw.trim();
        const at = `${where}:${i + 1}`;
        const section = line.match(/^#\s+(\S+)$/);
        const page = line.match(/^-\s+(\S+)$/);
        if (line === "") {
            continue;
        } else if (line === "---") {
            sections.push({ title: null, topics: [] });
        } else if (section) {
            if (!new RegExp(`^L\\["${section[1]}"\\]\\s*=`, "m").test(enUS)) {
                fail(at, `section name ${section[1]} is not a key in Locales/${BASE}.lua`);
            }
            sections.push({ title: section[1], topics: [] });
        } else if (page) {
            if (sections.length === 0) {
                fail(at, "a page before any \"# SECTION\"");
            } else if (!basePages.has(page[1])) {
                fail(at, `no docs/ingamehelp/${BASE}/${page[1]}.md`);
            } else if (listed.has(page[1])) {
                fail(at, `${page[1]} is listed twice`);
            } else {
                listed.add(page[1]);
                sections[sections.length - 1].topics.push(page[1]);
            }
        } else {
            fail(at, `none of "# SECTION", "---" or "- page": ${line}`);
        }
    }
    for (const s of sections.filter((s) => s.topics.length === 0)) {
        fail(where, `section ${s.title || "---"} has no pages`);
    }

    const lines = [
        "-- Generated by tools/build-help.js from docs/ingamehelp/index.md. Edit that and run",
        "-- `npm run help`; `npm run check:help` fails when this file and it disagree.",
        "local _, DebindPrivate = ...;",
        "",
        "DebindPrivate.HELP_SECTIONS = {",
    ];
    for (const s of sections) {
        lines.push("    {");
        if (s.title) {
            lines.push(`        title = "${s.title}",`);
        }
        lines.push("        topics = {");
        for (const page of s.topics) {
            const key = keyFor(page);
            lines.push(`            { name = "${page}", title = "${key}_TITLE", body = "${key}_BODY" },`);
        }
        lines.push("        },");
        lines.push("    },");
    }
    lines.push("};");
    return lines.join("\n") + "\n";
}

// **A file written and never loaded is the quiet failure here**: the check passes, and the game
// shows the key name where the page should be, or no page at all.
function checkLoaded(outputs) {
    const toc = fs.readFileSync(path.join(root, "Debind", "Debind.toc"), "utf8").split(/\r?\n/);
    const tocLine = path.posix.relative("Debind", REGISTRY_FILE);
    const registryAt = toc.indexOf(tocLine);
    if (registryAt < 0) {
        fail("Debind/Debind.toc", `does not load ${tocLine}`);
    } else if (registryAt > toc.indexOf("DebindMessageFrame.lua")) {
        fail("Debind/Debind.toc", `${tocLine} has to come before DebindMessageFrame.lua, which reads it as it loads`);
    }

    const xml = fs.readFileSync(localesXml, "utf8");
    for (const out of outputs.keys()) {
        if (!out.startsWith(`${HELP_DIR}/`)) {
            continue;
        }
        const locale = path.basename(out, ".lua");
        const entry = `<Script file="Locales/Help/${locale}.lua"/>`;
        const at = xml.indexOf(entry);
        if (at < 0) {
            fail("Debind/locales.xml", `does not load ${entry}`);
            continue;
        }
        // Each help file overwrites what its locale file set, so it has to come after that file.
        const own = xml.indexOf(`<Script file="Locales/${locale}.lua"/>`);
        if (own < 0 || own > at) {
            fail("Debind/locales.xml", `${entry} has to come after Locales/${locale}.lua`);
        }
    }
}

const outputs = build();
checkLoaded(outputs);

if (errors.length > 0) {
    for (const e of errors) {
        console.error(e);
    }
    process.exit(1);
}

// A locale folder deleted from docs leaves its Lua behind, still loaded and still overwriting enUS.
const stale = fs.existsSync(outDir)
    ? fs.readdirSync(outDir).filter((f) => f.endsWith(".lua")).map((f) => `${HELP_DIR}/${f}`).filter((f) => !outputs.has(f))
    : [];

if (CHECK) {
    let differs = false;
    for (const [out, text] of outputs) {
        const file = path.join(root, out);
        const onDisk = fs.existsSync(file) ? fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n") : null;
        if (onDisk !== text) {
            differs = true;
            console.error(`${out} ${onDisk === null ? "is missing" : "differs from its sources"}`);
        }
    }
    for (const out of stale) {
        differs = true;
        console.error(`${out} has no docs/ingamehelp/${path.basename(out, ".lua")}/ behind it`);
    }
    if (differs) {
        console.error("Run `npm run help` and look at the diff.");
        process.exit(1);
    }
    console.log(`Help matches its sources (${[...outputs.keys()].join(", ")}).`);
    process.exit(0);
}

fs.mkdirSync(outDir, { recursive: true });
for (const [out, text] of outputs) {
    fs.writeFileSync(path.join(root, out), text, "utf8");
}
for (const out of stale) {
    fs.unlinkSync(path.join(root, out));
}
console.log(`Wrote ${[...outputs.keys()].join(", ")}.`);
