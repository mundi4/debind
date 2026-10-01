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
// unlearned rows (`AddUnlearnedSpellEntries`), and it names each rank's first rank, which is the
// id an action stores (`keeping-a-pinned-rank-apart-from-the-spell.md`). Network-dependent, so it is
// run by hand and never by CI.
//
// **Every rank of a name goes in, each pointing at the first** (2026-10-01, owner). The first is the
// lowest level, and the lowest id between two of one level. Ranks are grouped by name **within one
// class** and never across them: the druid's Cure Poison and the shaman's are two spells.
//
// **A name goes in when one of its ids is above level 1** (2026-10-01, owner), which leaves out
// talents (level 0) and the abilities shared across classes.
//
// **Where a name's ids say "Rank N", only those are its ranks, one per number** (2026-10-01): the
// one wowhead gives a `source` (a trainer, a book, a quest), else the lowest id. A page carries
// Season of Discovery's runes and variants under a trained spell's name, with no rank of their own
// (Swipe 411128 "Cat", Flash of Light 1313342) or with the same one and no `source` (Raptor Strike
// 409693, a "Rank 2" beside 14260). A starting spell has no `source` either, and its "Rank 1" is the
// lowest id of that number (Raptor Strike 2973, beside runes 409691 and 415335).
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
// **An id a class trainer sells, or a spellbook holds, that no page carries comes from there**, as
// the camelot probe recorded it (2026-10-01, owner: what only a trainer lists belongs in the table,
// not in a read at run time). A trainer never sells what a new character already knows, so a
// starting spell's first rank is in the spellbook alone. A row's level is the one listed, which a
// trainer reports as 0 for a learned rank. These ids and the page's of one class are chained
// together. **A talent's spell is read too, as the first rank of a name a page carries**: some
// spells are taken as a talent and their higher ranks bought (Lava Burst 408490, then 1238299).
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
//
// **wowhead's pages are kept in .zzz/wowhead and read from there** (owner): a change to the rules
// above needs no new download, and wowhead turns away a run of them. `--refresh` downloads again.
//   npm run camelot-class-spells:fetch [-- --refresh] [path to DebindCamelotProbe.lua]

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
const pageDir = path.join(__dirname, "..", ".zzz", "wowhead");
const args = process.argv.slice(2);
const refresh = args.includes("--refresh");
const recordArg = args.find((a) => a !== "--refresh");

