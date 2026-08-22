// luacheck 러너. 바이너리가 없으면 GitHub 릴리스에서 한 번 받아온다.
//   npm run lint
// CI는 luarocks로 설치한 luacheck를 직접 실행한다 (BigWigsMods/actions/luacheck).
// 버전을 CI와 맞춰두어야 로컬 결과와 CI 결과가 일치한다.

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const VERSION = "1.2.0";
const repoRoot = path.resolve(__dirname, "..");
const binDir = path.join(__dirname, "bin");

function binaryName() {
    if (process.platform === "win32") return "luacheck.exe";
    if (process.platform === "linux") return "luacheck";
    return null; // macOS는 릴리스 바이너리가 없다
}

const name = binaryName();
if (!name) {
    console.error(
        `이 플랫폼(${process.platform})용 luacheck 바이너리가 릴리스에 없습니다.\n` +
        `luarocks install luacheck 으로 설치한 뒤 'luacheck -q .' 를 직접 실행하세요.`
    );
    process.exit(1);
}

const binPath = path.join(binDir, name);

if (!fs.existsSync(binPath)) {
    const url = `https://github.com/lunarmodules/luacheck/releases/download/v${VERSION}/${name}`;
    console.error(`luacheck ${VERSION} 내려받는 중...`);
    fs.mkdirSync(binDir, { recursive: true });

    const dl = spawnSync("curl", ["-fsSL", url, "-o", binPath], { stdio: "inherit" });
    if (dl.status !== 0) {
        console.error(`다운로드 실패: ${url}`);
        process.exit(1);
    }
    if (process.platform !== "win32") fs.chmodSync(binPath, 0o755);
}

// Folders `.luacheckrc` excludes, and the reason they are excluded is the same for both: they run
// against a client (or a shim) that hands them globals the config does not list, so a full pass is
// 78 lines of "undefined variable" and nothing else.
//
// **A syntax error is not that.** It is an error rather than a warning, it needs no globals to find,
// and in `DebindTest/` nothing else in `npm run check` would ever find it: no check loads that
// folder, so the first reader is the client at login and what comes back is one `LUA_WARNING` line
// on somebody's screen. A kit that does not parse runs no test at all, which is the most expensive
// silent failure this repo has. `tests/` is cheaper - the spec runner reads it - and it is in here
// so the same rule covers both.
//
// `--no-config` is what reaches them: `exclude_files` applies even to a file named on the command
// line, so the second pass has to leave the config behind and restate `--std`.
const SYNTAX_ONLY_DIRS = ["DebindTest", "tests"];

function runLuacheck(args) {
    const run = spawnSync(binPath, args, { cwd: repoRoot, stdio: "inherit" });
    return run.status === null ? 1 : run.status;
}

if (process.argv.slice(2).length) {
    process.exit(runLuacheck(process.argv.slice(2)));
}

const status = runLuacheck(["-q", "."]);
const syntax = runLuacheck(
    ["-q", ...SYNTAX_ONLY_DIRS, "--no-config", "--std", "lua51", "--only", "011"]);
process.exit(status || syntax);
