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

const args = process.argv.slice(2).length ? process.argv.slice(2) : ["-q", "."];
const run = spawnSync(binPath, args, { cwd: repoRoot, stdio: "inherit" });
process.exit(run.status === null ? 1 : run.status);
