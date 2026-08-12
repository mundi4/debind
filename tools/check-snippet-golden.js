// 구워진 스니펫 본문을 잠근다.
//
// **지키려는 것 하나.** dev용 주입(`PROBE.*` 치환)을 넣더라도, 그것이 꺼져 있을 때 게임에
// 들어가는 본문은 오늘과 **한 바이트도 달라지지 않는다.** 눈으로 보증할 수 있는 종류가
// 아니라서 - 스니펫은 문자열이고, 틀려도 조용히 "그 키만 안 먹는다"로 나타난다 - 결과를
// 통째로 박제해 두고 비교한다.
//
// 그래서 순서가 이렇게 된다:
//   1. 골든을 뜬다 (오늘의 진실)
//   2. 굽는 동안 주석 제거를 넣는다 -> 골든이 "주석만큼" 움직인다. 그 diff를 보면 다른 것이
//      안 바뀐 것이 증명된다.
//   3. `PROBE.*` 토큰을 넣는다 -> **골든이 안 움직여야 한다.** 이게 그 보증이다.
//
// 골든이 움직였다고 늘 잘못은 아니다. 본문을 진짜로 고쳤으면 움직이는 게 맞다. 이 도구가
// 막는 것은 **모르고 움직이는 것**이다. 의도한 변경이면 `--update`로 다시 뜨고 diff를 본다.
const fs = require("fs");
const path = require("path");
const { forEachSnippet } = require("./lib/snippets");
// 굽는 부분은 `lib/bake.js`에 있다 - 구운 본문을 파싱하는 `check-snippets.js`와 같은 것을
// 봐야 한다. 그쪽은 `Snippets.lua`의 함수를 그대로 부르므로, 이 도구가 지키는 것과 실제로
// 굽는 것이 갈릴 수가 없다.
const { bakeLive } = require("./lib/bake");

const root = path.join(__dirname, "..");
const srcDir = path.join(root, "Debind");
const goldenPath = path.join(__dirname, "snippet-golden.txt");

// 줄번호는 키에 안 넣는다. 위쪽 코드가 한 줄만 늘어도 전부 흔들려서, 진짜 변경이 잡음에
// 묻힌다. 파일 안 순서로 센다.
function build() {
    const out = [];
    const seen = new Map();

    forEachSnippet(srcDir, ({ file, call, label, body }) => {
        const n = (seen.get(file) || 0) + 1;
        seen.set(file, n);

        // 끝 공백을 털지 않는다. 주석 줄이 빈 줄로 남는 규칙이라, 털면 주석으로 끝나는 본문만
        // 짧아져서 그 뒤가 전부 어긋난다 - 진짜 변경과 구분이 안 된다. 구획은 `###`로 나뉘므로
        // 빈 줄이 남아도 읽는 데 문제가 없다.
        const head = `### ${file} #${n} ${call}${label ? ` (${label})` : ""}`;
        out.push(head, bakeLive(body).replace(/\r\n/g, "\n"), "");
    });

    return out.join("\n");
}

// 줄끝은 비교에서 뺀다.
//
// `core.autocrlf=true`인 머신에서 `.gitattributes`가 없으면, 이 도구가 LF로 써둔 골든을 git이
// 체크아웃할 때 CRLF로 바꿔놓는다. 그러면 LF로 만든 문자열과 CRLF 파일을 견주게 되어 **첫 줄부터
// 전부 다르다고 나온다** - 본문은 한 글자도 안 변했는데.
//
// 실제로 그렇게 났다. 도구가 방금 쓴 파일에서는 통과하다가, `git reset` 한 번에 깨졌다.
//
// 잠그려는 것은 본문이지 줄끝이 아니므로, 양쪽 다 LF로 접고 본다.
function normalize(text) {
    return text.replace(/\r\n/g, "\n");
}

/** 처음 갈라지는 줄만 짚어 준다. 전체 diff는 git이 더 잘 보여준다. */
function firstDifference(a, b) {
    const la = a.split("\n");
    const lb = b.split("\n");
    for (let i = 0; i < Math.max(la.length, lb.length); i++) {
        if (la[i] !== lb[i]) {
            let head = "";
            for (let k = i; k >= 0; k--) {
                if (la[k] && la[k].startsWith("### ")) { head = la[k]; break; }
            }
            return { line: i + 1, head, was: la[i], now: lb[i] };
        }
    }
    return null;
}

const built = normalize(build());
const update = process.argv.includes("--update");

if (update) {
    const existed = fs.existsSync(goldenPath);
    fs.writeFileSync(goldenPath, built, "utf8");
    const count = (built.match(/^### /gm) || []).length;
    console.log(`스니펫 골든 ${count}개를 ${existed ? "새로 떴다" : "만들었다"}. diff를 확인할 것.`);
    process.exit(0);
}

// **없으면 실패다.** 예전에는 없을 때 그냥 떠 놓고 통과했는데, 그러면 파일이 커밋에서 빠졌거나
// `git clean`에 날아갔거나 경로가 어긋난 순간 검사가 조용히 초록이 되고, 다음 실행은 **이미
// 어긋난 바이트**를 기준으로 삼는다. 이 도구가 지키려는 단 하나(개발용 주입이 배포 바이트를
// 한 글자도 안 바꾼다)가 그때부터 영영 안 지켜지는데 아무 데서도 안 터진다.
if (!fs.existsSync(goldenPath)) {
    console.error(`골든 파일이 없다: ${goldenPath}`);
    console.error("처음 만드는 것이면 `node tools/check-snippet-golden.js --update` 후 커밋할 것.");
    process.exit(1);
}

const golden = normalize(fs.readFileSync(goldenPath, "utf8"));

if (golden === built) {
    const count = (built.match(/^### /gm) || []).length;
    console.log(`구워진 스니펫 ${count}개가 골든과 같다.`);
    process.exit(0);
}

const d = firstDifference(golden, built);
console.log("구워진 스니펫이 골든과 다르다.");
if (d) {
    console.log(`  ${d.head || "(머리 없음)"}`);
    console.log(`  ${d.line}번째 줄`);
    console.log(`    골든: ${JSON.stringify(d.was)}`);
    console.log(`    지금: ${JSON.stringify(d.now)}`);
}
console.log("");
console.log("본문을 일부러 고쳤으면 `node tools/check-snippet-golden.js --update` 후 diff를 볼 것.");
console.log("PROBE 도입 커밋에서 이게 움직였다면 **그게 버그다** - live 갈래가 본문을 바꾸고 있다.");
process.exit(1);
