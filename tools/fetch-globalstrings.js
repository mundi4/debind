// Downloads the client's own strings, so that what we write can be checked against what the
// game already says.
//   npm run globalstrings
//
// Why: UI text has to use the game's words (devdocs/writing-user-facing-text.md), and until this
// existed the only way to check one was to launch a client in that language. Korean could be
// checked that way. Russian could not - it is not installed here and cannot be, so a Russian
// term was unverifiable from this machine. With the files on disk it is one grep.
//
// GlobalStrings lives in the client binary, not in the interface code, so wow-ui-source has none
// of it. Ketho/BlizzardInterfaceResources is the one maintained public copy split by locale; the
// two repos that come up first in a search, tekkub/wow-globalstrings and Sarjuuk/wow-globalstrings,
// both stopped in 2014.
//
// The locales fetched are whatever Debind/Locales holds, so adding a locale there brings its
// strings along without touching this file.

const fs = require("fs");
const path = require("path");

const REPO = "Ketho/BlizzardInterfaceResources";
const RAW = `https://raw.githubusercontent.com/${REPO}/master`;

const root = path.join(__dirname, "..");
const localesDir = path.join(root, "Debind", "Locales");
const outDir = path.join(root, "reference", "globalstrings");

async function get(url) {
    const res = await fetch(url);
    if (!res.ok) {
        throw new Error(`${res.status} ${res.statusText} - ${url}`);
    }
    return res.text();
}

/**
 * Reads the build out of the `GetBuildInfo()` line Ketho keeps in the README. It is the only
 * thing that says which client these words belong to. If it cannot be read the strings are
 * still worth having, so record that it is unknown and carry on rather than failing the fetch.
 */
async function readBuild() {
    try {
        const readme = await get(`${RAW}/README.md`);
        const m = readme.match(/GetBuildInfo\(\)\s*=>\s*(.+)/);
        return m ? m[1].trim() : "unknown";
    } catch {
        return "unknown";
    }
}

async function main() {
    const locales = fs.readdirSync(localesDir)
        .filter((f) => f.endsWith(".lua"))
        .map((f) => path.basename(f, ".lua"))
        .sort();

    fs.mkdirSync(outDir, { recursive: true });

    const build = await readBuild();
    const lines = [];

    for (const locale of locales) {
        const url = `${RAW}/Resources/GlobalStrings/${locale}.lua`;
        const text = await get(url);
        fs.writeFileSync(path.join(outDir, `${locale}.lua`), text);
        console.log(`${locale}: ${(text.length / 1024 / 1024).toFixed(1)}MB`);
        lines.push(`${locale}.lua  ${url}`);
    }

    // When these were taken and whose words they are. Reading a stale file as though it were
    // current is the only way this folder can mislead, so the answer sits next to the files.
    fs.writeFileSync(path.join(outDir, "SOURCE.txt"),
        `${REPO}\nGetBuildInfo() => ${build}\nfetched ${new Date().toISOString().slice(0, 10)}\n\n${lines.join("\n")}\n`);

    console.log(`\nbuild ${build}`);
}

main().catch((err) => {
    console.error(err.message);
    process.exitCode = 1;
});
