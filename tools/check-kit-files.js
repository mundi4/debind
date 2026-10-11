// Does every file of the in-game kit load, and does every name it takes off `Dev` exist?
//   npm run check:kit
//
// The kit is `DebindDev/TestHarness.lua`, the cases under `DebindDev/Tests/` and
// `DebindDev/TestRunner.lua`, sharing one private table: the harness puts its helpers on `Dev`
// and every other file takes them off it with `local X = Dev.X`. Two mistakes there raise nothing
// anywhere outside the game, since lint skips the kit and nothing headless runs it:
//
//   * a file under `Tests/` missing from `DebindDev.toc` is never loaded, and its cases drop out of
//     /debtest without a word;
//   * a name read off `Dev` that no file put there is a nil local, and the one case that calls it
//     dies at the press.
//
// So both are asked here. A name has to be put on `Dev` by the file reading it or by one the TOC
// loads before it, because most of the reads happen while the file loads.

const fs = require("fs");
const path = require("path");

const devRoot = path.resolve(__dirname, "..", "DebindDev");

const tocLines = fs.readFileSync(path.join(devRoot, "DebindDev.toc"), "utf8").split(/\r?\n/);
const kitFiles = tocLines
    .map((line) => line.trim().replace(/\\/g, "/"))
    .filter((line) => line !== "" && !line.startsWith("#") && /^Tests?(\/|[A-Z])/.test(line));

const problems = [];

for (const file of fs.readdirSync(path.join(devRoot, "Tests"))) {
    if (file.endsWith(".lua") && !kitFiles.includes(`Tests/${file}`)) {
        problems.push(`Tests/${file}이 DebindDev.toc에 없다. 이 파일의 케이스는 /debtest에 안 뜬다.`);
    }
}

// Comments and long strings carry `Dev.` in prose and in snippet bodies; neither is a read. Their
// line breaks stay, so a line number below is the file's own.
const keepLines = (s) => s.replace(/[^\n]/g, "");
const stripComments = (text) => text
    .replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, keepLines)
    .replace(/\[(=*)\[[\s\S]*?\]\1\]/g, (s) => "\"\"" + keepLines(s))
    .replace(/--[^\n]*/g, "");

const defined = new Set();
for (const file of kitFiles) {
    const full = path.join(devRoot, file);
    if (!fs.existsSync(full)) {
        problems.push(`DebindDev.toc가 ${file}을 싣는데 그 파일이 없다.`);
        continue;
    }
    const code = stripComments(fs.readFileSync(full, "utf8"));

    const here = new Set();
    for (const m of code.matchAll(/^[ \t]*(?:function[ \t]+Dev\.(\w+)|Dev\.(\w+)[ \t]*=[^=])/gm)) {
        here.add(m[1] || m[2]);
    }
    for (const m of code.matchAll(/\bDev\.(\w+)/g)) {
        const name = m[1];
        if (!defined.has(name) && !here.has(name)) {
            const line = code.slice(0, m.index).split("\n").length;
            problems.push(`${file}:${line}: Dev.${name}을 읽는데 이 파일도, TOC에서 앞선 파일도 그 이름을 두지 않는다.`);
        }
    }
    for (const name of here) {
        defined.add(name);
    }
}

if (problems.length > 0) {
    for (const p of problems) {
        process.stderr.write(p + "\n");
    }
    process.exit(1);
}
console.log(`킷 파일 ${kitFiles.length}개가 TOC에 다 있고, Dev에서 읽는 이름은 전부 앞에서 놓였다.`);
