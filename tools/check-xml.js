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
//
// **CDATA도 건너뛴다.** 그 안은 마크업이 아니라 스크립트 본문이라 `if (a < b and c > 0)`
// 같은 비교 연산자가 그냥 들어간다. 안 건너뛰면 `< b and c >`가 `b`라는 여는 태그로 잡혀서
// 스택이 영영 안 맞고, **멀쩡한 파일에 "안 닫힌 태그"를 찍으며 npm run check을 막는다.**
// 지금 저장소의 XML에는 CDATA가 없지만 이 도구가 check 경로에 올라와 있으므로 미리 막아둔다.
const TAG = /<(\/?)([A-Za-z][\w.]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>|<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>/g;

let failed = 0;
for (const file of files) {
    const text = fs.readFileSync(file, "utf8");
    const rel = path.relative(root, file);
    const stack = [];
    let bad = null;
    let m;
    TAG.lastIndex = 0;
    while ((m = TAG.exec(text))) {
        if (m[0].startsWith("<!--") || m[0].startsWith("<?") || m[0].startsWith("<![CDATA[")) continue;
        if (m[4] === "/") continue;
        const line = () => text.slice(0, m.index).split("\n").length;
        if (m[1] === "/") {
            const open = stack.pop();
            if (open && open.name !== m[2]) {
                bad = `${rel}:${line()}: </${m[2]}> 인데 열린 것은 <${open.name}> (${open.line}행)`;
                break;
            } else if (!open) {
                bad = `${rel}:${line()}: </${m[2]}> 인데 열린 것이 없음`;
                break;
            }
        } else {
            // 줄 번호를 같이 쌓는다. 예전에는 `{ name, line }.name`으로 즉시 버려서, 안 닫힌
            // 태그를 찾아놓고도 **어디인지는 말해주지 못했다.**
            stack.push({ name: m[2], line: line() });
        }
    }
    // **`--` inside a comment is illegal in XML.** Every tag can match and the parser still
    // rejects the whole file as "not well-formed", and it says so only in the game's log. Writing
    // ` -- ` mid-sentence out of Lua habit walks straight into it, which is how it first got here.
    if (!bad) {
        const COMMENT = /<!--([\s\S]*?)-->/g;
        let c;
        while ((c = COMMENT.exec(text))) {
            if (c[1].includes("--")) {
                const line = text.slice(0, c.index).split("\n").length;
                bad = `${rel}:${line}: 주석 안에 \`--\`가 있다. XML은 이걸 못 읽는다`
                    + ` (파일 전체가 로드 안 됨). 다른 글자로 바꿀 것`;
                break;
            }
        }
    }

    if (!bad && stack.length) {
        const where = stack.map((t) => `${t.name}(${t.line}행)`).join(", ");
        bad = `${rel}: 안 닫힌 태그 ${stack.length}개 - ${where}`;
    }
    if (bad) {
        console.log(bad);
        failed++;
    }
}

console.log(failed === 0 ? `XML ${files.length}개 전부 태그가 맞는다.` : `XML ${failed}개 실패.`);
process.exit(failed === 0 ? 0 : 1);
