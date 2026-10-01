// The last of the three steps in tools/fetch-camelot-class-spells.js: Debind/ClassSpells_Camelot.lua
// out of what the camelot probe recorded with `/camelotprobe classspells`, and nothing else
// (2026-10-01, owner).
//   npm run camelot-class-spells:build [path to DebindCamelotProbe.lua]
//
// A spell the client answered passive is left out, and so is one it has no name for: the release
// code no longer asks either question. **A rank left out takes nothing with it**: a chain whose
// first rank went has its lowest remaining rank as the first.
//
// **The professions' spells the probe found in a character's book (`professionSpells`) are kept**
// where the fetch did not name them: what a probe has seen is never left out (2026-10-01, owner).
//
// **The chains are checked against what the probe saw.** The release that carries the profile's
// migration fixes every id it rewrites for good (`keeping-a-pinned-rank-apart-from-the-spell.md`),
// so a chain that groups two spells or misses a rank has to show up here. Every spellbook and
// trainer the probe recorded lists ranks under a name; ids it lists under one name that the table
// puts on different first ranks, or leaves out while it holds another of that name, are printed.

const fs = require("fs");
const path = require("path");
const { die, findRecord, readLines } = require("./lib/camelot-probe-record");
const EXCLUDED = require("./lib/camelot-excluded");

const out = path.join(__dirname, "..", "Debind", "ClassSpells_Camelot.lua");

function readRecord(file) {
    const lines = readLines(file, `
        local r = DebindCamelotProbeDB and DebindCamelotProbeDB.classSpells
        if not r or r.version ~= 2 then
            io.stderr:write("no classSpells record of this shape: run /camelotprobe classspells with this tree's probe first\\n")
            os.exit(2)
        end
        print(r.build .. "\\t" .. r.measured)
        for id, s in pairs(r.spells) do
            print("spell\\t" .. id .. "\\t" .. s.first .. "\\t" .. tostring(s.source) .. "\\t" .. tostring(s.class)
                .. "\\t" .. tostring(s.name) .. "\\t" .. tostring(s.passive))
        end
        for id, s in pairs(DebindCamelotProbeDB.professionSpells or {}) do
            print("book\\t" .. id .. "\\t" .. tostring(s.name) .. "\\t" .. tostring(s.passive))
        end
        -- Every spellbook and trainer dump, one line each, for the check at the end.
        for character, levels in pairs(DebindCamelotProbeDB.characters or {}) do
            for level, record in pairs(levels) do
                if type(record) == "table" then
                    for what, text in pairs(record) do
                        if type(text) == "string" and (what == "spellbook" or what:find("^trainer ")) then
                            for row in text:gmatch("[^\\n]+") do
                                print("dump\\t" .. character .. " " .. level .. " " .. what .. "\\t" .. row)
                            end
                        end
                    end
                end
            end
        end`);
    const [build, measured] = lines.shift().split("\t");
    const spells = [], book = [], dumps = new Map();
    for (const l of lines) {
        const f = l.split("\t");
        if (f[0] === "spell") {
            const [, id, first, source, cls, name, passive] = f;
            spells.push({
                id: +id, first: +first, source: /^\d+$/.test(source) ? Number(source) : source,
                cls: cls === "false" ? null : cls, name: name === "false" ? null : name, passive: passive === "true",
            });
        } else if (f[0] === "book") {
            book.push({ id: +f[1], name: f[2], passive: f[3] === "true" });
        } else if (f[0] === "dump") {
            if (!dumps.has(f[1])) dumps.set(f[1], []);
            dumps.get(f[1]).push(f.slice(2).join("\t"));
        }
    }
    return { build, measured, spells, book, dumps };
}

/** `Map(id -> { first, source, cls, name })`, the chains re-formed over what the client kept. */
function chains(spells, dropped) {
    const kept = [];
    for (const s of spells) {
        if (EXCLUDED[s.id]) { continue; }
        if (!s.name) { dropped.unknown.push(`${s.cls || "profession"} ${s.id}`); continue; }
        if (s.passive) { dropped.passive.push(`${s.cls || "profession"} ${s.name}`); continue; }
        kept.push(s);
    }
    const byFirst = new Map();
    for (const s of kept) {
        if (!byFirst.has(s.first)) byFirst.set(s.first, []);
        byFirst.get(s.first).push(s);
    }
    const table = new Map();
    for (const ranks of byFirst.values()) {
        const level = (s) => (typeof s.source === "number" ? s.source : 0);
        ranks.sort((a, b) => level(a) - level(b) || a.id - b.id);
        const first = ranks.find((s) => s.id === ranks[0].first) ? ranks[0].first : ranks[0].id;
        for (const s of ranks) {
            table.set(s.id, { first, source: s.source, cls: s.cls, name: s.name });
        }
    }
    return table;
}

