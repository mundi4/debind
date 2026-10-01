// The first of three steps that make Debind/ClassSpells_Camelot.lua (2026-10-01, owner):
//
//   1. npm run camelot-class-spells:fetch   this file. wowhead's class ability lists for World of
//                                           Warcraft: Forever, narrowed, written into the camelot
//                                           probe as code (DebindCamelotProbe/ClassSpells.lua)
//   2. /camelotprobe classspells            in the game: the client is asked about each of them,
//                                           and the answers go to the probe's SavedVariables
//   3. npm run camelot-class-spells:build   tools/build-camelot-class-spells.js: the release table,
//                                           out of those answers alone
//
// Why: that client's spellbook holds only what has been learned, and a trainer window lists only
// what that trainer teaches and its filters let through. The table is the rest of the spell list's
// unlearned rows (`UnlearnedSpells_Camelot.lua`), and it names each rank's first rank, which is the
// id an action stores (`keeping-a-pinned-rank-apart-from-the-spell.md`). Network-dependent, so it is
// run by hand and never by CI.
//
// **Every rank of a name goes in, each pointing at the first** (2026-10-01, owner). The first is the
// lowest level, level 1 included, and the lowest id between two of one level. Ranks are grouped by
// name **within one class's page** and never across them: the druid's Cure Poison and the shaman's
// are two spells.
//
// **Level above 1 decides which names go in** (2026-10-01, owner: "roughly right"), and nothing else:
// a name qualifies when one of its ranks is above level 1. That drops talents (level 0), rune
// engravings and the abilities shared across classes (level 1 or below), and keeps what a trainer,
// a quest or a book teaches. Picking the first rank by it as well left a starting spell's second
// rank standing as its first (Shadow Bolt 695 for 686).
//
// **A spell with no skill line is left out**: those are a pet's (Growl, Great Stamina, a beast's own
// Lava Breath) or a companion's, cast by something other than the player. Every player spell on
// these pages carries one of its class's lines.
//
// **A pet's spells come from wowhead's pet ability page instead**, a hunter's and a warlock's told
// apart by the class the page names (`reqclass`), with "pet" where the level would be (2026-10-01,
// owner: a hunter had no pet row at all). A name's ranks within one class form a chain the way a
// class page's do, so a pet's first rank (Firebolt 3110, known when summoned) is the first.
//
// **The books a merchant sells are read too** (a Demon Trainer's grimoires), as the camelot probe
// recorded them (`books`), so this step reads its SavedVariables. The probe has only the spell that
// does the teaching; wowhead's page for that spell names the one taught. A taught spell the pet
// page already holds is in its chain; one it does not stands on its own.
//
// **The professions' own spells come from each profession's page** (2026-10-01, owner): the rank
// spells (Mining, Fishing) and the ones beside them (Find Minerals, Smelting, Disenchant). What
// creates an item or takes reagents is a recipe, and recipes are left out. A name's ids on one
// page form a chain the way a class's do, the lowest id first.
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

/** `Map(classFile -> [{ id, name, book }])`, one per name, the lowest book's. */
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
    const lists = new Map();
    for (const [cls, byName] of byClass) {
        lists.set(cls, [...byName.values()].sort((a, b) => a.name.localeCompare(b.name)));
    }
    return lists;
}

/** The class files wowhead's `reqclass` names on the pet ability page. */
const PET_CLASSES = { 4: "HUNTER", 256: "WARLOCK" };

/** `Map(classFile -> [{ id, first, source, name, comment }])`: the pet page's chains, the books'
 *  taught spells it does not hold standing on their own. */
async function petEntries(record) {
    const url = "https://www.wowhead.com/forever/spells/pet-abilities";
    const byClass = new Map();
    for (const s of readList(await get(url), url)) {
        const cls = PET_CLASSES[s.reqclass];
        if (cls && typeof s.id === "number" && s.name) {
            if (!byClass.has(cls)) byClass.set(cls, []);
            byClass.get(cls).push(s);
        }
    }
    const lists = new Map();
    for (const [cls, spells] of byClass) {
        const entries = [];
        for (const [name, ranks] of chains(spells)) {
            for (const s of ranks) {
                entries.push({ id: s.id, first: ranks[0].id, source: "pet", name });
            }
        }
        lists.set(cls, entries);
    }
    for (const [cls, books] of await petSpells(record)) {
        const entries = lists.get(cls) || [];
        lists.set(cls, entries);
        const held = new Set(entries.map((e) => e.id));
        for (const s of books) {
            if (!held.has(s.id)) {
                entries.push({ id: s.id, first: s.id, source: "pet", name: s.name, comment: s.book });
            }
        }
    }
    return lists;
}

