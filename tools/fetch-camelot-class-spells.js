// The first of three steps that make Debind/ClassSpells_Camelot.lua (2026-10-01, owner):
//
//   1. npm run camelot-class-spells:fetch   this file. wowhead's class ability lists for World of
//                                           Warcraft: Forever, narrowed, written into the camelot
//                                           probe as code (DebindCamelotProbe/ClassSpells.lua)
//   2. /camelotprobe classspells            in the game: the client is asked about each of them,
//                                           and the answers go to the probe's SavedVariables
//   3. npm run camelot-class-spells:build   tools/build-camelot-class-spells.js: the release list,
//                                           out of those answers alone
//
// Why: that client's spellbook holds only what has been learned, and a trainer window lists only
// what that trainer teaches and its filters let through. This is the rest of the spell list's
// unlearned rows (`UnlearnedSpells_Camelot.lua`). Network-dependent, so it is run by hand and never
// by CI.
//
// **Level above 1 is the main filter** (2026-10-01, owner: "roughly right"). It drops talents
// (level 0), rune engravings and the abilities shared across classes (level 1 or below), and
// keeps what a trainer, a quest or a book teaches. A variant that shares a name with a trainer
// spell comes along too and merges into that spell's row, since the list is one row per name.
//
// **A spell with no skill line is left out**: those are a pet's (Growl, Great Stamina, a beast's own
// Lava Breath) or a companion's, cast by something other than the player. Every player spell on
// these pages carries one of its class's lines.
//
// **A pet's spells come from the books a merchant sells instead** (a Demon Trainer's grimoires),
// as the camelot probe recorded them (`books`), so this step reads its SavedVariables too. The
// probe has only the spell that does the teaching; wowhead's page for that spell names the one
// taught. They go in their class's list with "pet" where the level would be (2026-10-01, owner).
//
// **The professions' own spells come from each profession's page** (2026-10-01, owner): the rank
// spells (Mining, Fishing) and the ones beside them (Find Minerals, Smelting, Disenchant). What
// creates an item or takes reagents is a recipe, and recipes are left out.
//
// **Rune abilities are left out by name, below**: Season of Discovery's, still in the client's data
// and on wowhead's pages, where nothing tells them apart from a quest spell. Forever's interface code
// has no engraving at all (1.60.1.70009), so nothing teaches them there.
//
// **A name the camelot probe has seen never goes on that list** (2026-10-01, owner): what a trainer
// listed or a talent tree held is measured on the client and outranks anything inferred here. A name
// that turns up there later comes off it.
//
// **Passives are not judged here.** The client is asked in step 2, which is the answer that counts
// (owner: the release code is no place to ask it).
//
// One id per name, the one with the lowest level (the lowest id for a profession's), since the
// spell list shows one row per name and a name casts the highest rank known.
//   npm run camelot-class-spells:fetch [path to DebindCamelotProbe.lua]

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { findRecord, readLines } = require("./lib/camelot-probe-record");

const CLASSES = {
    warrior: "WARRIOR", paladin: "PALADIN", hunter: "HUNTER", rogue: "ROGUE", priest: "PRIEST",
    shaman: "SHAMAN", mage: "MAGE", warlock: "WARLOCK", druid: "DRUID",
};

const PROFESSIONS = [
    "professions/alchemy", "professions/blacksmithing", "professions/enchanting",
    "professions/engineering", "professions/herbalism", "professions/leatherworking",
    "professions/mining", "professions/skinning", "professions/tailoring",
    "secondary-skills/cooking", "secondary-skills/first-aid", "secondary-skills/fishing",
];

/** Each one confirmed on wowhead as a rune's, 2026-10-01. */
const RUNE_ABILITIES = {
    "Shadow Cleave": "warlock, Metamorphosis rune",
    "Hammer of the Righteous": "paladin, Engrave Bracers - Hammer of the Righteous",
    "Aspect of the Falcon": "hunter, Engrave - Aspect of the Falcon",
};

const out = path.join(__dirname, "..", "DebindCamelotProbe", "ClassSpells.lua");

async function get(url) {
    const res = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0" } });
    if (!res.ok) {
        throw new Error(`${res.status} ${res.statusText} - ${url}`);
    }
    return res.text();
}

/**
 * The page carries the list as a JavaScript literal, not JSON: two keys are unquoted. It is
 * evaluated in an empty context, which reaches nothing of this process.
 */
function readList(html, url) {
    const m = html.match(/var listviewspells\s*=\s*(\[[\s\S]*?\]);\s*\n/);
    if (!m) {
        throw new Error(`no spell list in ${url}`);
    }
    return vm.runInNewContext(`(${m[1]})`, Object.create(null), { timeout: 1000 });
}

function luaString(s) {
    return String(s).replace(/[\r\n]/g, " ");
}

/** `[{ class, minLevel, learnSpell, name }]`: the books the probe saw a merchant sell. */
function readBooks(file) {
    return readLines(file, `
        for _, b in pairs(DebindCamelotProbeDB.books or {}) do
            print(b.class .. "\\t" .. tostring(b.minLevel) .. "\\t" .. b.learnSpell .. "\\t" .. b.name)
        end`).map((l) => {
        const [cls, minLevel, learnSpell, name] = l.split("\t");
        return { cls, minLevel: Number(minLevel) || 0, learnSpell: Number(learnSpell), name };
    });
}

