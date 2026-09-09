// Is an option that needs a reload also being applied without one?
//   npm run check:reload-options
//
// `RELOAD_REQUIRED_OPTIONS` in `Profile.lua` names the options this build reads once at login. Its
// box carries `REQUIRES_RELOAD`, and that is a promise: nothing about the answer changes until the
// client comes back. `ApplyOptions` in `Misc.lua` is the one place an answer is carried across to a
// live frame, so a name that appears in both says the two halves disagree.
//
// Why this exists: `blizzframes` sat in both for a release and **went different ways depending on
// which way the box moved**. Ticking one (leave the frame alone) could not take back a frame
// already wired, so it really did need the reload; unticking it reached `UpdateBlizzardFrames` and
// registered on the spot. One tooltip promised the same thing for both, and nothing anywhere raised
// -- the reader who unticked simply saw it work, and the reader who ticked saw nothing happen.
//
// The check is one direction only. An option **missing** from the list and applied at once is the
// ordinary case and most of the file; what cannot stand is being in both places.

const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const read = (f) => fs.readFileSync(path.join(repoRoot, f), "utf8");

const profile = read("Debind/Profile.lua");

const listMatch = profile.match(/RELOAD_REQUIRED_OPTIONS\s*=\s*\{([^}]*)\}/);
if (!listMatch) {
    process.stderr.write("Profile.lua에서 RELOAD_REQUIRED_OPTIONS를 못 읽었다.\n");
    process.exit(1);
}
const names = [...listMatch[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);
if (names.length === 0) {
    process.stderr.write("RELOAD_REQUIRED_OPTIONS가 비었다.\n");
    process.exit(1);
}

const misc = read("Debind/Misc.lua");

// The function body, from its header to the next top-level `end`. Column zero is what closes it:
// everything inside is indented, so the first `end` at the left margin is the last line of it.
const bodyMatch = misc.match(/function DebindPrivate\.ApplyOptions\([^)]*\)\n([\s\S]*?)\nend\n/);
if (!bodyMatch) {
    process.stderr.write("Misc.lua에서 ApplyOptions의 본문을 못 읽었다.\n");
    process.exit(1);
}
// Comments do not apply anything, and one of them is allowed to explain why a name is not here.
const body = bodyMatch[1].replace(/^[ \t]*--.*$/gm, "");

const problems = [];
for (const name of names) {
    const branch = new RegExp(`option\\s*==\\s*"${name}"`);
    if (branch.test(body)) {
        problems.push(
            `\`${name}\`이 RELOAD_REQUIRED_OPTIONS에 있으면서 ApplyOptions의 분기에도 있다.` +
            ` 리로드가 필요하다고 해놓고 그 자리에서 반영도 한다는 뜻이다.`
        );
    }
}

if (problems.length > 0) {
    for (const problem of problems) {
        process.stderr.write(`  ${problem}\n`);
    }
    process.exit(1);
}

process.stdout.write(
    `리로드가 필요한 옵션 ${names.length}개(${names.join(", ")})가 ApplyOptions의 분기에 없다.\n`
);