/** What the probe's dumps list under one name that the table does not put on one first rank. */
function check(table, dumps) {
    const findings = [];
    const row = /^\s+(?:\S+\s+)?(\d+)\s+(.+?)(?:\s{2,}|$)/;
    for (const [where, rows] of dumps) {
        const byName = new Map();
        for (const r of rows) {
            const m = r.match(row);
            if (!m || !/^\s+(?:Spell|FutureSpell|PetAction|\d+)\s/.test(r)) continue;
            const id = Number(m[1]);
            if (!byName.has(m[2])) byName.set(m[2], new Set());
            byName.get(m[2]).add(id);
        }
        for (const [name, ids] of byName) {
            const inTable = [...ids].filter((id) => table.has(id));
            if (!inTable.length) continue;
            const firsts = new Set(inTable.map((id) => table.get(id).first));
            const missing = [...ids].filter((id) => !table.has(id));
            if (firsts.size > 1 || missing.length) {
                findings.push(`${where}: ${name} on first ranks ${[...firsts].join(", ")}`
                    + (missing.length ? `, not in the table: ${missing.join(", ")}` : ""));
            }
        }
    }
    return [...new Set(findings)].sort();
}

function comment(name) {
    return name.replace(/[\r\n]/g, " ");
}

function main() {
    const file = process.argv[2] || findRecord();
    const { build, measured, spells, book, dumps } = readRecord(file);
    if (!spells.length) {
        die("the classSpells record holds no spells");
    }

    const dropped = { passive: [], unknown: [] };
    const table = chains(spells, dropped);
    for (const s of book) {
        if (s.passive) { dropped.passive.push(`profession ${s.name}`); continue; }
        if (!table.has(s.id)) {
            table.set(s.id, { first: s.id, source: "profession", cls: null, name: s.name });
        }
    }

    // First ranks by class, then by name; each one's higher ranks under it.
    const firsts = [...table].filter(([id, e]) => e.first === id)
        .sort(([, a], [, b]) => (a.cls || "~").localeCompare(b.cls || "~") || a.name.localeCompare(b.name));
    const higher = new Map();
    for (const [id, e] of table) {
        if (e.first !== id) {
            if (!higher.has(e.first)) higher.set(e.first, []);
            higher.get(e.first).push(id);
        }
    }
    const classes = [...new Set(firsts.map(([, e]) => e.cls).filter(Boolean))].sort();
    const lines = [];
    const counts = new Map();
    for (const [id, e] of firsts) {
        const source = typeof e.source === "number" ? e.source : JSON.stringify(e.source);
        lines.push(`    [${id}] = { ${source}${e.cls ? `, classes = ${e.cls}` : ""} }, -- ${comment(e.name)}`);
        for (const rank of (higher.get(id) || []).sort((a, b) => a - b)) {
            lines.push(`    [${rank}] = ${id},`);
        }
        const key = e.cls || "PROFESSION";
        counts.set(key, (counts.get(key) || 0) + 1);
    }
    for (const [key, n] of [...counts].sort()) {
        console.log(`${key.padEnd(10)} ${n} spells`);
    }
    console.log(`${table.size} ids in all`);

    fs.writeFileSync(out, `local _, DebindPrivate = ...;

--- **Generated by \`tools/build-camelot-class-spells.js\`. Do not edit by hand**: run the three
--- steps again (\`tools/fetch-camelot-class-spells.js\`). Built from the camelot probe's record of
--- ${build}, ${measured}: wowhead's class lists, a pet's books and the professions' pages, as the
--- client answered them, without what it called passive or did not know.
---
--- \`[first rank's id] = { level required, classes = }\`, and \`[higher rank's id] = first rank's id\`.
--- A string in a level's place says where the spell comes from (\`CompareUnlearnedValue\`); no
--- \`classes\` is every class's. The first ranks are the spell list's unlearned rows
--- (\`UnlearnedSpells_Camelot.lua\`), and the id an action stores (\`CanonicalSpellID\`). Loaded on
--- that client only (\`Debind.toc\`).
${classes.map((c) => `local ${c} = { ${c} = true };`).join("\n")}

DebindPrivate.CamelotSpells = {
${lines.join("\n")}
};
`);
    console.log(`\nleft out as passive (${dropped.passive.length}): ${dropped.passive.sort().join(", ") || "-"}`);
    console.log(`left out as unknown to the client (${dropped.unknown.length}): ${dropped.unknown.sort().join(", ") || "-"}`);
    const findings = check(table, dumps);
    console.log(`\nchains the probe's spellbooks and trainers disagree with (${findings.length}):`);
    for (const f of findings) {
        console.log(`  ${f}`);
    }
    console.log(`\nread ${file}\nwrote ${path.relative(process.cwd(), out)}`);
}

main();