async function get(url) {
    const kept = path.join(pageDir, url.replace(/^https:\/\/www\.wowhead\.com\//, "").replace(/[^\w.-]+/g, "_") + ".html");
    if (!refresh && fs.existsSync(kept)) {
        return fs.readFileSync(kept, "utf8");
    }
    const res = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0" } });
    if (!res.ok) {
        throw new Error(`${res.status} ${res.statusText} - ${url}`);
    }
    const text = await res.text();
    fs.mkdirSync(pageDir, { recursive: true });
    fs.writeFileSync(kept, text);
    return text;
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

/**
 * What the probe recorded the client listing, as `Map(where -> [{ id, name, level }])`: each class
 * trainer it read, and each character's spellbook outside General. `where` starts with the
 * character, which is how a spellbook finds its class.
 */
function readDumps(file) {
    const dumps = new Map();
    const lines = readLines(file, `
        for character, levels in pairs(DebindCamelotProbeDB.characters or {}) do
            for _, record in pairs(levels) do
                if type(record) == "table" then
                    for what, text in pairs(record) do
                        if type(text) == "string" and (what == "spellbook" or what == "talent spells"
                                or what:find("^trainer ")) then
                            for row in text:gmatch("[^\\n]+") do
                                print(character .. "\\t" .. what .. "\\t" .. row)
                            end
                        end
                    end
                end
            end
        end`);
    // `MeasureTrainer`'s row: index, spell id, name, rank, "lv" level, service type.
    const trainerRow = /^\s+\d+\s+(\d+)\s+(.+?)\s{2,}.*?lv (\d+)\s/;
    // `Spellbook`'s: type, id, name, subtext, "lv" level learned, under a "line N" heading.
    const bookRow = /^\s+Spell\s+(\d+)\s+(.+?)\s{2,}.*?lv (\d+)/;
    // `TalentSpells`': node, entry, the spell and its name, then the group.
    const talentRow = /spell=(\d+)\s+(.+?)\s*\|/;
    let line = 0;
    for (const l of lines) {
        const [character, what, text] = l.split("\t");
        const heading = text.match(/^\s+line (\d+)\s/);
        if (heading) {
            line = Number(heading[1]);
            continue;
        }
        const book = what === "spellbook";
        const talent = what === "talent spells";
        const m = text.match(talent ? talentRow : book ? bookRow : trainerRow);
        if (!m || (book && line === 1)) continue;
        const where = `${character}\t${what}`;
        if (!dumps.has(where)) dumps.set(where, []);
        dumps.get(where).push({ id: Number(m[1]), name: m[2], level: talent ? 0 : Number(m[3]), talent });
    }
    return dumps;
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

/** `[{ id, name, level }]`: what one class page lists that goes in. */
function classRows(spells, runesMet) {
    const usable = spells.filter((s) => {
        if (typeof s.id !== "number" || !s.name || !s.skill || !s.skill.length) {
            return false;
        }
        if (RUNE_ABILITIES[s.name]) {
            runesMet.add(s.name);
            return false;
        }
        return true;
    });
    const taken = [];
    for (const ranks of chains(usable).values()) {
        if (!ranks.some((s) => s.level > 1)) continue;
        const numbered = ranks.filter((s) => /^Rank \d+$/.test(s.rank || ""));
        if (!numbered.length) {
            taken.push(...ranks.filter((s) => s.level > 1));
            continue;
        }
        const byRank = new Map();
        for (const s of numbered) {
            const held = byRank.get(s.rank);
            if (!held || (!held.source && s.source) || (!held.source === !s.source && s.id < held.id)) {
                byRank.set(s.rank, s);
            }
        }
        taken.push(...byRank.values());
    }
    return taken.map((s) => ({ id: s.id, name: s.name, level: s.level, rank: s.rank }));
}

/**
 * `[{ id, first, source, name, comment }]`: one class's rows chained by name. A talent's spell is
 * its name's first rank, so a page's "Rank 1" beside it is not that spell (Penance 402284 beside
 * the talent's 402174).
 */
function classEntries(rows) {
    const entries = [];
    for (const [name, all] of chains(rows)) {
        const ranks = all.some((s) => s.talent) ? all.filter((s) => s.talent || s.rank !== "Rank 1") : all;
        for (const s of ranks) {
            entries.push({ id: s.id, first: ranks[0].id, source: s.level, name, comment: s.comment });
        }
    }
    return entries;
}

/**
 * `Map(classFile -> [{ id, name, level, comment }])`: the ids a class trainer sells, or a spellbook
 * holds, that no class page carries. A trainer is that class's when every id it sells that a class
 * page holds is on that page; one with none (a profession's, a pet's) or several is not read. A
 * spellbook's class is its character's, told the same way by everything the character recorded: a
 * new character's book holds only level 1 spells, which no page carries.
 */
function dumpEntries(dumps, pages) {
    const classOf = new Map();
    for (const [classFile, entries] of pages) {
        for (const e of entries) classOf.set(e.id, classFile);
    }
    const classesIn = (rows) => new Set(rows.map((r) => classOf.get(r.id)).filter(Boolean));
    const characterRows = new Map();
    for (const [where, rows] of dumps) {
        const character = where.split("\t")[0];
        characterRows.set(character, (characterRows.get(character) || []).concat(rows));
    }
    const rowsByClass = new Map();
    for (const [where, rows] of dumps) {
        const [character, what] = where.split("\t");
        const classes = classesIn(what.startsWith("trainer ") ? rows : characterRows.get(character));
        if (classes.size !== 1) continue;
        const [classFile] = classes;
        if (!rowsByClass.has(classFile)) rowsByClass.set(classFile, new Map());
        const byId = rowsByClass.get(classFile);
        const pageNames = new Set(pages.get(classFile).map((s) => s.name));
        for (const r of rows) {
            if (classOf.has(r.id) || RUNE_ABILITIES[r.name]) continue;
            // A talent's spell only as the first rank of what a trainer sells on (Lava Burst 408490).
            if (r.talent && !pageNames.has(r.name)) continue;
            // A learned rank reports level 0 at a trainer; another read of the same id may have it.
            const held = byId.get(r.id);
            if (!held || r.level > held.level) {
                byId.set(r.id, { ...r, comment: what });
            }
        }
    }
    // An id two classes list would belong to two classes, which the probe's table cannot hold
    // (`class` is one name).
    const sellers = new Map();
    for (const [classFile, byId] of rowsByClass) {
        for (const id of byId.keys()) sellers.set(id, (sellers.get(id) || []).concat(classFile));
    }
    for (const [id, classes] of sellers) {
        if (classes.length > 1) {
            console.log(`left out, listed for ${classes.join(" and ")}: ${id} (${rowsByClass.get(classes[0]).get(id).name})`);
            for (const classFile of classes) rowsByClass.get(classFile).delete(id);
        }
    }
    const lists = new Map();
    for (const [classFile, byId] of rowsByClass) {
        lists.set(classFile, [...byId.values()]);
    }
    return lists;
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
    const record = recordArg || findRecord();
    const pets = await petEntries(record);

    const runesMet = new Set();
    const pages = new Map();
    for (const [slug, classFile] of Object.entries(CLASSES)) {
        const url = `https://www.wowhead.com/forever/spells/abilities/${slug}`;
        pages.set(classFile, classRows(readList(await get(url), url), runesMet));
    }
    const fromTrainers = dumpEntries(readDumps(record), pages);

    const blocks = [];
    const owner = new Map();
    for (const classFile of Object.values(CLASSES)) {
        const entries = classEntries(pages.get(classFile).concat(fromTrainers.get(classFile) || []));
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

    // **The version moves only when the list does**: the probe asks the client again on login when
    // its record was taken from another version, and the build refuses one that was.
    const spellsText = `Probe.Spells = {\n${blocks.join("\n")}\n};\n`;
    const previous = fs.existsSync(out) ? fs.readFileSync(out, "utf8").replace(/\r\n/g, "\n") : "";
    const at = previous.indexOf("Probe.Spells = {\n");
    const held = (previous.match(/^Probe\.SpellsVersion = (\d+);$/m) || [])[1];
    if (held && at >= 0 && previous.slice(at) === spellsText) {
        console.log(`\nunchanged: ${path.relative(process.cwd(), out)}, version ${held}`);
    } else {
        const version = Number(held || 0) + 1;
        fs.writeFileSync(out, `local _, Probe = ...;

--- **Generated by \`tools/fetch-camelot-class-spells.js\`. Do not edit by hand**: run it again.
--- Fetched ${new Date().toISOString().slice(0, 10)} from wowhead.com/forever/spells/abilities/<class>, the
--- pages its books' learning spells have there, wowhead.com/forever/spells/<profession>, and the
--- trainers and spellbooks the probe recorded.
---
--- \`[spellID] = { first =, source =, class = }\`: every rank, the id of its name's first rank, its
--- level or where it comes from, and its class (none for a profession's). What
--- \`/camelotprobe classspells\` asks the client about, and carries into its record for the release
--- table to be built from.
Probe.SpellsVersion = ${version};
${spellsText}`);
        console.log(`\nwrote ${path.relative(process.cwd(), out)}, version ${version}`);
    }
    console.log(`\nleft out as rune abilities: ${[...runesMet].join(", ") || "none"}`);
    // A name on the list that the pages no longer carry is a line nobody needs, and left there it
    // would read as a decision still being applied.
    for (const name of Object.keys(RUNE_ABILITIES)) {
        if (!runesMet.has(name)) {
            console.warn(`!! "${name}" is on RUNE_ABILITIES and on no page any more: take it off`);
        }
    }
    console.log(`read ${record}`);
    console.log("next: log in on the camelot client, which asks the client on its own, then"
        + " npm run camelot-class-spells:build");
}

main().catch((err) => {
    console.error(err.message);
    process.exitCode = 1;
});