/** Ranks grouped by name, the first rank first: the lowest level, then the lowest id. */
function chains(spells) {
    const byName = new Map();
    for (const s of spells) {
        if (!byName.has(s.name)) byName.set(s.name, []);
        byName.get(s.name).push(s);
    }
    for (const ranks of byName.values()) {
        ranks.sort((a, b) => (a.level || 0) - (b.level || 0) || a.id - b.id);
    }
    return byName;
}

/** `[{ id, first, source, name, comment }]` for one class page. */
function classEntries(spells, runesMet) {
    const usable = spells.filter((s) => typeof s.id === "number" && s.name && s.skill && s.skill.length);
    const entries = [];
    for (const [name, ranks] of chains(usable)) {
        if (!ranks.some((s) => s.level > 1)) {
            continue;
        }
        if (RUNE_ABILITIES[name]) {
            runesMet.add(name);
            continue;
        }
        const first = ranks[0].id;
        for (const s of ranks) {
            entries.push({ id: s.id, first, source: s.level || 0, name });
        }
    }
    return entries;
}

async function professionEntries() {
    const entries = [];
    const seen = new Set();
    for (const page of PROFESSIONS) {
        const url = `https://www.wowhead.com/forever/spells/${page}`;
        const usable = readList(await get(url), url)
            .filter((s) => !s.creates && !s.reagents && typeof s.id === "number" && s.name);
        for (const [name, ranks] of chains(usable)) {
            ranks.sort((a, b) => a.id - b.id);
            for (const s of ranks) {
                if (!seen.has(s.id)) {
                    seen.add(s.id);
                    entries.push({ id: s.id, first: ranks[0].id, source: "profession", name, comment: page });
                }
            }
        }
    }
    return entries;
}

/** One entry as a line of the probe's table. */
function line(e, cls) {
    const classPart = cls ? `, class = "${cls}"` : "";
    const source = typeof e.source === "number" ? e.source : JSON.stringify(e.source);
    const note = e.comment ? ` (${luaString(e.comment)})` : "";
    return `    [${e.id}] = { first = ${e.first}, source = ${source}${classPart} }, -- ${luaString(e.name)}${note}`;
}

async function main() {
    const record = process.argv[2] || findRecord();
    const pets = await petEntries(record);

    const blocks = [];
    const runesMet = new Set();
    const owner = new Map();
    for (const [slug, classFile] of Object.entries(CLASSES)) {
        const url = `https://www.wowhead.com/forever/spells/abilities/${slug}`;
        const entries = classEntries(readList(await get(url), url), runesMet);
        for (const e of entries) {
            // Two pages naming one id would need it to belong to two chains. None did on 2026-10-01;
            // the table has one class per first rank, so one that does now has to be looked at.
            if (owner.has(e.id)) {
                throw new Error(`${e.id} (${e.name}) is on the ${owner.get(e.id)} and ${classFile} pages`);
            }
            owner.set(e.id, classFile);
        }
        const petList = pets.get(classFile) || [];
        for (const e of petList) {
            if (owner.has(e.id)) {
                throw new Error(`${e.id} (${e.name}) is a ${classFile} pet's and on the ${owner.get(e.id)} page`);
            }
            owner.set(e.id, classFile);
        }
        const names = new Set(entries.map((e) => e.name)).size;
        const petNames = new Set(petList.map((e) => e.name)).size;
        console.log(`${classFile.padEnd(8)} ${names} spells in ${entries.length} ranks, `
            + `${petNames} pet spells in ${petList.length} ranks`);
        entries.sort((a, b) => a.first - b.first || a.source - b.source || a.id - b.id);
        petList.sort((a, b) => a.first - b.first || a.id - b.id);
        blocks.push(`    -- ${classFile}\n${entries.concat(petList).map((e) => line(e, classFile)).join("\n")}`);
    }

    const professions = await professionEntries();
    console.log(`PROFESSION ${professions.length} spells`);
    blocks.push(`    -- every class's, the professions'\n${professions.map((e) => line(e)).join("\n")}`);

    fs.writeFileSync(out, `local _, Probe = ...;

--- **Generated by \`tools/fetch-camelot-class-spells.js\`. Do not edit by hand**: run it again.
--- Fetched ${new Date().toISOString().slice(0, 10)} from wowhead.com/forever/spells/abilities/<class>, the
--- pages its books' learning spells have there, and wowhead.com/forever/spells/<profession>.
---
--- \`[spellID] = { first =, source =, class = }\`: every rank, the id of its name's first rank, its
--- level or where it comes from, and its class (none for a profession's). What
--- \`/camelotprobe classspells\` asks the client about, and carries into its record for the release
--- table to be built from.
Probe.Spells = {
${blocks.join("\n")}
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
