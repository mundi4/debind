// The camelot probe's SavedVariables, for the tools that make Debind/ClassSpells_Camelot.lua.
//
// Without a path given, the newest DebindCamelotProbe.lua under the camelot client's WTF is read
// (`WOW_ROOT` as `npm run link` takes it). It is read by the same Lua the game uses rather than by
// a parser of our own.
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const WOW_ROOT = process.env.WOW_ROOT || "C:\\Games\\World of Warcraft";
const CLIENT = "_classic_beta_";

function die(msg) {
    console.error(msg);
    process.exit(1);
}

function findRecord() {
    const accounts = path.join(WOW_ROOT, CLIENT, "WTF", "Account");
    if (!fs.existsSync(accounts)) {
        die(`No ${accounts}   (pass the file's path, or set WOW_ROOT)`);
    }
    const found = fs.readdirSync(accounts)
        .map((a) => path.join(accounts, a, "SavedVariables", "DebindCamelotProbe.lua"))
        .filter((f) => fs.existsSync(f))
        .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
    if (!found.length) {
        die(`No DebindCamelotProbe.lua under ${accounts}`);
    }
    return found[0];
}

/**
 * The lines `script` prints with `DebindCamelotProbeDB` loaded from `file`. A script that exits 2
 * has said on stderr what is missing from the record.
 */
function readLines(file, script) {
    let text;
    try {
        text = execFileSync("lua5.1", ["-e", `dofile(${JSON.stringify(file)})\n${script}`], { encoding: "utf8" });
    } catch (err) {
        die((err.stderr || err.message).trim());
    }
    return text.trim().split(/\r?\n/).filter((l) => l !== "");
}

module.exports = { die, findRecord, readLines };
