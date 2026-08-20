// Is `DB_VERSION` in step with the migration ladder?
//   npm run check:dbver
//
// `MigrateLayer` in `Profile.lua` opens its steps with `dbver <= N`, and `MigrateDB` stops when the
// stored version is already `Constants.DB_VERSION`. So the highest step and the constant have to
// agree: the last step raises data to `N + 1`, and that is what `DB_VERSION` must be.
//
// Why this exists: leaving `DB_VERSION` behind while the storage shape moves raises **nothing
// anywhere**. Every headless spec calls `MigrateLayer(layer, N)` directly and so never reads the
// constant; lint sees a number; the game boots. What happens instead is that `MigrateDB` returns at
// the door, the new `CleanUpDB` walks the un-migrated actions, and every field the new
// `KEYS_TO_SAVE` no longer names is deleted from the user's profile. `dbver` is then stamped
// forward on the next login and the migration never gets another chance.
//
// That is exactly what shipped in `2b8e87d` and cost a profile's conditions. One line would have
// caught it.

const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const read = (f) => fs.readFileSync(path.join(repoRoot, f), "utf8");

const constants = read("Debind/Constants.lua");
const declared = constants.match(/Constants\.DB_VERSION\s*=\s*(\d+)/);
if (!declared) {
    process.stderr.write("Constants.lua에서 DB_VERSION을 못 읽었다.\n");
    process.exit(1);
}
const dbVersion = Number(declared[1]);

const profile = read("Debind/Profile.lua");
const steps = [...profile.matchAll(/if\s*\(dbver\s*<=\s*(\d+)\)\s*then/g)].map((m) => Number(m[1]));
if (steps.length === 0) {
    process.stderr.write("Profile.lua에서 마이그레이션 단계를 하나도 못 읽었다.\n");
    process.exit(1);
}

const problems = [];

const highest = Math.max(...steps);
if (highest + 1 !== dbVersion) {
    problems.push(
        `DB_VERSION이 ${dbVersion}인데 제일 높은 단계는 \`dbver <= ${highest}\`다.` +
        ` 마지막 단계가 올려놓는 판은 ${highest + 1}이므로 DB_VERSION도 그 값이어야 한다.`
    );
}

// The ladder is walked top to bottom in one pass, so each step has to stand on the shape the one
// before it produced. Out of order, an earlier step looks for a shape a later one already moved.
for (let i = 1; i < steps.length; i++) {
    if (steps[i] <= steps[i - 1]) {
        problems.push(
            `단계가 오름차순이 아니다: \`dbver <= ${steps[i - 1]}\` 다음에 \`dbver <= ${steps[i]}\`.` +
            ` 각 단계는 앞 단계가 낸 모양 위에서 돈다.`
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
    `DB_VERSION ${dbVersion}이 마이그레이션 단계 ${steps.length}개와 맞는다 ` +
    `(마지막은 dbver <= ${highest}).\n`
);