/** The spell a book's learning spell teaches, off the "Learn Spell" effect on its wowhead page. */
async function taughtSpell(learnSpell) {
    const url = `https://www.wowhead.com/forever/spell=${learnSpell}`;
    const m = (await get(url)).match(/Learn Spell<table class="icontab">[\s\S]*?\/forever\/spell=(\d+)[^"]*">([^<]+)</);
    if (!m) {
        throw new Error(`no Learn Spell effect on ${url}`);
    }
    return { id: Number(m[1]), name: m[2] };
}

async function petSpells(file) {
    const byClass = new Map();
    for (const book of readBooks(file)) {
        const taught = await taughtSpell(book.learnSpell);
        if (!byClass.has(book.cls)) byClass.set(book.cls, new Map());
        const byName = byClass.get(book.cls);
        const held = byName.get(taught.name);
        if (!held || book.minLevel < held.minLevel) {
            byName.set(taught.name, { ...taught, minLevel: book.minLevel, book: book.name });
        }
    }
    return byClass;
}

async function professionSpells() {
    const byName = new Map();
    for (const page of PROFESSIONS) {
        const url = `https://www.wowhead.com/forever/spells/${page}`;
        for (const s of readList(await get(url), url)) {
            if (s.creates || s.reagents || typeof s.id !== "number" || !s.name) {
                continue;
            }
            const held = byName.get(s.name);
            if (!held || s.id < held.id) {
                byName.set(s.name, { id: s.id, name: s.name, page });
            }
        }
    }
    return [...byName.values()].sort((a, b) => a.page.localeCompare(b.page) || a.name.localeCompare(b.name));
}

async function main() {
    const record = process.argv[2] || findRecord();
    const pets = await petSpells(record);

    const blocks = [];
    const runesMet = new Set();
    for (const [slug, classFile] of Object.entries(CLASSES)) {
        const url = `https://www.wowhead.com/forever/spells/abilities/${slug}`;
        const spells = readList(await get(url), url);

        const byName = new Map();
        for (const s of spells) {
            if (!(s.level > 1) || typeof s.id !== "number" || !s.name || !(s.skill && s.skill.length)) {
                continue;
            }
            if (RUNE_ABILITIES[s.name]) {
                runesMet.add(s.name);
                continue;
            }
            const held = byName.get(s.name);
            if (!held || s.level < held.level || (s.level === held.level && s.id < held.id)) {
                byName.set(s.name, s);
            }
        }
        const rows = [...byName.values()].sort((a, b) => a.level - b.level || a.name.localeCompare(b.name));
        const petRows = [...(pets.get(classFile) || new Map()).values()].sort((a, b) => a.name.localeCompare(b.name));
        console.log(`${classFile.padEnd(8)} ${rows.length} spells, ${petRows.length} pet spells`);

        const lines = rows.map((s) => `        [${s.id}] = ${s.level}, -- ${luaString(s.name)}`)
            .concat(petRows.map((s) => `        [${s.id}] = "pet", -- ${luaString(s.name)} (${luaString(s.book)})`));
        blocks.push(`    ${classFile} = {\n${lines.join("\n")}\n    },`);
    }

    const professions = await professionSpells();
    console.log(`PROFESSION ${professions.length} spells`);
    const professionLines = professions.map((s) => `    [${s.id}] = "profession", -- ${luaString(s.name)} (${s.page})`);

    fs.writeFileSync(out, `local _, Probe = ...;

--- **Generated by \`tools/fetch-camelot-class-spells.js\`. Do not edit by hand**: run it again.
--- Fetched ${new Date().toISOString().slice(0, 10)} from wowhead.com/forever/spells/abilities/<class>, the
--- pages its books' learning spells have there, and wowhead.com/forever/spells/<profession>.
---
--- \`[classFile] = { [spellID] = level required }\`, one id per name, "pet" in a level's place for a
--- pet's: what \`/camelotprobe classspells\` asks the client about, and carries into its record for
--- the release list to be built from.
Probe.ClassSpells = {
${blocks.join("\n")}
};

--- \`[spellID] = "profession"\`, every class's, asked about the same way.
Probe.ProfessionSpells = {
${professionLines.join("\n")}
};
`);
    console.log(`\nleft out as rune abilities: ${[...runesMet].join(", ") || "none"}`);
    // A name on the list that the pages no longer carry is a line nobody needs, and left there it
    // would read as a decision still being applied.
    for (const name of Object.keys(RUNE_ABILITIES)) {
        if (!runesMet.has(name)) {
            console.warn(`!! "${name}" is on RUNE_ABILITIES and on no page any more: take it off`);
        }
    }
    console.log(`read ${record}\nwrote ${path.relative(process.cwd(), out)}`);
    console.log("next: /camelotprobe classspells in the game, then npm run camelot-class-spells:build");
}

main().catch((err) => {
    console.error(err.message);
    process.exitCode = 1;
});
