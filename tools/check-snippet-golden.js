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
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");
const { forEachSnippet } = require("./lib/snippets");

const root = path.join(__dirname, "..");
const srcDir = path.join(root, "Debind");
const goldenPath = path.join(__dirname, "snippet-golden.txt");

// live 표의 `PROBE.*` 치환. dev 표는 이 저장소에 없다(테스트 애드온이 런타임에 들고 온다).
// live에서는 감싼 것이 벗겨져 원래 호출만 남는다 - 그래서 토큰을 넣기 전과 결과가 같다.
const PROBE_LIVE = /\bPROBE\.([_A-Za-z0-9]+)\(/g;

/**
 * 주석 제거는 **`Snippets.lua`의 것을 그대로 부른다.** 여기에 JS로 한 벌 더 적으면 그건
 * 갈릴 수 있는 사본이고, 갈리는 순간 이 도구는 실제로 굽는 것이 아닌 다른 것을 지키게 된다.
 *
 * `Constants`는 빈 테이블로 충분하다 - `StripSnippetComments`는 값을 안 본다. `BakeSnippet`
 * 전체를 부르지 않는 이유이기도 하다(그쪽은 진짜 상수가 필요하고, 이 도구가 잠그려는 것도
 * 아니다).
 */
function loadStripComments() {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);

    if (lauxlib.luaL_loadfile(L, to_luastring(path.join(srcDir, "Snippets.lua"))) !== lua.LUA_OK) {
        throw new Error(`Snippets.lua 로드 실패: ${lua.lua_tojsstring(L, -1)}`);
    }

    // `local _, DebindPrivate = ...` 규약대로 두 인자를 넘긴다.
    lua.lua_pushstring(L, to_luastring("Debind"));
    lua.lua_newtable(L);
    lua.lua_newtable(L);
    lua.lua_setfield(L, -2, to_luastring("Constants"));
    lua.lua_pushvalue(L, -1);
    lua.lua_setglobal(L, to_luastring("__private"));

    if (lua.lua_pcall(L, 2, 0, 0) !== lua.LUA_OK) {
        throw new Error(`Snippets.lua 실행 실패: ${lua.lua_tojsstring(L, -1)}`);
    }

    return (body) => {
        lua.lua_getglobal(L, to_luastring("__private"));
        lua.lua_getfield(L, -1, to_luastring("StripSnippetComments"));
        lua.lua_pushstring(L, to_luastring(body));
        if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) {
            throw new Error(`StripSnippetComments 실패: ${lua.lua_tojsstring(L, -1)}`);
        }
        const out = to_jsstring(lua.lua_tostring(L, -1));
        lua.lua_pop(L, 2);
        return out;
    };
}

const stripComments = loadStripComments();

/**
 * 게임에 들어가는 형태로 만든다. `BakeSnippet`의 live 갈래와 같은 결과여야 한다.
 * 순서도 같다 - 주석을 먼저 걷고 치환한다.
 *
 * `CONSTANTS.*`는 일부러 안 푼다. 값을 읽으려면 `Constants.lua`를 실행해야 하고, 그 자리는
 * 이 작업이 건드리는 곳이 아니다 - 이름이 틀리면 `BakeSnippet`의 `assert`가 게임에서 죽인다.
 * 여기서 잠그려는 것은 **PROBE 도입이 본문을 바꾸지 않는다**는 것 하나다.
 *
 * 본문 끝의 공백은 아래에서 한 번 더 턴다. 그래서 골든은 굽힌 결과와 바이트로 같지는 않다 -
 * 이 파일이 잡으려는 것은 절대적인 형태가 아니라 **변화**다.
 */
function bakeLive(body) {
    return stripComments(body).replace(PROBE_LIVE, "$1(");
}

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

const built = build();
const update = process.argv.includes("--update");

if (update || !fs.existsSync(goldenPath)) {
    fs.writeFileSync(goldenPath, built, "utf8");
    const count = (built.match(/^### /gm) || []).length;
    console.log(`스니펫 골든 ${count}개를 ${fs.existsSync(goldenPath) ? "새로 떴다" : "만들었다"}. diff를 확인할 것.`);
    process.exit(0);
}

const golden = fs.readFileSync(goldenPath, "utf8");

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
