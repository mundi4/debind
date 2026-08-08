// XML 태그 짝 검사. 프레임XML은 게임이 읽기 전까지 아무도 안 여는 파일이라, 태그 하나가
// 어긋나면 그 파일 **전체**가 조용히 안 로드된다(에러는 게임 로그에만 한 줄 남는다).
// 값싼 검사이므로 매번 돌린다.
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const files = [];
(function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.name.startsWith(".") || entry.name === "node_modules" || entry.name === "BlizzardInterfaceCode") continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(full);
        else if (entry.name.endsWith(".xml")) files.push(full);
    }
})(root);

// 주석과 문자열 안의 꺾쇠는 태그가 아니다. 둘 다 건너뛰고 나머지만 센다.
const TAG = /<(\/?)([A-Za-z][\w.]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>|<!--[\s\S]*?-->|<\?[\s\S]*?\?>/g;

let failed = 0;
for (const file of files) {
    const text = fs.readFileSync(file, "utf8");
    const rel = path.relative(root, file);
    const stack = [];
    let bad = null;
    let m;
    TAG.lastIndex = 0;
    while ((m = TAG.exec(text))) {
        if (m[0].startsWith("<!--") || m[0].startsWith("<?")) continue;
        if (m[4] === "/") continue;
        const line = () => text.slice(0, m.index).split("\n").length;
        if (m[1] === "/") {
            const open = stack.pop();
            if (open !== m[2]) {
                bad = `${rel}:${line()}: </${m[2]}> 인데 열린 것은 <${open || "없음"}>`;
                break;
            }
        } else {
            stack.push({ name: m[2], line: line() }.name);
        }
    }
    if (!bad && stack.length) bad = `${rel}: 안 닫힌 태그 ${stack.length}개 (${stack.join(", ")})`;
    if (bad) {
        console.log(bad);
        failed++;
    }
}

console.log(failed === 0 ? `XML ${files.length}개 전부 태그가 맞는다.` : `XML ${failed}개 실패.`);
process.exit(failed === 0 ? 0 : 1);
